extends Node
class_name EnemySpawner
## Field enemy spawn controller
## - initial scattered spawn
## - respawn when off camera

# -----------------------------------------------------------------------------
# Spawn config
# -----------------------------------------------------------------------------
var DEFAULT_MAX_ENEMIES: int = 6
var FIELD_ENEMY_COUNT_MULTIPLIER: float = 1.35
var MIN_SPAWN_DISTANCE_BETWEEN: float = 24.0
var EDGE_SPAWN_PADDING: float = 32.0
var MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER: float = 120.0
var ELITE_SPAWN_CHANCE: float = 0.15
var MAX_SPAWN_ATTEMPTS: int = 50

# Respawn config
var RESPAWN_DELAY_MIN: float = 1.0
var RESPAWN_DELAY_MAX: float = 2.5
var FIELD_ENEMY_Z: int = 48

# Dynamic bonus spawn (grudge-driven)
var PROACTIVE_SPAWN_INTERVAL: float = 0.45

@export_group("Config")
@export var config: EnemySpawnerConfig

@export_group("Fallback / Override")
@export var field_enemy_scene: PackedScene = preload("res://scenes/field/FieldEnemy.tscn")

@export_group("Initial Spawn")
@export var use_spawn_markers_for_initial_spawn: bool = true
@export var spawn_markers_root_path: NodePath = NodePath("EnemySpawnPoints")

@export_group("Tile Mapping")
@export var tile_type_map: Dictionary = {
	0: "grass",
	1: "forest",
	2: "mountain",
	3: "water",
	4: "cave",
}

var field: Node2D
var tilemap: TileMapLayer

# Cached map data
var map_bounds: Rect2 = Rect2()
var bounds_calculated: bool = false
var target_enemy_count_cached: int = -1
var dynamic_bonus_enemy_count: int = 0
var proactive_spawn_cooldown: float = 0.0
var cached_spawn_markers: Array[Marker2D] = []

# Respawn queue
# [{"tile_type": String, "delay_timer": float, "original_pos": Vector2}]
var respawn_queue: Array[Dictionary] = []

signal enemy_spawned(enemy: Node2D)
signal enemy_respawned(enemy: Node2D)


func _ready() -> void:
	_apply_config_overrides()


func setup(p_field: Node2D, p_tilemap: TileMapLayer) -> void:
	_apply_config_overrides()
	field = p_field
	tilemap = p_tilemap
	if field_enemy_scene == null:
		field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn") as PackedScene
	bounds_calculated = false
	target_enemy_count_cached = -1
	dynamic_bonus_enemy_count = 0
	proactive_spawn_cooldown = 0.0
	respawn_queue.clear()
	cached_spawn_markers.clear()


func _apply_config_overrides() -> void:
	if config == null:
		return

	if config.field_enemy_scene != null:
		field_enemy_scene = config.field_enemy_scene
	DEFAULT_MAX_ENEMIES = maxi(1, config.default_max_enemies)
	FIELD_ENEMY_COUNT_MULTIPLIER = maxf(0.1, config.field_enemy_count_multiplier)
	MIN_SPAWN_DISTANCE_BETWEEN = maxf(0.0, config.min_spawn_distance_between)
	EDGE_SPAWN_PADDING = maxf(0.0, config.edge_spawn_padding)
	MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER = maxf(0.0, config.min_initial_spawn_distance_from_player)
	MAX_SPAWN_ATTEMPTS = maxi(1, config.max_spawn_attempts)

	RESPAWN_DELAY_MIN = maxf(0.0, config.respawn_delay_min)
	RESPAWN_DELAY_MAX = maxf(RESPAWN_DELAY_MIN, config.respawn_delay_max)
	FIELD_ENEMY_Z = config.field_enemy_z
	PROACTIVE_SPAWN_INTERVAL = maxf(0.05, config.proactive_spawn_interval)

	use_spawn_markers_for_initial_spawn = config.use_spawn_markers_for_initial_spawn
	if not config.spawn_markers_root_path.is_empty():
		spawn_markers_root_path = config.spawn_markers_root_path
	if not config.tile_type_map.is_empty():
		tile_type_map = config.tile_type_map.duplicate(true)


func spawn_initial_enemies(field_enemies: Array) -> void:
	if FieldManager.is_boss_field():
		_spawn_boss(field_enemies)
		return

	if not bounds_calculated:
		_calculate_map_data()

	var player_pos: Vector2 = _get_player_position()
	var spawned_positions: Array[Vector2] = []
	if target_enemy_count_cached <= 0:
		target_enemy_count_cached = _roll_target_enemy_count()
	var target_enemy_count: int = target_enemy_count_cached

	for enemy in field_enemies:
		if is_instance_valid(enemy):
			spawned_positions.append(enemy.global_position)

	var current_non_boss: int = _get_non_boss_enemy_count(field_enemies)
	var spawn_needed: int = maxi(0, target_enemy_count - current_non_boss)

	if use_spawn_markers_for_initial_spawn:
		var marker_positions: Array[Vector2] = _get_spawn_marker_positions()
		marker_positions.shuffle()
		for marker_pos in marker_positions:
			if spawn_needed <= 0:
				break
			if not _is_spawn_position_valid(marker_pos, spawned_positions, player_pos, MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER):
				continue
			var marker_tile_type: String = _get_tile_type_at(marker_pos)
			_spawn_enemy_at({"position": marker_pos, "tile_type": marker_tile_type}, field_enemies)
			spawned_positions.append(marker_pos)
			spawn_needed -= 1

	for _i in range(spawn_needed):
		var pos: Vector2 = _find_spawn_position_on_map(
			spawned_positions,
			Rect2(),
			false,
			player_pos,
			MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER
		)
		if pos == Vector2.ZERO:
			pos = _find_spawn_position_on_map(
				spawned_positions,
				Rect2(),
				false,
				player_pos,
				MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER * 0.6
			)
		if pos != Vector2.ZERO:
			var tile_type: String = _get_tile_type_at(pos)
			_spawn_enemy_at({"position": pos, "tile_type": tile_type}, field_enemies)
			spawned_positions.append(pos)

	spawn_field_boss(field_enemies)


func setup_respawn_timer(_parent: Node) -> void:
	pass


func update_movement_spawn(field_enemies: Array) -> void:
	if FieldManager.is_boss_field():
		return

	var delta: float = field.get_process_delta_time() if field else 0.016
	proactive_spawn_cooldown = maxf(0.0, proactive_spawn_cooldown - delta)

	var camera_rect: Rect2 = _get_camera_rect()
	if target_enemy_count_cached <= 0:
		target_enemy_count_cached = _roll_target_enemy_count()
	var target_enemy_count: int = get_target_enemy_count()

	# collect existing positions
	var existing_positions: Array[Vector2] = []
	for enemy in field_enemies:
		if is_instance_valid(enemy):
			existing_positions.append(enemy.global_position)

	# respawn queue
	var to_respawn: Array[int] = []
	for i in range(respawn_queue.size()):
		var entry: Dictionary = respawn_queue[i]
		entry["delay_timer"] = float(entry.get("delay_timer", 0.0)) - delta
		respawn_queue[i] = entry

		if float(entry.get("delay_timer", 0.0)) <= 0.0:
			if _get_non_boss_enemy_count(field_enemies) >= target_enemy_count:
				continue

			var original_pos: Vector2 = entry.get("original_pos", Vector2.ZERO)
			var spawn_pos: Vector2 = Vector2.ZERO
			if _is_spawn_position_valid(original_pos, existing_positions) and not camera_rect.has_point(original_pos):
				spawn_pos = original_pos
			elif camera_rect.has_point(original_pos):
				continue
			else:
				spawn_pos = _find_spawn_position_on_map(existing_positions, camera_rect, true)

			if spawn_pos != Vector2.ZERO:
				to_respawn.append(i)
				var tile_type: String = str(entry.get("tile_type", "grass"))
				_spawn_enemy_at({"position": spawn_pos, "tile_type": tile_type}, field_enemies, false, true)
				existing_positions.append(spawn_pos)

	to_respawn.reverse()
	for idx in to_respawn:
		respawn_queue.remove_at(idx)

	# proactive spawn to reach dynamic target
	var current_non_boss: int = _get_non_boss_enemy_count(field_enemies)
	if current_non_boss < target_enemy_count and proactive_spawn_cooldown <= 0.0:
		existing_positions.clear()
		for enemy in field_enemies:
			if is_instance_valid(enemy):
				existing_positions.append(enemy.global_position)

		var player_pos: Vector2 = _get_player_position()
		var spawn_pos: Vector2 = _find_spawn_position_on_map(
			existing_positions,
			camera_rect,
			true,
			player_pos,
			60.0
		)
		if spawn_pos != Vector2.ZERO:
			var tile_type: String = _get_tile_type_at(spawn_pos)
			_spawn_enemy_at({"position": spawn_pos, "tile_type": tile_type}, field_enemies)
			proactive_spawn_cooldown = PROACTIVE_SPAWN_INTERVAL


func on_enemy_killed(tile_type: String, position: Vector2) -> void:
	var delay: float = randf_range(RESPAWN_DELAY_MIN, RESPAWN_DELAY_MAX)
	respawn_queue.append({
		"tile_type": tile_type,
		"delay_timer": delay,
		"original_pos": position,
	})


func stop_respawn() -> void:
	respawn_queue.clear()


# -----------------------------------------------------------------------------
# Map data
# -----------------------------------------------------------------------------
func _calculate_map_data() -> void:
	if not tilemap:
		map_bounds = Rect2(0, 0, 800, 600)
		bounds_calculated = true
		return

	var used_rect: Rect2i = tilemap.get_used_rect()
	var tile_size: Vector2 = Vector2(16, 16)
	map_bounds = Rect2(Vector2(used_rect.position) * tile_size, Vector2(used_rect.size) * tile_size)
	bounds_calculated = true


# -----------------------------------------------------------------------------
# Spawn position helpers
# -----------------------------------------------------------------------------
func _find_spawn_position_on_map(
	existing: Array[Vector2],
	avoid_rect: Rect2 = Rect2(),
	require_outside_avoid_rect: bool = false,
	player_pos: Vector2 = Vector2.ZERO,
	min_player_distance: float = 0.0
) -> Vector2:
	if not bounds_calculated:
		_calculate_map_data()

	var x_min: float = map_bounds.position.x + EDGE_SPAWN_PADDING
	var x_max: float = map_bounds.end.x - EDGE_SPAWN_PADDING
	var y_min: float = map_bounds.position.y + EDGE_SPAWN_PADDING
	var y_max: float = map_bounds.end.y - EDGE_SPAWN_PADDING

	if x_min >= x_max or y_min >= y_max:
		return Vector2.ZERO

	for _i in range(MAX_SPAWN_ATTEMPTS):
		var pos := Vector2(randf_range(x_min, x_max), randf_range(y_min, y_max))
		if require_outside_avoid_rect and avoid_rect.size.x > 0.0 and avoid_rect.has_point(pos):
			continue
		if not _is_spawn_position_valid(pos, existing, player_pos, min_player_distance):
			continue
		return pos

	return Vector2.ZERO


func _is_spawn_position_valid(
	pos: Vector2,
	existing: Array[Vector2],
	player_pos: Vector2 = Vector2.ZERO,
	min_player_distance: float = 0.0
) -> bool:
	if pos == Vector2.ZERO:
		return false
	if bounds_calculated and not map_bounds.has_point(pos):
		return false
	if min_player_distance > 0.0 and pos.distance_to(player_pos) < min_player_distance:
		return false

	var tile_type: String = _get_tile_type_at(pos)
	if not FieldManager.can_spawn_on_tile(tile_type):
		return false

	for other_pos in existing:
		if pos.distance_to(other_pos) < MIN_SPAWN_DISTANCE_BETWEEN:
			return false
	return true


func _get_non_boss_enemy_count(field_enemies: Array) -> int:
	var count: int = 0
	for enemy in field_enemies:
		if is_instance_valid(enemy) and not enemy.is_boss:
			count += 1
	return count


func _roll_target_enemy_count() -> int:
	if FieldManager and not FieldManager.current_area_data.is_empty():
		var enemy_count: Dictionary = FieldManager.current_area_data.get("enemy_count", {}) as Dictionary
		var min_count: int = int(enemy_count.get("min", DEFAULT_MAX_ENEMIES))
		var max_count: int = int(enemy_count.get("max", min_count))
		if max_count < min_count:
			max_count = min_count
		var rolled: int = randi_range(min_count, max_count)
		var boosted: int = int(round(float(rolled) * FIELD_ENEMY_COUNT_MULTIPLIER))
		if GameManager != null and GameManager.has_method("get_trinket_field_enemy_count_multiplier"):
			var trinket_mult: float = float(GameManager.call("get_trinket_field_enemy_count_multiplier"))
			boosted = int(round(float(boosted) * trinket_mult))
		return maxi(1, boosted)
	return DEFAULT_MAX_ENEMIES


func set_dynamic_bonus_enemy_count(value: int) -> void:
	dynamic_bonus_enemy_count = maxi(0, value)


func get_dynamic_bonus_enemy_count() -> int:
	return dynamic_bonus_enemy_count


func get_base_target_enemy_count() -> int:
	if target_enemy_count_cached <= 0:
		target_enemy_count_cached = _roll_target_enemy_count()
	return target_enemy_count_cached


func get_target_enemy_count() -> int:
	return get_base_target_enemy_count() + dynamic_bonus_enemy_count


func _get_camera_rect() -> Rect2:
	if not field:
		return Rect2()

	var viewport_size: Vector2 = field.get_viewport_rect().size
	var camera: Camera2D = field.get_viewport().get_camera_2d()
	var player_pos: Vector2 = _get_player_position()
	var margin: float = 32.0

	if camera:
		var view_size: Vector2 = viewport_size / camera.zoom
		var rect := Rect2(camera.global_position - view_size / 2, view_size)
		return rect.grow(margin)

	return Rect2(player_pos - viewport_size / 2, viewport_size).grow(margin)


# -----------------------------------------------------------------------------
# Internal spawn functions
# -----------------------------------------------------------------------------
func _spawn_boss(field_enemies: Array) -> void:
	var boss_id: String = FieldManager.get_boss_enemy()
	if boss_id.is_empty():
		push_error("[EnemySpawner] boss id missing")
		return

	var enemy: Node2D = _instantiate_enemy()
	if enemy == null:
		return
	enemy.z_index = FIELD_ENEMY_Z
	field.add_child(enemy)

	var boss_pos: Vector2 = map_bounds.get_center() if bounds_calculated else Vector2(350, 135)
	enemy.setup(boss_id, "grass", boss_pos, false)
	enemy.is_boss = true
	enemy.add_to_group("field_boss")
	enemy.add_to_group("field_enemy")
	field_enemies.append(enemy)
	enemy_spawned.emit(enemy)


func spawn_field_boss(field_enemies: Array) -> void:
	if not bounds_calculated:
		_calculate_map_data()

	var boss_id: String = FieldManager.get_field_boss_enemy()
	if boss_id.is_empty():
		boss_id = "slime"

	var enemy: Node2D = _instantiate_enemy()
	if enemy == null:
		return
	enemy.z_index = FIELD_ENEMY_Z
	field.add_child(enemy)

	var boss_pos: Vector2 = map_bounds.get_center() if bounds_calculated else Vector2(480, 270)
	if field and field.has_method("get_field_boss_spawn_position"):
		var custom_pos: Variant = field.call("get_field_boss_spawn_position")
		if custom_pos is Vector2 and custom_pos != Vector2.ZERO:
			boss_pos = custom_pos as Vector2

	var player_pos: Vector2 = _get_player_position()
	if boss_pos.distance_to(player_pos) < 280.0:
		if bounds_calculated:
			boss_pos = Vector2(map_bounds.end.x - 96.0, map_bounds.position.y + 96.0)
		else:
			boss_pos = player_pos + Vector2(320.0, -180.0)

	enemy.setup(boss_id, "grass", boss_pos, false)
	enemy.is_boss = true
	enemy.add_to_group("field_boss")
	enemy.add_to_group("field_enemy")
	enemy.scale = Vector2(3, 3)
	enemy.set_deferred("wander_speed", 0.0)
	enemy.set_deferred("chase_speed", 0.0)
	enemy.set_deferred("detection_range", 0.0)

	field_enemies.append(enemy)
	enemy_spawned.emit(enemy)

	print("[EnemySpawner] field boss spawned: %s at %s" % [boss_id, boss_pos])


func _spawn_enemy_at(tile_data: Dictionary, field_enemies: Array, force_elite: bool = false, is_respawn: bool = false) -> void:
	var enemy: Node2D = _instantiate_enemy()
	if enemy == null:
		return
	enemy.z_index = FIELD_ENEMY_Z
	field.add_child(enemy)

	var tile_type: String = str(tile_data.get("tile_type", "grass"))
	var enemy_id: String = FieldManager.select_field_enemy_for_tile(tile_type)
	var is_elite: bool = force_elite
	enemy.setup(enemy_id, tile_type, tile_data.get("position", Vector2.ZERO), is_elite)
	enemy.add_to_group("field_enemy")
	field_enemies.append(enemy)

	if is_respawn:
		enemy_respawned.emit(enemy)
	else:
		enemy_spawned.emit(enemy)


func _get_player_position() -> Vector2:
	if field:
		var leader_variant: Variant = field.get("party_leader")
		if leader_variant is Node2D and is_instance_valid(leader_variant):
			return (leader_variant as Node2D).global_position
	return Vector2(200, 150)


func _get_tile_type_at(pos: Vector2) -> String:
	if not tilemap:
		return "grass"

	var cell: Vector2i = tilemap.local_to_map(pos)
	var source_id: int = tilemap.get_cell_source_id(cell)
	if source_id == -1:
		return "grass"
	return str(tile_type_map.get(source_id, "grass"))


func _get_spawn_marker_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if field == null or spawn_markers_root_path.is_empty():
		return positions
	var root: Node = field.get_node_or_null(spawn_markers_root_path)
	if root == null:
		return positions
	if cached_spawn_markers.is_empty():
		for child in root.get_children():
			if child is Marker2D:
				cached_spawn_markers.append(child as Marker2D)
	for marker in cached_spawn_markers:
		if marker != null and is_instance_valid(marker):
			positions.append(marker.global_position)
	return positions


func _instantiate_enemy() -> Node2D:
	if field_enemy_scene == null:
		push_error("[EnemySpawner] field_enemy_scene is not assigned")
		return null
	return field_enemy_scene.instantiate() as Node2D
