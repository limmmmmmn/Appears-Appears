extends RefCounted
class_name CombatCalculator
## CombatCalculator: 전투 데미지 및 판정 계산

enum DamageResult { NORMAL, CRITICAL, EVADED }


static func calculate_physical_damage(attacker_atk: int, defender_p_def: int, is_critical: bool = false) -> int:
	## 물리 데미지 계산
	## 크리티컬 시 방어 무시
	if is_critical:
		return maxi(1, attacker_atk)
	return maxi(1, attacker_atk - (defender_p_def / 2))


static func calculate_magic_damage(skill_base: int, caster_int: int, skill_multiplier: float, defender_m_def: int) -> int:
	## 마법 데미지 계산
	var raw_damage := skill_base + int(caster_int * skill_multiplier)
	return maxi(1, raw_damage - (defender_m_def / 2))


static func calculate_heal(heal_base: int, caster_int: int, heal_multiplier: float) -> int:
	## 힐량 계산
	return heal_base + int(caster_int * heal_multiplier)


static func roll_evasion(defender_eva: float) -> bool:
	## 회피 판정 (true = 회피 성공)
	return randf() * 100.0 < defender_eva


static func roll_critical(attacker_crit: float) -> bool:
	## 크리티컬 판정 (true = 크리티컬)
	return randf() * 100.0 < attacker_crit


static func perform_attack(attacker_atk: int, attacker_crit: float, defender_p_def: int, defender_eva: float) -> Dictionary:
	## 완전한 공격 판정 수행
	## 반환: { "result": DamageResult, "damage": int }
	
	# 회피 판정
	if roll_evasion(defender_eva):
		return {"result": DamageResult.EVADED, "damage": 0}
	
	# 크리티컬 판정
	var is_crit := roll_critical(attacker_crit)
	var damage := calculate_physical_damage(attacker_atk, defender_p_def, is_crit)
	
	if is_crit:
		return {"result": DamageResult.CRITICAL, "damage": damage}
	return {"result": DamageResult.NORMAL, "damage": damage}


static func calculate_escape_chance(party_avg_spd: float, enemy_avg_spd: float, base_rate: float = 30.0) -> float:
	## 도주 확률 계산
	var chance := base_rate + (party_avg_spd - enemy_avg_spd) * 2.0
	return clampf(chance, 5.0, 95.0)


static func roll_escape(party_avg_spd: float, enemy_avg_spd: float) -> bool:
	## 도주 판정
	var chance := calculate_escape_chance(party_avg_spd, enemy_avg_spd)
	return randf() * 100.0 < chance
