class_name ItemData extends Resource
# [Blueprint v1.4] 4. 아이템 데이터 - 장비 및 소모품

# 아이템 종류: 무기, 방어구, 장신구, 그리고 특수(이벤트/키 아이템)
enum ItemType { WEAPON, ARMOR, ACCESSORY, SPECIAL }

@export_group("Identity")
@export var name: String = "아이템 이름"
@export var icon: Texture2D
@export var type: ItemType = ItemType.WEAPON
@export var price: int = 50
@export_multiline var description: String = ""

@export_group("Stat Modifiers")
@export var bonus_hp: int = 0
@export var bonus_atk: int = 0
@export var bonus_def: int = 0

@export_group("Dual Speed Modifiers (가속 보정)")
# 유닛의 기본 1.0에 더해지는 방식 (예: +0.2면 1.2배 속도)
@export var bonus_phys_spd: float = 0.0 
@export var bonus_mag_spd: float = 0.0

@export_group("Luck Modifiers")
@export var bonus_crit: float = 0.0 # 예: 0.05면 치명타율 5% 증가

@export_group("Special")
# 장착 시 부여될 특수 효과나 스킬이 있다면 여기에 추가 (선택사항)
@export var granted_skills: Array[SkillData] = []
