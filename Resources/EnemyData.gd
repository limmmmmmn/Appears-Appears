# res://Resources/EnemyData.gd
class_name EnemyData extends Resource

@export_group("기본 정보")
@export var enemy_name: String = "슬라임"
@export var sprite: Texture2D

@export_group("전투 스탯")
@export var max_hp: int = 50
@export var attack: int = 5
@export var speed: int = 3
@export var xp_reward: int = 10
