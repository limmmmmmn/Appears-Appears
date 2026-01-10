class_name StageDef
extends Resource

@export var id: String = ""
@export var stage_name: String = ""
@export var enemy_pool: Dictionary = {} # {"enemy_id": weight}
@export var spawn_rate: float = 1.0 # 1.0 = 표준, 낮을수록 자주 등장
