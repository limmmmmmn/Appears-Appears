class_name UnitRuntime extends RefCounted
# [Blueprint v1.4] 4. 런타임 상태 - JRPG식 데미지 연산

var _data: UnitData
var current_hp: int
var skill_cooldowns: Dictionary = {}

var weapon: ItemData
var armor: ItemData

signal hp_changed(current, max_hp)

func _init(p_data: UnitData) -> void:
	_data = p_data
	current_hp = get_max_hp()
	for s in _data.skills:
		skill_cooldowns[s] = 0.0

# --- 데미지 판정 핵심 로직 ---
func take_damage(attacker: UnitRuntime, skill: SkillData) -> int:
	var raw_damage: int = 0
	
	if skill.is_fixed_damage:
		# 1. 마법/고정 데미지: 공격력/방어력 무시하고 수치 그대로 적용
		raw_damage = skill.fixed_damage_value
	else:
		# 2. 물리/공격력 기반: (공격자 ATK * 배율) - 방어자 DEF
		var calculated_atk = attacker.get_atk() * skill.power_multiplier
		raw_damage = int(calculated_atk - get_def())
	
	# 최종 데미지는 최소 1 보장
	var final_dmg = int(max(1, raw_damage))
	
	current_hp -= final_dmg
	hp_changed.emit(current_hp, get_max_hp())
	return final_dmg
	
	
# [Blueprint v1.4] 비주얼 데이터 접근용 헬퍼 함수
func get_texture() -> Texture2D:
	return _data.texture
# [Blueprint v1.4] 필드 이동 및 일반 속도 참조용 함수
func get_speed() -> float:
	# 물리 가속(phys_spd)을 기반으로 필드 이동 속도를 계산합니다.
	# 수치가 1.0 기준이므로, 필드 이동을 위해 100~150 정도를 곱해줍니다.
	return get_phys_spd() * 100.0

# --- 능력치 합산 로직 (기존과 동일) ---
func get_max_hp() -> int: return _data.base_hp + (armor.hp_bonus if armor else 0)
func get_atk() -> int: return _data.base_atk + (weapon.atk_bonus if weapon else 0)
func get_def() -> int: return _data.base_def + (armor.def_bonus if armor else 0)
func get_phys_spd() -> float: return _data.phys_spd + (weapon.phys_spd_bonus if weapon else 0.0)
func get_mag_spd() -> float: return _data.mag_spd + (weapon.mag_spd_bonus if weapon else 0.0)
