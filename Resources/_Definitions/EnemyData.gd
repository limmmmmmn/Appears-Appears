# res://Resources/_Definitions/EnemyData.gd
class_name EnemyData
extends UnitData

@export_group("Rewards")
@export var drop_gold: int = 10
@export var drop_exp: int = 5

@export_group("AI")
@export var aggression: float = 1.0 # 공격 성향 등 (추후 확장용)
