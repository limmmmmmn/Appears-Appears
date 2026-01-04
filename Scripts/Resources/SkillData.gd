extends Resource
class_name SkillData

# [설계도 96] 스킬 이름
@export var skill_name: String
# [설계도 97] 데미지 계수 (공격력의 n배)
@export var damage_multiplier: float = 1.0
# [설계도 98] 쿨타임
@export var cooldown: float = 0.0
# [설계도 99] 타격 이펙트 씬
@export var vfx_scene: PackedScene
