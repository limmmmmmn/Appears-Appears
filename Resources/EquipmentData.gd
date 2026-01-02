# res://Resources/EquipmentData.gd
extends ItemData # 할아버지 상속
class_name EquipmentData

enum EquipmentSlot { WEAPON, ARMOR, ACCESSORY }

@export_group("장비 스탯")
@export var slot: EquipmentSlot = EquipmentSlot.WEAPON
@export var attack_bonus: int = 0
@export var agility_bonus: int = 0
@export var hp_bonus: int = 0

# [New] ★ 태어날 때(초기화) 자동으로 명찰 바꿔달기!
func _init():
	type = ItemType.EQUIPMENT
