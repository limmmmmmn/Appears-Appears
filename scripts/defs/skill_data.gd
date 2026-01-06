class_name SkillData extends Resource
# [Blueprint v1.4] 3. 데이터 카드 - 물리/마법 판정 분리

enum SkillCategory { PHYSICAL, MAGIC }

@export_group("Identity")
@export var name: String = "기술"
@export var category: SkillCategory = SkillCategory.PHYSICAL

@export_group("Combat Logic")
@export var cooldown_time: float = 3.0

# --- JRPG식 판정 분리 ---
@export var power_multiplier: float = 1.0 # 물리용: ATK의 배율
@export var is_fixed_damage: bool = false # 마법용: 고정 데미지 여부
@export var fixed_damage_value: int = 0    # 마법용: 고정 데미지 수치
