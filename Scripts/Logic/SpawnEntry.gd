# res://Scripts/Logic/SpawnEntry.gd
class_name SpawnEntry
extends Resource

@export var enemy: EnemyData  # 어떤 적이?
@export var weight: int = 10  # 얼마나 자주? (가중치)
