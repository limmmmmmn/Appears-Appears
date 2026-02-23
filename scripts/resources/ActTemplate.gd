extends Resource
class_name ActTemplate

@export var act_id: String = "act_1"
@export var act_name: String = "액트 1"
@export var act_order: int = 1

@export_group("Combat Defaults")
@export var terrain_enemies: Dictionary = {}
@export var default_enemy_pool: Dictionary = {}
@export var elite_pool: Array[String] = []
@export var boss_enemy_id: String = "boss_goblin_king"
@export var default_enemy_count: Dictionary = {"min": 4, "max": 6}
@export var default_elite_chance: float = 0.2

@export_group("Area Count")
@export var min_regular_areas: int = 5
@export var max_regular_areas: int = 7

@export_group("Guarantees")
@export var guaranteed_town_count: int = 1
@export var guaranteed_event_count: int = 1
@export var guaranteed_dungeon_count: int = 1

@export_group("Type Weight")
@export var field_weight: float = 0.5
@export var dungeon_weight: float = 0.25
@export var event_weight: float = 0.15
@export var town_weight: float = 0.10

@export_group("Branching")
@export var skip_link_chance: float = 0.28
@export var side_branch_chance: float = 0.12

@export_group("Area Pools")
@export var start_area_pool: Array = []
@export var field_pool: Array = []
@export var dungeon_pool: Array[Dictionary] = []
@export var event_pool: Array[Dictionary] = []
@export var town_pool: Array = []
@export var fixed_area_path: Array = []
@export var fixed_area_sequence: Array[String] = []

@export_group("Boss")
@export var boss_area: Dictionary = {}
