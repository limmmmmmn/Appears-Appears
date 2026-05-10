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
const TILE_CARD_POPUP_SCENE: PackedScene = preload("res://scenes/ui/tile_card_popup.tscn")
const TOWN_TILE_TEXTURE: Texture2D = preload("res://assets/sprites/objects/town.png")
const TOWN_TILE_CARD_ID: StringName = &"town"
const TOWN_TILE_CARD_TITLE: String = "Town"
const TOWN_TILE_CARD_DESC: String = "A safe haven appears in your travels."

## Fixed world-map size for every field.
const FIELD_SIZE: Vector2 = Vector2(720, 405)
const TILE_SIZE: int = 16
const SPAWN_MARGIN: float = 48.0
## Don't drop slimes within this radius of the player on stage start.
const PARTY_SAFE_RADIUS: float = 80.0
const DECOR_SAFE_RADIUS: float = 104.0
const TOWN_TILE_SAFE_RADIUS: float = 96.0
const TOWN_TILE_INSET: Vector2 = Vector2(96, 72)
## Just a thin edge margin so the tile sprite doesn't clip the field border.
## The map is small enough that any spawn position is reachable in seconds,
## so we don't bother keeping the tile on-camera at reveal time — letting
## the player walk to it feels more like a proper world map.
const TOWN_TILE_EDGE_MARGIN: float = 32.0
## Minimum distance from the player on reveal — keeps the tile from popping
## right on top of the party.
const TOWN_TILE_MIN_PLAYER_DISTANCE: float = 120.0
const BASE_FIELD_AREA: float = FIELD_SIZE.x * FIELD_SIZE.y

@export var peaceful_start_enemies: int = 3
@export var enemies_added_per_stage: int = 1
@export var enemies_added_per_field_area: float = 1.4
@export var small_forest_cluster_count_min: int = 3
@export var small_forest_cluster_count_max: int = 5
@export var small_forest_min_trees: int = 8
@export var small_forest_max_trees: int = 16
@export var large_forest_cluster_count_min: int = 1
@export var large_forest_cluster_count_max: int = 2
@export var large_forest_min_trees: int = 100
@export var large_forest_max_trees: int = 200
@export var scattered_tree_count: int = 8
@export var spawn_interval: float = 2.5
@export var spawn_batch_size: int = 2

@onready var _background: ColorRect = $Background
@onready var _decorations_root: Node2D = $Decorations
@onready var _town_tile: FieldTownTile = $Tiles/TownTile
@onready var _enemies_root: Node2D = $Enemies
@onready var _party_root: Node2D = $Party

var _player: Player
var _decor_rng := RandomNumberGenerator.new()
var _forest_cells: Dictionary = {}
var _spawn_timer: float = 0.0
var _field_size: Vector2 = FIELD_SIZE
## True once the town tile has been placed on the current map (either silently
## at stage start, or via the unlock-card flow on stage 1's first kill).
var _town_revealed: bool = false
## Suppresses re-firing the unlock-card popup if multiple kill signals slip
## through before the popup actually shows.
var _showing_town_card: bool = false


func _ready() -> void:
	EventBus.party_changed.connect(_setup_party_visuals)
	EventBus.all_battles_resolved.connect(_check_stage_clear)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
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
		_player.set_field_bounds(Vector2.ZERO, _field_size)
	_player.position = _field_size * 0.5
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
	_decor_rng.randomize()
	_apply_stage_field_size(_stage_num)
	_town_revealed = false
	_showing_town_card = false
	_clear_field_enemies()
	_clear_decorations()
	_town_tile.reset()
	_recenter_party()
	_scatter_decorations()
	_spawn_timer = spawn_interval
	_refill_enemy_population(_enemy_count_for_stage(GameState.current_stage))
	# Town tile drops in immediately on every stage *after* the player has
	# unlocked it; stage 1's first run shows the unlock-card popup instead.
	if GameState.has_acquired_tile_card(TOWN_TILE_CARD_ID):
		_reveal_town_tile()


## Teleport the whole party back to the field center for a fresh start.
## Without this, party would drift further and further from spawn each stage.
func _recenter_party() -> void:
	if _player == null:
		return
	var center: Vector2 = _field_size * 0.5
	if _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)
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
	# Forest decorations are now a shop unlock — until the player buys the
	# Forest tile in town, fields stay open grass.
	if GameState.modifier_level(&"forest_tile") < 1:
		return
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var occupied: Dictionary = {}
	var large_count: int = _decor_range(large_forest_cluster_count_min, large_forest_cluster_count_max)
	for i in large_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			large_forest_min_trees,
			large_forest_max_trees,
			7,
			10
		)
	var small_count: int = _decor_range(small_forest_cluster_count_min, small_forest_cluster_count_max)
	for i in small_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			small_forest_min_trees,
			small_forest_max_trees,
			2,
			4
		)
	for i in scattered_tree_count:
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


func _add_forest_cluster(
	avoid: Vector2,
	occupied: Dictionary,
	min_trees: int,
	max_trees: int,
	min_radius: int,
	max_radius: int
) -> void:
	var center: Vector2i = _random_decor_cell(avoid, occupied)
	if center == Vector2i(-1, -1):
		return
	var target_count: int = _decor_range(min_trees, max_trees)
	var radius: int = _decor_range(min_radius, max_radius)
	var cluster: Array[Vector2i] = [center]
	var cluster_set: Dictionary = { center: true }
	var attempts: int = target_count * 28
	while cluster.size() < target_count and attempts > 0:
		attempts -= 1
		var anchor: Vector2i = cluster[_decor_rng.randi_range(0, cluster.size() - 1)]
		var candidate: Vector2i = anchor + _random_forest_step()
		if cluster_set.has(candidate):
			continue
		if not _is_valid_decor_cell(candidate, avoid, occupied):
			continue
		var offset := Vector2(candidate - center)
		var distance: float = offset.length()
		var soft_radius: float = float(radius) + _decor_rng.randf_range(-0.8, 1.15)
		if distance > soft_radius:
			continue
		var keep_chance: float = clampf(1.08 - (distance / maxf(float(radius), 1.0)) * 0.58, 0.38, 0.96)
		if _decor_rng.randf() > keep_chance:
			continue
		cluster.append(candidate)
		cluster_set[candidate] = true
	for cell in cluster:
		_add_tree_cell(cell, occupied, true)


func _random_forest_step() -> Vector2i:
	var steps: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	return steps[_decor_rng.randi_range(0, steps.size() - 1)]


func _decor_range(min_value: int, max_value: int) -> int:
	return _decor_rng.randi_range(mini(min_value, max_value), maxi(min_value, max_value))


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
	return floori((_field_size.x - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _max_grid_y() -> int:
	return floori((_field_size.y - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _refill_enemy_population(max_to_spawn: int) -> void:
	var desired_count: int = _enemy_count_for_stage(GameState.current_stage)
	var missing_count: int = desired_count - _enemies_root.get_child_count()
	var spawn_count: int = mini(max_to_spawn, missing_count)
	for i in spawn_count:
		_spawn_field_enemy(_enemy_data_for_stage(GameState.current_stage))


func _spawn_field_enemy(data: EnemyData) -> void:
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var fe: FieldEnemy = FIELD_ENEMY_SCENE.instantiate()
	fe.setup(data)
	fe.wander_bounds_min = Vector2.ONE * 16.0
	fe.wander_bounds_max = _field_size - Vector2.ONE * 16.0
	fe.position = _random_spawn_position_for_enemy(data, safe_origin)
	_enemies_root.add_child(fe)


func _enemy_count_for_stage(stage: int) -> int:
	var field_area: float = _field_size.x * _field_size.y
	var area_ratio: float = field_area / BASE_FIELD_AREA
	var area_bonus: int = int(round((area_ratio - 1.0) * enemies_added_per_field_area))
	var pressure_bonus: int = maxi(0, stage - 1) * enemies_added_per_stage
	return peaceful_start_enemies + area_bonus + pressure_bonus + GameState.extra_field_enemies()


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
	return _town_revealed and pos.distance_to(_town_tile.position) < TOWN_TILE_SAFE_RADIUS


func _random_position() -> Vector2:
	return Vector2(
		randf_range(SPAWN_MARGIN, _field_size.x - SPAWN_MARGIN),
		randf_range(SPAWN_MARGIN, _field_size.y - SPAWN_MARGIN),
	)


func _apply_stage_field_size(_stage_num: int) -> void:
	_field_size = FIELD_SIZE
	_background.size = _field_size
	_town_tile.position = _hidden_town_tile_position()
	if _player and _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)


func _on_enemy_defeated(_enemy: Node, _gold: int, _world_position: Vector2) -> void:
	if GameState.current_stage <= 0:
		return
	if GameState.has_acquired_tile_card(TOWN_TILE_CARD_ID):
		return
	if _showing_town_card:
		return
	# First kill of stage 1 unlocks the town tile via a centered card popup;
	# subsequent stages skip the popup and just drop the tile at stage start.
	if GameState.current_stage == 1:
		_show_town_card_popup()


func _show_town_card_popup() -> void:
	_showing_town_card = true
	var popup: TileCardPopup = TILE_CARD_POPUP_SCENE.instantiate()
	popup.setup(TOWN_TILE_CARD_TITLE, TOWN_TILE_TEXTURE, TOWN_TILE_CARD_DESC)
	popup.closed.connect(_on_town_card_closed)
	get_tree().paused = true
	# Add to the scene root so the popup survives even if the field is
	# rebuilt / hidden in some debug edge case.
	get_parent().add_child(popup)


func _on_town_card_closed() -> void:
	_showing_town_card = false
	GameState.acquire_tile_card(TOWN_TILE_CARD_ID)
	get_tree().paused = false
	_reveal_town_tile()


func _reveal_town_tile() -> void:
	if _town_revealed:
		return
	_town_revealed = true
	var avoid: Vector2 = _player.global_position if _player else _field_size * 0.5
	_town_tile.position = _town_tile_reveal_position(avoid)
	_town_tile.reveal_with_impact()


## Random spot anywhere on the field (with a thin edge margin so the sprite
## doesn't clip). Retries a few times to keep at least
## `TOWN_TILE_MIN_PLAYER_DISTANCE` away from the player so the tile doesn't
## land on top of them; if no candidate qualifies, returns whatever was
## sampled — being a bit close is fine on a small map.
func _town_tile_reveal_position(avoid: Vector2) -> Vector2:
	var x_min: float = TOWN_TILE_EDGE_MARGIN
	var x_max: float = _field_size.x - TOWN_TILE_EDGE_MARGIN
	var y_min: float = TOWN_TILE_EDGE_MARGIN
	var y_max: float = _field_size.y - TOWN_TILE_EDGE_MARGIN
	var fallback := Vector2(
		randf_range(x_min, x_max),
		randf_range(y_min, y_max),
	)
	for attempt in 24:
		var candidate := Vector2(
			randf_range(x_min, x_max),
			randf_range(y_min, y_max),
		)
		if candidate.distance_to(avoid) >= TOWN_TILE_MIN_PLAYER_DISTANCE:
			return candidate
	return fallback


func _hidden_town_tile_position() -> Vector2:
	return Vector2(_field_size.x + 256.0, _field_size.y + 256.0)


## All windows closed AND the field is empty → stage clear.
## Echo Strike can keep extra windows running after the last field enemy is
## consumed, so we listen to all_battles_resolved (not battle_window_closed)
## and combine with the field-empty check.
func _check_stage_clear() -> void:
	if not _town_revealed and _enemies_root.get_child_count() == 0:
		_refill_enemy_population(spawn_batch_size)
