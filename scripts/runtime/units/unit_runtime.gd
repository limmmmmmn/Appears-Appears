# scripts/runtime/unit_runtime.gd (업데이트)
extends RefCounted
class_name UnitRuntime

signal hp_changed(current: int, max_h: int)
signal dead
signal on_damage_taken # 피격 시그널

var data: UnitData
var current_hp: int
var action_cooldown: float = 0.0 # 공격 쿨타임 추가

func init_from(d: UnitData) -> void:
	data = d
	current_hp = get_max_hp()
	action_cooldown = randf_range(0.0, 1.0) # 전투 시작 시 약간의 시차 부여

func get_max_hp() -> int:
	return data.base_stats.hp if data.base_stats else 10

func is_dead() -> bool:
	return current_hp <= 0

func take_damage(amount: int) -> void:
	current_hp -= amount
	current_hp = max(0, current_hp)
	
	emit_signal("hp_changed", current_hp, get_max_hp())
	emit_signal("on_damage_taken")
	
	if current_hp == 0:
		emit_signal("dead")
