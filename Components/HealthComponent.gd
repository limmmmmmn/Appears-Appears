# res://Components/HealthComponent.gd
class_name HealthComponent extends Node

@export var max_hp: int = 100
var current_hp: int

# 내 주인님(플레이어/몬스터)이 누구인지
@onready var parent_entity = get_parent()

func init(hp_value: int):
	max_hp = hp_value
	current_hp = hp_value

func take_damage(amount: int):
	current_hp = max(0, current_hp - amount)
	
	# 전 세계에 알림: "내 주인이 맞았어요!"
	SignalBus.unit_damaged.emit(parent_entity, amount, false)
	
	if current_hp <= 0:
		die()

func heal(amount: int):
	current_hp = min(max_hp, current_hp + amount)
	SignalBus.unit_healed.emit(parent_entity, amount)

func die():
	# 사망 처리 (일단 간단하게)
	print(parent_entity.name + " 사망!")
	# 나중에 여기에 SignalBus.unit_died.emit() 추가 가능
