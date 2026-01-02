extends Resource
class_name BattleStats

@export_group("Base Stats")
@export var max_hp: int = 100
@export var attack_power: int = 10
@export var base_defense: int = 0

@export_group("Attack Settings")
# 무기 속도: 기본적으로 몇 초마다 때릴지 (낮을수록 빠름)
@export var base_weapon_cooldown: float = 2.0 

# 민첩성: 높을수록 쿨타임이 줄어듦 (예: 20이면 1.2배 빨라짐)
@export var agility: float = 0.0

# ---------------------------------------------------------
# [핵심] 쿨타임 계산 공식
# ---------------------------------------------------------
func get_final_cooldown() -> float:
	# 민첩성 1당 공격 속도 1% 증가 공식
	# 예: 기본 2초, 민첩 100 -> 2.0 / (1 + 1.0) = 1.0초 (2배 빨라짐)
	var speed_multiplier = 1.0 + (agility * 0.01)
	return base_weapon_cooldown / speed_multiplier
