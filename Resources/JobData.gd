# res://Resources/JobData.gd
class_name JobData extends Resource

@export_group("기본 정보")
@export var job_name: String = "직업명"
@export var sprite: Texture2D
@export_enum("attack", "heal") var role: String = "attack"

@export_group("스탯")
@export var base_hp: int = 100
@export var base_attack: int = 10
@export var base_speed: int = 5
