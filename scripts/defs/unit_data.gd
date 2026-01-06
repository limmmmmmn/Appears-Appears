class_name UnitData extends Resource
# [Blueprint v1.4] 3. 데이터 카드 - 캐릭터 및 적 기본 제원

enum AIStrategy { BALANCED, LOW_HP, STRONGEST }

@export_group("Identity")
@export var name: String = "용병"
@export var texture: Texture2D
@export var hire_cost: int = 200

@export_group("Base Stats")
@export var base_hp: int = 100
@export var base_atk: int = 20
@export var base_def: int = 10

@export_group("Dual Speed (가속)")
@export var phys_spd: float = 1.0 # 물리 스킬 쿨다운 가속
@export var mag_spd: float = 1.0  # 마법 스킬 쿨다운 가속

@export_group("Luck")
@export var base_crit: float = 0.05 # 5% 치명타

@export_group("AI & Skills")
@export var strategy: AIStrategy = AIStrategy.BALANCED
@export var skills: Array[SkillData] = []
