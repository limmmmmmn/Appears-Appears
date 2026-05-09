class_name Field
extends Node2D

## Top-down stage. Spawns enemies + the visible party (player leading,
## companions trailing). Player movement lives on the Player node;
## encounters fire EventBus signals.

const FIELD_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/field_enemy.tscn")
const FIELD_DECORATION_SCENE: PackedScene = preload("res://scenes/decorations/field_decoration.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const COMPANION_SCENE: PackedScene = preload("res://scenes/companion.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")
const BAT_DATA: EnemyData = preload("res://data/enemies/bat.tres")
const ORC_DATA: EnemyData = preload("res://data/enemies/orc.tres")
const TREE_TEXTURE: Texture2D = preload("res://assets/sprites/decorations/tree.png")

## Field is 1.5x the viewport so the camera still scrolls, but the map stays compact.
const FIELD_SIZE: Vector2 = Vector2(960, 540)
const TILE_SIZE: int = 16
const SPAWN_MARGIN: float = 48.0
## Don't drop slimes within this radius of the player on stage start.
const PARTY_SAFE_RADIUS: float = 80.0
const DECOR_SAFE_RADIUS: float = 104.0
const TOWN_TILE_SAFE_RADIUS: float = 96.0

@export var enemies_per_stage: int = 12
@export var enemies_added_per_stage: int = 2
@export var tree_count: int = 8
@export var forest_cluster_count: int = 7
@export var forest_cluster_min_trees: int = 14
@export var forest_cluster_max_trees: int = 26
@export var spawn_interval: float = 2.5
@export var spawn_batch_size: int = 2

@onready var _decorations_root: Node2D = $Decorations
@onready var _town_tile: FieldTownTile = $Tiles/TownTile
@onready var _enemies_root: Node2D = $Enemies
@onready var _party_root: Node2D = $Party

var _player: Player
var _decor_rng := RandomNumberGenerator.new()
var _forest_cells: Dictionary = {}
var _spawn_timer: float = 0.0


func _ready() -> void:
	EventBus.party_changed.connect(_setup_party_visuals)
	EventBus.all_battles_resolved.connect(_check_stage_clear)
	EventBus.stage_started.connect(_on_stage_started)
	# Cover the case where party was already set before this scene mounted.
	_setup_party_visuals()


func _process(delta: float) -> void:
	if GameState.current_stage <= 0 or GameState.is_party_wiped():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval
	_refill_enemy_population(spawn_batch_size)


# ─── Party visuals (data-driven) ──────────────────────────────────────
## Rebuilds the visible party from GameState.party. Slot 0 = player avatar,
## slots 1..N = companions trailing each previous member like a JRPG snake.
func _setup_party_visuals() -> void:
	for child in _party_root.get_children():
		child.queue_free()
	_player = null
	if GameState.party_size() == 0:
		return
	_player = PLAYER_SCENE.instantiate()
	_player.setup(GameState.party[0])
	if _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, FIELD_SIZE)
	_player.position = FIELD_SIZE * 0.5
	_party_root.add_child(_player)
	var leader: Node2D = _player
	for i in range(1, GameState.party_size()):
		var comp: Companion = COMPANION_SCENE.instantiate()
		comp.setup(GameState.party[i])
		comp.leader = leader
		# All stack on the player exactly — z_index on the player keeps the
		# leader visible until the column starts trailing on first move.
		comp.position = _player.position
		_party_root.add_child(comp)
		leader = comp


# ─── Enemy spawning ───────────────────────────────────────────────────
func _on_stage_started(_stage_num: int) -> void:
	_decor_rng.seed = int(_stage_num * 1009 + 17)
	_clear_field_enemies()
	_clear_decorations()
	_town_tile.reset()
	_recenter_party()
	_scatter_decorations()
	_spawn_timer = spawn_interval
	_refill_enemy_population(_enemy_count_for_stage(GameState.current_stage))


## Teleport the whole party back to the field center for a fresh start.
## Without this, party would drift further and further from spawn each stage.
func _recenter_party() -> void:
	if _player == null:
		return
	var center: Vector2 = FIELD_SIZE * 0.5
	_player.position = center
	# Reset camera smoothing so it doesn't pan from the old spot.
	if _player.has_method("snap_camera"):
		_player.snap_camera()
	for child in _party_root.get_children():
		if child is Companion:
			child.position = center


func _clear_field_enemies() -> void:
	for child in _enemies_root.get_children():
		child.queue_free()


func _clear_decorations() -> void:
	_forest_cells.clear()
	for child in _decorations_root.get_children():
		child.queue_free()


func _scatter_decorations() -> void:
	var safe_origin: Vector2 = _player.position if _player else FIELD_SIZE * 0.5
	var occupied: Dictionary = {}
	for i in forest_cluster_count:
		_add_forest_cluster(safe_origin, occupied)
	for i in tree_count:
		var cell: Vector2i = _random_decor_cell(safe_origin, occupied)
		if cell == Vector2i(-1, -1):
			return
		_add_tree_cell(cell, occupied)


func _add_decoration(texture: Texture2D, pos: Vector2) -> void:
	var sprite := FIELD_DECORATION_SCENE.instantiate() as Sprite2D
	sprite.texture = texture
	sprite.position = pos
	sprite.scale = Vector2.ONE
	_decorations_root.add_child(sprite)


func _add_forest_cluster(avoid: Vector2, occupied: Dictionary) -> void:
	var center: Vector2i = _random_decor_cell(avoid, occupied)
	if center == Vector2i(-1, -1):
		return
	var target_count: int = _decor_rng.randi_range(forest_cluster_min_trees, forest_cluster_max_trees)
	var radius: int = _decor_rng.randi_range(2, 4)
	var candidates: Array[Dictionary] = []
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var cell := center + Vector2i(x, y)
			if not _is_valid_decor_cell(cell, avoid, occupied):
				continue
			var distance: float = Vector2(float(x), float(y)).length()
			var edge_noise: float = _decor_rng.randf_range(-0.45, 0.45)
			candidates.append({
				"cell": cell,
				"score": -distance + edge_noise,
			})
	candidates.sort_custom(_compare_forest_candidate)
	var count: int = mini(target_count, candidates.size())
	for i in count:
		_add_tree_cell(candidates[i]["cell"], occupied, true)


func _compare_forest_candidate(a: Dictionary, b: Dictionary) -> bool:
	return float(a["score"]) > float(b["score"])


func _add_tree_cell(cell: Vector2i, occupied: Dictionary, is_forest: bool = false) -> void:
	occupied[cell] = true
	if is_forest:
		_forest_cells[cell] = true
	_add_decoration(TREE_TEXTURE, _cell_to_world(cell))


func _random_decor_cell(avoid: Vector2, occupied: Dictionary) -> Vector2i:
	for attempt in 80:
		var cell := Vector2i(
			_decor_rng.randi_range(_min_grid_index(), _max_grid_x()),
			_decor_rng.randi_range(_min_grid_index(), _max_grid_y())
		)
		if _is_valid_decor_cell(cell, avoid, occupied):
			return cell
	return Vector2i(-1, -1)


func _is_valid_decor_cell(cell: Vector2i, avoid: Vector2, occupied: Dictionary) -> bool:
	if occupied.has(cell):
		return false
	var pos: Vector2 = _cell_to_world(cell)
	return pos.distance_to(avoid) >= DECOR_SAFE_RADIUS and not _is_near_town_tile(pos)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE * 0.5, cell.y * TILE_SIZE + TILE_SIZE * 0.5)


func _min_grid_index() -> int:
	return ceili(SPAWN_MARGIN / float(TILE_SIZE))


func _max_grid_x() -> int:
	return floori((FIELD_SIZE.x - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _max_grid_y() -> int:
	return floori((FIELD_SIZE.y - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _refill_enemy_population(max_to_spawn: int) -> void:
	var desired_count: int = _enemy_count_for_stage(GameState.current_stage)
	var missing_count: int = desired_count - _enemies_root.get_child_count()
	var spawn_count: int = mini(max_to_spawn, missing_count)
	for i in spawn_count:
		_spawn_field_enemy(_enemy_data_for_stage(GameState.current_stage))


func _spawn_field_enemy(data: EnemyData) -> void:
	var safe_origin: Vector2 = _player.position if _player else FIELD_SIZE * 0.5
	var fe: FieldEnemy = FIELD_ENEMY_SCENE.instantiate()
	fe.setup(data)
	fe.wander_bounds_min = Vector2.ONE * 16.0
	fe.wander_bounds_max = FIELD_SIZE - Vector2.ONE * 16.0
	fe.position = _random_spawn_position_for_enemy(data, safe_origin)
	_enemies_root.add_child(fe)


func _enemy_count_for_stage(stage: int) -> int:
	return enemies_per_stage + maxi(0, stage - 1) * enemies_added_per_stage + GameState.extra_field_enemies()


func _enemy_data_for_stage(stage: int) -> EnemyData:
	var roll: float = randf()
	if stage >= 5:
		if roll < 0.20:
			return ORC_DATA
		if roll < 0.50:
			return BAT_DATA
		return SLIME_DATA
	if stage >= 3:
		if roll < 0.35:
			return BAT_DATA
	return SLIME_DATA


func _random_spawn_position_for_enemy(data: EnemyData, avoid: Vector2) -> Vector2:
	if data == BAT_DATA:
		return _random_forest_position(avoid)
	if data == SLIME_DATA:
		return _random_grassland_position(avoid)
	return _random_safe_position(avoid)


func _random_forest_position(avoid: Vector2) -> Vector2:
	var cells: Array = _forest_cells.keys()
	cells.shuffle()
	for cell: Vector2i in cells:
		var pos: Vector2 = _cell_to_world(cell)
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_safe_position(avoid)


func _random_grassland_position(avoid: Vector2) -> Vector2:
	for attempt in 48:
		var cell := Vector2i(
			_decor_rng.randi_range(_min_grid_index(), _max_grid_x()),
			_decor_rng.randi_range(_min_grid_index(), _max_grid_y())
		)
		if _forest_cells.has(cell):
			continue
		var pos: Vector2 = _cell_to_world(cell)
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_safe_position(avoid)


func _random_safe_position(avoid: Vector2) -> Vector2:
	for attempt in 24:
		var pos: Vector2 = _random_position()
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_position()


func _is_safe_enemy_spawn_position(pos: Vector2, avoid: Vector2) -> bool:
	return pos.distance_to(avoid) >= PARTY_SAFE_RADIUS and not _is_near_town_tile(pos)


func _is_near_town_tile(pos: Vector2) -> bool:
	return pos.distance_to(_town_tile.position) < TOWN_TILE_SAFE_RADIUS


func _random_position() -> Vector2:
	return Vector2(
		randf_range(SPAWN_MARGIN, FIELD_SIZE.x - SPAWN_MARGIN),
		randf_range(SPAWN_MARGIN, FIELD_SIZE.y - SPAWN_MARGIN),
	)


## All windows closed AND the field is empty → stage clear.
## Echo Strike can keep extra windows running after the last field enemy is
## consumed, so we listen to all_battles_resolved (not battle_window_closed)
## and combine with the field-empty check.
func _check_stage_clear() -> void:
	if _enemies_root.get_child_count() == 0:
		_refill_enemy_population(spawn_batch_size)
