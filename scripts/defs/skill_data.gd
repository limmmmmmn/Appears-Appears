# scripts/defs/skill_data.gd
extends Resource
class_name SkillData

@export var skill_name: String
@export var damage_multiplier: float = 1.0
@export var cooldown: float = 1.0
@export var vfx_scene: PackedScene # 스킬 사용 시 재생할 이펙트 씬
