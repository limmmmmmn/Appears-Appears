class_name Field
extends Node2D

## Top-down stage. Spawns enemies + the visible party (player leading,
## companions trailing). Player movement lives on the Player node;
## encounters fire EventBus signals.

const FIELD_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/field_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const COMPANION_SCENE: PackedScene = preload("res://scenes/companion.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")

## Field is 2x the viewport so the camera has somewhere to scroll.
const FIELD_SIZE: Vector2 = Vector2(1280, 720)
const SPAWN_MARGIN: float = 48.0
## Don't drop slimes within this radius of the player on stage start.
const PARTY_SAFE_RADIUS: float = 80.0

@export var enemies_per_stage: int = 12

@onready var _enemies_root: Node2D = $Enemies
@onready var _party_root: Node2D = $Party

var _player: Player


func _ready() -> void:
	EventBus.party_changed.connect(_setup_party_visuals)
	EventBus.all_battles_resolved.connect(_check_stage_clear)
	EventBus.stage_started.connect(_on_stage_started)
	# Cover the case where party was already set before this scene mounted.
	_setup_party_visuals()


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
	_clear_field_enemies()
	_recenter_party()
	_spawn_enemies()


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


func _spawn_enemies() -> void:
	var safe_origin: Vector2 = _player.position if _player else FIELD_SIZE * 0.5
	for i in enemies_per_stage:
		var fe: FieldEnemy = FIELD_ENEMY_SCENE.instantiate()
		fe.setup(SLIME_DATA)
		fe.position = _random_safe_position(safe_origin)
		_enemies_root.add_child(fe)


func _random_safe_position(avoid: Vector2) -> Vector2:
	for attempt in 24:
		var pos: Vector2 = _random_position()
		if pos.distance_to(avoid) >= PARTY_SAFE_RADIUS:
			return pos
	return _random_position()


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
		EventBus.stage_cleared.emit(GameState.current_stage)
