# res://Resources/ConsumableItem.gd (새로 만들기)
extends ItemData  # 할아버지 상속
class_name ConsumableItem

enum EffectType { HEAL_HP, BUFF_ATK, BUFF_AGILITY }

@export_group("소비 효과")
@export var effect_type: EffectType = EffectType.HEAL_HP
@export var value: int = 30 # 회복량

# [New] ★ 태어날 때(초기화) 자동으로 명찰 바꿔달기!
func _init():
	type = ItemType.CONSUMABLE
