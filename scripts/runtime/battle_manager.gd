class_name BattleManager
extends CanvasLayer

## Spawns BattleWindows on enemy_encountered, then lets them drift away from
## overlapping windows or the player and settle into their new world position.
##
## CanvasLayer base = screen-space rendering, but the manager keeps each
## BattleWindow anchored to a world-space rect. The screen position is derived
## from the active camera every frame, while physics stays in field space.

const BATTLE_WINDOW_SCENE: PackedScene = preload("res://scenes/battle_window.tscn")
const MANUAL_BATTLE_SCENE: PackedScene = preload("res://scenes/manual_battle.tscn")
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

## Fallback if no valid player-relative spawn point exists.
const SPAWN_CENTER: Vector2 = Vector2(260, 56)

const SLOT_MARGIN: float = 2.0
const HUD_RESERVED_BOTTOM: float = 8.0
const SPAWN_DISTANCE: float = 52.0
const WINDOW_PUSH_STRENGTH: float = 260.0
const PARTY_COLLISION_SIZE: Vector2 = Vector2(18.0, 24.0)
const PARTY_COLLISION_STRENGTH: float = 1800.0
const WALL_PUSH_STRENGTH: float = 900.0
const ORC_WINDOW_PUSH_MULTIPLIER: float = 0.35
const ORC_WINDOW_DRAG_SPEED_MULTIPLIER: float = 0.45
const ORC_WINDOW_DRAG_DURATION: float = 0.12
const VELOCITY_DAMPING: float = 4.6
const MAX_WINDOW_SPEED: float = 180.0
const WINDOW_COLLISION_DAMAGE_COOLDOWN: float = 1.5
const PARTY_COLLISION_DAMAGE_COOLDOWN: float = 1.2
const SHOCKWAVE_RADIUS: float = 150.0
const SHOCKWAVE_COOLDOWN: float = 0.7
const SHOCKWAVE_BOOST_DURATION: float = 0.24
const SHOCKWAVE_MAX_WINDOW_SPEED: float = 560.0
const WINDOW_SPLIT_HANDLE_REVEAL_RADIUS: float = 62.0
const WINDOW_SPLIT_HANDLE_RADIUS: float = 12.0
const WINDOW_SPLIT_HANDLE_PUSH_SPEED: float = 18.0
const WINDOW_SPLIT_HANDLE_COOLDOWN: float = 0.45
const WINDOW_SPLIT_HOLD_DURATION: float = 0.70
const WINDOW_SPLIT_GAP: float = 12.0
const WINDOW_SPLIT_PUSH_SPEED: float = 95.0
const WINDOW_SPIN_PIN_RADIUS: float = 72.0
const WINDOW_SPIN_INITIAL_SPEED: float = 0.22
const WINDOW_SPIN_PARTY_IMPULSE: float = 0.78
const WINDOW_SPIN_WINDOW_IMPULSE: float = 0.62
const WINDOW_SPIN_EDGE_TRANSFER: float = 0.18
const WINDOW_SPIN_DAMPING: float = 0.46
const WINDOW_SPIN_GEAR_COUPLING: float = 0.18
const WINDOW_SPIN_CONTACT_MARGIN: float = 6.0
const WINDOW_SPIN_DAMAGE_MIN_SPEED: float = 2.35
const WINDOW_SPIN_DAMAGE_COOLDOWN: float = 0.48
const WINDOW_SPIN_MAX_ANGULAR_SPEED: float = 9.5
const PARTY_VELOCITY_MAX: float = 440.0
## Max total HP that bump_blessing can heal from a single window's lifetime.
## Prevents "infinite bump-heal" sustain via repeated collisions.
const BUMP_HEAL_PER_WINDOW_CAP: int = 8
const DROP_RING_RADIUS: float = 16.0
const DROP_RING_RADIUS_STEP: float = 7.0
const DROP_RING_SLOTS: int = 8

var _window_rects: Dictionary = {}  ## BattleWindow -> Rect2 world rect.
var _window_velocities: Dictionary = {}  ## BattleWindow -> Vector2 world velocity.
var _collision_cooldowns: Dictionary = {}  ## window pair key -> remaining seconds.
var _party_collision_cooldowns: Dictionary = {}  ## battle window id -> remaining seconds.
var _bump_heal_totals: Dictionary = {}  ## battle window id -> cumulative HP healed.
var _shockwave_boost_timers: Dictionary = {}  ## battle window id -> remaining boost seconds.
var _shockwave_cooldown: float = 0.0
var _spin_angular_velocities: Dictionary = {}  ## BattleWindow -> radians per second.
var _spin_collision_cooldowns: Dictionary = {}  ## window pair key -> remaining seconds.
var _spin_rewarded_windows: Dictionary = {}  ## battle window id -> rewards already paid while pinned.
var _split_handle_cooldowns: Dictionary = {}  ## battle window id -> remaining seconds.
var _split_pending_windows: Dictionary = {}  ## battle window id -> held split data.
var _party_previous_positions: Dictionary = {}  ## party member id -> previous world position.
var _party_velocities: Dictionary = {}  ## party member id -> smoothed world velocity.
var _all_battles_resolved_sent: bool = true
var _manual_battle: ManualBattle = null


func _ready() -> void:
	EventBus.enemy_encountered.connect(_on_enemy_encountered)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)
	EventBus.battle_window_enemy_attack_started.connect(_on_battle_window_enemy_attack_started)
	EventBus.party_wiped.connect(_on_party_wiped)


func _process(delta: float) -> void:
	_purge_invalid_window_references()
	_tick_collision_cooldowns(delta)
	_tick_party_collision_cooldowns(delta)
	_tick_shockwave_state(delta)
	_tick_window_spin_cooldowns(delta)
	_tick_split_handle_cooldowns(delta)
	_update_party_velocities(delta)
	if _window_rects.is_empty():
		return
	_apply_window_push(delta)
	_tick_window_spin(delta)
	_claim_finished_spin_windows()
	_emit_all_battles_resolved_if_no_live_fights()


func active_window_count() -> int:
	_purge_invalid_window_references()
	return _window_rects.size()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_SPACE:
			if _try_pin_window_spin() or _try_cast_shockwave():
				get_viewport().set_input_as_handled()


# ─── Spawning ─────────────────────────────────────────────────────────
func _on_enemy_encountered(field_enemy: Node) -> void:
	if GameState.is_party_wiped() or not is_instance_valid(field_enemy):
		return
	var data: EnemyData = field_enemy.data
	if data == null:
		return
	if GameState.is_manual_battle_mode():
		_open_manual_battle(data)
		return
	var source := field_enemy as Node2D
	var enemy_count: int = _encounter_enemy_count(field_enemy)
	spawn_battle(data, source, enemy_count)
	# Echo Strike & friends: roll for bonus duplicate windows.
	var extras: int = GameState.roll_window_duplicates()
	for i in extras:
		spawn_battle(data, source, enemy_count)


## Manual DQ1-style command screen. While open, GameState registers it
## so is_field_combat_locked() returns true — player/companions/field
## enemies freeze, but the field's _process keeps running so the stage
## timer and spawner still tick. Tree is NOT paused: the player should
## feel pressure during a slow manual fight.
## tree_exited handles both victory (battle_finished → queue_free) and
## defeat (party_wiped path also frees the window).
func _open_manual_battle(data: EnemyData) -> void:
	if _manual_battle != null and is_instance_valid(_manual_battle):
		return
	var window: ManualBattle = MANUAL_BATTLE_SCENE.instantiate()
	window.setup(data)
	window.tree_exited.connect(_on_manual_battle_closed)
	add_child(window)
	_manual_battle = window


func _on_manual_battle_closed() -> void:
	_manual_battle = null


## Public API. Used by enemy_encountered handler and debug helpers.
func spawn_battle(data: EnemyData, source: Node2D = null, enemy_count: int = 0) -> void:
	_spawn_window(data, source, enemy_count)


func _spawn_window(data: EnemyData, source: Node2D = null, enemy_count: int = 0) -> void:
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	var field_drop_position: Vector2 = source.global_position if source != null and is_instance_valid(source) else Vector2.INF
	window.setup(data, field_drop_position, enemy_count)
	var window_size: Vector2 = window.get_expected_window_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var spawn_position: Vector2 = _spawn_position_for_encounter(window_size, source, viewport_size)
	window.position = _world_to_screen_position(spawn_position, viewport_size)
	_window_rects[window] = Rect2(spawn_position, window_size)
	_window_velocities[window] = Vector2.ZERO
	_all_battles_resolved_sent = false
	add_child(window)
	_bring_window_to_front(window)
	_apply_window_push(0.0, true)


func _encounter_enemy_count(field_enemy: Node) -> int:
	if field_enemy is FieldEnemy:
		return (field_enemy as FieldEnemy).encounter_enemy_count()
	return 0


# ─── Window drift ─────────────────────────────────────────────────────
func _spawn_position_for_encounter(window_size: Vector2, source: Node2D, viewport_size: Vector2) -> Vector2:
	if not GameState.field_combat_movement_enabled():
		return _center_spawn_position(window_size, viewport_size)
	if source == null or not is_instance_valid(source):
		return _random_spawn_position(window_size, viewport_size)
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return _clamped_position(_screen_to_world_position(SPAWN_CENTER, viewport_size), window_size, viewport_size)
	var source_position: Vector2 = source.global_position
	var direction: Vector2 = source_position - player_position
	if direction.length_squared() < 1.0:
		return _random_spawn_position(window_size, viewport_size)
	direction = direction.normalized()
	var half_extent: float = absf(direction.x) * window_size.x * 0.5 + absf(direction.y) * window_size.y * 0.5
	var center: Vector2 = player_position + direction * (SPAWN_DISTANCE + half_extent)
	return _clamped_position(center - window_size * 0.5, window_size, viewport_size)


func _center_spawn_position(window_size: Vector2, viewport_size: Vector2) -> Vector2:
	var screen_top_left: Vector2 = (viewport_size - window_size) * 0.5
	return _clamped_position(_screen_to_world_position(screen_top_left, viewport_size), window_size, viewport_size)


func _random_spawn_position(window_size: Vector2, viewport_size: Vector2) -> Vector2:
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return _clamped_position(_screen_to_world_position(SPAWN_CENTER, viewport_size), window_size, viewport_size)
	var candidates: Array[Vector2] = [
		player_position + Vector2(-window_size.x * 0.5, -SPAWN_DISTANCE - window_size.y),
		player_position + Vector2(-window_size.x * 0.5, SPAWN_DISTANCE),
		player_position + Vector2(-SPAWN_DISTANCE - window_size.x, -window_size.y * 0.5),
		player_position + Vector2(SPAWN_DISTANCE, -window_size.y * 0.5),
	]
	candidates.shuffle()
	for candidate: Vector2 in candidates:
		if _is_spawn_position_valid(candidate, window_size, viewport_size):
			return candidate
	return _clamped_position(candidates.front(), window_size, viewport_size)


func _is_spawn_position_valid(pos: Vector2, size: Vector2, viewport_size: Vector2) -> bool:
	var bounds: Rect2 = _field_window_bounds(viewport_size)
	var margin_x: float = SLOT_MARGIN
	var margin_y: float = SLOT_MARGIN
	var play_bottom: float = bounds.end.y - HUD_RESERVED_BOTTOM
	return (
		pos.x >= bounds.position.x + margin_x
		and pos.y >= bounds.position.y + margin_y
		and pos.x + size.x <= bounds.end.x - margin_x
		and pos.y + size.y <= play_bottom
	)


func _apply_window_push(delta: float, burst: bool = false) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var party_bodies: Array[Dictionary] = _party_collision_bodies()
	var window_collision_enabled: bool = GameState.battle_window_push_enabled()
	var window_fusion_enabled: bool = GameState.window_fusion_enabled()
	var window_spin_active: bool = GameState.window_spin_enabled() or not _spin_angular_velocities.is_empty()
	var party_collision_enabled: bool = GameState.party_window_push_enabled()
	var windows: Array[BattleWindow] = _active_windows()
	for window: BattleWindow in windows:
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		var clamped_rect: Rect2 = _window_rects[window]
		if not _is_spin_pinned(window):
			clamped_rect.position = _clamped_position(clamped_rect.position, clamped_rect.size, viewport_size)
		_window_rects[window] = clamped_rect
	_update_window_split_handles(windows, party_bodies, 0.0 if burst else delta)
	for window: BattleWindow in windows:
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		var force := Vector2.ZERO
		var rect: Rect2 = _window_rects[window]
		var fused_this_window: bool = false
		for other: BattleWindow in windows:
			if window == other or not is_instance_valid(other) or not _window_rects.has(other):
				continue
			if window_collision_enabled or window_fusion_enabled or window_spin_active:
				if window.get_instance_id() < other.get_instance_id():
					if window_fusion_enabled and _apply_window_fusion(window, rect, other, _window_rects[other], viewport_size):
						fused_this_window = true
						break
					if window_collision_enabled:
						_apply_window_collision_damage(window, rect, other, _window_rects[other])
					if window_spin_active:
						if _window_spin_contacting(rect, _window_rects[other]):
							_apply_window_spin_contact_impulse(window, rect, other, _window_rects[other])
						_apply_window_spin_collision_damage(window, rect, other, _window_rects[other])
					if not is_instance_valid(window) or not is_instance_valid(other):
						break
				if window_collision_enabled and _window_rects.has(other):
					force += _window_overlap_push(window, rect, other, _window_rects[other])
		if fused_this_window:
			continue
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		if party_collision_enabled or window_spin_active:
			for party_body: Dictionary in party_bodies:
				var party_position: Vector2 = party_body.get("position", Vector2.ZERO)
				var party_velocity: Vector2 = party_body.get("velocity", Vector2.ZERO)
				var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
				if rect.intersects(party_rect):
					if party_collision_enabled:
						_apply_party_collision_effects(window)
					_apply_window_spin_party_impulse(window, rect, party_position, party_velocity)
					if not is_instance_valid(window) or not _window_rects.has(window):
						break
					_apply_party_drag_effects(window)
				if party_collision_enabled and not _is_spin_pinned(window):
					force += _party_collision_push(rect, party_position)
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		var bounce_enabled: bool = GameState.window_bounce_enabled()
		if not _is_spin_pinned(window) and (window_collision_enabled or window_fusion_enabled or party_collision_enabled or bounce_enabled):
			force += _wall_push(rect, viewport_size)
		var bounce_multiplier: float = GameState.window_bounce_multiplier()
		force *= _window_push_multiplier(window) * bounce_multiplier
		var velocity: Vector2 = _window_velocities.get(window, Vector2.ZERO)
		var step_delta: float = 1.0 / 60.0 if burst else delta
		if _is_spin_pinned(window):
			_window_velocities[window] = Vector2.ZERO
			_window_rects[window] = Rect2(rect.position, rect.size)
			window.push_to(_world_to_screen_position(rect.position, viewport_size))
			continue
		velocity += force * step_delta
		velocity = velocity.limit_length(_max_speed_for_window(window))
		velocity = velocity.move_toward(Vector2.ZERO, VELOCITY_DAMPING * velocity.length() * step_delta)
		var raw_next_position: Vector2 = rect.position + velocity * step_delta
		var next_position: Vector2 = _clamped_position(raw_next_position, rect.size, viewport_size)
		if bounce_enabled:
			velocity = _bounce_velocity_off_walls(velocity, raw_next_position, next_position)
		_window_velocities[window] = velocity
		_window_rects[window] = Rect2(next_position, rect.size)
		window.push_to(_world_to_screen_position(next_position, viewport_size))


func _active_windows() -> Array[BattleWindow]:
	var windows: Array[BattleWindow] = []
	for raw_window in _window_rects.keys():
		if not is_instance_valid(raw_window):
			_forget_window_reference(raw_window)
			continue
		var window := raw_window as BattleWindow
		if window == null:
			_forget_window_reference(raw_window)
			continue
		windows.append(window)
	return windows


func _purge_invalid_window_references() -> void:
	for raw_window in _window_rects.keys():
		if not is_instance_valid(raw_window):
			_forget_window_reference(raw_window)


func _forget_window_reference(window) -> void:
	_window_rects.erase(window)
	_window_velocities.erase(window)
	_spin_angular_velocities.erase(window)
	if is_instance_valid(window):
		var window_key: String = str(window.get_instance_id())
		if window.has_method("set_split_handles_visible"):
			window.set_split_handles_visible(false)
		_party_collision_cooldowns.erase(window_key)
		_bump_heal_totals.erase(window_key)
		_shockwave_boost_timers.erase(window_key)
		_spin_rewarded_windows.erase(window_key)
		_split_handle_cooldowns.erase(window_key)
		_split_pending_windows.erase(window_key)
		_erase_pair_cooldowns_for_window(window_key)


func _on_battle_window_enemy_attack_started(window: Node) -> void:
	var battle_window := window as BattleWindow
	if battle_window == null or not _window_rects.has(battle_window):
		return
	_bring_window_to_front(battle_window)


func _bring_window_to_front(window: BattleWindow) -> void:
	if not is_instance_valid(window) or window.get_parent() != self:
		return
	for raw_window in _window_rects.keys():
		var battle_window := raw_window as BattleWindow
		if battle_window != null and is_instance_valid(battle_window):
			battle_window.z_index = 0
	window.z_index = 1
	move_child(window, get_child_count() - 1)


func _window_overlap_push(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> Vector2:
	if not rect.intersects(other):
		return Vector2.ZERO
	var delta: Vector2 = rect.get_center() - other.get_center()
	if delta == Vector2.ZERO:
		delta = _stable_separation_direction(window, other_window)
	var overlap_x: float = minf(rect.end.x, other.end.x) - maxf(rect.position.x, other.position.x)
	var overlap_y: float = minf(rect.end.y, other.end.y) - maxf(rect.position.y, other.position.y)
	var push: float = maxf(0.0, minf(overlap_x, overlap_y))
	return delta.normalized() * push * WINDOW_PUSH_STRENGTH


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
	var dealt: int = 0
	if not _is_spin_pinned(window):
		dealt += window.apply_window_collision_damage(damage_ratio)
	if not _is_spin_pinned(other_window):
		dealt += other_window.apply_window_collision_damage(damage_ratio)
	if dealt > 0:
		_collision_cooldowns[key] = WINDOW_COLLISION_DAMAGE_COOLDOWN


func _apply_window_fusion(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2, viewport_size: Vector2) -> bool:
	if not rect.intersects(other):
		return false
	if _is_spin_pinned(window) or _is_spin_pinned(other_window):
		return false
	if not window.absorb_window(other_window):
		return false
	var merged_rect: Rect2 = rect.merge(other)
	var next_size: Vector2 = window.size
	var next_position: Vector2 = _clamped_position(merged_rect.get_center() - next_size * 0.5, next_size, viewport_size)
	var merged_velocity: Vector2 = (_window_velocities.get(window, Vector2.ZERO) + _window_velocities.get(other_window, Vector2.ZERO)) * 0.5
	_forget_window_reference(other_window)
	_window_rects[window] = Rect2(next_position, next_size)
	_window_velocities[window] = merged_velocity
	window.push_to(_world_to_screen_position(next_position, viewport_size))
	_bring_window_to_front(window)
	return true


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
		# Bump attack spreads its damage budget evenly across enemies in
		# the window. Window-on-window crashes still hit each target fully.
		dealt = window.apply_window_collision_damage(damage_ratio, "Bump attack", true)
	var healed: int = 0
	if heal_amount > 0:
		var already_healed: int = int(_bump_heal_totals.get(key, 0))
		var allowed: int = maxi(0, BUMP_HEAL_PER_WINDOW_CAP - already_healed)
		if allowed > 0:
			healed = _apply_party_collision_heal(window, mini(heal_amount, allowed))
			if healed > 0:
				_bump_heal_totals[key] = already_healed + healed
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


func _tick_shockwave_state(delta: float) -> void:
	_shockwave_cooldown = maxf(0.0, _shockwave_cooldown - delta)
	for key: String in _shockwave_boost_timers.keys():
		var remaining: float = float(_shockwave_boost_timers[key]) - delta
		if remaining <= 0.0:
			_shockwave_boost_timers.erase(key)
		else:
			_shockwave_boost_timers[key] = remaining


func _tick_window_spin_cooldowns(delta: float) -> void:
	for key: String in _spin_collision_cooldowns.keys():
		var remaining: float = float(_spin_collision_cooldowns[key]) - delta
		if remaining <= 0.0:
			_spin_collision_cooldowns.erase(key)
		else:
			_spin_collision_cooldowns[key] = remaining


func _tick_split_handle_cooldowns(delta: float) -> void:
	for key: String in _split_handle_cooldowns.keys():
		var remaining: float = float(_split_handle_cooldowns[key]) - delta
		if remaining <= 0.0:
			_split_handle_cooldowns.erase(key)
		else:
			_split_handle_cooldowns[key] = remaining


func _tick_window_spin(delta: float) -> void:
	for window: BattleWindow in _active_windows():
		if not _is_spin_pinned(window):
			continue
		var angular_velocity: float = float(_spin_angular_velocities.get(window, 0.0))
		if absf(angular_velocity) > 0.01:
			window.set_spin_angle(window.rotation + angular_velocity * delta)
			angular_velocity = lerpf(angular_velocity, 0.0, clampf(WINDOW_SPIN_DAMPING * delta, 0.0, 1.0))
			_spin_angular_velocities[window] = angular_velocity


func _update_window_split_handles(windows: Array[BattleWindow], party_bodies: Array[Dictionary], delta: float) -> void:
	if not GameState.window_split_enabled() or party_bodies.is_empty():
		_cancel_all_pending_window_splits()
		for window: BattleWindow in windows:
			if is_instance_valid(window):
				window.set_split_handles_visible(false)
		return
	for window: BattleWindow in windows:
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		var key: String = str(window.get_instance_id())
		var rect: Rect2 = _window_rects[window]
		if _split_pending_windows.has(key):
			window.set_split_handles_visible(false)
			_update_pending_window_split(window, rect, party_bodies, delta)
			continue
		if not _is_window_split_candidate(window):
			window.set_split_handles_visible(false)
			continue
		var near: bool = _party_near_split_handles(rect, party_bodies)
		window.set_split_handles_visible(near)
		if near:
			_try_split_window_from_handles(window, rect, party_bodies)


func _is_window_split_candidate(window: BattleWindow) -> bool:
	if not is_instance_valid(window) or not _window_rects.has(window) or _is_spin_pinned(window):
		return false
	if window.living_enemy_count() <= 1:
		return false
	var key: String = str(window.get_instance_id())
	if bool(_split_pending_windows.get(key, false)):
		return false
	return float(_split_handle_cooldowns.get(key, 0.0)) <= 0.0


func _party_near_split_handles(rect: Rect2, party_bodies: Array[Dictionary]) -> bool:
	for party_body: Dictionary in party_bodies:
		var party_position: Vector2 = party_body.get("position", Vector2.ZERO)
		if _distance_to_rect(party_position, rect) <= WINDOW_SPLIT_HANDLE_REVEAL_RADIUS:
			return true
	return false


func _try_split_window_from_handles(window: BattleWindow, rect: Rect2, party_bodies: Array[Dictionary]) -> bool:
	for handle: Dictionary in _split_handles_for_rect(rect):
		var handle_position: Vector2 = handle["position"]
		var normal: Vector2 = handle["normal"]
		var handle_rect := Rect2(
			handle_position - Vector2.ONE * WINDOW_SPLIT_HANDLE_RADIUS,
			Vector2.ONE * WINDOW_SPLIT_HANDLE_RADIUS * 2.0
		)
		for party_body: Dictionary in party_bodies:
			var party_position: Vector2 = party_body.get("position", Vector2.ZERO)
			var party_velocity: Vector2 = party_body.get("velocity", Vector2.ZERO)
			var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
			if not party_rect.intersects(handle_rect):
				continue
			if party_velocity.dot(-normal) < WINDOW_SPLIT_HANDLE_PUSH_SPEED:
				continue
			return _start_window_split_hold(window, normal)
	return false


func _split_handles_for_rect(rect: Rect2) -> Array[Dictionary]:
	return [
		{"position": rect.position + Vector2(rect.size.x * 0.5, 0.0), "normal": Vector2.UP},
		{"position": rect.position + Vector2(rect.size.x * 0.5, rect.size.y), "normal": Vector2.DOWN},
		{"position": rect.position + Vector2(0.0, rect.size.y * 0.5), "normal": Vector2.LEFT},
		{"position": rect.position + Vector2(rect.size.x, rect.size.y * 0.5), "normal": Vector2.RIGHT},
	]


func _split_axis_for_handle_normal(normal: Vector2) -> Vector2:
	if absf(normal.y) > absf(normal.x):
		return Vector2.RIGHT
	return Vector2.DOWN


func _start_window_split_hold(window: BattleWindow, handle_normal: Vector2) -> bool:
	if not _is_window_split_candidate(window):
		return false
	var key: String = str(window.get_instance_id())
	var split_direction: Vector2 = _split_axis_for_handle_normal(handle_normal)
	_split_pending_windows[key] = {
		"window": window,
		"normal": handle_normal,
		"direction": split_direction,
		"elapsed": 0.0,
	}
	_split_handle_cooldowns[key] = WINDOW_SPLIT_HANDLE_COOLDOWN
	window.set_split_handles_visible(false)
	window.play_window_split_stretch(split_direction)
	return true


func _update_pending_window_split(window: BattleWindow, rect: Rect2, party_bodies: Array[Dictionary], delta: float) -> void:
	var key: String = str(window.get_instance_id())
	var pending: Dictionary = _split_pending_windows.get(key, {})
	var handle_normal: Vector2 = pending.get("normal", Vector2.ZERO)
	if not _is_split_handle_still_pressed(rect, handle_normal, party_bodies):
		_cancel_pending_window_split(window, key)
		return
	var elapsed: float = float(pending.get("elapsed", 0.0)) + maxf(delta, 0.0)
	pending["elapsed"] = elapsed
	_split_pending_windows[key] = pending
	if elapsed < WINDOW_SPLIT_HOLD_DURATION:
		return
	var split_direction: Vector2 = pending.get("direction", _split_axis_for_handle_normal(handle_normal))
	_finish_window_split_hold(window, split_direction, key)


func _is_split_handle_still_pressed(rect: Rect2, handle_normal: Vector2, party_bodies: Array[Dictionary]) -> bool:
	var handle_rect: Rect2 = _split_handle_rect(rect, handle_normal)
	for party_body: Dictionary in party_bodies:
		var party_position: Vector2 = party_body.get("position", Vector2.ZERO)
		var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
		if party_rect.intersects(handle_rect):
			return true
	return false


func _split_handle_rect(rect: Rect2, handle_normal: Vector2) -> Rect2:
	var handle_position: Vector2 = rect.get_center()
	if handle_normal == Vector2.UP:
		handle_position = rect.position + Vector2(rect.size.x * 0.5, 0.0)
	elif handle_normal == Vector2.DOWN:
		handle_position = rect.position + Vector2(rect.size.x * 0.5, rect.size.y)
	elif handle_normal == Vector2.LEFT:
		handle_position = rect.position + Vector2(0.0, rect.size.y * 0.5)
	elif handle_normal == Vector2.RIGHT:
		handle_position = rect.position + Vector2(rect.size.x, rect.size.y * 0.5)
	return Rect2(
		handle_position - Vector2.ONE * WINDOW_SPLIT_HANDLE_RADIUS,
		Vector2.ONE * WINDOW_SPLIT_HANDLE_RADIUS * 2.0
	)


func _cancel_pending_window_split(window: BattleWindow, key: String) -> void:
	_split_pending_windows.erase(key)
	if is_instance_valid(window):
		window.cancel_window_split_stretch()
	_split_handle_cooldowns[key] = 0.12


func _cancel_all_pending_window_splits() -> void:
	for key: String in _split_pending_windows.keys():
		var pending: Dictionary = _split_pending_windows.get(key, {})
		var window := pending.get("window", null) as BattleWindow
		if window != null and is_instance_valid(window):
			window.cancel_window_split_stretch()
	_split_pending_windows.clear()


func _finish_window_split_hold(window: BattleWindow, split_direction: Vector2, key: String) -> void:
	if not is_instance_valid(window) or not _window_rects.has(window):
		_split_pending_windows.erase(key)
		return
	window.finish_window_split_stretch()
	var split_data: Array[EnemyData] = window.split_off_for_window_split()
	_split_pending_windows.erase(key)
	if split_data.is_empty():
		return
	_spawn_split_window(window, split_data, split_direction)


func _spawn_split_window(source: BattleWindow, split_data: Array[EnemyData], preferred_direction: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(source) or not _window_rects.has(source):
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var old_rect: Rect2 = _window_rects[source]
	var source_size: Vector2 = source.size
	var source_position: Vector2 = _clamped_position(old_rect.get_center() - source_size * 0.5, source_size, viewport_size)
	_window_rects[source] = Rect2(source_position, source_size)
	source.push_to(_world_to_screen_position(source_position, viewport_size))

	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	window.setup_with_enemy_list(split_data, source.field_drop_position())
	var window_size: Vector2 = window.get_expected_window_size()
	var split_direction: Vector2 = preferred_direction.normalized() if preferred_direction != Vector2.ZERO else _split_spawn_direction(old_rect)
	var new_position: Vector2 = _split_window_position(source_position, source_size, window_size, split_direction, viewport_size)
	window.position = _world_to_screen_position(new_position, viewport_size)
	_window_rects[window] = Rect2(new_position, window_size)
	_window_velocities[window] = split_direction * WINDOW_SPLIT_PUSH_SPEED
	_window_velocities[source] = -split_direction * WINDOW_SPLIT_PUSH_SPEED * 0.5
	_split_handle_cooldowns[str(window.get_instance_id())] = WINDOW_SPLIT_HANDLE_COOLDOWN
	_all_battles_resolved_sent = false
	add_child(window)
	_bring_window_to_front(window)


func _split_spawn_direction(source_rect: Rect2) -> Vector2:
	var origin: Vector2 = _party_world_center()
	if origin != Vector2.INF:
		var away: Vector2 = source_rect.get_center() - origin
		if away.length_squared() > 1.0:
			return away.normalized()
	var angle: float = float(int(source_rect.position.x + source_rect.position.y) % 360) * TAU / 360.0
	return Vector2(cos(angle), sin(angle))


func _split_window_position(source_position: Vector2, source_size: Vector2, window_size: Vector2, direction: Vector2, viewport_size: Vector2) -> Vector2:
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var primary_offset: Vector2 = direction.normalized() * (source_size.length() * 0.25 + window_size.length() * 0.25 + WINDOW_SPLIT_GAP)
	var candidates: Array[Vector2] = [
		source_position + primary_offset,
		source_position - primary_offset,
		source_position + Vector2(source_size.x + WINDOW_SPLIT_GAP, 0.0),
		source_position - Vector2(window_size.x + WINDOW_SPLIT_GAP, 0.0),
		source_position + Vector2(0.0, source_size.y + WINDOW_SPLIT_GAP),
		source_position - Vector2(0.0, window_size.y + WINDOW_SPLIT_GAP),
	]
	for candidate: Vector2 in candidates:
		var clamped: Vector2 = _clamped_position(candidate, window_size, viewport_size)
		if not Rect2(clamped, window_size).intersects(Rect2(source_position, source_size)):
			return clamped
	return _clamped_position(candidates.front(), window_size, viewport_size)


func _try_pin_window_spin() -> bool:
	if not GameState.window_spin_enabled() or _window_rects.is_empty():
		return false
	var origin: Vector2 = _party_world_center()
	if origin == Vector2.INF:
		return false
	var best_window: BattleWindow = null
	var best_distance: float = INF
	for window: BattleWindow in _active_windows():
		if not is_instance_valid(window) or not _window_rects.has(window) or _is_spin_pinned(window):
			continue
		var distance: float = _distance_to_rect(origin, _window_rects[window])
		if distance <= WINDOW_SPIN_PIN_RADIUS and distance < best_distance:
			best_window = window
			best_distance = distance
	if best_window == null:
		return false
	if not best_window.pin_window_spin():
		return false
	_spin_angular_velocities[best_window] = _pin_initial_spin(best_window)
	_spin_rewarded_windows.erase(str(best_window.get_instance_id()))
	_bring_window_to_front(best_window)
	return true


func _pin_initial_spin(window: BattleWindow) -> float:
	var origin: Vector2 = _party_world_center()
	if origin == Vector2.INF or not _window_rects.has(window):
		return 0.0
	var rect: Rect2 = _window_rects[window]
	var radius: Vector2 = _closest_point_on_rect(origin, rect) - rect.get_center()
	if radius.length_squared() < 1.0:
		radius = origin - rect.get_center()
	var tangent_speed: float = 0.0
	if radius.length_squared() > 1.0:
		var tangent: Vector2 = Vector2(-radius.y, radius.x).normalized()
		var bodies: Array[Dictionary] = _party_collision_bodies()
		for body: Dictionary in bodies:
			var velocity: Vector2 = body.get("velocity", Vector2.ZERO)
			tangent_speed += velocity.dot(tangent)
		tangent_speed /= maxf(1.0, float(bodies.size()))
	var natural_spin: float = tangent_speed / maxf(24.0, rect.size.length() * 0.5) * 0.35
	if absf(natural_spin) >= WINDOW_SPIN_INITIAL_SPEED:
		return clampf(natural_spin, -WINDOW_SPIN_MAX_ANGULAR_SPEED, WINDOW_SPIN_MAX_ANGULAR_SPEED)
	var sign: float = -1.0 if int(window.get_instance_id()) % 2 == 0 else 1.0
	return sign * WINDOW_SPIN_INITIAL_SPEED


func _distance_to_rect(point: Vector2, rect: Rect2) -> float:
	var closest: Vector2 = _closest_point_on_rect(point, rect)
	return point.distance_to(closest)


func _closest_point_on_rect(point: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)


func _rect_contact_point(rect: Rect2, other: Rect2) -> Vector2:
	var on_rect: Vector2 = _closest_point_on_rect(other.get_center(), rect)
	var on_other: Vector2 = _closest_point_on_rect(rect.get_center(), other)
	return (on_rect + on_other) * 0.5


func _spin_inertia_for_rect(rect: Rect2) -> float:
	var radius: float = maxf(12.0, rect.size.length() * 0.5)
	return radius * radius


func _is_spin_pinned(window: BattleWindow) -> bool:
	return window != null and is_instance_valid(window) and window.is_spin_pinned()


func _apply_window_spin_party_impulse(window: BattleWindow, rect: Rect2, party_position: Vector2, party_velocity: Vector2) -> void:
	if not _is_spin_pinned(window):
		return
	if party_velocity.length_squared() < 1.0:
		return
	var contact_point: Vector2 = _closest_point_on_rect(party_position, rect)
	var radius: Vector2 = contact_point - rect.get_center()
	if radius.length_squared() < 1.0:
		radius = party_position - rect.get_center()
	if radius.length_squared() < 1.0:
		return
	var normal: Vector2 = (party_position - contact_point).normalized()
	if normal == Vector2.ZERO:
		normal = (party_position - rect.get_center()).normalized()
	var tangent: Vector2 = Vector2(-radius.y, radius.x).normalized()
	var approach_speed: float = maxf(0.0, party_velocity.dot(-normal))
	var tangent_speed: float = party_velocity.dot(tangent)
	var contact_strength: float = clampf((approach_speed + absf(tangent_speed) * 0.45) / 150.0, 0.0, 1.25)
	if contact_strength <= 0.02:
		return
	var inertia: float = _spin_inertia_for_rect(rect)
	var torque: float = radius.cross(party_velocity) / inertia
	_add_window_spin_impulse(window, torque * WINDOW_SPIN_PARTY_IMPULSE * contact_strength)


func _apply_window_spin_contact_impulse(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> void:
	if _is_spin_pinned(window) and _is_spin_pinned(other_window):
		_apply_spin_gear_contact(window, rect, other_window, other)
		return
	if _is_spin_pinned(window):
		_apply_single_spin_window_contact(window, rect, other_window, other)
	if _is_spin_pinned(other_window):
		_apply_single_spin_window_contact(other_window, other, window, rect)


func _apply_spin_gear_contact(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> void:
	if not _window_spin_contacting(rect, other):
		return
	var contact_point: Vector2 = _rect_contact_point(rect, other)
	var radius_a: float = maxf(8.0, (contact_point - rect.get_center()).length())
	var radius_b: float = maxf(8.0, (contact_point - other.get_center()).length())
	var omega_a: float = float(_spin_angular_velocities.get(window, 0.0))
	var omega_b: float = float(_spin_angular_velocities.get(other_window, 0.0))
	var target_a: float = -omega_b * radius_b / radius_a
	var target_b: float = -omega_a * radius_a / radius_b
	var coupled_a: float = lerpf(omega_a, target_a, WINDOW_SPIN_GEAR_COUPLING)
	var coupled_b: float = lerpf(omega_b, target_b, WINDOW_SPIN_GEAR_COUPLING)
	_spin_angular_velocities[window] = clampf(coupled_a, -WINDOW_SPIN_MAX_ANGULAR_SPEED, WINDOW_SPIN_MAX_ANGULAR_SPEED)
	_spin_angular_velocities[other_window] = clampf(coupled_b, -WINDOW_SPIN_MAX_ANGULAR_SPEED, WINDOW_SPIN_MAX_ANGULAR_SPEED)


func _apply_single_spin_window_contact(spinning_window: BattleWindow, spinning_rect: Rect2, other_window: BattleWindow, other_rect: Rect2) -> void:
	if not _window_spin_contacting(spinning_rect, other_rect):
		return
	var contact_point: Vector2 = _rect_contact_point(spinning_rect, other_rect)
	var radius: Vector2 = contact_point - spinning_rect.get_center()
	if radius.length_squared() < 1.0:
		radius = other_rect.get_center() - spinning_rect.get_center()
	if radius.length_squared() < 1.0:
		return
	var tangent: Vector2 = Vector2(-radius.y, radius.x).normalized()
	var angular_velocity: float = float(_spin_angular_velocities.get(spinning_window, 0.0))
	var edge_velocity: Vector2 = tangent * angular_velocity * radius.length()
	var other_velocity: Vector2 = _window_velocities.get(other_window, Vector2.ZERO)
	var inertia: float = _spin_inertia_for_rect(spinning_rect)
	var incoming_torque: float = radius.cross(other_velocity) / inertia
	_add_window_spin_impulse(spinning_window, incoming_torque * WINDOW_SPIN_WINDOW_IMPULSE)
	if _is_spin_pinned(other_window):
		return
	var normal: Vector2 = (other_rect.get_center() - spinning_rect.get_center()).normalized()
	if normal == Vector2.ZERO:
		normal = tangent
	var separation_speed: float = maxf(0.0, edge_velocity.dot(normal))
	var bounce_multiplier: float = GameState.window_bounce_multiplier()
	var scrape_velocity: Vector2 = edge_velocity * WINDOW_SPIN_EDGE_TRANSFER * bounce_multiplier
	var shove_velocity: Vector2 = normal * separation_speed * 0.22 * bounce_multiplier
	_window_velocities[other_window] = (other_velocity + scrape_velocity + shove_velocity).limit_length(_max_speed_for_window(other_window))


func _add_window_spin_impulse(window: BattleWindow, impulse: float) -> void:
	if not _is_spin_pinned(window):
		return
	var current: float = float(_spin_angular_velocities.get(window, 0.0))
	_spin_angular_velocities[window] = clampf(current + impulse, -WINDOW_SPIN_MAX_ANGULAR_SPEED, WINDOW_SPIN_MAX_ANGULAR_SPEED)


func _apply_window_spin_collision_damage(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> bool:
	if not _window_spin_contacting(rect, other):
		return false
	if _is_spin_pinned(window) and _is_spin_pinned(other_window):
		return false
	var key: String = _collision_pair_key(window, other_window) + ":spin"
	if float(_spin_collision_cooldowns.get(key, 0.0)) > 0.0:
		return false
	var damage_ratio: float = GameState.window_spin_damage_ratio()
	if damage_ratio <= 0.0:
		return false
	var dealt: int = 0
	if _spin_is_damaging(window):
		dealt += other_window.apply_window_collision_damage(_spin_damage_ratio_for_window(window, damage_ratio), "Window Spin")
	if _spin_is_damaging(other_window):
		dealt += window.apply_window_collision_damage(_spin_damage_ratio_for_window(other_window, damage_ratio), "Window Spin")
	if dealt > 0:
		_spin_collision_cooldowns[key] = WINDOW_SPIN_DAMAGE_COOLDOWN
		return true
	return false


func _window_spin_contacting(rect: Rect2, other: Rect2) -> bool:
	return rect.grow(WINDOW_SPIN_CONTACT_MARGIN).intersects(other)


func _spin_is_damaging(window: BattleWindow) -> bool:
	return _is_spin_pinned(window) and absf(float(_spin_angular_velocities.get(window, 0.0))) >= WINDOW_SPIN_DAMAGE_MIN_SPEED


func _spin_damage_ratio_for_window(window: BattleWindow, base_ratio: float) -> float:
	var speed: float = absf(float(_spin_angular_velocities.get(window, 0.0)))
	var speed_bonus: float = clampf(speed / WINDOW_SPIN_DAMAGE_MIN_SPEED, 1.0, 2.4)
	return base_ratio * speed_bonus


func _try_cast_shockwave() -> bool:
	var shockwave_speed: float = GameState.window_shockwave_speed()
	if shockwave_speed <= 0.0 or _shockwave_cooldown > 0.0 or _window_rects.is_empty():
		return false
	var origin: Vector2 = _party_world_center()
	if origin == Vector2.INF:
		return false
	var hit_any: bool = false
	for window: BattleWindow in _active_windows():
		if not is_instance_valid(window) or not _window_rects.has(window):
			continue
		var rect: Rect2 = _window_rects[window]
		var delta: Vector2 = rect.get_center() - origin
		var distance: float = delta.length()
		if distance > SHOCKWAVE_RADIUS:
			continue
		var direction: Vector2 = delta.normalized() if distance > 1.0 else _shockwave_fallback_direction(window)
		var falloff: float = lerpf(1.0, 0.55, clampf(distance / SHOCKWAVE_RADIUS, 0.0, 1.0))
		var velocity: Vector2 = _window_velocities.get(window, Vector2.ZERO)
		_window_velocities[window] = velocity + direction * shockwave_speed * falloff
		_shockwave_boost_timers[str(window.get_instance_id())] = SHOCKWAVE_BOOST_DURATION
		hit_any = true
	if hit_any:
		_shockwave_cooldown = SHOCKWAVE_COOLDOWN
	return hit_any


func _max_speed_for_window(window: BattleWindow) -> float:
	var speed: float = MAX_WINDOW_SPEED * GameState.window_bounce_speed_multiplier()
	if float(_shockwave_boost_timers.get(str(window.get_instance_id()), 0.0)) > 0.0:
		return maxf(speed, SHOCKWAVE_MAX_WINDOW_SPEED)
	return speed


func _bounce_velocity_off_walls(velocity: Vector2, raw_position: Vector2, clamped_position: Vector2) -> Vector2:
	var restitution: float = GameState.window_wall_bounce_restitution()
	if restitution <= 0.0:
		return velocity
	var min_speed: float = GameState.window_wall_bounce_min_speed()
	var bounced: Vector2 = velocity
	if not is_equal_approx(raw_position.x, clamped_position.x):
		var direction_x: float = 1.0 if raw_position.x < clamped_position.x else -1.0
		bounced.x = direction_x * maxf(absf(bounced.x) * restitution, min_speed)
	if not is_equal_approx(raw_position.y, clamped_position.y):
		var direction_y: float = 1.0 if raw_position.y < clamped_position.y else -1.0
		bounced.y = direction_y * maxf(absf(bounced.y) * restitution, min_speed)
	return bounced


func _party_world_center() -> Vector2:
	var positions: Array[Vector2] = _party_world_positions()
	if positions.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for position: Vector2 in positions:
		sum += position
	return sum / float(positions.size())


func _shockwave_fallback_direction(window: BattleWindow) -> Vector2:
	var angle: float = float(int(window.get_instance_id()) % 360) * TAU / 360.0
	return Vector2(cos(angle), sin(angle))


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


func _wall_push(rect: Rect2, viewport_size: Vector2) -> Vector2:
	var bounds: Rect2 = _field_window_bounds(viewport_size)
	var margin_x: float = SLOT_MARGIN
	var margin_y: float = SLOT_MARGIN
	var play_bottom: float = bounds.end.y - HUD_RESERVED_BOTTOM
	var force := Vector2.ZERO
	if rect.position.x < bounds.position.x + margin_x:
		force.x += (bounds.position.x + margin_x - rect.position.x) * WALL_PUSH_STRENGTH
	if rect.end.x > bounds.end.x - margin_x:
		force.x -= (rect.end.x - bounds.end.x + margin_x) * WALL_PUSH_STRENGTH
	if rect.position.y < bounds.position.y + margin_y:
		force.y += (bounds.position.y + margin_y - rect.position.y) * WALL_PUSH_STRENGTH
	if rect.end.y > play_bottom:
		force.y -= (rect.end.y - play_bottom) * WALL_PUSH_STRENGTH
	return force


func _clamped_position(pos: Vector2, size: Vector2, viewport_size: Vector2) -> Vector2:
	var bounds: Rect2 = _field_window_bounds(viewport_size)
	var margin_x: float = SLOT_MARGIN
	var margin_y: float = SLOT_MARGIN
	var play_bottom: float = bounds.end.y - HUD_RESERVED_BOTTOM
	return Vector2(
		clampf(pos.x, bounds.position.x + margin_x, maxf(bounds.position.x + margin_x, bounds.end.x - margin_x - size.x)),
		clampf(pos.y, bounds.position.y + margin_y, maxf(bounds.position.y + margin_y, play_bottom - size.y))
	)


func _field_window_bounds(viewport_size: Vector2) -> Rect2:
	var field: Node = get_tree().get_first_node_in_group("field_root")
	if field != null and field.has_method("field_world_bounds"):
		var bounds = field.call("field_world_bounds")
		if bounds is Rect2:
			return bounds
	return _camera_visible_world_rect(viewport_size)


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


func _party_collision_bodies() -> Array[Dictionary]:
	var bodies: Array[Dictionary] = []
	for member: Node in get_tree().get_nodes_in_group("party_member"):
		if not member is Node2D:
			continue
		var key: String = str(member.get_instance_id())
		bodies.append({
			"position": (member as Node2D).global_position,
			"velocity": _party_velocities.get(key, Vector2.ZERO),
		})
	return bodies


func _update_party_velocities(delta: float) -> void:
	var live_keys: Dictionary = {}
	for member: Node in get_tree().get_nodes_in_group("party_member"):
		if not member is Node2D:
			continue
		var key: String = str(member.get_instance_id())
		var position: Vector2 = (member as Node2D).global_position
		var previous: Vector2 = _party_previous_positions.get(key, position)
		var velocity := Vector2.ZERO
		if delta > 0.0001:
			velocity = ((position - previous) / delta).limit_length(PARTY_VELOCITY_MAX)
		var old_velocity: Vector2 = _party_velocities.get(key, velocity)
		_party_velocities[key] = old_velocity.lerp(velocity, 0.42).limit_length(PARTY_VELOCITY_MAX)
		_party_previous_positions[key] = position
		live_keys[key] = true
	for key: String in _party_previous_positions.keys():
		if not live_keys.has(key):
			_party_previous_positions.erase(key)
			_party_velocities.erase(key)


func _camera_visible_world_rect(viewport_size: Vector2) -> Rect2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return Rect2(Vector2.ZERO, viewport_size)
	var visible_size: Vector2 = viewport_size * camera.zoom
	return Rect2(camera.get_screen_center_position() - visible_size * 0.5, visible_size)


func _camera_zoom() -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return Vector2.ONE
	return camera.zoom


func _world_to_screen_position(world_position: Vector2, viewport_size: Vector2) -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return world_position
	return (world_position - camera.get_screen_center_position()) / camera.zoom + viewport_size * 0.5


func _screen_to_world_position(screen_position: Vector2, viewport_size: Vector2) -> Vector2:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return screen_position
	return camera.get_screen_center_position() + (screen_position - viewport_size * 0.5) * camera.zoom


func _on_battle_window_closed(window: Node) -> void:
	if not _window_rects.has(window):
		return
	# Snapshot the window's world rect *before* erasing — we need it to
	# anchor drop positions at the window the player was just fighting in,
	# not at the player's body.
	var window_rect: Rect2 = _window_rects[window]
	_forget_window_reference(window)
	var battle_window := window as BattleWindow
	if battle_window:
		var xp_reward: int = battle_window.claim_xp_reward()
		if xp_reward > 0:
			GameState.add_party_xp(xp_reward)
		_drop_rewards_from_window(battle_window, window_rect)
	# Tell anyone who cares (Field, etc.) when the last fight ends. This is
	# the gate Field uses before declaring stage_cleared — Echo Strike means
	# the *first* window closing is rarely the last one.
	_emit_all_battles_resolved_if_no_live_fights()


func _claim_finished_spin_windows() -> void:
	for window: BattleWindow in _active_windows():
		if not _is_spin_pinned(window):
			continue
		if window.living_enemy_count() > 0:
			continue
		var key: String = str(window.get_instance_id())
		if bool(_spin_rewarded_windows.get(key, false)):
			continue
		var window_rect: Rect2 = _window_rects.get(window, Rect2())
		var xp_reward: int = window.claim_xp_reward()
		if xp_reward > 0:
			GameState.add_party_xp(xp_reward)
		_drop_rewards_from_window(window, window_rect)
		_spin_rewarded_windows[key] = true


func _emit_all_battles_resolved_if_no_live_fights() -> void:
	if _all_battles_resolved_sent:
		return
	for window: BattleWindow in _active_windows():
		if _is_spin_pinned(window):
			continue
		if window.living_enemy_count() > 0:
			return
	_all_battles_resolved_sent = true
	EventBus.all_battles_resolved.emit()


func _drop_rewards_from_window(window: BattleWindow, window_rect: Rect2) -> void:
	var drops: Array[ItemData] = window.claim_item_drops()
	var orb_count: int = window.claim_recovery_orb_count()
	var total_count: int = drops.size() + orb_count
	if total_count <= 0:
		return
	var base_pos: Vector2 = _world_position_for_window_rect(window_rect)
	var slot_index: int = 0
	for i in drops.size():
		EventBus.field_item_drop_requested.emit(drops[i], _drop_slot_position(base_pos, slot_index, total_count))
		slot_index += 1
	for i in orb_count:
		var kind: StringName = GameState.RECOVERY_ORB_HP if randf() < 0.5 else GameState.RECOVERY_ORB_MP
		EventBus.field_recovery_orb_requested.emit(kind, _drop_slot_position(base_pos, slot_index, total_count))
		slot_index += 1


func _drop_slot_position(base_pos: Vector2, index: int, total_count: int) -> Vector2:
	if total_count <= 1:
		return base_pos
	var ring: int = int(floor(float(index) / float(DROP_RING_SLOTS)))
	var slot: int = index % DROP_RING_SLOTS
	var slots_in_ring: int = mini(DROP_RING_SLOTS, total_count - ring * DROP_RING_SLOTS)
	var angle_offset: float = 0.35 * float(ring)
	var angle: float = TAU * float(slot) / float(maxi(1, slots_in_ring)) + angle_offset
	var radius: float = DROP_RING_RADIUS + DROP_RING_RADIUS_STEP * float(ring)
	return base_pos + Vector2(cos(angle), sin(angle)) * radius


## Drops land under the world-anchored window the player was just fighting in,
## not at the player's feet.
func _world_position_for_window_rect(window_rect: Rect2) -> Vector2:
	var fallback_pos: Vector2 = Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		fallback_pos = player.global_position
	if window_rect.size == Vector2.ZERO:
		return fallback_pos
	# Anchor the drop slightly above the bottom of the window so loot spawns
	# under the enemy stack rather than over the action log.
	return window_rect.position + Vector2(window_rect.size.x * 0.5, window_rect.size.y * 0.65)


# ─── Run-over cleanup ─────────────────────────────────────────────────
func _on_party_wiped() -> void:
	abort_all_battles()


## Force-close every active battle window. No gold, no signals, no log —
## the run is dead. Used on party_wipe and (later) explicit run resets.
func abort_all_battles() -> void:
	for window: Node in _window_rects.keys():
		if is_instance_valid(window):
			window.queue_free()
	_window_rects.clear()
	_window_velocities.clear()
	_collision_cooldowns.clear()
	_party_collision_cooldowns.clear()
	_bump_heal_totals.clear()
	_shockwave_boost_timers.clear()
	_spin_angular_velocities.clear()
	_spin_collision_cooldowns.clear()
	_spin_rewarded_windows.clear()
	_split_handle_cooldowns.clear()
	_split_pending_windows.clear()
	_party_previous_positions.clear()
	_party_velocities.clear()
	_shockwave_cooldown = 0.0
	_all_battles_resolved_sent = true


func _erase_pair_cooldowns_for_window(window_key: String) -> void:
	for key: String in _collision_cooldowns.keys():
		if key.begins_with(window_key + ":") or key.contains(":" + window_key):
			_collision_cooldowns.erase(key)
	for key: String in _spin_collision_cooldowns.keys():
		if key.begins_with(window_key + ":") or key.contains(":" + window_key + ":"):
			_spin_collision_cooldowns.erase(key)
