class_name SkillDef
extends Resource

@export var id: String = ""
@export var cooldown: float = 3.0
@export var target_rule: String = "single_enemy"
@export var power: int = 10

# 나중을 위한 필수 필드 (빈 문자열 허용)
@export var effect_id: String = "" 
@export var anim_key: String = ""
