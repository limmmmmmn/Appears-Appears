# res://Scripts/Data/EnemyData.gd
class_name EnemyData extends Resource

# 사양서 몬스터 관리
@export var enemy_name: String = "슬라임"
@export var hp: int = 50
@export var attack: int = 5
@export var speed: int = 3
@export var exp_reward: int = 10
@export var gold_reward: int = 5
@export var sprite: Texture2D
