extends RefCounted
class_name Hero
## Hero: 영웅 인스턴스 데이터 관리

var id: String = ""
var hero_name: String = ""
var class_id: String = ""
var hero_class_name: String = ""  # class_name은 Godot 예약어

# 레벨/경험치
const MAX_LEVEL: int = 50
const BASE_EXP: int = 100
const EXP_EXPONENT: float = 1.5
const BENCH_EXP_RATIO: float = 0.5

# 성장/전투 상수
const SEED_CAP: int = 99
const AGI_CRIT_RATIO: float = 0.003 # 민첩 100 -> 크리 30%
const DEFAULT_SKILL_UNLOCK_LEVELS: Array[int] = [1, 5, 10, 15]

# 행동 타이머 상수 (내부 ATB)
const ACTION_INTERVAL: float = 5.0     # 행동 간격 기준값
const ACTION_FILL_RATE: float = 1.0    # 초당 충전 속도

# 기본(레벨) 스탯: hp/str/agi/wis/luk
var level: int = 1
var current_exp: int = 0
var level_stats: Dictionary = {
	"hp": 30,
	"str": 5,
	"agi": 3,
	"wis": 0,
	"luk": 2,
}

# 씨앗 보너스 (스탯당 +99 상한)
var seed_bonus: Dictionary = {
	"hp": 0,
	"str": 0,
	"agi": 0,
	"wis": 0,
	"luk": 0,
}

# 기존 코드 호환용 base_* 캐시
var base_hp: int = 0
var base_str: int = 0
var base_def: int = 0
var base_int: int = 0
var base_dex: int = 0
var base_luk: int = 0

# 레벨별 성장 테이블 (index == level)
var growth_per_level: Dictionary = {
	"hp": [0],
	"str": [0],
	"agi": [0],
	"wis": [0],
	"luk": [0],
}

# 클래스별 스킬 해금 레벨
var skill_unlock_levels: Dictionary = {}
var unlocked_skills: Array = []

# 현재 상태
var current_hp: int = 0
var is_dead: bool = false

# 도발 상태 (기사 방패 강타)
var taunt_count: int = 0

# 장비
var equipment: Dictionary = {
	"main_hand": "", "off_hand": "", "head": "", "body": "", "acc1": "", "acc2": ""
}

# 스킬 토글
var skill_toggles: Dictionary = {}

var tags: Array = []
var portrait: String = ""
var field_sprite: String = ""

# 행동 타이머 (내부 ATB, UI 비노출)
var action_timer: float = 0.0
var skill_action_timer: float = 0.0


static func create_from_id(hero_id: String) -> Hero:
	var hero := Hero.new()
	hero._initialize(hero_id)
	return hero


static func get_required_exp_for_level(level_value: int) -> int:
	## 현재 레벨 -> 다음 레벨에 필요한 EXP
	return int(round(BASE_EXP * pow(float(maxi(1, level_value)), EXP_EXPONENT)))


func _initialize(hero_id: String) -> void:
	var hero_data: Dictionary = DataManager.get_hero(hero_id)
	if hero_data.is_empty():
		return

	id = hero_id
	hero_name = hero_data.get("name", "Unknown")
	class_id = hero_data.get("class_id", "")
	portrait = hero_data.get("sprite_face", hero_data.get("portrait", ""))
	field_sprite = hero_data.get("sprite_field", hero_data.get("field_sprite", ""))

	var class_data: Dictionary = DataManager.get_class_data(class_id)
	hero_class_name = class_data.get("name", "Unknown")
	tags = class_data.get("tags", []) + hero_data.get("tags", [])

	var base_stats: Dictionary = DataManager.get_class_base_stats(class_id)
	base_hp = int(base_stats.get("hp", 30))
	base_str = int(base_stats.get("str", 5))
	base_def = int(base_stats.get("def", 5))
	base_int = int(base_stats.get("int", 5))
	base_dex = int(base_stats.get("dex", 5))
	base_luk = int(base_stats.get("luk", 5))

	level_stats = {
		"hp": base_hp,
		"str": base_str,
		"agi": base_dex,
		"wis": base_int,
		"luk": base_luk,
	}
	seed_bonus = {
		"hp": 0,
		"str": 0,
		"agi": 0,
		"wis": 0,
		"luk": 0,
	}

	growth_per_level = _build_growth_table(class_data)
	_setup_skill_unlocks(class_data)

	current_hp = get_max_hp()
	_init_skill_toggles()


func _build_growth_table(class_data: Dictionary) -> Dictionary:
	var table: Dictionary = {
		"hp": [0],
		"str": [0],
		"agi": [0],
		"wis": [0],
		"luk": [0],
	}

	var custom_table: Dictionary = class_data.get("growth_per_level", {})
	if not custom_table.is_empty():
		for key in ["hp", "str", "agi", "wis", "luk"]:
			var arr: Array = custom_table.get(key, [])
			if arr.is_empty():
				arr = [0]
			elif int(arr[0]) != 0:
				arr.insert(0, 0)
			table[key] = arr
		return table

	# fallback: 클래스 성장 고정치 기반
	var growth: Dictionary = DataManager.get_class_growth(class_id)
	var hp_g: int = int(growth.get("hp", 5))
	var str_g: int = int(growth.get("str", 1))
	var agi_g: int = int(growth.get("agi", growth.get("dex", 1)))
	var wis_g: int = int(growth.get("wis", growth.get("int", 1)))
	var luk_g: int = int(growth.get("luk", 1))

	for _lv in range(1, MAX_LEVEL + 1):
		table["hp"].append(hp_g)
		table["str"].append(str_g)
		table["agi"].append(agi_g)
		table["wis"].append(wis_g)
		table["luk"].append(luk_g)

	return table


func _setup_skill_unlocks(class_data: Dictionary) -> void:
	skill_unlock_levels.clear()
	unlocked_skills.clear()

	var class_skills: Array = DataManager.get_class_skills(class_id)
	var custom_unlocks: Dictionary = class_data.get("skill_unlocks", {})
	var idx: int = 0

	for skill_id in class_skills:
		var sid: String = str(skill_id)
		if sid == "basic_attack":
			skill_unlock_levels[sid] = 1
			continue

		if custom_unlocks.has(sid):
			skill_unlock_levels[sid] = int(custom_unlocks[sid])
		else:
			var unlock_level: int = DEFAULT_SKILL_UNLOCK_LEVELS[min(idx, DEFAULT_SKILL_UNLOCK_LEVELS.size() - 1)]
			skill_unlock_levels[sid] = unlock_level
			idx += 1

	for sid in skill_unlock_levels.keys():
		if int(skill_unlock_levels[sid]) <= level:
			unlocked_skills.append(str(sid))

	if not unlocked_skills.has("basic_attack"):
		unlocked_skills.append("basic_attack")


func _init_skill_toggles() -> void:
	## 클래스 스킬에 대한 토글 초기화 (기본값: 모두 활성화)
	skill_toggles.clear()
	var class_skills: Array = DataManager.get_class_skills(class_id)
	for skill_id in class_skills:
		skill_toggles[skill_id] = true


func _normalize_stat_key(stat: String) -> String:
	match stat:
		"int", "wis":
			return "wis"
		"dex", "agi":
			return "agi"
		"def":
			return "def"
		_:
			return stat


#region 스탯 계산
func get_base_stat(stat: String) -> int:
	var key: String = _normalize_stat_key(stat)
	if key == "def":
		return 0
	return int(level_stats.get(key, 0)) + int(seed_bonus.get(key, 0))


func get_max_hp() -> int:
	return get_base_stat("hp") + _get_equipment_stat("hp")


func get_str() -> int:
	return get_base_stat("str")


func get_def() -> int:
	return get_defense()


func get_int() -> int:
	# 기존 코드 호환: INT 참조는 마법공격력으로 매핑
	return get_magic_attack()


func get_dex() -> int:
	return get_base_stat("agi")


func get_luk() -> int:
	return get_base_stat("luk")


func get_attack() -> int:
	return get_base_stat("str") + _get_equipment_stat("atk")


func get_atk() -> int:
	return get_attack()


func get_defense() -> int:
	# DEF = base_def + growth_def*(level-1) + seed_bonus_def + equipment_def
	var growth: Dictionary = DataManager.get_class_growth(class_id)
	var growth_def: int = int(growth.get("def", 0))
	var level_bonus: int = growth_def * maxi(0, level - 1)
	var seed_bonus_def: int = int(seed_bonus.get("def", 0))
	return base_def + level_bonus + seed_bonus_def + _get_equipment_stat("def")


func get_p_def() -> int:
	return get_defense()


func get_m_def() -> int:
	# MDEF = base_mdef(0) + INT*0.5 + equipment_mdef
	var int_stat: int = get_base_stat("wis")
	var equip_mdef: int = _get_equipment_stat("mdef") + _get_equipment_stat("m_def")
	return int(round(float(int_stat) * 0.5)) + equip_mdef


func get_magic_attack() -> int:
	# INT 기반 + 장비 마법공격 보정(matk/matk_bonus/mag/int)
	return get_base_stat("wis") + _get_equipment_stat("matk") + _get_equipment_stat("matk_bonus") + _get_equipment_stat("mag") + _get_equipment_stat("int")


func get_atb_speed() -> float:
	## 레거시 호환
	return 1.0


func get_spd() -> int:
	# 기존 UI 표기용: 민첩 + 장비 SPD
	return get_base_stat("agi") + _get_equipment_stat("spd")


func get_crit() -> float:
	# crit_chance = LUK * 0.5 + equipment_crit_chance
	var equip_crit: float = float(_get_equipment_stat("crit")) + float(_get_equipment_stat("crit_chance"))
	return clampf(get_base_stat("luk") * 0.5 + equip_crit, 0.0, 95.0)


func get_hit_rate() -> float:
	# 명중은 무기/장비 성능 기반
	return clampf(90.0 + _get_equipment_stat("hit") + _get_equipment_stat("acc"), 40.0, 100.0)


func get_eva() -> float:
	# 회피는 장비 + 운 보정
	return clampf(_get_equipment_stat("eva") + get_base_stat("luk") * 0.1, 0.0, 60.0)


func _get_equipment_stat(stat: String) -> int:
	var total: int = 0
	for slot in equipment:
		var equip_id: String = equipment[slot]
		if equip_id.is_empty():
			continue
		var data: Dictionary = DataManager.get_equipment(equip_id)
		if data.is_empty():
			continue
		var stats: Dictionary = data.get("stats", {})
		total += int(stats.get(stat, 0))
	return total
#endregion


#region 레벨/경험치
func get_exp_to_next_level() -> int:
	if level >= MAX_LEVEL:
		return 0
	return get_required_exp_for_level(level)


func get_exp_ratio() -> float:
	var need: int = get_exp_to_next_level()
	if need <= 0:
		return 1.0
	return clampf(float(current_exp) / float(need), 0.0, 1.0)


func get_exp_percent() -> float:
	## 레거시 호환용 별칭
	return get_exp_ratio()


func gain_exp(amount: int) -> Dictionary:
	## EXP 획득 및 레벨업 처리
	var result := {
		"gained_exp": maxi(0, amount),
		"leveled_up": false,
		"levels": [],
	}

	if amount <= 0 or level >= MAX_LEVEL:
		return result

	var remaining: int = amount
	while remaining > 0 and level < MAX_LEVEL:
		var need: int = get_exp_to_next_level() - current_exp
		var gain: int = mini(need, remaining)
		current_exp += gain
		remaining -= gain

		if current_exp >= get_exp_to_next_level():
			level += 1
			current_exp = 0
			var grown: Dictionary = _apply_level_growth(level)
			var unlocked: Array = _unlock_skills_for_level(level)
			full_restore() # 레벨업 시 HP 전회복

			var lv_result := {
				"level": level,
				"growth": grown,
				"unlocked_skills": unlocked,
			}
			result["levels"].append(lv_result)

	if level >= MAX_LEVEL:
		current_exp = 0

	result["leveled_up"] = not (result["levels"] as Array).is_empty()
	return result


func _apply_level_growth(new_level: int) -> Dictionary:
	var delta: Dictionary = {
		"hp": 0,
		"str": 0,
		"agi": 0,
		"wis": 0,
		"luk": 0,
	}

	for key in delta.keys():
		var growth_val: int = _get_growth_value_for_level(key, new_level)
		delta[key] = growth_val
		level_stats[key] = int(level_stats.get(key, 0)) + growth_val

	return delta


func _get_growth_value_for_level(stat: String, lv: int) -> int:
	var arr: Array = growth_per_level.get(stat, [0])
	if lv >= 0 and lv < arr.size():
		return int(arr[lv])
	if arr.is_empty():
		return 0
	return int(arr[arr.size() - 1])


func _unlock_skills_for_level(new_level: int) -> Array:
	var newly_unlocked: Array = []
	for sid in skill_unlock_levels.keys():
		var skill_id: String = str(sid)
		# 레벨 2 스킬은 3지선다 팝업으로 선택하므로 자동 해금 건너뜀
		if int(skill_unlock_levels[skill_id]) == 2 and skill_id != "basic_attack":
			continue
		if int(skill_unlock_levels[skill_id]) == new_level and not unlocked_skills.has(skill_id):
			unlocked_skills.append(skill_id)
			newly_unlocked.append(skill_id)
	return newly_unlocked


func set_progress(saved_level: int, saved_exp: int, saved_level_stats: Dictionary = {}, saved_unlocked_skills: Array = []) -> void:
	level = clampi(saved_level, 1, MAX_LEVEL)
	current_exp = maxi(0, saved_exp)

	if saved_level_stats.is_empty():
		level_stats = {
			"hp": base_hp,
			"str": base_str,
			"agi": base_dex,
			"wis": base_int,
			"luk": base_luk,
		}
		for lv in range(2, level + 1):
			_apply_level_growth(lv)
	else:
		for key in saved_level_stats.keys():
			var normalized: String = _normalize_stat_key(str(key))
			if normalized == "def":
				continue
			if level_stats.has(normalized):
				level_stats[normalized] = int(saved_level_stats[key])

	if not saved_unlocked_skills.is_empty():
		unlocked_skills.clear()
		for sid in saved_unlocked_skills:
			unlocked_skills.append(str(sid))
	else:
		# 기존 세이브 호환
		_setup_skill_unlocks(DataManager.get_class_data(class_id))

	# 현재 레벨에 맞게 재해금 보정 (레벨 2 스킬은 팝업 선택이므로 자동 재해금 제외)
	for sid in skill_unlock_levels.keys():
		var skill_id: String = str(sid)
		var unlock_lv: int = int(skill_unlock_levels[skill_id])
		if unlock_lv == 2 and skill_id != "basic_attack":
			continue
		if unlock_lv <= level and not unlocked_skills.has(skill_id):
			unlocked_skills.append(skill_id)

	if not unlocked_skills.has("basic_attack"):
		unlocked_skills.append("basic_attack")

	if level >= MAX_LEVEL:
		current_exp = 0
	else:
		current_exp = mini(current_exp, get_exp_to_next_level())
#endregion


#region 전투
func take_damage(amount: int) -> int:
	var actual := maxi(1, amount)
	current_hp = maxi(0, current_hp - actual)
	if current_hp <= 0:
		is_dead = true
	return actual


func heal(amount: int) -> int:
	if is_dead:
		return 0
	var actual := mini(amount, get_max_hp() - current_hp)
	current_hp += actual
	return actual


func revive(hp_percent: float = 0.3) -> void:
	if not is_dead:
		return
	is_dead = false
	current_hp = int(get_max_hp() * hp_percent)


# === 행동 타이머 ===
func is_action_ready() -> bool:
	return action_timer >= get_action_delay()


func reset_action_timer() -> void:
	action_timer = 0.0


func is_skill_action_ready() -> bool:
	return skill_action_timer >= get_skill_action_delay()


func reset_skill_action_timer() -> void:
	skill_action_timer = 0.0


func get_action_delay() -> float:
	# 기본공격 기준 액션 딜레이: 2.0 - DEX*0.05, 최소 0.5
	return maxf(0.5, 2.0 - get_dex() * 0.05)


func get_skill_action_delay() -> float:
	# 액티브 스킬 ATB는 기본공격보다 느리게 충전
	return maxf(1.0, 3.8 - get_dex() * 0.03)


func apply_seed_bonus(stat: String, value: int) -> void:
	## 씨앗으로 영구 스탯 증가 (스탯당 +99 제한)
	if value <= 0:
		return

	var key: String = _normalize_stat_key(stat)
	if key == "def":
		# 수비력은 장비 전용 설계
		return
	if not seed_bonus.has(key):
		return

	var old_val: int = int(seed_bonus[key])
	var new_val: int = mini(SEED_CAP, old_val + value)
	var applied: int = new_val - old_val
	if applied <= 0:
		return
	seed_bonus[key] = new_val

	if key == "hp":
		current_hp = mini(current_hp + applied, get_max_hp())


func full_restore() -> void:
	current_hp = get_max_hp()
	is_dead = false


func apply_taunt(count: int) -> void:
	## 도발 효과 적용
	taunt_count = count


func consume_taunt() -> bool:
	## 도발 카운트 소모 (피격 시 호출)
	if taunt_count > 0:
		taunt_count -= 1
		return true
	return false


func has_taunt() -> bool:
	## 도발 상태인지 확인
	return taunt_count > 0
#endregion


static func normalize_equipment_slot(slot: String) -> String:
	match slot:
		"main_hand", "off_hand", "head", "body", "acc1", "acc2":
			return slot
		"ring", "ring1", "ring2", "acc", "necklace", "boots", "shoes", "gloves", "hands", "feet":
			return "acc"
		_:
			return slot


#region 장비
func can_equip(equip_id: String) -> bool:
	var data: Dictionary = DataManager.get_equipment(equip_id)
	if data.is_empty():
		return false
	var equip_type: String = data.get("type", "")
	if equip_type.is_empty():
		return true
	return DataManager.can_class_equip(class_id, equip_type)


func equip_item(equip_id: String, slot: String) -> String:
	if not equipment.has(slot):
		return ""
	var old: String = equipment[slot]
	equipment[slot] = equip_id
	return old


func unequip_slot(slot: String) -> String:
	if not equipment.has(slot):
		return ""
	var old: String = equipment[slot]
	equipment[slot] = ""
	return old


func can_dual_wield() -> bool:
	return DataManager.can_class_dual_wield(class_id)


func is_off_hand_disabled() -> bool:
	var main: String = equipment["main_hand"]
	if main.is_empty():
		return false
	var data: Dictionary = DataManager.get_equipment(main)
	return data.get("two_handed", false)
#endregion


#region 스킬 토글
func toggle_skill(skill_id: String) -> void:
	if skill_toggles.has(skill_id):
		skill_toggles[skill_id] = not skill_toggles[skill_id]


func is_skill_enabled(skill_id: String) -> bool:
	## skill_toggles에 없으면 기본값 true (기존 세이브 호환)
	return skill_toggles.get(skill_id, true)


func get_enabled_skills() -> Array:
	var result: Array = []
	for skill_id in skill_toggles:
		if skill_toggles[skill_id]:
			result.append(skill_id)
	return result


func get_available_skills() -> Array:
	## 현재 레벨에서 해금된 스킬 목록 반환
	return unlocked_skills.duplicate()


func get_usable_skills() -> Array:
	## 토글 ON이고 쿨타임이 없는 스킬 목록 반환 (기본 공격 제외, ATB 무관)
	var result: Array = []
	var skills: Array = get_available_skills()
	for skill_id in skills:
		if skill_id == "basic_attack":
			continue
		# 토글이 OFF면 스킵
		if not is_skill_enabled(skill_id):
			continue
		# 쿨타임 체크
		if CooldownManager.is_skill_ready(id, skill_id):
			result.append(skill_id)
	return result


func can_use_skill(skill_id: String) -> bool:
	## 해당 스킬을 사용할 수 있는지 확인 (기본공격=ATB, 액티브=쿨타임만)
	if skill_id == "basic_attack":
		return is_action_ready()
	return CooldownManager.is_skill_ready(id, skill_id)
#endregion


func use_seed(stat: String, value: int) -> void:
	apply_seed_bonus(stat, value)


func get_hp_percent() -> float:
	var max_hp: int = get_max_hp()
	if max_hp <= 0:
		return 1.0
	return float(current_hp) / float(max_hp)


#region 특성
func get_traits() -> Array:
	## 영웅의 특성 데이터 목록 반환
	var result: Array = []
	var trait_ids: Array = DataManager.get_hero_traits(id)
	for trait_id in trait_ids:
		var trait_data: Dictionary = DataManager.get_trait(str(trait_id))
		if not trait_data.is_empty():
			result.append(trait_data)
	return result


func has_trait(trait_id: String) -> bool:
	var trait_ids: Array = DataManager.get_hero_traits(id)
	return trait_id in trait_ids
#endregion


func get_stat_summary() -> String:
	return "[%s] %s | Lv.%d EXP:%d/%d | HP:%d/%d | STR:%d AGI:%d WIS:%d LUK:%d ATK:%d DEF:%d" % [
		hero_name, hero_class_name,
		level, current_exp, get_exp_to_next_level(),
		current_hp, get_max_hp(),
		get_str(), get_base_stat("agi"), get_base_stat("wis"), get_luk(),
		get_attack(), get_defense()
	]
