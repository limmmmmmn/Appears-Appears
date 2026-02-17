extends RefCounted
class_name FieldGrassController

const TEST_TILE_SIZE := 16
const FIELD_TILE_TYPE_MAP := {
	0: "grass",
	1: "forest",
	2: "mountain",
	3: "water",
	4: "cave",
}

const FIELD_GRASS_SCENE := preload("res://scenes/field/Grass.tscn")
const DEFAULT_GRASS_TEXTURE := preload("res://assets/sprites/tilesets/grass.png")
const FIELD_GRASS_A_CANDIDATE_PATHS: Array[String] = [
	"res://assets/sprites/tilesets/Grass_A.png",
	"res://assets/sprites/tilesets/grass_a.png",
	"res://assets/sprites/tilesets/GrassA.png",
]
const FIELD_GRASS_B_CANDIDATE_PATHS: Array[String] = [
	"res://assets/sprites/tilesets/Grass_B.png",
	"res://assets/sprites/tilesets/grass_b.png",
	"res://assets/sprites/tilesets/GrassB.png",
]

const FIELD_GRASS_MIN_COUNT: int = 420
const FIELD_GRASS_MAX_COUNT: int = 620
const FIELD_GRASS_PATCH_COUNT: int = 96
const FIELD_GRASS_PATCH_SIZE_MIN: int = 8
const FIELD_GRASS_PATCH_SIZE_MAX: int = 22
const FIELD_GRASS_PATCH_RADIUS_MIN_TILES: float = 1.3
const FIELD_GRASS_PATCH_RADIUS_MAX_TILES: float = 3.6
const FIELD_GRASS_FILL_ATTEMPTS: int = 1800
const FIELD_GRASS_MIN_SEPARATION: float = 2.3
const FIELD_GRASS_PADDING: float = 24.0
const FIELD_GRASS_MIN_DIST_PLAYER: float = 34.0
const FIELD_GRASS_MIN_DIST_ENEMY: float = 26.0
const FIELD_GRASS_MIN_DIST_OBJECT: float = 22.0
const FIELD_GRASS_INTERACT_RADIUS: float = 30.0
const FIELD_GRASS_INTERACT_STRENGTH: float = 1.0
const FIELD_GRASS_ENEMY_INTERACT_RADIUS: float = 26.0
const FIELD_GRASS_ENEMY_INTERACT_STRENGTH: float = 0.85
const FIELD_GRASS_WIND_INTERVAL_MIN: float = 2.4
const FIELD_GRASS_WIND_INTERVAL_MAX: float = 6.0
const FIELD_GRASS_WIND_DURATION_MIN: float = 1.1
const FIELD_GRASS_WIND_DURATION_MAX: float = 2.6
const FIELD_GRASS_WIND_PEAK_MIN: float = 0.35
const FIELD_GRASS_WIND_PEAK_MAX: float = 1.0
const FIELD_GRASS_BACK_Z: int = 36
const FIELD_GRASS_FRONT_Z: int = 108
const FIELD_GRASS_FRONT_RATIO: float = 0.42
const FIELD_GRASS_FRONT_ALPHA: float = 0.9

var field_grass_container: Node2D = null
var field_grass_nodes: Array = []
var field_grass_texture_a: Texture2D = null
var field_grass_texture_b: Texture2D = null
var grass_wind_strength: float = 0.0
var grass_wind_dir: float = 1.0
var grass_wind_active: bool = false
var grass_wind_timer: float = 0.0
var grass_wind_duration: float = 0.0
var grass_wind_peak: float = 0.0


func load_textures() -> void:
	field_grass_texture_a = _load_first_existing_texture(FIELD_GRASS_A_CANDIDATE_PATHS)
	field_grass_texture_b = _load_first_existing_texture(FIELD_GRASS_B_CANDIDATE_PATHS)
	if field_grass_texture_a == null:
		field_grass_texture_a = DEFAULT_GRASS_TEXTURE
	if field_grass_texture_b == null:
		field_grass_texture_b = field_grass_texture_a


func spawn(
	host: Node2D,
	is_test_field: bool,
	is_boss_field: bool,
	bounds: Rect2,
	tilemap: TileMapLayer,
	party_leader: Node2D,
	field_enemies: Array,
	field_treasure_chests: Array,
	recruit_npc_root: Node2D,
	sanctuary_root: Node2D
) -> void:
	field_grass_nodes.clear()
	if field_grass_container != null and is_instance_valid(field_grass_container):
		field_grass_container.queue_free()
	field_grass_container = null

	if not is_test_field:
		return
	if is_boss_field:
		return
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	field_grass_container = Node2D.new()
	field_grass_container.name = "FieldGrass"
	field_grass_container.z_index = 0
	host.add_child(field_grass_container)

	var placed_positions: Array[Vector2] = []

	for _patch_idx in range(FIELD_GRASS_PATCH_COUNT):
		if field_grass_nodes.size() >= FIELD_GRASS_MAX_COUNT:
			break
		var center := Vector2(
			randf_range(bounds.position.x + FIELD_GRASS_PADDING, bounds.end.x - FIELD_GRASS_PADDING),
			randf_range(bounds.position.y + FIELD_GRASS_PADDING, bounds.end.y - FIELD_GRASS_PADDING)
		)
		var patch_size: int = randi_range(FIELD_GRASS_PATCH_SIZE_MIN, FIELD_GRASS_PATCH_SIZE_MAX)
		var patch_radius_px: float = randf_range(
			FIELD_GRASS_PATCH_RADIUS_MIN_TILES * TEST_TILE_SIZE,
			FIELD_GRASS_PATCH_RADIUS_MAX_TILES * TEST_TILE_SIZE
		)

		for _i in range(patch_size):
			if field_grass_nodes.size() >= FIELD_GRASS_MAX_COUNT:
				break
			var angle: float = randf() * TAU
			var dist: float = patch_radius_px * pow(randf(), 1.45)
			var spawn_pos := center + Vector2(cos(angle), sin(angle)) * dist
			spawn_pos += Vector2(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5))
			if not _can_place_field_grass_at(
				spawn_pos,
				tilemap,
				party_leader,
				field_enemies,
				field_treasure_chests,
				recruit_npc_root,
				sanctuary_root
			):
				continue
			if not _is_grass_spacing_ok(spawn_pos, placed_positions):
				continue
			if _spawn_single_field_grass(spawn_pos):
				placed_positions.append(spawn_pos)

	var fill_attempts: int = 0
	while field_grass_nodes.size() < FIELD_GRASS_MIN_COUNT and fill_attempts < FIELD_GRASS_FILL_ATTEMPTS:
		fill_attempts += 1
		var fill_pos := Vector2(
			randf_range(bounds.position.x + FIELD_GRASS_PADDING, bounds.end.x - FIELD_GRASS_PADDING),
			randf_range(bounds.position.y + FIELD_GRASS_PADDING, bounds.end.y - FIELD_GRASS_PADDING)
		)
		if not _can_place_field_grass_at(
			fill_pos,
			tilemap,
			party_leader,
			field_enemies,
			field_treasure_chests,
			recruit_npc_root,
			sanctuary_root
		):
			continue
		if not _is_grass_spacing_ok(fill_pos, placed_positions):
			continue
		if _spawn_single_field_grass(fill_pos):
			placed_positions.append(fill_pos)

	grass_wind_strength = 0.0
	grass_wind_active = false
	grass_wind_duration = 0.0
	grass_wind_peak = 0.0
	grass_wind_timer = randf_range(FIELD_GRASS_WIND_INTERVAL_MIN, FIELD_GRASS_WIND_INTERVAL_MAX)
	grass_wind_dir = -1.0 if randi() % 2 == 0 else 1.0


func update(delta: float, tilemap: TileMapLayer, party_leader: CharacterBody2D, field_enemies: Array) -> void:
	if field_grass_nodes.is_empty():
		return

	_update_wind(delta)

	var actor_pos_list: Array[Vector2] = []
	var actor_vel_list: Array[Vector2] = []
	var actor_radius_list: Array[float] = []
	var actor_strength_list: Array[float] = []

	if party_leader:
		var p_speed := party_leader.velocity.length()
		actor_pos_list.append(party_leader.global_position)
		actor_vel_list.append(party_leader.velocity)
		actor_radius_list.append(FIELD_GRASS_INTERACT_RADIUS + clampf(p_speed * 0.08, 0.0, 12.0))
		actor_strength_list.append(FIELD_GRASS_INTERACT_STRENGTH + clampf(p_speed / 55.0, 0.0, 1.2))

	for enemy_any in field_enemies:
		var enemy := enemy_any as CharacterBody2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var e_speed := enemy.velocity.length()
		actor_pos_list.append(enemy.global_position)
		actor_vel_list.append(enemy.velocity)
		actor_radius_list.append(FIELD_GRASS_ENEMY_INTERACT_RADIUS + clampf(e_speed * 0.08, 0.0, 9.0))
		actor_strength_list.append(FIELD_GRASS_ENEMY_INTERACT_STRENGTH + clampf(e_speed / 85.0, 0.0, 0.8))

	for i in range(field_grass_nodes.size() - 1, -1, -1):
		var node_ref = field_grass_nodes[i]
		if node_ref == null or not is_instance_valid(node_ref):
			field_grass_nodes.remove_at(i)
			continue
		if node_ref.has_method("set_global_wind"):
			node_ref.call("set_global_wind", grass_wind_strength, grass_wind_dir)
		if not node_ref.has_method("apply_player_influence"):
			continue

		var grass_node := node_ref as Node2D
		if grass_node == null:
			continue

		var grass_world_pos: Vector2 = grass_node.global_position + Vector2(TEST_TILE_SIZE * 0.5, TEST_TILE_SIZE * 0.5)
		var best_idx: int = -1
		var best_effect: float = 0.0

		for j in range(actor_pos_list.size()):
			var radius: float = actor_radius_list[j]
			if radius <= 0.0:
				continue
			var dist: float = grass_world_pos.distance_to(actor_pos_list[j])
			if dist > radius:
				continue
			var effect: float = (1.0 - dist / radius) * actor_strength_list[j]
			if effect > best_effect:
				best_effect = effect
				best_idx = j

		if best_idx >= 0:
			node_ref.call(
				"apply_player_influence",
				actor_pos_list[best_idx],
				actor_vel_list[best_idx],
				actor_radius_list[best_idx],
				actor_strength_list[best_idx],
				delta
			)
		else:
			node_ref.call("apply_player_influence", Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, delta)


func _spawn_single_field_grass(spawn_pos: Vector2) -> bool:
	if field_grass_container == null or not is_instance_valid(field_grass_container):
		return false
	if field_grass_nodes.size() >= FIELD_GRASS_MAX_COUNT:
		return false
	var grass_node := FIELD_GRASS_SCENE.instantiate()
	if not (grass_node is Node2D):
		return false
	var grass := grass_node as Node2D
	grass.position = spawn_pos
	var front_layer: bool = randf() < FIELD_GRASS_FRONT_RATIO
	if grass is CanvasItem:
		var canvas_item := grass as CanvasItem
		canvas_item.z_index = FIELD_GRASS_FRONT_Z if front_layer else FIELD_GRASS_BACK_Z
		var alpha: float = FIELD_GRASS_FRONT_ALPHA if front_layer else 1.0
		canvas_item.modulate = Color(1.0, 1.0, 1.0, alpha)
	field_grass_container.add_child(grass)
	if grass.has_method("set_grass_textures"):
		grass.call("set_grass_textures", field_grass_texture_a, field_grass_texture_b)
	if grass.has_method("set_global_wind"):
		grass.call("set_global_wind", grass_wind_strength, grass_wind_dir)
	field_grass_nodes.append(grass)
	return true


func _is_grass_spacing_ok(spawn_pos: Vector2, placed_positions: Array[Vector2]) -> bool:
	for p in placed_positions:
		if p.distance_to(spawn_pos) < FIELD_GRASS_MIN_SEPARATION:
			return false
	return true


func _can_place_field_grass_at(
	world_pos: Vector2,
	tilemap: TileMapLayer,
	party_leader: Node2D,
	field_enemies: Array,
	field_treasure_chests: Array,
	recruit_npc_root: Node2D,
	sanctuary_root: Node2D
) -> bool:
	var tile_center := world_pos + Vector2(TEST_TILE_SIZE * 0.5, TEST_TILE_SIZE * 0.5)
	if not _is_walkable_tile_at_world(tile_center, tilemap):
		return false

	if party_leader and world_pos.distance_to(party_leader.global_position) < FIELD_GRASS_MIN_DIST_PLAYER:
		return false

	if recruit_npc_root != null and is_instance_valid(recruit_npc_root):
		if world_pos.distance_to(recruit_npc_root.global_position) < FIELD_GRASS_MIN_DIST_OBJECT:
			return false

	if sanctuary_root != null and is_instance_valid(sanctuary_root):
		if world_pos.distance_to(sanctuary_root.global_position) < FIELD_GRASS_MIN_DIST_OBJECT + 8.0:
			return false

	for enemy_any in field_enemies:
		var enemy := enemy_any as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if world_pos.distance_to(enemy.global_position) < FIELD_GRASS_MIN_DIST_ENEMY:
			return false

	for chest_any in field_treasure_chests:
		var chest: Dictionary = chest_any as Dictionary
		var root: Node2D = chest.get("root", null) as Node2D
		if root == null or not is_instance_valid(root):
			continue
		if world_pos.distance_to(root.global_position) < FIELD_GRASS_MIN_DIST_OBJECT:
			return false

	return true


func _is_walkable_tile_at_world(world_pos: Vector2, tilemap: TileMapLayer) -> bool:
	if tilemap == null:
		return true
	var cell: Vector2i = tilemap.local_to_map(world_pos)
	var source_id: int = tilemap.get_cell_source_id(cell)
	if source_id == -1:
		return true
	var tile_type: String = str(FIELD_TILE_TYPE_MAP.get(source_id, "grass"))
	return FieldManager.is_tile_walkable(tile_type)


func _update_wind(delta: float) -> void:
	if grass_wind_active:
		grass_wind_timer += delta
		var t := clampf(grass_wind_timer / maxf(0.001, grass_wind_duration), 0.0, 1.0)
		grass_wind_strength = sin(t * PI) * grass_wind_peak
		if t >= 1.0:
			grass_wind_active = false
			grass_wind_strength = 0.0
			grass_wind_timer = randf_range(FIELD_GRASS_WIND_INTERVAL_MIN, FIELD_GRASS_WIND_INTERVAL_MAX)
			grass_wind_dir = -1.0 if randi() % 2 == 0 else 1.0
		return

	grass_wind_timer -= delta
	if grass_wind_timer > 0.0:
		return

	grass_wind_active = true
	grass_wind_timer = 0.0
	grass_wind_duration = randf_range(FIELD_GRASS_WIND_DURATION_MIN, FIELD_GRASS_WIND_DURATION_MAX)
	grass_wind_peak = randf_range(FIELD_GRASS_WIND_PEAK_MIN, FIELD_GRASS_WIND_PEAK_MAX)
	grass_wind_dir = -1.0 if randi() % 2 == 0 else 1.0


func _load_first_existing_texture(candidate_paths: Array[String]) -> Texture2D:
	for path in candidate_paths:
		if not ResourceLoader.exists(path):
			continue
		var tex_res := load(path)
		if tex_res is Texture2D:
			return tex_res as Texture2D
	return null
