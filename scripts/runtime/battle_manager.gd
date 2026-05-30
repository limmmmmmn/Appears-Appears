class_name BattleManager
extends Node2D

## Spawns BattleWindows on enemy_encountered, then lets them drift away from
## overlapping windows or the player and settle into their world position.
## Battle windows live on the field, so the camera can move away from them.

const BATTLE_WINDOW_SCENE: PackedScene = preload("res://scenes/battle_window.tscn")
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

## Fallback if no valid player-relative spawn point exists.
const SPAWN_CENTER_OFFSET: Vector2 = Vector2(-64, -48)

const SLOT_MARGIN: float = 2.0
const SPAWN_DISTANCE: float = 52.0
const WINDOW_PUSH_PADDING: float = 10.0
const WINDOW_PUSH_STRENGTH: float = 260.0
const PARTY_COLLISION_SIZE: Vector2 = Vector2(18.0, 24.0)
const PARTY_COLLISION_STRENGTH: float = 1800.0
const ORC_WINDOW_PUSH_MULTIPLIER: float = 0.35
const ORC_WINDOW_DRAG_SPEED_MULTIPLIER: float = 0.45
const ORC_WINDOW_DRAG_DURATION: float = 0.12
const VELOCITY_DAMPING: float = 4.6
const MAX_WINDOW_SPEED: float = 180.0
const SETTLE_SPEED: float = 10.0
const SETTLE_INTERVAL: float = 0.08
const WINDOW_COLLISION_DAMAGE_COOLDOWN: float = 0.85
const PARTY_COLLISION_DAMAGE_COOLDOWN: float = 0.45
const MODAL_WINDOW_SIZE_MULTIPLIER: float = 1.0
## Width of the left dock. The play area is inset by this on the left so battle
## windows never spawn/drift underneath it.
const LEFT_BAR_WIDTH: float = 46.0


## Play area right edge = viewport minus the right panel. Read at runtime from
## UITheme so narrowing the panel automatically widens the field.
func _play_area_right_edge() -> float:
	return 640.0 - UITheme.RIGHT_PANEL_WIDTH

var _window_rects: Dictionary = {}  ## BattleWindow -> Rect2 target it took
var _window_velocities: Dictionary = {}  ## BattleWindow -> Vector2 world velocity.
## Tracks the last-broadcast chest-buffer-full state (System 2) to avoid
## re-emitting chest_buffer_full_changed every frame.
var _chest_buffer_full: bool = false
var _modal_windows: Dictionary = {}  ## BattleWindow -> true for pre-movement modal battles.
var _collision_cooldowns: Dictionary = {}  ## window pair key -> remaining seconds.
var _party_collision_cooldowns: Dictionary = {}  ## battle window id -> remaining seconds.
var _settle_timer: float = 0.0


func _ready() -> void:
	# GameState.can_accept_new_battle_window() looks us up by group to read
	# active_window_count() against the multi-window cap.
	add_to_group("battle_manager")
	EventBus.enemy_encountered.connect(_on_enemy_encountered)
	EventBus.combo_attack_damage_requested.connect(_on_combo_attack_damage_requested)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)
	EventBus.battle_window_resolved.connect(_on_battle_window_resolved)
	EventBus.party_wiped.connect(_on_party_wiped)


func _process(delta: float) -> void:
	# Drive the downed → refill → auto-stand cycle every frame (runs even between
	# fights so knocked-out members always recover). No passive regen otherwise.
	GameState.tick_downed_recovery(delta)
	if _window_rects.is_empty():
		return
	_settle_timer += delta
	_tick_collision_cooldowns(delta)
	_tick_party_collision_cooldowns(delta)
	_apply_window_push(delta)


## How many battle windows the cap should treat as "fighting right now".
## Excludes chest windows (reward boxes) since their fight is over — they just
## linger until the player hovers them open.
func active_window_count() -> int:
	var count: int = 0
	for window in _window_rects.keys():
		if not is_instance_valid(window):
			continue
		if window.has_method("is_chest_active") and window.is_chest_active():
			continue
		count += 1
	return count


## How many unopened reward chests are currently lingering (System 2 buffer).
func chest_window_count() -> int:
	var count: int = 0
	for window in _window_rects.keys():
		if not is_instance_valid(window):
			continue
		if window.has_method("is_chest_active") and window.is_chest_active():
			count += 1
	return count


## Recompute the chest buffer and broadcast full/not-full transitions so the HUD
## can show/hide the "상자 가득! 열어주세요" banner. Cheap; called on chest
## create/close.
func _update_chest_buffer_state() -> void:
	var is_full: bool = chest_window_count() >= Balance.CHEST_BUFFER_MAX
	if is_full == _chest_buffer_full:
		return
	_chest_buffer_full = is_full
	EventBus.chest_buffer_full_changed.emit(is_full)


## Fight inside `window` just ended (window is becoming a chest). Release the
## modal-battle pause (if applicable) so the player can move again, and clear
## it from `_modal_windows` so the eventual `_on_battle_window_closed` doesn't
## try to release the same pause a second time.
func _on_battle_window_resolved(window: Node) -> void:
	if _modal_windows.has(window):
		_modal_windows.erase(window)
		GameState.end_field_battle_pause()
	# A new chest just appeared — it counts toward the anti-idle buffer.
	_update_chest_buffer_state()


# ─── Spawning ─────────────────────────────────────────────────────────
func _on_enemy_encountered(field_enemy: Node) -> void:
	if GameState.is_party_wiped() or not is_instance_valid(field_enemy):
		return
	var data: EnemyData = field_enemy.data
	if data == null:
		return
	var source := field_enemy as Node2D
	var is_combo_encounter: bool = bool(field_enemy.get_meta("combo_encounter", false))
	var is_modal_battle: bool = not is_combo_encounter and not GameState.battle_movement_unlocked()
	var window: BattleWindow = spawn_battle(data, source, is_modal_battle, is_combo_encounter)
	if is_combo_encounter and window:
		window.set_meta("combo_batch_id", int(field_enemy.get_meta("combo_batch_id", 0)))


func _on_combo_attack_damage_requested(damage_ratio: float, combo_batch_id: int) -> void:
	if damage_ratio <= 0.0 or combo_batch_id <= 0:
		return
	for window: BattleWindow in _window_rects.keys():
		if is_instance_valid(window) and int(window.get_meta("combo_batch_id", 0)) == combo_batch_id:
			window.apply_window_collision_damage(damage_ratio, "Combo attack")


## Public API. Used by enemy_encountered handler and debug helpers.
func spawn_battle(data: EnemyData, source: Node2D = null, is_modal_battle: bool = false, at_source_position: bool = false) -> BattleWindow:
	return _spawn_window(data, source, is_modal_battle, at_source_position)


func _spawn_window(data: EnemyData, source: Node2D = null, is_modal_battle: bool = false, at_source_position: bool = false) -> BattleWindow:
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	var field_drop_position: Vector2 = source.global_position if source != null and is_instance_valid(source) else Vector2.INF
	window.setup(data, field_drop_position, MODAL_WINDOW_SIZE_MULTIPLIER if is_modal_battle else 1.0)
	var window_size: Vector2 = window.get_expected_window_size()
	# Modal (pre-multi-window-unlock) spawns at the meeting point of the party
	# member and the enemy so the popup hides both. Drift mode keeps the
	# directional offset-from-player layout.
	var spawn_position: Vector2 = _encounter_midpoint_position(window_size, source) if is_modal_battle else _spawn_position_for_encounter(window_size, source, at_source_position)
	# Encounter / midpoint spawns near the play-area edge can otherwise pop a
	# window half off screen. Clamp to the visible play area.
	spawn_position = _clamp_position_to_play_area(spawn_position, window_size)
	window.position = spawn_position
	_window_rects[window] = Rect2(spawn_position, window_size)
	_window_velocities[window] = Vector2.ZERO
	if is_modal_battle:
		_modal_windows[window] = true
		GameState.begin_field_battle_pause()
	add_child(window)
	window.play_open_intro()
	if not is_modal_battle:
		_apply_window_push(0.0, true)
	return window


func _centered_modal_position(window_size: Vector2) -> Vector2:
	var visible_rect: Rect2 = _play_area_visible_world_rect()
	return visible_rect.get_center() - window_size * 0.5


## Pre-multi-window-unlock modal spawn: cover the spot where the party member
## and the field enemy actually met (midpoint of their world positions). Both
## characters are tiny (~16px) and the window is ~128×96, so anchoring on the
## midpoint reliably hides both behind the popup.
func _encounter_midpoint_position(window_size: Vector2, source: Node2D) -> Vector2:
	if source == null or not is_instance_valid(source):
		return _centered_modal_position(window_size)
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return source.global_position - window_size * 0.5
	var midpoint: Vector2 = (player_position + source.global_position) * 0.5
	return midpoint - window_size * 0.5


# ─── Window drift ─────────────────────────────────────────────────────
func _spawn_position_for_encounter(window_size: Vector2, source: Node2D, at_source_position: bool = false) -> Vector2:
	if source == null or not is_instance_valid(source):
		return _random_spawn_position(window_size)
	if at_source_position:
		return source.global_position - window_size * 0.5
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return _play_area_visible_world_rect().get_center() + SPAWN_CENTER_OFFSET
	var source_position: Vector2 = source.global_position
	var direction: Vector2 = source_position - player_position
	if direction.length_squared() < 1.0:
		return _random_spawn_position(window_size)
	direction = direction.normalized()
	var half_extent: float = absf(direction.x) * window_size.x * 0.5 + absf(direction.y) * window_size.y * 0.5
	var center: Vector2 = player_position + direction * (SPAWN_DISTANCE + half_extent)
	return center - window_size * 0.5


func _random_spawn_position(window_size: Vector2) -> Vector2:
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return _play_area_visible_world_rect().get_center() + SPAWN_CENTER_OFFSET
	var candidates: Array[Vector2] = [
		player_position + Vector2(-window_size.x * 0.5, -SPAWN_DISTANCE - window_size.y),
		player_position + Vector2(-window_size.x * 0.5, SPAWN_DISTANCE),
		player_position + Vector2(-SPAWN_DISTANCE - window_size.x, -window_size.y * 0.5),
		player_position + Vector2(SPAWN_DISTANCE, -window_size.y * 0.5),
	]
	candidates.shuffle()
	for candidate: Vector2 in candidates:
		if _is_spawn_position_valid(candidate, window_size):
			return candidate
	return candidates.front()


func _is_spawn_position_valid(pos: Vector2, size: Vector2) -> bool:
	var field_rect: Rect2 = _field_rect()
	return (
		pos.x >= field_rect.position.x + SLOT_MARGIN
		and pos.y >= field_rect.position.y + SLOT_MARGIN
		and pos.x + size.x <= field_rect.end.x - SLOT_MARGIN
		and pos.y + size.y <= field_rect.end.y - SLOT_MARGIN
	)


func _apply_window_push(delta: float, burst: bool = false) -> void:
	var party_positions: Array[Vector2] = _party_world_positions()
	var window_collision_enabled: bool = GameState.battle_window_push_enabled()
	var party_collision_enabled: bool = GameState.party_window_push_enabled()
	var windows: Array = _window_rects.keys()
	for window: BattleWindow in windows:
		if not is_instance_valid(window):
			continue
		if _modal_windows.has(window):
			continue
		if window.is_opening():
			continue
		# Chests freeze in place so the hover-to-open gauge isn't fighting a
		# drifting target. Zero velocity too in case something already
		# accumulated before the transition.
		if window.has_method("is_chest_active") and window.is_chest_active():
			_window_velocities[window] = Vector2.ZERO
			continue
		_window_rects[window] = _window_rect(window)
		var force := Vector2.ZERO
		var rect: Rect2 = _window_rects[window]
		for other: BattleWindow in windows:
			if window == other or not is_instance_valid(other):
				continue
			if window_collision_enabled:
				if window.get_instance_id() < other.get_instance_id():
					_apply_window_collision_damage(window, rect, other, _window_rects[other])
				force += _window_overlap_push(window, rect, other, _window_rects[other])
		if party_collision_enabled:
			for party_position: Vector2 in party_positions:
				var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
				if rect.intersects(party_rect):
					_apply_party_collision_effects(window)
					_apply_party_drag_effects(window)
				force += _party_collision_push(rect, party_position)
		force *= _window_push_multiplier(window)
		var velocity: Vector2 = _window_velocities.get(window, Vector2.ZERO)
		var step_delta: float = 1.0 / 60.0 if burst else delta
		velocity += force * step_delta
		velocity = velocity.limit_length(MAX_WINDOW_SPEED)
		velocity = velocity.move_toward(Vector2.ZERO, VELOCITY_DAMPING * velocity.length() * step_delta)
		var next_position: Vector2 = window.position + velocity * step_delta
		# Camera is fixed → keep windows inside the visible play area. On hit
		# we damp the perpendicular velocity component so the window settles
		# against the wall with a tiny cute bounce instead of vibrating.
		var clamped_position: Vector2 = _clamp_position_to_play_area(next_position, rect.size)
		if not is_equal_approx(clamped_position.x, next_position.x):
			velocity.x = -velocity.x * 0.3
		if not is_equal_approx(clamped_position.y, next_position.y):
			velocity.y = -velocity.y * 0.3
		next_position = clamped_position
		_window_velocities[window] = velocity
		_window_rects[window] = Rect2(next_position, rect.size)
		if burst or velocity.length() >= SETTLE_SPEED:
			window.push_to(next_position)
		elif _settle_timer >= SETTLE_INTERVAL:
			window.settle_to(next_position)
	if _settle_timer >= SETTLE_INTERVAL:
		_settle_timer = 0.0


func _window_overlap_push(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> Vector2:
	var padded := Rect2(rect.position - Vector2.ONE * WINDOW_PUSH_PADDING, rect.size + Vector2.ONE * WINDOW_PUSH_PADDING * 2.0)
	var other_padded := Rect2(other.position - Vector2.ONE * WINDOW_PUSH_PADDING, other.size + Vector2.ONE * WINDOW_PUSH_PADDING * 2.0)
	if not padded.intersects(other_padded):
		return Vector2.ZERO
	var delta: Vector2 = padded.get_center() - other_padded.get_center()
	if delta == Vector2.ZERO:
		delta = _stable_separation_direction(window, other_window)
	var overlap_x: float = minf(padded.end.x, other_padded.end.x) - maxf(padded.position.x, other_padded.position.x)
	var overlap_y: float = minf(padded.end.y, other_padded.end.y) - maxf(padded.position.y, other_padded.position.y)
	var push: float = maxf(0.0, minf(overlap_x, overlap_y))
	return delta.normalized() * push * WINDOW_PUSH_STRENGTH


func _window_rect(window: BattleWindow) -> Rect2:
	var size: Vector2 = _window_rects.get(window, Rect2(window.position, window.get_expected_window_size())).size
	return Rect2(window.position, size)


func _window_push_multiplier(window: BattleWindow) -> float:
	if window.has_living_enemy_id(&"orc"):
		return ORC_WINDOW_PUSH_MULTIPLIER
	return 1.0


func _apply_party_drag_effects(window: BattleWindow) -> void:
	if window.has_living_enemy_id(&"orc"):
		GameState.apply_move_speed_drag(ORC_WINDOW_DRAG_SPEED_MULTIPLIER, ORC_WINDOW_DRAG_DURATION)


func _apply_window_collision_damage(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> void:
	var damage_ratio: float = GameState.window_collision_damage_ratio()
	if damage_ratio <= 0.0:
		return
	if not rect.intersects(other):
		return
	var key: String = _collision_pair_key(window, other_window)
	if float(_collision_cooldowns.get(key, 0.0)) > 0.0:
		return
	# Ambient window-vs-window crash — damage number / flash only, no log line.
	var dealt: int = window.apply_window_collision_damage(damage_ratio, "Window crash", true)
	dealt += other_window.apply_window_collision_damage(damage_ratio, "Window crash", true)
	if dealt > 0:
		_collision_cooldowns[key] = WINDOW_COLLISION_DAMAGE_COOLDOWN


func _apply_party_collision_effects(window: BattleWindow) -> void:
	var damage_ratio: float = GameState.party_bump_damage_ratio()
	var heal_amount: int = GameState.window_collision_heal_amount()
	if damage_ratio <= 0.0 and heal_amount <= 0:
		return
	var key: String = str(window.get_instance_id())
	if float(_party_collision_cooldowns.get(key, 0.0)) > 0.0:
		return
	var dealt: int = 0
	var counter_damage_ratio: float = 0.0
	if damage_ratio > 0.0:
		counter_damage_ratio = window.party_bump_counter_damage_ratio()
		# Party shoving the window — same silent treatment as window crashes.
		dealt = window.apply_window_collision_damage(damage_ratio, "Bump attack", true)
	var healed: int = 0
	if heal_amount > 0:
		healed = _apply_party_collision_heal(window, heal_amount)
	var countered: int = 0
	if dealt > 0 and counter_damage_ratio > 0.0:
		countered = _apply_party_bump_counter_damage(window, counter_damage_ratio)
	if dealt > 0 or healed > 0 or countered > 0:
		_party_collision_cooldowns[key] = PARTY_COLLISION_DAMAGE_COOLDOWN


func _apply_party_bump_counter_damage(window: BattleWindow, ratio: float) -> int:
	var total_dealt: int = 0
	for i in GameState.party_size():
		if not GameState.is_alive(i):
			continue
		var amount: int = maxi(1, ceili(float(GameState.effective_max_hp(i)) * ratio))
		var before_hp: int = GameState.party_hp[i]
		GameState.damage_party_member(i, amount)
		var dealt: int = before_hp - GameState.party_hp[i]
		if dealt <= 0:
			continue
		total_dealt += dealt
		_spawn_party_damage_number(i, dealt)
	if total_dealt > 0:
		window.show_party_bump_counter_damage(total_dealt, ratio)
	return total_dealt


func _apply_party_collision_heal(window: BattleWindow, amount: int) -> int:
	var target_index: int = _lowest_wounded_party_index()
	if target_index == -1:
		return 0
	var before_hp: int = GameState.party_hp[target_index]
	GameState.heal_party_member(target_index, amount)
	var healed: int = GameState.party_hp[target_index] - before_hp
	if healed > 0:
		var member_name: String = GameState.party[target_index].display_name
		_spawn_party_heal_number(target_index, healed)
		window.show_window_collision_heal(member_name, healed)
	return healed


func _spawn_party_damage_number(party_index: int, amount: int) -> void:
	var target: Node2D = _party_member_node_for_index(party_index)
	if target == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	target.add_child(num)
	num.position = Vector2(randf_range(-5.0, 5.0), -18.0 + randf_range(-2.0, 2.0))
	num.z_index = 30
	num.setup_text("-%d" % amount, Color(1.0, 0.28, 0.18, 1.0))


func _spawn_party_heal_number(party_index: int, amount: int) -> void:
	var target: Node2D = _party_member_node_for_index(party_index)
	if target == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	target.add_child(num)
	num.position = Vector2(randf_range(-5.0, 5.0), -18.0 + randf_range(-2.0, 2.0))
	num.z_index = 30
	num.setup_heal(amount)


func _party_member_node_for_index(party_index: int) -> Node2D:
	if party_index < 0:
		return null
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return _party_member_node_from_group(party_index)
	if party_index == 0:
		return player
	var party_root: Node = player.get_parent()
	if party_root == null:
		return _party_member_node_from_group(party_index)
	var current_index: int = 0
	for child in party_root.get_children():
		if child is Node2D and child.is_in_group("party_member"):
			if current_index == party_index:
				return child as Node2D
			current_index += 1
	return _party_member_node_from_group(party_index)


func _party_member_node_from_group(party_index: int) -> Node2D:
	var current_index: int = 0
	for node in get_tree().get_nodes_in_group("party_member"):
		var member := node as Node2D
		if member == null:
			continue
		if current_index == party_index:
			return member
		current_index += 1
	return null


func _lowest_wounded_party_index() -> int:
	var best_index: int = -1
	var best_ratio: float = 1.1
	for i in GameState.party_size():
		if not GameState.is_alive(i):
			continue
		var max_hp: int = GameState.effective_max_hp(i)
		if max_hp <= 0 or GameState.party_hp[i] >= max_hp:
			continue
		var ratio: float = float(GameState.party_hp[i]) / float(max_hp)
		if ratio < best_ratio:
			best_ratio = ratio
			best_index = i
	return best_index


func _collision_pair_key(window: BattleWindow, other_window: BattleWindow) -> String:
	var a: int = int(window.get_instance_id())
	var b: int = int(other_window.get_instance_id())
	if a > b:
		var temp: int = a
		a = b
		b = temp
	return "%d:%d" % [a, b]


func _tick_collision_cooldowns(delta: float) -> void:
	for key: String in _collision_cooldowns.keys():
		var remaining: float = float(_collision_cooldowns[key]) - delta
		if remaining <= 0.0:
			_collision_cooldowns.erase(key)
		else:
			_collision_cooldowns[key] = remaining


func _tick_party_collision_cooldowns(delta: float) -> void:
	for key: String in _party_collision_cooldowns.keys():
		var remaining: float = float(_party_collision_cooldowns[key]) - delta
		if remaining <= 0.0:
			_party_collision_cooldowns.erase(key)
		else:
			_party_collision_cooldowns[key] = remaining


func _stable_separation_direction(window: BattleWindow, other_window: BattleWindow) -> Vector2:
	var pair_hash: int = int(window.get_instance_id() + other_window.get_instance_id())
	var angle: float = float(pair_hash % 360) * TAU / 360.0
	var direction := Vector2(cos(angle), sin(angle))
	if window.get_instance_id() < other_window.get_instance_id():
		return direction
	return -direction


func _party_collision_push(rect: Rect2, party_position: Vector2) -> Vector2:
	var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
	if not rect.intersects(party_rect):
		return Vector2.ZERO
	var delta: Vector2 = rect.get_center() - party_position
	if delta == Vector2.ZERO:
		delta = Vector2.UP
	var overlap_x: float = minf(rect.end.x, party_rect.end.x) - maxf(rect.position.x, party_rect.position.x)
	var overlap_y: float = minf(rect.end.y, party_rect.end.y) - maxf(rect.position.y, party_rect.position.y)
	var penetration: float = maxf(1.0, minf(overlap_x, overlap_y))
	return delta.normalized() * penetration * PARTY_COLLISION_STRENGTH


func _field_rect() -> Rect2:
	var field := get_node_or_null("../Field")
	if field and field.has_method("get_field_rect"):
		return field.get_field_rect()
	return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)


func _visible_world_rect() -> Rect2:
	var camera := get_viewport().get_camera_2d()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if camera == null:
		return Rect2(Vector2.ZERO, viewport_size)
	return Rect2(camera.get_screen_center_position() - viewport_size * 0.5, viewport_size)


func _play_area_visible_world_rect() -> Rect2:
	var camera := get_viewport().get_camera_2d()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# Usable width = viewport minus the right shop panel minus the left dock.
	var play_width: float = minf(viewport_size.x, _play_area_right_edge()) - LEFT_BAR_WIDTH
	var play_size := Vector2(maxf(1.0, play_width), viewport_size.y)
	if camera == null:
		return Rect2(Vector2(LEFT_BAR_WIDTH, 0.0), play_size)
	var visible_size: Vector2 = viewport_size * camera.zoom
	var play_world_size: Vector2 = play_size * camera.zoom
	var origin: Vector2 = camera.get_screen_center_position() - visible_size * 0.5
	origin.x += LEFT_BAR_WIDTH * camera.zoom.x
	return Rect2(origin, play_world_size)


## Clamp a window's top-left so the whole rect stays inside the visible play
## area (camera viewport minus the right-hand HUD panel). Used both at spawn
## time and inside the drift loop so neither force can shove a window off
## screen.
func _clamp_position_to_play_area(pos: Vector2, window_size: Vector2) -> Vector2:
	var bounds: Rect2 = _play_area_visible_world_rect()
	var max_x: float = maxf(bounds.position.x, bounds.end.x - window_size.x)
	var max_y: float = maxf(bounds.position.y, bounds.end.y - window_size.y)
	return Vector2(
		clampf(pos.x, bounds.position.x, max_x),
		clampf(pos.y, bounds.position.y, max_y)
	)


func _player_world_position() -> Vector2:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node2D:
		return Vector2.INF
	return (players[0] as Node2D).global_position


func _party_world_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for member: Node in get_tree().get_nodes_in_group("party_member"):
		if member is Node2D:
			positions.append((member as Node2D).global_position)
	return positions


func _on_battle_window_closed(window: Node) -> void:
	if not _window_rects.has(window):
		return
	_window_rects.erase(window)
	_window_velocities.erase(window)
	if _modal_windows.has(window):
		_modal_windows.erase(window)
		GameState.end_field_battle_pause()
	var battle_window := window as BattleWindow
	if battle_window:
		var xp_reward: int = battle_window.claim_xp_reward()
		if xp_reward > 0:
			GameState.add_party_xp(xp_reward)
		# Gold and items no longer drop onto the field — the chest reveal
		# inside the window applies them directly to GameState before close.
		# _drop_gold_from_window / _drop_items_from_window kept for now in
		# case we want to bring back optional field drops via a skill node.
	# Tell anyone who cares (Field, etc.) when the last fight ends. This is
	# the gate Field uses before declaring field_loop_settled — Echo Strike means
	# the *first* window closing is rarely the last one.
	if _window_rects.is_empty():
		EventBus.all_battles_resolved.emit()
	# A chest may have just been opened/removed — re-open the production gate.
	_update_chest_buffer_state()


func _drop_gold_from_window(window: BattleWindow) -> void:
	var amount: int = window.claim_gold_drops()
	if amount <= 0:
		return
	var base_pos: Vector2 = _drop_base_position(window)
	for i in amount:
		var angle: float = TAU * float(i) / float(maxi(1, amount))
		var radius: float = 10.0 if amount > 1 else 0.0
		EventBus.field_gold_drop_requested.emit(1, base_pos + Vector2(cos(angle), sin(angle)) * radius)


func _drop_items_from_window(window: BattleWindow) -> void:
	var drops: Array[ItemData] = window.claim_item_drops()
	if drops.is_empty():
		return
	var base_pos: Vector2 = _drop_base_position(window)
	for i in drops.size():
		var angle: float = TAU * float(i) / float(maxi(1, drops.size()))
		var radius: float = 10.0 if drops.size() > 1 else 0.0
		EventBus.field_item_drop_requested.emit(drops[i], base_pos + Vector2(cos(angle), sin(angle)) * radius)


func _drop_base_position(window: BattleWindow) -> Vector2:
	var base_pos: Vector2 = window.field_drop_position()
	if base_pos == Vector2.INF:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		base_pos = player.global_position if player else Vector2.ZERO
	return base_pos


# ─── Run-over cleanup ─────────────────────────────────────────────────
func _on_party_wiped() -> void:
	abort_all_battles()


## Force-close every active battle window. No gold, no signals, no log —
## the run is dead. Used on party_wipe and (later) explicit run resets.
func abort_all_battles() -> void:
	for window: Node in _window_rects.keys():
		if is_instance_valid(window):
			window.queue_free()
		if _modal_windows.has(window):
			GameState.end_field_battle_pause()
	_window_rects.clear()
	_window_velocities.clear()
	_modal_windows.clear()
	_collision_cooldowns.clear()
	_party_collision_cooldowns.clear()
