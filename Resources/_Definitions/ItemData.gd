extends Resource
class_name ItemData

# 장비 타입 정의 (무기, 방어구, 장신구)
enum Type { WEAPON, ARMOR, ACCESSORY }

@export_group("Basic Info")
@export var name: String = "아이템 이름"
@export var icon: Texture2D
@export var item_type: Type = Type.WEAPON
@export_multiline var description: String = "장비 설명"

@export_group("Stat Bonuses")
# 장착 시 올려줄 스탯들 (0이면 효과 없음)
@export var bonus_attack: int = 0      # 공격력 (주로 무기)
@export var bonus_defense: int = 0     # 방어력 (주로 방어구)
@export var bonus_hp: int = 0          # 최대 체력 (주로 방어구/장신구)
@export var bonus_agility: float = 0.0 # 민첩/공속 (주로 장신구)
