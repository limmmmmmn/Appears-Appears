# res://Scripts/Data/JobData.gd
class_name JobData extends Resource

# 사양서 직업 시스템 반영
@export var job_name: String = "직업이름" # 예: 전사
@export var base_hp: int = 100
@export var base_attack: int = 10
@export var base_speed: int = 5
@export var allowed_weapon_type: String = "sword" # 무기 제약
@export var sprite: Texture2D # 캐릭터 이미지
