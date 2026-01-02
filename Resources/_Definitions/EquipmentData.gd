# res://Resources/_Definitions/EquipmentData.gd
class_name EquipmentData
extends ItemData

enum SlotType { WEAPON, ARMOR, ACCESSORY }

@export var slot_type: SlotType = SlotType.WEAPON
@export var attack_bonus: int = 0
@export var defense_bonus: int = 0
@export var agility_bonus: int = 0
@export var speed_modifier: float = 0.0 # 무기 속도 보정
