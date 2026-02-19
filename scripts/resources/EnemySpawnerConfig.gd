extends Resource
class_name EnemySpawnerConfig

@export_group("Resources")
@export var field_enemy_scene: PackedScene = preload("res://scenes/field/FieldEnemy.tscn")

@export_group("Counts")
@export var default_max_enemies: int = 6
@export var field_enemy_count_multiplier: float = 1.35

@export_group("Initial Spawn")
@export var use_spawn_markers_for_initial_spawn: bool = true
@export var spawn_markers_root_path: NodePath = NodePath("EnemySpawnPoints")
@export var min_spawn_distance_between: float = 24.0
@export var edge_spawn_padding: float = 32.0
@export var min_initial_spawn_distance_from_player: float = 120.0
@export var max_spawn_attempts: int = 50

@export_group("Respawn")
@export var respawn_delay_min: float = 1.0
@export var respawn_delay_max: float = 2.5
@export var field_enemy_z: int = 48
@export var proactive_spawn_interval: float = 0.45

@export_group("Tile Mapping")
@export var tile_type_map: Dictionary = {
	0: "grass",
	1: "forest",
	2: "mountain",
	3: "water",
	4: "cave",
}
