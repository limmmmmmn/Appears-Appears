extends RefCounted
class_name Hero
## Hero: 용사 인스턴스 데이터 관리

var id: String = ""
var hero_name: String = ""
var class_id: String = ""
var hero_class_name: String = ""  # class_name은 Godot 예약어

# 레벨/경험치 (formulas.json에서 로드)
const MAX_LEVEL: int = 50
static var BASE_EXP: int = 100
static var EXP_EXPONENT: float = 1.5
static var BENCH_EXP_RATIO: float = 0.5
static var _formulas_loaded: bool = false

# 성장/전투 상수
const SEED_CAP: int = 99
const AGI_CRIT_RATIO: float = 0.003 # 민첩 100 -> 크리 30%

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
var skill_levels: Dictionary = {}   # { skill_id: int } — 기본 1, 중복 선택 시 +1

# 현재 상태
var current_hp: int = 0
var is_dead: bool = false

# 스킬 쿨다운 타이머: { skill_id: 남은_쿨다운(초) } — 0이면 사용 가능
var skill_cooldowns: Dictionary = {}

# 도발 상태 (기사 방패 강타)
var taunt_count: int = 0

# 버프 시스템: { buff_id: { "remaining": float, "value": float } }
var buffs: Dictionary = {}

# 장비
var equipment: Dictionary = {
	"main_hand": "", "off_hand": "", "head": "", "body": "", "acc1": "", "acc2": ""
}

# 스킬 토글
var skill_toggles: Dictionary = {}
# 스킬 우선순위 (작전 탭에서 설정, 인덱스 0이 가장 우선)
var skill_priority: Array = []

var tags: Array = []
var hidden_tags: Array = []
var portrait: String = ""
var field_sprite: String = ""

# 행동 타이머 (기본공격 ATB)
var action_timer: float = 0.0

# 예약 스킬: 자동 선택 또는 수동 예약 시 다음 행동에 사용
var queued_skill: String = ""
var queued_skill_enemy: Object = null   # BattleEnemy or null
var queued_skill_ally_id: String = ""


static func create_from_id(hero_id: String) -> Hero:
	var hero := Hero.new()
	hero._initialize(hero_id)
	return hero


static func _load_formulas_once() -> void:
	if _formulas_loaded:
		return
	_formulas_loaded = true
	var exp_f: Dictionary = DataManager.get_formula("exp") as Dictionary
	BASE_EXP = int(exp_f.get("base_exp", 100))
	EXP_EXPONENT = float(exp_f.get("exp_exponent", 1.5))
	BENCH_EXP_RATIO = float(exp_f.get("bench_exp_ratio", 0.5))


static func get_required_exp_for_level(level_value: int) -> int:
	## 현재 레벨 -> 다음 레벨에 필요한 EXP
	return int(round(BASE_EXP * pow(float(maxi(1, level_value)), EXP_EXPONENT)))


func _initialize(hero_id: String) -> void:
	_load_formulas_once()
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
	tags = hero_data.get("tags", [])
	hidden_tags = hero_data.get("hidden_tags", [])

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
	_init_skill_cooldowns()


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

	# 레벨1에는 스킬 없음 — 레벨업 시 스킬 선택으로 습득
	if not unlocked_skills.has("basic_attack"):
		unlocked_skills.append("basic_attack")


func _init_skill_toggles() -> void:
	## 클래스 스킬에 대한 토글 초기화 (기본값: 모두 활성화)
	skill_toggles.clear()
	var class_skills: Array = DataManager.get_class_skills(class_id)
	for skill_id in class_skills:
		skill_toggles[skill_id] = true
	# 우선순위 초기화 (basic_attack 제외, 해금 순서)
	_init_skill_priority()


func _init_skill_priority() -> void:
	## 스킬 우선순위 초기화 — 해금된 스킬만, basic_attack 제외
	if not skill_priority.is_empty():
		# 이미 설정됨 (세이브 로드 등) — 새로 해금된 스킬만 추가
		for sid in unlocked_skills:
			if sid != "basic_attack" and not skill_priority.has(sid):
				skill_priority.append(sid)
		return
	skill_priority.clear()
	for sid in unlocked_skills:
		if sid != "basic_attack":
			skill_priority.append(sid)


func get_skill_priority_list() -> Array:
	## 작전 탭용: 우선순위 순서대로 스킬 목록 반환
	# 해금되지 않은 스킬 제거, 새로 해금된 스킬 추가
	var result: Array = []
	for sid in skill_priority:
		if unlocked_skills.has(sid):
			result.append(sid)
	for sid in unlocked_skills:
		if sid != "basic_attack" and not result.has(sid):
			result.append(sid)
	return result


func move_skill_priority(skill_id: String, direction: int) -> void:
	## direction: -1 = 위로 (더 높은 우선순위), +1 = 아래로
	var idx: int = skill_priority.find(skill_id)
	if idx < 0:
		return
	var new_idx: int = clampi(idx + direction, 0, skill_priority.size() - 1)
	if new_idx == idx:
		return
	skill_priority.remove_at(idx)
	skill_priority.insert(new_idx, skill_id)


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


#region 태그
func get_all_tags() -> Array:
	## tags + hidden_tags + 클래스의 tags를 합친 전체 태그 목록
	var result: Array = tags.duplicate()
	for t in hidden_tags:
		if not result.has(t):
			result.append(t)
	var class_data: Dictionary = DataManager.get_class_data(class_id)
	var class_tags: Array = class_data.get("tags", [])
	for t in class_tags:
		if not result.has(t):
			result.append(t)
	return result


func has_tag(tag: String) -> bool:
	return tag in get_all_tags()
#endregion


#region 스탯 계산
func get_base_stat(stat: String) -> int:
	var key: String = _normalize_stat_key(stat)
	if key == "def":
		return 0
	return int(level_stats.get(key, 0)) + int(seed_bonus.get(key, 0))


func _get_synergy_mult(stat_key: String) -> float:
	## 시너지 배율 합산 (all_stats_mult, hp_mult, atk_mult, def_mult 등)
	var mult: float = 0.0
	if PartyManager == null:
		return mult
	var effects: Array = PartyManager.get_synergy_effects()
	for effect in effects:
		var etype: String = str(effect.get("type", ""))
		var value: float = float(effect.get("value", 0.0))
		if etype == "all_stats_mult":
			mult += value
		elif etype == "hp_mult" and stat_key == "hp":
			mult += value
		elif etype == "atk_mult" and stat_key == "atk":
			mult += value
		elif etype == "def_mult" and stat_key == "def":
			mult += value
	return mult


func _get_synergy_add(stat_key: String) -> float:
	## 시너지 고정 수치 합산 (eva_add, crit_add 등)
	var add: float = 0.0
	if PartyManager == null:
		return add
	var effects: Array = PartyManager.get_synergy_effects()
	for effect in effects:
		var etype: String = str(effect.get("type", ""))
		var value: float = float(effect.get("value", 0.0))
		if etype == "eva_add" and stat_key == "eva":
			add += value
		elif etype == "crit_add" and stat_key == "crit":
			add += value
	return add


func get_max_hp() -> int:
	var base: int = get_base_stat("hp") + _get_equipment_stat("hp")
	var synergy_mult: float = _get_synergy_mult("hp")
	if synergy_mult > 0.0:
		return int(float(base) * (1.0 + synergy_mult))
	return base


func get_max_mp() -> int:
	## (레거시 호환 — MP 시스템 삭제됨. 0 반환)
	return 0


func get_str() -> int:
	var base: int = get_base_stat("str")
	var synergy_mult: float = _get_synergy_mult("str")
	if synergy_mult > 0.0:
		return int(float(base) * (1.0 + synergy_mult))
	return base


func get_def() -> int:
	return get_defense()


func get_int() -> int:
	# 기존 코드 호환: INT 참조는 마법공격력으로 매핑
	return get_magic_attack()


func get_dex() -> int:
	var base: int = get_base_stat("agi")
	var synergy_mult: float = _get_synergy_mult("agi")
	if synergy_mult > 0.0:
		return int(float(base) * (1.0 + synergy_mult))
	return base


func get_luk() -> int:
	var base: int = get_base_stat("luk")
	var synergy_mult: float = _get_synergy_mult("luk")
	if synergy_mult > 0.0:
		return int(float(base) * (1.0 + synergy_mult))
	return base


func get_attack() -> int:
	var base: int = get_base_stat("str") + _get_equipment_stat("atk")
	var synergy_mult: float = _get_synergy_mult("atk")
	if synergy_mult > 0.0:
		return int(float(base) * (1.0 + synergy_mult))
	return base


func get_atk() -> int:
	return get_attack()


func get_defense() -> int:
	# DEF = base_def + growth_def*(level-1) + seed_bonus_def + equipment_def
	var growth: Dictionary = DataManager.get_class_growth(class_id)
	var growth_def: int = int(growth.get("def", 0))
	var level_bonus: int = growth_def * maxi(0, level - 1)
	var seed_bonus_def: int = int(seed_bonus.get("def", 0))
	var base: int = base_def + level_bonus + seed_bonus_def + _get_equipment_stat("def")
	var synergy_mult: float = _get_synergy_mult("def")
	if synergy_mult > 0.0:
		return int(float(base) * (1.0 + synergy_mult))
	return base


func get_p_def() -> int:
	return get_defense()


func get_m_def() -> int:
	var f: Dictionary = DataManager.get_formula("stats", "mdef")
	var mult: float = float(f.get("multiplier", 0.5))
	var int_stat: int = get_base_stat("wis")
	var equip_mdef: int = _get_equipment_stat("mdef") + _get_equipment_stat("m_def")
	return int(round(float(int_stat) * mult)) + equip_mdef


func get_magic_attack() -> int:
	# INT 기반 + 장비 마법공격 보정(matk/matk_bonus/mag/int)
	var base: int = get_base_stat("wis") + _get_equipment_stat("matk") + _get_equipment_stat("matk_bonus") + _get_equipment_stat("mag") + _get_equipment_stat("int")
	var synergy_mult: float = _get_synergy_mult("wis")
	if synergy_mult > 0.0:
		return int(float(base) * (1.0 + synergy_mult))
	return base


func get_atb_speed() -> float:
	## 레거시 호환
	return 1.0


func get_spd() -> int:
	# 기존 UI 표기용: 민첩 + 장비 SPD
	return get_base_stat("agi") + _get_equipment_stat("spd")


func get_crit() -> float:
	var f: Dictionary = DataManager.get_formula("stats", "crit_chance")
	var mult: float = float(f.get("multiplier", 0.5))
	var equip_crit: float = float(_get_equipment_stat("crit")) + float(_get_equipment_stat("crit_chance"))
	var synergy_crit: float = _get_synergy_add("crit")
	return clampf(get_base_stat("luk") * mult + equip_crit + synergy_crit, float(f.get("min", 0.0)), float(f.get("max", 95.0)))


func get_hit_rate() -> float:
	var f: Dictionary = DataManager.get_formula("stats", "hit_rate")
	var base: float = float(f.get("base", 90.0))
	return clampf(base + _get_equipment_stat("hit") + _get_equipment_stat("acc"), float(f.get("min", 40.0)), float(f.get("max", 100.0)))


func get_eva() -> float:
	var f: Dictionary = DataManager.get_formula("stats", "evasion")
	var mult: float = float(f.get("multiplier", 0.1))
	var synergy_eva: float = _get_synergy_add("eva")
	return clampf(_get_equipment_stat("eva") + get_base_stat("luk") * mult + synergy_eva, float(f.get("min", 0.0)), float(f.get("max", 60.0)))


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
	return []


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

	_setup_skill_unlocks(DataManager.get_class_data(class_id))
	if not saved_unlocked_skills.is_empty():
		unlocked_skills.clear()
		for sid in saved_unlocked_skills:
			unlocked_skills.append(str(sid))

	if not unlocked_skills.has("basic_attack"):
		unlocked_skills.append("basic_attack")

	_init_skill_toggles()
	_init_skill_cooldowns()

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


func use_mp(_amount: int) -> bool:
	## (레거시 호환 — MP 시스템 삭제됨)
	return true


func restore_mp(_amount: int) -> int:
	## (레거시 호환 — MP 시스템 삭제됨)
	return 0


func revive(hp_percent: float = 0.3) -> void:
	if not is_dead:
		return
	is_dead = false
	current_hp = int(get_max_hp() * hp_percent)
	reset_all_skill_cooldowns()


# === 행동 타이머 (스킬별 독립 ATB) ===
func is_action_ready() -> bool:
	## 기본공격 ATB 준비 완료 여부
	return action_timer >= get_action_delay()


func reset_action_timer() -> void:
	action_timer = 0.0


func get_action_delay() -> float:
	## 기본공격 ATB 딜레이 = action_speed (classes.json) + 시너지 asp_mult 반영
	var base: float = _get_class_action_speed()
	var asp_mult: float = _get_synergy_asp_mult()
	if asp_mult != 0.0:
		base = base * (1.0 + asp_mult)
	return maxf(0.3, base)  # 최소 0.3초


func _get_synergy_asp_mult() -> float:
	## 시너지 행동속도 배율 합산
	if PartyManager == null:
		return 0.0
	var effects: Array = PartyManager.get_synergy_effects()
	var total: float = 0.0
	for effect in effects:
		if str(effect.get("type", "")) == "asp_mult":
			total += float(effect.get("value", 0.0))
	return total


func _get_class_action_speed() -> float:
	## 클래스 데이터에서 action_speed 가져오기 (없으면 기본 2.0)
	if class_id.is_empty():
		return 2.0
	var class_data: Dictionary = DataManager.get_class_data(class_id)
	return float(class_data.get("action_speed", 2.0))


# === 스킬 쿨다운 시스템 ===
func _init_skill_cooldowns() -> void:
	## 해금된 스킬마다 쿨다운 0 초기화 (사용 가능 상태)
	skill_cooldowns.clear()
	for skill_id in unlocked_skills:
		if skill_id == "basic_attack":
			continue
		skill_cooldowns[skill_id] = 0.0


func get_skill_cooldown_value(skill_id: String) -> float:
	## skills.json의 cooldown 값 반환 (기본공격=0)
	if skill_id == "basic_attack":
		return 0.0
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	return float(skill_data.get("cooldown", 0.0))


func is_skill_off_cooldown(skill_id: String) -> bool:
	## 스킬 쿨다운이 끝났는지 (사용 가능 여부)
	if skill_id == "basic_attack":
		return true
	var remaining: float = float(skill_cooldowns.get(skill_id, 0.0))
	return remaining <= 0.0


func start_skill_cooldown(skill_id: String) -> void:
	## 스킬 사용 후 쿨다운 시작
	if skill_id == "basic_attack":
		return
	skill_cooldowns[skill_id] = get_skill_cooldown_value(skill_id)


func reset_all_skill_cooldowns() -> void:
	## 모든 스킬 쿨다운 리셋 (부활 등 — 전부 사용 가능)
	for skill_id in skill_cooldowns.keys():
		skill_cooldowns[skill_id] = 0.0
	action_timer = 0.0


func get_skill_cooldown_percent(skill_id: String) -> float:
	## UI 표시용: 0.0 = 쿨다운 막 시작, 1.0 = 준비 완료
	if skill_id == "basic_attack":
		var delay: float = get_action_delay()
		if delay <= 0.0:
			return 1.0
		return clampf(action_timer / delay, 0.0, 1.0)
	var total: float = get_skill_cooldown_value(skill_id)
	if total <= 0.0:
		return 1.0
	var remaining: float = float(skill_cooldowns.get(skill_id, 0.0))
	if remaining <= 0.0:
		return 1.0
	return clampf(1.0 - (remaining / total), 0.0, 1.0)


func tick_cooldowns(delta: float) -> void:
	## 매 프레임 호출: 모든 스킬 쿨다운 감소
	for skill_id in skill_cooldowns.keys():
		if skill_cooldowns[skill_id] > 0.0:
			skill_cooldowns[skill_id] = maxf(0.0, skill_cooldowns[skill_id] - delta)


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


# === 버프 시스템 ===
func apply_buff(buff_id: String, duration: float, value: float = 0.0) -> void:
	buffs[buff_id] = { "remaining": duration, "value": value }


func has_buff(buff_id: String) -> bool:
	return buffs.has(buff_id) and buffs[buff_id].get("remaining", 0.0) > 0.0


func get_buff_value(buff_id: String) -> float:
	if not has_buff(buff_id):
		return 0.0
	return float(buffs[buff_id].get("value", 0.0))


func consume_buff(buff_id: String) -> bool:
	## 1회성 버프 소모 (마력집중 등)
	if has_buff(buff_id):
		buffs.erase(buff_id)
		return true
	return false


func tick_buffs(delta: float) -> void:
	var expired: Array[String] = []
	for buff_id in buffs:
		buffs[buff_id]["remaining"] -= delta
		if buffs[buff_id]["remaining"] <= 0.0:
			expired.append(buff_id)
	for buff_id in expired:
		buffs.erase(buff_id)


func get_buffed_atk() -> int:
	var base: int = get_atk()
	if has_buff("atk_up"):
		base = int(float(base) * (1.0 + get_buff_value("atk_up")))
	return base


func get_buffed_def() -> int:
	var base: int = get_defense()
	if has_buff("def_up"):
		base = int(float(base) * (1.0 + get_buff_value("def_up")))
	return base


func get_buffed_eva() -> float:
	var base: float = get_eva()
	if has_buff("eva_up"):
		base += get_buff_value("eva_up")
	var f: Dictionary = DataManager.get_formula("stats", "evasion")
	return clampf(base, 0.0, float(f.get("buffed_max", 80.0)))
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


func get_skill_level(skill_id: String) -> int:
	return int(skill_levels.get(skill_id, 1))


func level_up_skill(skill_id: String) -> int:
	## 스킬 레벨 +1, 새 레벨 반환
	var cur: int = get_skill_level(skill_id)
	skill_levels[skill_id] = cur + 1
	return cur + 1


func get_usable_skills() -> Array:
	## 토글 ON + 쿨다운 완료된 스킬 목록 반환 (기본 공격 제외)
	var result: Array = []
	var skills: Array = get_available_skills()
	for skill_id in skills:
		if skill_id == "basic_attack":
			continue
		if not is_skill_enabled(skill_id):
			continue
		if not is_skill_off_cooldown(skill_id):
			continue
		result.append(skill_id)
	return result


func can_use_skill(skill_id: String) -> bool:
	## 해당 스킬을 사용할 수 있는지 확인 (기본공격=항상, 스킬=쿨다운)
	if skill_id == "basic_attack":
		return true
	return is_skill_off_cooldown(skill_id)
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
	## 용사의 특성 데이터 목록 반환
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
