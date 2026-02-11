extends RefCounted
class_name Hero
## Hero: 영웅 인스턴스 데이터 관리

var id: String = ""
var hero_name: String = ""
var class_id: String = ""
var hero_class_name: String = ""  # class_name은 Godot 예약어

# 기본 스탯
var base_hp: int = 0
var base_mp: int = 0
var base_str: int = 0
var base_def: int = 0
var base_int: int = 0
var base_dex: int = 0
var base_luk: int = 0

# 씨앗 보너스
var seed_bonus: Dictionary = {"hp": 0, "mp": 0, "str": 0, "def": 0, "int": 0, "dex": 0, "luk": 0}

# 현재 상태
var current_hp: int = 0
var current_mp: int = 0
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

# 룬 (특성 부여)
var equipped_rune_id: String = ""


static func create_from_id(hero_id: String) -> Hero:
	var hero := Hero.new()
	hero._initialize(hero_id)
	return hero


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
	base_mp = int(base_stats.get("mp", 20))
	base_str = int(base_stats.get("str", 5))
	base_def = int(base_stats.get("def", 5))
	base_int = int(base_stats.get("int", 5))
	base_dex = int(base_stats.get("dex", 5))
	base_luk = int(base_stats.get("luk", 5))

	current_hp = get_max_hp()
	current_mp = get_max_mp()
	_init_skill_toggles()


func _init_skill_toggles() -> void:
	## 클래스 스킬에 대한 토글 초기화 (기본값: 모두 활성화)
	skill_toggles.clear()
	var class_skills: Array = DataManager.get_class_skills(class_id)
	for skill_id in class_skills:
		skill_toggles[skill_id] = true  # 기본적으로 모든 스킬 활성화


#region 스탯 계산
const HP_MULTIPLIER: float = 1.0  # HP 배율 (1/4로 축소)

func get_max_hp() -> int:
	return int((base_hp + seed_bonus["hp"] + _get_equipment_stat("hp")) * HP_MULTIPLIER)

func get_max_mp() -> int:
	return base_mp + seed_bonus["mp"] + _get_equipment_stat("mp")

func get_str() -> int:
	return base_str + seed_bonus["str"] + _get_equipment_stat("str")

func get_def() -> int:
	return base_def + seed_bonus["def"] + _get_equipment_stat("def")

func get_int() -> int:
	return base_int + seed_bonus["int"] + _get_equipment_stat("int")

func get_dex() -> int:
	return base_dex + seed_bonus["dex"] + _get_equipment_stat("dex")

func get_luk() -> int:
	return base_luk + seed_bonus["luk"] + _get_equipment_stat("luk")

func get_atk() -> int:
	return get_str() + _get_equipment_stat("atk")

func get_p_def() -> int:
	return get_def()

func get_m_def() -> int:
	return get_int()

func get_spd() -> int:
	return _get_equipment_stat("spd")

func get_eva() -> float:
	return get_dex() * 0.5 + get_luk() * 0.2

func get_crit() -> float:
	return get_luk() * 0.5 + 5.0


func _get_equipment_stat(stat: String) -> int:
	var total: int = 0
	for slot in equipment:
		var equip_id: String = equipment[slot]
		if equip_id.is_empty():
			continue
		var data: Dictionary = DataManager.get_equipment(equip_id)
		total += int(data.get("stats", {}).get(stat, 0))
	return total
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
	current_mp = int(get_max_mp() * hp_percent)


func consume_mp(amount: int) -> bool:
	## MP 소모. 충분하면 소모 후 true, 부족하면 false
	if amount <= 0:
		return true
	if current_mp < amount:
		return false
	current_mp -= amount
	return true


func restore_mp(amount: int) -> int:
	## MP 회복
	var actual := mini(amount, get_max_mp() - current_mp)
	current_mp += actual
	return actual


func has_enough_mp(skill_id: String) -> bool:
	## 스킬 사용에 필요한 MP가 있는지 확인
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var cost: int = int(skill_data.get("mp_cost", 0))
	return current_mp >= cost


func apply_seed_bonus(stat: String, value: int) -> void:
	## 씨앗으로 영구 스탯 증가
	if seed_bonus.has(stat):
		seed_bonus[stat] += value

	# HP 증가 시 현재 값도 증가
	if stat == "hp":
		current_hp = mini(current_hp + value, get_max_hp())
	if stat == "mp":
		current_mp = mini(current_mp + value, get_max_mp())


func full_restore() -> void:
	current_hp = get_max_hp()
	current_mp = get_max_mp()
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
	## 클래스가 보유한 스킬 목록 반환
	return DataManager.get_class_skills(class_id)


func get_usable_skills() -> Array:
	## 토글 ON이고 쿨타임이 없는 스킬 목록 반환 (기본 공격 제외)
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
	## 해당 스킬을 사용할 수 있는지 확인 (쿨타임 체크)
	return CooldownManager.is_skill_ready(id, skill_id)
#endregion


func use_seed(stat: String, value: int) -> void:
	if seed_bonus.has(stat):
		seed_bonus[stat] += value


func get_hp_percent() -> float:
	return float(current_hp) / float(get_max_hp())


func get_mp_percent() -> float:
	var max_mp := get_max_mp()
	if max_mp <= 0:
		return 1.0
	return float(current_mp) / float(max_mp)


#region 룬/특성
func get_equipped_rune() -> Dictionary:
	## 장착된 룬 데이터 반환
	if equipped_rune_id.is_empty():
		return {}
	return DataManager.get_rune(equipped_rune_id)


func get_traits() -> Array:
	## 영웅의 특성 데이터 목록 반환 (장착된 룬에서 가져옴)
	var result: Array = []
	if not equipped_rune_id.is_empty():
		var trait_data: Dictionary = DataManager.get_rune_trait(equipped_rune_id)
		if not trait_data.is_empty():
			result.append(trait_data)
	return result


func has_trait(trait_id: String) -> bool:
	if equipped_rune_id.is_empty():
		return false
	var rune_data: Dictionary = DataManager.get_rune(equipped_rune_id)
	return rune_data.get("trait_id", "") == trait_id


func equip_rune(rune_id: String) -> String:
	## 룬 장착 - 이전 룬 ID 반환
	var old_rune := equipped_rune_id
	equipped_rune_id = rune_id
	return old_rune


func unequip_rune() -> String:
	## 룬 해제 - 이전 룬 ID 반환
	var old_rune := equipped_rune_id
	equipped_rune_id = ""
	return old_rune
#endregion


func get_stat_summary() -> String:
	return "[%s] %s | HP:%d/%d MP:%d/%d | STR:%d DEF:%d INT:%d DEX:%d LUK:%d" % [
		hero_name, hero_class_name,
		current_hp, get_max_hp(),
		current_mp, get_max_mp(),
		get_str(), get_def(), get_int(), get_dex(), get_luk()
	]
