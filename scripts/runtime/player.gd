class_name Player
extends CharacterBody2D

## Top-down player avatar. Conceptually = the camera = the party (README: 시스템 3).
## Owns the Camera2D and its CharacterVisual. Combat lives in battle_windows.

@export var speed: float = 60.0
## Camera is fixed in world space, not parented to the player's transform.
## Centered on the FIELD center so the hero sits at the true viewport center
## (the left dock / right panel just overlay the edges — they don't shift the
## center). The Field updates this each loop via recenter_camera(). The field now
## spans the full 640 viewport width, so its center == viewport center (320).
@export var camera_world_position: Vector2 = Vector2(320.0, 180.0)
## The hero always auto-walks toward the nearest valid field enemy (this is an
## auto-move game). WASD / arrows now pan the CAMERA, not the hero.
@export var auto_move_to_enemies: bool = true
## Click radius (world px) around the hero that counts as "click the hero" to snap
## the free-look camera back onto it.
@export var hero_click_radius: float = 24.0
## How fast the follow-camera eases toward the hero (higher = snappier). Kept
## gentle so the roam doesn't feel jerky / nauseating.
const CAMERA_SMOOTHING_SPEED: float = 4.0
## Keyboard pan speed (world px/sec) for WASD / arrow-key camera nudging.
const KEYBOARD_PAN_SPEED: float = 220.0
## Speed (world px/sec) the hero rushes to its battle-formation slot. The roam base
## speed (~60) lags behind the companions (≤180), so formation uses this snappy one.
const FORMATION_MOVE_SPEED: float = 175.0
## Mouse-wheel zoom range + step. zoom 1 = default; lower = see more (zoom out),
## higher = closer. MIN 0.32 shows ≈2000×1125 of world, framing the whole 1200×900
## board with a clear void margin all around (~400px sides, ~110px top/bottom) so a
## full zoom-out reads as a board floating in the void; MAX 3 is a close-up.
const ZOOM_MIN: float = 0.32
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.15
const SELECTION_CORNERS_SCRIPT = preload("res://scripts/runtime/selection_corners.gd")
const SELECTION_PAD: float = 3.0

@onready var _visual: CharacterVisual = $Visual
@onready var _camera: Camera2D = $Camera2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _pending_data: CharacterData
var _field_bounds := Rect2(Vector2.ZERO, Vector2(960, 540))
var _camera_world_center: Vector2 = Vector2.INF
var _camera_shake_tween: Tween
## True while this avatar's party member is downed (shows the lying pose).
var _downed_visual: bool = false
## One-time scripted walk target (campfire mage event). Overrides auto-move.
var _forced_target_active: bool = false
var _forced_target: Vector2 = Vector2.ZERO
## Battle formation: show the hero's back (face UP) while settled in formation.
var _force_face_up: bool = false
## Battle formation: rush to this world slot (fast), then face up. Same interface as
## Companion so BattleManager drives the whole party uniformly.
var _formation_slot_active: bool = false
var _formation_slot: Vector2 = Vector2.ZERO
## Camera mode. While following, the camera is glued to the hero. The first pan
## input (WASD / arrows / mouse drag) DETACHES it into free-look — the hero can
## then walk anywhere without moving the view. Clicking the hero or a party box
## re-attaches it (see focus_camera_on_hero). The camera is top_level, so we drive
## its global_position directly in both modes.
var _camera_following: bool = true
## World position the free-look camera holds while detached.
var _free_camera_pos: Vector2 = Vector2.ZERO
## Mouse drag-pan state — fully polled in _update_camera_pan (no reliance on
## _unhandled_input, which a full-rect UI Control or Area2D physics picking can
## swallow). _drag_last_mouse is the cursor position last frame; _was_mouse_pressed
## tracks the button edge so we only test "started over UI?" once, on press.
var _is_drag_panning: bool = false
var _drag_last_mouse: Vector2 = Vector2.ZERO
var _was_mouse_pressed: bool = false
var _selection_corners: Node2D


func set_forced_move_target(pos: Vector2) -> void:
	_forced_target = pos
	_forced_target_active = true


func clear_forced_move_target() -> void:
	_forced_target_active = false


## Window-keeper loop: the player clicked a field enemy → the hero hunts THIS one
## (walks to it; his collision opens the window). Replaces the old WASD/auto-hunt
## as the default way the hero engages. Cleared when the target is consumed/dies.
var _engage_target: Node2D


func set_engage_target(enemy: Node2D) -> void:
	_engage_target = enemy
	_reset_idle_life()


## True while the hero is actively walking toward a clicked enemy — the wave clock
## only runs when the hero is DOING something (or 자동 이동 / a fight is on).
func is_engaged() -> bool:
	return is_instance_valid(_engage_target)


## Battle formation: when on, the hero shows its back (faces UP toward the enemy
## windows) once it stops moving. BattleManager toggles this on arrival at the
## formation point and off when the fight ends.
func set_formation_facing(on: bool) -> void:
	_force_face_up = on


## Battle formation: rush to this world slot at FORMATION_MOVE_SPEED, then (settled)
## face up. BattleManager calls this on every party member (hero + companions).
func set_formation_slot(pos: Vector2) -> void:
	_formation_slot_active = true
	_formation_slot = pos
	_force_face_up = true


## Leave battle formation and resume auto-roam.
func clear_formation() -> void:
	_formation_slot_active = false
	_force_face_up = false


# ─── Hit reaction ──────────────────────────────────────────────────────
## Flinch fires whenever party member 0 takes damage in any battle window,
## wherever the hero is standing.
func _on_party_damage_taken(member_index: int, _amount: int) -> void:
	if member_index == 0 and _visual != null and not _downed_visual:
		_visual.play_hit_flinch()


## Classic-RPG attack tell — ONLY while standing in battle formation (back shown,
## under the window): lunge toward the window and snap back. While roaming
## between fights (멀티 전투창 movement) attacks stay effect-free.
func _on_party_member_attacked(member_index: int) -> void:
	if member_index == 0 and _formation_slot_active and _visual != null and not _downed_visual:
		_visual.play_attack_lunge()


func _ready() -> void:
	# Field enemies look us up via this group. Set before anything else so
	# enemies spawned on the same frame find us.
	add_to_group("player")
	add_to_group("party_member")
	# Camera is TOP-LEVEL (world space, not parented to our transform) so free-look
	# can hold a fixed world point while the hero walks off. In follow mode we drive
	# its global_position onto the hero each frame; smoothing eases both the roam and
	# the glide back when re-focusing.
	# Camera is FIXED at the field center now (no hero-follow, no pan). Smoothing off
	# so it sits dead-still; limits cleared so the small field isn't shoved off-center.
	_camera.top_level = true
	_camera.position_smoothing_enabled = false
	if _camera_world_center == Vector2.INF:
		_camera_world_center = _field_bounds.get_center()
	_camera.global_position = _camera_world_center
	_free_camera_pos = _camera.global_position
	_apply_zoom(GameState.field_camera_zoom)  # restore the player's last wheel zoom
	_camera.make_current()
	# Party-panel boxes emit this on click → snap the view back onto the hero.
	EventBus.camera_focus_hero_requested.connect(focus_camera_on_hero)
	EventBus.inspector_target_selected.connect(_on_inspector_target_selected)
	# Hit flinch always; attack lunge only while in battle formation (see handlers).
	EventBus.party_damage_taken.connect(_on_party_damage_taken)
	EventBus.party_member_attacked.connect(_on_party_member_attacked)
	if _pending_data:
		_visual.setup(_pending_data)
		_apply_character_layout()
	_add_inspector_hotspot()
	_rebuild_selection_marker()


## A world-space click hotspot over the hero sprite → selects it in the right
## inspector (the hero has no Area2D picking; a Control hotspot is simplest, same
## trick FieldStructure uses). Sized/placed from the character frame when known.
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


## Right property inspector: hero (party index 0) — header + role line + ③ 무기(공격력) 강화.
func get_inspector_data() -> Dictionary:
	return GameState.member_inspector_data(0, _pending_data)


## Inject the character data (sprite sheet, stats). Safe to call before _ready.
func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)
		_apply_character_layout()
		_rebuild_selection_marker()


func _apply_character_layout() -> void:
	if _pending_data == null:
		return
	# Camera is top-level / fixed — its position is set once in _ready and is
	# not re-derived from the character data. We only update body collision
	# here so different party leaders (hero vs companion) still get a hitbox
	# that matches their sprite.
	if _collision_shape:
		var rect_shape := _collision_shape.shape as RectangleShape2D
		if rect_shape == null:
			rect_shape = RectangleShape2D.new()
			_collision_shape.shape = rect_shape
		rect_shape.size = _pending_data.body_size
		_collision_shape.position = _pending_data.body_center_local()


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


func set_field_bounds(min_pos: Vector2, max_pos: Vector2) -> void:
	_field_bounds = Rect2(min_pos, max_pos - min_pos)
	# Fixed camera: drop the edge limits (a field smaller than the viewport would get
	# shoved off-center by them) and just park the view on the field center.
	if _camera:
		_camera.limit_left = -10000000
		_camera.limit_top = -10000000
		_camera.limit_right = 10000000
		_camera.limit_bottom = 10000000
		_camera.global_position = _camera_world_center


func set_camera_world_center(center: Vector2) -> void:
	_camera_world_center = center
	if _camera:
		_camera.global_position = _camera_world_center


# ─── Mouse-wheel zoom ──────────────────────────────────────────────────
## Drag-pan is NOT handled here — it's fully polled in _update_camera_pan, because
## a full-rect UI Control (or Area2D physics picking) was eating the button/motion
## events before they reached this node. Wheel zoom still comes through fine.
func _unhandled_input(event: InputEvent) -> void:
	# Wheel zoom disabled for now — keep the field at a fixed zoom.
	pass


func _apply_zoom(z: float) -> void:
	var clamped: float = clampf(z, ZOOM_MIN, ZOOM_MAX)
	GameState.field_camera_zoom = clamped
	if _camera:
		_camera.zoom = Vector2(clamped, clamped)


func _physics_process(delta: float) -> void:
	# Camera pan runs first so you can look around even while combat is paused.
	_update_camera_pan(delta)
	# 따로 다니기: only the HERO party's own window cap freezes the hero — other
	# split squads fighting elsewhere never hold him still. EXCEPTION: while a
	# battle stance is assigned he may still walk to his row under the window
	# (the formation branch below owns movement; roam input stays out).
	if GameState.is_group_frozen_for_battle(0) and not _formation_slot_active:
		velocity = Vector2.ZERO
		_visual.set_velocity(velocity)
		return
	# Whole party collapsed → hold still until everyone has fully recovered, then
	# resume together (movement latch in GameState).
	if GameState.is_movement_frozen():
		velocity = Vector2.ZERO
		_visual.set_velocity(Vector2.ZERO)
		return
	# Manual movement by default (WASD / arrows); the 자동 이동 upgrade adds enemy-seeking.
	var move_dir := Vector2.ZERO
	var move_speed: float = GameState.effective_move_speed(speed)
	if _formation_slot_active or _forced_target_active:
		_reset_idle_life()  # scripted moves park the hero somewhere new — re-anchor later
	if _formation_slot_active:
		# Battle formation: hustle to the slot fast (the slow roam speed lagged the
		# companions). Facing up is handled below once settled.
		var to_slot: Vector2 = _formation_slot - global_position
		if to_slot.length() > 2.0:
			move_dir = to_slot.normalized()
		move_speed = FORMATION_MOVE_SPEED
	elif _forced_target_active:
		# Scripted walk (campfire mage event) overrides player control until the
		# field clears the target on arrival.
		var to_fire: Vector2 = _forced_target - global_position
		if to_fire.length() > 1.0:
			move_dir = to_fire.normalized()
	else:
		# WASD 수동 조향: 누르는 동안 클릭 명령·자동 사냥보다 우선한다. 놓으면
		# 자동 이동이 그대로 복귀 — 키보드는 "세부 조절" 레이어다.
		var steer := Vector2(
			(1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0)
				- (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0),
			(1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
				- (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0))
		if steer != Vector2.ZERO:
			_engage_target = null  # manual steering cancels the standing click order
			move_dir = steer.normalized()
			_reset_idle_life()
		# Window-keeper: the hero hunts the CLICKED enemy (his collision opens the
		# window).
		elif is_instance_valid(_engage_target):
			_reset_idle_life()
			var to_e: Vector2 = (_engage_target as Node2D).global_position - global_position
			if to_e.length() > 1.0:
				move_dir = to_e.normalized()
		else:
			_engage_target = null
			if GameState.auto_move_unlocked:
				# 자동 사냥 upgrade (automation): the hero picks targets himself.
				var target := _find_nearest_in_group(&"field_enemy")
				if target == null:
					target = _find_nearest_in_group(&"field_pickup")
				if target != null:
					var to_target: Vector2 = target.global_position - global_position
					if to_target.length() > 0.01:
						move_dir = to_target.normalized()
			# No idle wander: the hero holds still until you point him at an enemy
			# (the wandering read as "is he doing something?" — too ambiguous).
			_reset_idle_life()
	velocity = move_dir * move_speed
	move_and_slide()
	global_position = Vector2(
		clampf(global_position.x, _field_bounds.position.x, _field_bounds.end.x),
		clampf(global_position.y, _field_bounds.position.y, _field_bounds.end.y)
	)
	# While downed, show the lying pose (idle frame) even if dragged along.
	# In battle formation, once settled, force the back-view (facing UP toward the
	# enemy windows) instead of the last walk direction.
	if _force_face_up and not _downed_visual and velocity.length_squared() < 1.0:
		_visual.face_dir(CharacterVisual.Dir.UP)
	elif _idle_face_point != Vector2.INF and not _downed_visual and velocity.length_squared() < 1.0:
		# Idle chat / fire-watching: stand still, look at the thing.
		_visual.set_velocity(Vector2.ZERO)
		_visual.face_dir(_facing_dir(_idle_face_point))
	else:
		_visual.set_velocity(Vector2.ZERO if _downed_visual else velocity)


## Drive the camera each frame. Fixed at the field center now — pan/follow removed.
func _update_camera_pan(_delta: float) -> void:
	# Camera is fixed at the field center now — no hero-follow, no keyboard/drag pan.
	if _camera == null:
		return
	_camera.global_position = _camera_world_center


## Re-attach the camera to the hero. Smoothing on so it glides back instead of
## snapping. Safe to call any time (party-box click, field-hero click, loop start).
func focus_camera_on_hero() -> void:
	# Fixed camera: re-park on the field center (kept for existing callers).
	if _camera:
		_camera.global_position = _camera_world_center


# ─── 서성임 (idle life) ─────────────────────────────────────────────────
## When nothing drives the hero — no input, no auto-seek target, no script —
## he putters around the spot: a step or two, a pause, sometimes turning to chat
## with a nearby member ("···") or strolling over to watch the campfire. Cozy.
const IDLE_MILL_RADIUS: float = 8.0
const IDLE_MILL_SPEED: float = 13.0
const IDLE_CHAT_RANGE: float = 26.0
const IDLE_FIRE_RANGE: float = 64.0
## Personal space while idling — 옹기종기 but a full sprite-width apart (no 야릇함).
const IDLE_SEPARATION: float = 18.0
## Small talk is an occasional treat, not a habit — per-member cooldown.
const CHAT_COOLDOWN_MIN_MS: int = 10000
const CHAT_COOLDOWN_MAX_MS: int = 22000
const IDLE_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

var _idle_anchor: Vector2 = Vector2.INF
var _idle_target: Vector2 = Vector2.INF
var _idle_wait: float = 0.0
var _idle_gaze_timer: float = 0.0
var _idle_face_point: Vector2 = Vector2.INF
var _idle_arrive_gaze: Vector2 = Vector2.INF
var _next_chat_msec: int = 0


func _tick_idle_life(delta: float) -> Vector2:
	if _idle_anchor == Vector2.INF:
		_idle_anchor = global_position
	if _idle_gaze_timer > 0.0:  # holding a look (fire / chat partner)
		_idle_gaze_timer -= delta
		if _idle_gaze_timer <= 0.0:
			_idle_face_point = Vector2.INF
			_idle_wait = randf_range(0.6, 1.6)
		return Vector2.ZERO
	if _idle_wait > 0.0:
		_idle_wait -= delta
		return Vector2.ZERO
	if _idle_target != Vector2.INF and global_position.distance_to(_idle_target) <= 1.5:
		_idle_target = Vector2.INF
		if _idle_arrive_gaze != Vector2.INF:  # walked over to the fire → watch it
			_idle_face_point = _idle_arrive_gaze
			_idle_arrive_gaze = Vector2.INF
			_idle_gaze_timer = randf_range(1.6, 3.2)
		else:
			_idle_wait = randf_range(0.9, 2.4)
		return Vector2.ZERO
	if _idle_target == Vector2.INF:
		_pick_idle_action()
		return Vector2.ZERO
	return (_idle_target - global_position).normalized()


func _pick_idle_action() -> void:
	# 겹침 방지 최우선: someone's standing in our pixels → step away first.
	var crowding: Node2D = _nearest_buddy_within(IDLE_SEPARATION)
	if crowding != null:
		var away: Vector2 = global_position - crowding.global_position
		if away.length_squared() < 0.5:
			away = Vector2.RIGHT.rotated(randf() * TAU)
		_idle_target = global_position + away.normalized() * randf_range(10.0, 14.0)
		return
	var roll: float = randf()
	# 모닥불 구경: the fire is close → wander over and watch it a while.
	if roll < 0.15 and GameState.campfire_placed \
			and _idle_anchor.distance_to(GameState.campfire_position) <= IDLE_FIRE_RANGE:
		_idle_target = _pick_clear_spot(GameState.campfire_position, 13.0, 19.0)
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
	# 그냥 서성: a couple of px around the anchor, with personal space.
	_idle_target = _pick_clear_spot(_idle_anchor, 2.0, IDLE_MILL_RADIUS)


func _reset_idle_life() -> void:
	_idle_anchor = Vector2.INF
	_idle_target = Vector2.INF
	_idle_wait = 0.0
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
	lbl.add_theme_font_override("font", IDLE_FONT)
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.position = Vector2(-7.0, -32.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var t := create_tween().set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - 5.0, 1.3)
	t.tween_property(lbl, "modulate:a", 0.0, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)


## Field shows this avatar lying down while its party member is downed/refilling.
func set_downed_visual(is_down: bool) -> void:
	_downed_visual = is_down
	if _visual:
		_visual.rotation = deg_to_rad(90.0) if is_down else 0.0
		_visual.modulate = Color(0.6, 0.6, 0.66, 1.0) if is_down else Color(1, 1, 1, 1)


## Linear scan over a node group, returning the nearest Node2D whose
## `is_auto_move_target()` (if present) is still true. Used for both the
## `field_enemy` and `field_pickup` groups; lists are small (≤30) so a per-
## frame walk is fine.
func _find_nearest_in_group(group: StringName) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist_sq: float = INF
	for node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node):
			continue
		if node.has_method("is_auto_move_target") and not node.is_auto_move_target():
			continue
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		var d: float = global_position.distance_squared_to(node_2d.global_position)
		if d < nearest_dist_sq:
			nearest_dist_sq = d
			nearest = node_2d
	return nearest


## Re-attach to the hero and cancel easing so the view snaps straight onto it
## (no glide). Kept so existing callers (Field on loop start) still work.
func snap_camera() -> void:
	# Fixed camera: snap onto the field center.
	if _camera:
		_camera.position_smoothing_enabled = false
		_camera.global_position = _camera_world_center
		_free_camera_pos = _camera.global_position
		_camera.reset_smoothing()


## Re-center the view on the hero (leaves free-look, snaps on). Called by the Field
## on each loop start. Param kept for call-site compatibility.
func recenter_camera(_world_center: Vector2 = Vector2.ZERO) -> void:
	snap_camera()


## Quick decaying screen shake. Tweens the camera offset (separate from the
## smoothed follow position) so it always returns cleanly to zero. Runs even
## while the field is battle-paused since tweens ignore our pause flag.
func shake_camera(strength: float = 4.0, duration: float = 0.25) -> void:
	if _camera == null:
		return
	if _camera_shake_tween and _camera_shake_tween.is_valid():
		_camera_shake_tween.kill()
	_camera_shake_tween = create_tween()
	var steps: int = 6
	var step_time: float = duration / float(steps)
	for i in steps:
		var falloff: float = 1.0 - float(i) / float(steps)
		var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * falloff
		_camera_shake_tween.tween_property(_camera, "offset", offset, step_time)\
			.set_trans(Tween.TRANS_SINE)
	_camera_shake_tween.tween_property(_camera, "offset", Vector2.ZERO, step_time)
