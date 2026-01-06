class_name ItemData extends Resource
# [Blueprint v1.4] 3. 데이터 카드 - 아이템 정의

enum ItemType { WEAPON, ARMOR, ACCESSORY, CONSUMABLE }

@export_group("Identity")
@export var name: String = ""
@export var price: int = 100
@export var type: ItemType = ItemType.WEAPON

@export_group("Stat Bonuses")
@export var atk_bonus: int = 0
@export var def_bonus: int = 0
@export var hp_bonus: int = 0
@export var phys_spd_bonus: float = 0.0
@export var mag_spd_bonus: float = 0.0
@export var crit_bonus: float = 0.0
