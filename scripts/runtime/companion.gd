class_name Companion
extends Node2D

## A non-combatant party member that follows the player's path like a classic
## JRPG party line. Pure visual — no physics body, no collision.

@export var follow_spacing: float = 18.0
@export var trail_min_step: float = 0.5
@export var trail_max_points: int = 240
@export var diagonal_trail_step: float = 0.5
@export var max_speed: float = 180.0
@export var catch_up_factor: float = 12.0  ## higher = snappier catch-up
@export var stop_distance: float = 0.5

const SELECTION_CORNERS_SCRIPT = preload("res://scripts/runtime/selection_corners.gd")
const SELECTION_PAD: float = 3.0

## 따로 다니기: members in a split group (1+) leave the snake and roam as a SQUAD.
## The lowest party index in the group leads — actively hunting field enemies —
## and the others hold a small wedge behind it. Enemies that reach any of them
## start battles (see FieldEnemy's detached-contact check).
const DETACH_WANDER_RADIUS: float = 56.0
const DETACH_WANDER_SPEED: float = 42.0
const HUNT_SPEED: float = 55.0
## Idle milling (서성임): whenever a member's chain has stopped — hero standing
## still, squad leader resting — it shuffles a step or two around its slot
## instead of freezing in place. Tiny radius so the formation still reads.
## Sometimes it turns to chat with a neighbor ("···") or strolls over to watch
## the campfire for a while — the cozy camp life.
const IDLE_MILL_RADIUS: float = 8.0
const IDLE_MILL_SPEED: float = 13.0
const IDLE_CHAT_RANGE: float = 26.0
const IDLE_FIRE_RANGE: float = 64.0
## Personal space while idling — 옹기종기 but a full sprite-width apart (no 야릇함).
const IDLE_SEPARATION: float = 18.0
## Small talk is an occasional treat, not a habit — per-member cooldown.
const CHAT_COOLDOWN_MIN_MS: int = 10000
const CHAT_COOLDOWN_MAX_MS: int = 22000
const CHAT_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

var player: CharacterBody2D
var slot_index: int = 1
var _group_id: int = 0
var _wander_anchor: Vector2 = Vector2.ZERO
var _wander_target: Vector2 = Vector2.ZERO
var _wander_wait: float = 0.0
var _idle_mill_target: Vector2 = Vector2.INF
var _idle_mill_wait: float = 0.0
var _idle_gaze_timer: float = 0.0
var _idle_face_point: Vector2 = Vector2.INF
var _idle_arrive_gaze: Vector2 = Vector2.INF
var _next_chat_msec: int = 0
var _pending_data: CharacterData
var _last_position: Vector2
var _player_trail: Array[Vector2] = []
## True while this companion's party member is downed (shows the lying pose).
var _downed_visual: bool = false
## Battle formation: when on, the companion leaves the snake and walks to its
## assigned row slot below the windows, then faces UP (back to camera).
var _in_formation: bool = false
var _formation_target: Vector2 = Vector2.ZERO
var _selection_corners: Node2D

@onready var _visual: CharacterVisual = $Visual


func _ready() -> void:
	add_to_group("party_member")
	_last_position = global_position
	_seed_trail()
	if _pending_data:
		_visual.setup(_pending_data)
	# Hit flinch always; attack lunge only while in battle formation (see handlers).
	EventBus.party_damage_taken.connect(_on_party_damage_taken)
	EventBus.party_member_attacked.connect(_on_party_member_attacked)
	EventBus.member_group_changed.connect(_on_group_changed)
	EventBus.inspector_target_selected.connect(_on_inspector_target_selected)
	_group_id = GameState.member_group(slot_index)
	if _group_id > 0:
		_wander_anchor = global_position
		_wander_target = global_position
	_add_inspector_hotspot()
	_rebuild_selection_marker()


## A world-space click hotspot over this companion → selects it in the right inspector.
func _add_inspector_hotspot() -> void:
	var hotspot := Control.new()
	hotspot.mouse_filter = Control.MOUSE_FILTER_STOP
	hotspot.z_index = 4
	if _pending_data != null:
		var fs: Vector2 = _pending_data.frame_size_vec()
		hotspot.size = fs
		hotspot.position = _pending_data.visual_center_local() - fs * 0.5
	else:
		hotspot.size = Vector2(16, 24)
		hotspot.position = Vector2(-8, -22)
	hotspot.gui_input.connect(_on_inspector_hotspot_input)
	add_child(hotspot)


func _on_inspector_hotspot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		EventBus.inspector_target_selected.emit(self)
		get_viewport().set_input_as_handled()


func _on_inspector_target_selected(target: Node) -> void:
	set_selected(target == self)


func set_selected(selected: bool) -> void:
	if _selection_corners != null:
		_selection_corners.set_selected(selected)


## Right property inspector: companion — header + role line + ③ 무기(공격력) 강화.
func get_inspector_data() -> Dictionary:
	return GameState.member_inspector_data(slot_index, _pending_data)


## Inject the character data. Safe to call before _ready.
func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)
		_rebuild_selection_marker()


func _rebuild_selection_marker() -> void:
	if _selection_corners != null:
		_selection_corners.queue_free()
		_selection_corners = null
	var rect := Rect2(Vector2(-8.0, -22.0), Vector2(16.0, 24.0)).grow(SELECTION_PAD)
	if _pending_data != null:
		var fs: Vector2 = _pending_data.frame_size_vec()
		rect = Rect2(_pending_data.visual_center_local() - fs * 0.5, fs).grow(SELECTION_PAD)
	_selection_corners = SELECTION_CORNERS_SCRIPT.new()
	_selection_corners.configure(rect)
	add_child(_selection_corners)


func _physics_process(delta: float) -> void:
	if player == null:
		_visual.set_velocity(Vector2.ZERO)
		_last_position = global_position
		return
	# Battle formation: break off the snake, walk to the assigned slot, face up.
	if _in_formation:
		var to_slot: Vector2 = _formation_target - global_position
		if to_slot.length() > 1.0:
			var spd: float = minf(max_speed, maxf(60.0, to_slot.length() * catch_up_factor))
			var prev: Vector2 = global_position
			global_position = global_position.move_toward(_formation_target, spd * delta)
			_visual.set_velocity((global_position - prev) / maxf(delta, 0.001))
		else:
			global_position = _formation_target
			if _downed_visual:
				_visual.set_velocity(Vector2.ZERO)
			else:
				_visual.face_dir(CharacterVisual.Dir.UP)  # back to camera, facing the windows
		_last_position = global_position
		return
	# 따로 다니기: split squads (group ≥ 1) act on their own instead of trailing.
	if _group_id > 0:
		_process_squad(delta)
		return
	_remember_player_position()
	# A downed member falls to the BACK of the snake (trails behind everyone) while
	# it's knocked out; alive members keep their normal slot spacing.
	var slots: float = float(slot_index)
	if _downed_visual:
		slots = float(GameState.party_size() + slot_index)
	var target_position: Vector2 = _trail_target(slots * follow_spacing)
	# 서성임: the hero is standing still and we're at (or near) our slot → mill
	# around it instead of freezing. (idle-life "busy" keeps a fire visit alive
	# past the radius.) The moment he moves, the snake resumes.
	if not _downed_visual and player.velocity.length() < 2.0 \
			and not GameState.is_movement_frozen() \
			and not GameState.is_group_frozen_for_battle(_group_id) \
			and (global_position.distance_to(target_position) <= IDLE_MILL_RADIUS + 3.0 \
				or _idle_life_busy()):
		_process_idle_mill(delta, target_position)
		return
	_reset_idle_mill()
	var to_target: Vector2 = target_position - global_position
	var dist_to_target: float = to_target.length()
	if dist_to_target > stop_distance:
		var player_speed: float = player.velocity.length()
		var speed: float = minf(max_speed, maxf(player_speed + follow_spacing * 2.0, dist_to_target * catch_up_factor))
		var previous_position: Vector2 = global_position
		global_position = global_position.move_toward(target_position, speed * delta)
		var velocity: Vector2 = (global_position - previous_position) / maxf(delta, 0.001)
		_visual.set_velocity(velocity)
	else:
		global_position = target_position
		_visual.set_velocity(Vector2.ZERO)
	if _downed_visual:
		_visual.set_velocity(Vector2.ZERO)  # lying pose: no walk animation
	_last_position = global_position


# ─── 따로 다니기 (split squads: hunt + mini-formation) ──────────────────
func is_detached() -> bool:
	return _group_id > 0


func _on_group_changed(index: int, group: int) -> void:
	if index != slot_index:
		return
	_group_id = group
	# Mid-fight transfer: drop the OLD party's battle row immediately — the new
	# party's stance (if it's fighting) re-claims us on the next manager tick.
	clear_formation()
	if group > 0:
		# The chain snapped HERE — this spot seeds the squad's roaming.
		_wander_anchor = global_position
		_wander_target = global_position
		_wander_wait = 0.3
	else:
		_seed_trail()  # rejoin: walk back into the snake from wherever we are


## Squad tick: the lowest living party index in the group LEADS; others wedge.
## Freezes on the SQUAD's own window cap — other parties' fights don't hold us.
func _process_squad(delta: float) -> void:
	if _downed_visual or GameState.is_group_frozen_for_battle(_group_id):
		_visual.set_velocity(Vector2.ZERO)
		_last_position = global_position
		return
	var leader: Companion = _squad_leader()
	if leader == self:
		_process_hunt(delta)
	else:
		_follow_squad_leader(leader, delta)


func _squad_leader() -> Companion:
	var best: Companion = self
	for node in get_tree().get_nodes_in_group("party_member"):
		if node is Companion:
			var comp := node as Companion
			if comp._group_id == _group_id and not comp._downed_visual \
					and comp.slot_index < best.slot_index:
				best = comp
	return best


## My 0-based rank among the squad's followers (drives the wedge slot).
func _squad_rank(leader: Companion) -> int:
	var rank: int = 0
	for node in get_tree().get_nodes_in_group("party_member"):
		if node is Companion:
			var comp := node as Companion
			if comp._group_id == _group_id and comp != leader and comp.slot_index < slot_index:
				rank += 1
	return rank


## Leader: march at the nearest living enemy — contact starts the battle (the
## enemy's detached-contact check). No enemies / window cap full → local wander.
func _process_hunt(delta: float) -> void:
	var target: Node2D = _nearest_field_enemy()
	if target == null or not GameState.can_group_accept_battle_window(_group_id):
		_wander_anchor = global_position
		_process_detached_wander(delta)
		return
	var prev: Vector2 = global_position
	global_position = global_position.move_toward(target.global_position, HUNT_SPEED * delta)
	_visual.set_velocity((global_position - prev) / maxf(delta, 0.001))
	_last_position = global_position


func _nearest_field_enemy() -> Node2D:
	var nearest: Node2D = null
	var best_sq: float = INF
	for node in get_tree().get_nodes_in_group("field_enemy"):
		var enemy := node as Node2D
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var dist_sq: float = global_position.distance_squared_to(enemy.global_position)
		if dist_sq < best_sq:
			best_sq = dist_sq
			nearest = enemy
	return nearest


## Followers hold a small wedge off the leader so the squad reads as ONE party.
func _follow_squad_leader(leader: Companion, delta: float) -> void:
	var offsets: Array[Vector2] = [
		Vector2(-14.0, 10.0), Vector2(14.0, 10.0), Vector2(0.0, 20.0), Vector2(-26.0, 18.0),
	]
	var rank: int = clampi(_squad_rank(leader), 0, offsets.size() - 1)
	var target: Vector2 = leader.global_position + offsets[rank]
	var to_target: Vector2 = target - global_position
	# 서성임: leader's resting and we're near our wedge spot → mill around it.
	if not _downed_visual and leader.current_speed() < 2.0 \
			and (to_target.length() <= IDLE_MILL_RADIUS + 3.0 or _idle_life_busy()):
		_process_idle_mill(delta, target)
		return
	_reset_idle_mill()
	if to_target.length() <= 1.5:
		_visual.set_velocity(Vector2.ZERO)
		_last_position = global_position
		return
	var speed: float = minf(max_speed, maxf(HUNT_SPEED + 12.0, to_target.length() * 4.0))
	var prev: Vector2 = global_position
	global_position = global_position.move_toward(target, speed * delta)
	_visual.set_velocity((global_position - prev) / maxf(delta, 0.001))
	_last_position = global_position


## Tiny camp-idle shared by snake slots and squad wedges: stroll a couple px
## around `anchor`, pause, repeat — sometimes chatting with a neighbor or
## strolling to the fire for a look. Never far enough to break the formation read
## (the fire visit is the one sanctioned field trip).
func _process_idle_mill(delta: float, anchor: Vector2) -> void:
	# Holding a look (fire-watch / chat partner): stand still, keep facing it.
	if _idle_gaze_timer > 0.0:
		_idle_gaze_timer -= delta
		_visual.set_velocity(Vector2.ZERO)
		if _idle_face_point != Vector2.INF:
			_visual.face_dir(_facing_dir(_idle_face_point))
		if _idle_gaze_timer <= 0.0:
			_idle_face_point = Vector2.INF
			_idle_mill_wait = randf_range(0.6, 1.6)
		_last_position = global_position
		return
	if _idle_mill_wait > 0.0:
		_idle_mill_wait -= delta
		_visual.set_velocity(Vector2.ZERO)
		_last_position = global_position
		return
	if _idle_mill_target != Vector2.INF and global_position.distance_to(_idle_mill_target) <= 1.0:
		_idle_mill_target = Vector2.INF
		if _idle_arrive_gaze != Vector2.INF:  # arrived at the fire → watch it
			_idle_face_point = _idle_arrive_gaze
			_idle_arrive_gaze = Vector2.INF
			_idle_gaze_timer = randf_range(1.6, 3.2)
		else:
			_idle_mill_wait = randf_range(0.8, 2.4)
		return
	if _idle_mill_target == Vector2.INF:
		_pick_idle_action(anchor)
		return
	var prev: Vector2 = global_position
	global_position = global_position.move_toward(_idle_mill_target, IDLE_MILL_SPEED * delta)
	_visual.set_velocity((global_position - prev) / maxf(delta, 0.001))
	_last_position = global_position


func _pick_idle_action(anchor: Vector2) -> void:
	# 겹침 방지 최우선: someone's standing in our pixels → step away first.
	var crowding: Node2D = _nearest_buddy_within(IDLE_SEPARATION)
	if crowding != null:
		var away: Vector2 = global_position - crowding.global_position
		if away.length_squared() < 0.5:
			away = Vector2.RIGHT.rotated(randf() * TAU)
		_idle_mill_target = global_position + away.normalized() * randf_range(10.0, 14.0)
		return
	var roll: float = randf()
	# 모닥불 구경: the fire is close → wander over and watch it a while.
	if roll < 0.15 and GameState.campfire_placed \
			and anchor.distance_to(GameState.campfire_position) <= IDLE_FIRE_RANGE:
		_idle_mill_target = _pick_clear_spot(GameState.campfire_position, 13.0, 19.0)
		_idle_arrive_gaze = GameState.campfire_position
		return
	# 수다: rare (small band + long cooldown) — 현실 친구들도 이 정도는 아니니까.
	if roll < 0.23 and Time.get_ticks_msec() >= _next_chat_msec:
		var buddy: Node2D = _nearest_chat_buddy()
		if buddy != null:
			_next_chat_msec = Time.get_ticks_msec() \
				+ randi_range(CHAT_COOLDOWN_MIN_MS, CHAT_COOLDOWN_MAX_MS)
			_idle_face_point = buddy.global_position
			_idle_gaze_timer = randf_range(1.2, 2.2)
			_spawn_chat_dots()
			if buddy.has_method("react_chat"):
				buddy.react_chat(global_position)
			return
	# 그냥 서성.
	_idle_mill_target = _pick_clear_spot(anchor, 2.0, IDLE_MILL_RADIUS)


## An idle action is mid-flight (fire trip / gaze) — keeps the mill gate open
## while we're legitimately beyond the small radius.
func _idle_life_busy() -> bool:
	return _idle_mill_target != Vector2.INF or _idle_gaze_timer > 0.0 \
		or _idle_arrive_gaze != Vector2.INF


func _reset_idle_mill() -> void:
	_idle_mill_target = Vector2.INF
	_idle_mill_wait = 0.0
	_idle_gaze_timer = 0.0
	_idle_face_point = Vector2.INF
	_idle_arrive_gaze = Vector2.INF


## A buddy turned to talk to us — glance back for a moment (felt while idling).
func react_chat(from: Vector2) -> void:
	_idle_face_point = from
	_idle_gaze_timer = maxf(_idle_gaze_timer, randf_range(1.0, 1.8))


func _facing_dir(point: Vector2) -> CharacterVisual.Dir:
	var d: Vector2 = point - global_position
	if absf(d.x) > absf(d.y):
		return CharacterVisual.Dir.RIGHT if d.x > 0.0 else CharacterVisual.Dir.LEFT
	return CharacterVisual.Dir.DOWN if d.y > 0.0 else CharacterVisual.Dir.UP


func _nearest_chat_buddy() -> Node2D:
	return _nearest_buddy_within(IDLE_CHAT_RANGE)


func _nearest_buddy_within(range_px: float) -> Node2D:
	var best: Node2D = null
	var best_sq: float = range_px * range_px
	for node in get_tree().get_nodes_in_group("party_member"):
		if node == self or not (node is Node2D):
			continue
		var dist_sq: float = global_position.distance_squared_to((node as Node2D).global_position)
		if dist_sq < best_sq:
			best_sq = dist_sq
			best = node as Node2D
	return best


## A ring spot around `center` that keeps personal space from the others —
## a few tries, then take what we got (the step-away rule untangles later).
func _pick_clear_spot(center: Vector2, radius_min: float, radius_max: float) -> Vector2:
	var candidate: Vector2 = center
	for attempt in 6:
		var ang: float = randf() * TAU
		candidate = center + Vector2(cos(ang), sin(ang)) * randf_range(radius_min, radius_max)
		if _idle_spot_clear(candidate):
			return candidate
	return candidate


func _idle_spot_clear(pos: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("party_member"):
		if node == self or not (node is Node2D):
			continue
		if pos.distance_squared_to((node as Node2D).global_position) < IDLE_SEPARATION * IDLE_SEPARATION:
			return false
	return true


## "···" puff above the head — reads as small talk between idle members.
func _spawn_chat_dots() -> void:
	var lbl := Label.new()
	lbl.text = "···"
	lbl.add_theme_font_override("font", CHAT_FONT)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.position = Vector2(-7.0, -30.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var t := create_tween().set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - 5.0, 1.3)
	t.tween_property(lbl, "modulate:a", 0.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)


## Idle-wander around the squad anchor: short strolls, short pauses — close to
## the BG feel of an unchained party member holding position.
func _process_detached_wander(delta: float) -> void:
	if _downed_visual or GameState.is_group_frozen_for_battle(_group_id):
		_visual.set_velocity(Vector2.ZERO)
		_last_position = global_position
		return
	if _wander_wait > 0.0:
		_wander_wait -= delta
		_visual.set_velocity(Vector2.ZERO)
		_last_position = global_position
		return
	var to_target: Vector2 = _wander_target - global_position
	if to_target.length() <= 2.0:
		_wander_wait = randf_range(0.6, 1.8)
		var angle: float = randf() * TAU
		var radius: float = randf_range(12.0, DETACH_WANDER_RADIUS)
		var next: Vector2 = _wander_anchor + Vector2(cos(angle), sin(angle)) * radius
		_wander_target = Vector2(
			clampf(next.x, 16.0, Field.FIELD_SIZE.x - 16.0),
			clampf(next.y, 16.0, Field.FIELD_SIZE.y - 16.0),
		)
		return
	var prev: Vector2 = global_position
	global_position = global_position.move_toward(_wander_target, DETACH_WANDER_SPEED * delta)
	_visual.set_velocity((global_position - prev) / maxf(delta, 0.001))
	_last_position = global_position


## Field shows this companion lying down while its party member is downed.
func set_downed_visual(is_down: bool) -> void:
	_downed_visual = is_down
	if _visual:
		_visual.rotation = deg_to_rad(90.0) if is_down else 0.0
		_visual.modulate = Color(0.6, 0.6, 0.66, 1.0) if is_down else Color(1, 1, 1, 1)


func current_speed() -> float:
	return (global_position - _last_position).length() / maxf(get_physics_process_delta_time(), 0.001)


## BattleManager assigns this companion's battle-formation row slot (world pos).
func set_formation_slot(pos: Vector2) -> void:
	_in_formation = true
	_formation_target = pos


## Leave battle formation and rejoin the trailing snake.
func clear_formation() -> void:
	if not _in_formation:
		return
	_in_formation = false
	_seed_trail()  # restart the trail from here so the snake doesn't snap


# ─── Hit / attack reactions ────────────────────────────────────────────
## Flinch fires whenever this member takes damage in any battle window, wherever
## it's standing.
func _on_party_damage_taken(member_index: int, _amount: int) -> void:
	if member_index == slot_index and _visual != null and not _downed_visual:
		_visual.play_hit_flinch()


## Classic-RPG attack tell — ONLY while standing in battle formation (back shown,
## under the window): lunge toward the window and snap back. Roaming between
## fights stays effect-free.
func _on_party_member_attacked(member_index: int) -> void:
	if member_index == slot_index and _in_formation and _visual != null and not _downed_visual:
		_visual.play_attack_lunge()


func snap_to_formation() -> void:
	if player == null:
		return
	_seed_trail()
	global_position = _trail_target(float(slot_index) * follow_spacing)
	_last_position = global_position


func _seed_trail() -> void:
	_player_trail.clear()
	if player == null:
		return
	_player_trail.append(player.global_position)
	for i in range(1, maxi(slot_index + 4, 8)):
		_player_trail.append(player.global_position + Vector2.UP * follow_spacing * float(i))


func _remember_player_position() -> void:
	if _player_trail.is_empty():
		_seed_trail()
		return
	var pos: Vector2 = player.global_position
	var step: float = _current_trail_step()
	if pos.distance_squared_to(_player_trail[0]) >= step * step:
		_player_trail.push_front(pos)
	while _player_trail.size() > trail_max_points:
		_player_trail.pop_back()


func _current_trail_step() -> float:
	if absf(player.velocity.x) > 0.01 and absf(player.velocity.y) > 0.01:
		return diagonal_trail_step
	return trail_min_step


func _trail_target(distance: float) -> Vector2:
	if _player_trail.is_empty():
		return player.global_position if player else global_position
	var previous: Vector2 = _player_trail[0]
	var traveled: float = 0.0
	for i in range(1, _player_trail.size()):
		var point: Vector2 = _player_trail[i]
		var segment: float = previous.distance_to(point)
		if segment <= 0.001:
			previous = point
			continue
		if traveled + segment >= distance:
			var t: float = (distance - traveled) / segment
			return previous.lerp(point, t)
		traveled += segment
		previous = point
	return _player_trail.back()
