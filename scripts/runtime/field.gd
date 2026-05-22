class_name Field
extends Node2D

## Top-down field loop. Spawns enemies + the visible party (player leading,
## companions trailing). Player movement lives on the Player node;
## encounters fire EventBus signals.

const FIELD_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/field_enemy.tscn")
const FIELD_DECORATION_SCENE: PackedScene = preload("res://scenes/decorations/field_decoration.tscn")
const FIELD_ITEM_DROP_SCENE: PackedScene = preload("res://scenes/objects/field_item_drop.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const COMPANION_SCENE: PackedScene = preload("res://scenes/companion.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")
const SLIME_CHASER_DATA: EnemyData = preload("res://data/enemies/slime_chaser.tres")
const BAT_DATA: EnemyData = preload("res://data/enemies/bat.tres")
const ORC_DATA: EnemyData = preload("res://data/enemies/orc.tres")
const BLADE_BUG_DATA: EnemyData = preload("res://data/enemies/blade_bug.tres")
const TREE_TEXTURE: Texture2D = preload("res://assets/sprites/decorations/tree.png")

## Base world-map size. Starts as one camera-sized field; nodes expand it.
const FIELD_SIZE: Vector2 = Vector2(640, 360)
const TILE_SIZE: int = 16
const SPAWN_MARGIN: float = 24.0
## Don't drop slimes within this radius of the player on field-loop start.
const PARTY_SAFE_RADIUS: float = 48.0
const DECOR_SAFE_RADIUS: float = 104.0
const TOWN_TILE_SAFE_RADIUS: float = 96.0
const TOWN_TILE_INSET: Vector2 = Vector2(96, 72)
const DROP_PLAYER_SAFE_RADIUS: float = 42.0
const DROP_SEPARATION_RADIUS: float = 20.0
const DROP_SCATTER_RADIUS_MIN: float = 28.0
const DROP_SCATTER_RADIUS_MAX: float = 52.0
const CLEARED_FIELD_REMAINING_TIME: float = 3.0

@export var initial_slime_count: int = 16
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
@export var spawn_batch_size: int = 3
@export var entry_burst_bonus: int = 0
@export var crowd_growth_per_wave: int = 1
@export var max_crowd_pressure: int = 7
@export var field_loop_time: float = 20.0

@onready var _background: ColorRect = $Background
@onready var _decorations_root: Node2D = $Decorations
@onready var _town_tile: FieldTownTile = get_node_or_null("Tiles/TownTile") as FieldTownTile
@onready var _items_root: Node2D = $Items
@onready var _enemies_root: Node2D = $Enemies
@onready var _party_root: Node2D = $Party

var _player: Player
var _decor_rng := RandomNumberGenerator.new()
var _forest_cells: Dictionary = {}
var _spawn_timer: float = 0.0
var _crowd_pressure: int = 0
var _field_size: Vector2 = FIELD_SIZE
var _town_revealed: bool = false
var _loop_elapsed: float = 0.0
var _loop_settlement_time: float = 20.0
var _loop_complete: bool = false
var _loop_hurried: bool = false
var _last_countdown_seconds: int = -1
var _active_battle_windows: int = 0
var _chaser_spawned_this_loop: bool = false


func _ready() -> void:
	EventBus.party_changed.connect(_setup_party_visuals)
	EventBus.battle_window_opened.connect(_on_battle_window_opened)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)
	EventBus.all_battles_resolved.connect(_check_refill_after_battles)
	EventBus.field_loop_started.connect(_on_field_loop_started)
	EventBus.field_item_drop_requested.connect(_on_field_item_drop_requested)
	EventBus.field_gold_drop_requested.connect(_on_field_gold_drop_requested)
	EventBus.field_loop_finish_requested.connect(_on_field_loop_finish_requested)
	# Cover the case where party was already set before this scene mounted.
	_setup_party_visuals()


func _process(delta: float) -> void:
	if GameState.field_loop_count <= 0 or GameState.is_party_wiped():
		return
	_update_loop_timer(delta)
	if GameState.is_field_battle_paused():
		return
	if _loop_complete:
		return
	_try_hurry_loop_when_cleared()
	if _loop_hurried:
		return
	if not GameState.field_spawner_enabled():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval * GameState.field_spawn_interval_multiplier()
	_grow_crowd_pressure()
	_refill_enemy_population(spawn_batch_size + GameState.field_spawn_batch_bonus())


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
func _on_field_loop_started(_loop_num: int) -> void:
	_decor_rng.randomize()
	_apply_field_size()
	_town_revealed = false
	_loop_elapsed = 0.0
	_loop_settlement_time = field_loop_time
	_loop_complete = false
	_loop_hurried = false
	_active_battle_windows = 0
	_chaser_spawned_this_loop = false
	_last_countdown_seconds = -1
	_emit_loop_timer_changed()
	_clear_field_enemies()
	_clear_decorations()
	_clear_items()
	_crowd_pressure = entry_burst_bonus
	if _town_tile:
		_town_tile.reset()
	_recenter_party()
	_scatter_decorations()
	_spawn_timer = spawn_interval
	_refill_enemy_population(_desired_enemy_count())
	_spawn_repeating_node_drops()


## Teleport the whole party back to the field center for a fresh start.
## Without this, party would drift further and further from spawn each loop.
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
		_enemies_root.remove_child(child)
		child.queue_free()


func _despawn_field_enemies() -> void:
	for child in _enemies_root.get_children():
		if child is FieldEnemy:
			(child as FieldEnemy).despawn_with_pop()
		else:
			child.queue_free()


func _clear_decorations() -> void:
	_forest_cells.clear()
	for child in _decorations_root.get_children():
		child.queue_free()


func _clear_items() -> void:
	for child in _items_root.get_children():
		child.queue_free()


func _scatter_decorations() -> void:
	if not GameState.has_skill_node(&"map_expand"):
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


func _grow_crowd_pressure() -> void:
	if _active_field_enemy_count() <= 0:
		_crowd_pressure = 0
		return
	_crowd_pressure = mini(max_crowd_pressure + GameState.field_crowd_cap_bonus(), _crowd_pressure + crowd_growth_per_wave)


func _refill_enemy_population(max_to_spawn: int) -> void:
	var desired_count: int = _desired_enemy_count()
	var missing_count: int = desired_count - _active_field_enemy_count()
	var spawn_count: int = maxi(0, mini(max_to_spawn, missing_count))
	for i in spawn_count:
		_spawn_field_enemy(_enemy_data_for_current_nodes())


func _active_field_enemy_count() -> int:
	var count: int = 0
	for child in _enemies_root.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _active_item_count() -> int:
	var count: int = 0
	for child in _items_root.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _on_battle_window_opened(_window: Node) -> void:
	_active_battle_windows += 1


func _on_battle_window_closed(_window: Node) -> void:
	_active_battle_windows = maxi(0, _active_battle_windows - 1)


func debug_spawn_all_enemy_types() -> int:
	var enemy_types: Array[EnemyData] = [
		SLIME_DATA,
		SLIME_CHASER_DATA,
		BAT_DATA,
		ORC_DATA,
		BLADE_BUG_DATA,
	]
	for data: EnemyData in enemy_types:
		_spawn_field_enemy(data)
	return enemy_types.size()


func _desired_enemy_count() -> int:
	return _enemy_count_for_current_nodes() + _crowd_pressure


func _spawn_field_enemy(data: EnemyData) -> void:
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var fe: FieldEnemy = FIELD_ENEMY_SCENE.instantiate()
	fe.setup(data)
	fe.wander_bounds_min = Vector2.ONE * 16.0
	fe.wander_bounds_max = _field_size - Vector2.ONE * 16.0
	fe.position = _random_spawn_position_for_enemy(data, safe_origin)
	_enemies_root.add_child(fe)
	if data == SLIME_CHASER_DATA:
		_chaser_spawned_this_loop = true


func _enemy_count_for_current_nodes() -> int:
	return initial_slime_count + GameState.field_enemy_count_bonus()


func _enemy_data_for_current_nodes() -> EnemyData:
	if not GameState.chaser_enemies_enabled():
		return SLIME_DATA
	if not _chaser_spawned_this_loop:
		return SLIME_CHASER_DATA
	return SLIME_CHASER_DATA if randf() < 0.35 else SLIME_DATA


func _random_spawn_position_for_enemy(data: EnemyData, avoid: Vector2) -> Vector2:
	if data == BAT_DATA:
		return _random_forest_position(avoid)
	if data == SLIME_DATA or data == SLIME_CHASER_DATA:
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
	return pos.distance_to(avoid) >= _party_safe_radius() and not _is_near_town_tile(pos)


func _party_safe_radius() -> float:
	return PARTY_SAFE_RADIUS


func _on_field_item_drop_requested(item: ItemData, world_position: Vector2) -> void:
	if item == null:
		return
	_spawn_item_drop(item, world_position)


func _spawn_item_drop(item: ItemData, world_position: Vector2) -> void:
	var drop := FIELD_ITEM_DROP_SCENE.instantiate() as FieldItemDrop
	drop.setup(item)
	drop.position = _drop_position_near(world_position)
	_items_root.add_child(drop)
	drop.reveal_with_pop()


func _on_field_gold_drop_requested(amount: int, world_position: Vector2) -> void:
	if amount <= 0:
		return
	_spawn_gold_drop(amount, world_position)


func _spawn_gold_drop(amount: int, world_position: Vector2) -> void:
	var drop := FIELD_ITEM_DROP_SCENE.instantiate() as FieldItemDrop
	drop.setup_gold_drop(amount)
	drop.position = _drop_position_near(world_position)
	_items_root.add_child(drop)
	drop.reveal_with_pop()


func _spawn_repeating_node_drops() -> void:
	var origin: Vector2 = _field_size * 0.5
	if GameState.gold_drops_enabled():
		_spawn_gold_drop(1, origin)
	if GameState.item_drops_enabled():
		var item: ItemData = ItemDB.get_by_id(&"hero_sword")
		if item:
			_spawn_item_drop(item, origin)


func _drop_position_near(origin: Vector2) -> Vector2:
	var safe_origin: Vector2 = _clamp_field_position(origin)
	for attempt in 36:
		var angle: float = randf() * TAU
		var radius: float = randf_range(DROP_SCATTER_RADIUS_MIN, DROP_SCATTER_RADIUS_MAX)
		var candidate: Vector2 = _clamp_field_position(safe_origin + Vector2(cos(angle), sin(angle)) * radius)
		if _is_valid_drop_position(candidate):
			return candidate
	for attempt in 36:
		var candidate: Vector2 = _random_position()
		if _is_valid_drop_position(candidate):
			return candidate
	return safe_origin


func _is_valid_drop_position(pos: Vector2) -> bool:
	var party_pos: Vector2 = _player.position if _player else _field_size * 0.5
	if pos.distance_to(party_pos) < DROP_PLAYER_SAFE_RADIUS:
		return false
	for child in _items_root.get_children():
		if child is Node2D and not child.is_queued_for_deletion():
			if pos.distance_to((child as Node2D).position) < DROP_SEPARATION_RADIUS:
				return false
	return true


func _clamp_field_position(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 16.0, _field_size.x - 16.0),
		clampf(pos.y, 16.0, _field_size.y - 16.0)
	)


func _is_near_town_tile(pos: Vector2) -> bool:
	return _town_tile != null and _town_revealed and pos.distance_to(_town_tile.position) < TOWN_TILE_SAFE_RADIUS


func _random_position() -> Vector2:
	return Vector2(
		randf_range(SPAWN_MARGIN, _field_size.x - SPAWN_MARGIN),
		randf_range(SPAWN_MARGIN, _field_size.y - SPAWN_MARGIN),
	)


func _apply_field_size() -> void:
	_field_size = FIELD_SIZE * GameState.field_size_multiplier()
	_background.size = _field_size
	if _town_tile:
		_town_tile.position = _hidden_town_tile_position()
	if _player and _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)


func get_field_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _field_size)


func _reveal_town_tile() -> void:
	if _town_tile == null or _town_revealed:
		return
	_town_revealed = true
	_town_tile.position = _town_tile_corner_position()
	_town_tile.reveal_with_impact()


func _update_loop_timer(delta: float) -> void:
	if _loop_complete:
		return
	_loop_elapsed += delta
	_emit_loop_timer_changed()
	if _loop_elapsed >= _loop_settlement_time:
		_finish_field_loop_timer()


func _finish_field_loop_timer() -> void:
	_loop_complete = true
	GameState.clear_move_speed_drag()
	EventBus.field_loop_timer_changed.emit(0)
	EventBus.field_loop_settled.emit(GameState.field_loop_count)


func _on_field_loop_finish_requested() -> void:
	if GameState.field_loop_count <= 0 or _loop_complete:
		return
	_loop_elapsed = _loop_settlement_time
	_finish_field_loop_timer()


func _emit_loop_timer_changed() -> void:
	var remaining: int = maxi(0, ceili(_loop_settlement_time - _loop_elapsed))
	if remaining == _last_countdown_seconds:
		return
	_last_countdown_seconds = remaining
	EventBus.field_loop_timer_changed.emit(remaining)


func _try_hurry_loop_when_cleared() -> void:
	if _loop_hurried or _loop_complete:
		return
	if _active_battle_windows > 0:
		return
	if _active_field_enemy_count() > 0 or _active_item_count() > 0:
		return
	var remaining: float = _loop_settlement_time - _loop_elapsed
	if remaining <= CLEARED_FIELD_REMAINING_TIME:
		return
	_loop_hurried = true
	_loop_settlement_time = _loop_elapsed + CLEARED_FIELD_REMAINING_TIME
	_last_countdown_seconds = -1
	_emit_loop_timer_changed()


func _town_tile_corner_position() -> Vector2:
	var candidates: Array[Vector2] = [
		TOWN_TILE_INSET,
		Vector2(_field_size.x - TOWN_TILE_INSET.x, TOWN_TILE_INSET.y),
		Vector2(TOWN_TILE_INSET.x, _field_size.y - TOWN_TILE_INSET.y),
		_field_size - TOWN_TILE_INSET,
	]
	return candidates.pick_random()


func _hidden_town_tile_position() -> Vector2:
	return Vector2(_field_size.x + 256.0, _field_size.y + 256.0)


## All windows closed AND the field is empty → refill pressure.
## Echo Strike can keep extra windows running after the last field enemy is
## consumed, so we listen to all_battles_resolved (not battle_window_closed)
## and combine with the field-empty check.
func _check_refill_after_battles() -> void:
	_active_battle_windows = 0
	if _loop_complete:
		return
	if not GameState.field_spawner_enabled():
		return
	if not _town_revealed and _active_field_enemy_count() == 0:
		_refill_enemy_population(spawn_batch_size)
