extends RefCounted
class_name Hero
## Hero: 영웅 인스턴스 데이터 관리

var id: String = ""
var hero_name: String = ""
var class_id: String = ""
var hero_class_name: String = ""  # class_name은 Godot 예약어

var level: int = 1
var exp: int = 0
var exp_to_next: int = 100

# 기본 스탯
var base_hp: int = 0
var base_mp: int = 0
var base_str: int = 0
var base_def: int = 0
var base_int: int = 0
var base_spd: int = 0
var base_luk: int = 0

# 씨앗 보너스
var seed_bonus: Dictionary = {"hp": 0, "mp": 0, "str": 0, "def": 0, "int": 0, "spd": 0, "luk": 0}

# 현재 상태
var current_hp: int = 0
var current_mp: int = 0
var is_dead: bool = false

# 장비
var equipment: Dictionary = {
	"main_hand": "", "off_hand": "", "head": "", "body": "", "acc1": "", "acc2": ""
}

# 스킬 토글
var skill_toggles: Dictionary = {}

var tags: Array = []
var portrait: String = ""
var field_sprite: String = ""


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
	portrait = hero_data.get("portrait", "")
	field_sprite = hero_data.get("field_sprite", "")
	
	var class_data: Dictionary = DataManager.get_class_data(class_id)
	hero_class_name = class_data.get("name", "Unknown")
	tags = class_data.get("tags", []) + hero_data.get("tags", [])
	
	var base_stats: Dictionary = DataManager.get_class_base_stats(class_id)
	base_hp = int(base_stats.get("hp", 30))
	base_mp = int(base_stats.get("mp", 10))
	base_str = int(base_stats.get("str", 5))
	base_def = int(base_stats.get("def", 5))
	base_int = int(base_stats.get("int", 5))
	base_spd = int(base_stats.get("spd", 5))
	base_luk = int(base_stats.get("luk", 5))
	
	current_hp = get_max_hp()
	current_mp = get_max_mp()
	_init_skill_toggles()


func _init_skill_toggles() -> void:
	var class_data: Dictionary = DataManager.get_class_data(class_id)
	for skill_id in class_data.get("skills", []):
		var skill_data: Dictionary = DataManager.get_skill(skill_id)
		skill_toggles[skill_id] = skill_data.get("default_on", true)


#region 스탯 계산
func get_max_hp() -> int:
	return base_hp + seed_bonus["hp"] + _get_equipment_stat("hp")

func get_max_mp() -> int:
	return base_mp + seed_bonus["mp"] + _get_equipment_stat("mp")

func get_str() -> int:
	return base_str + seed_bonus["str"] + _get_equipment_stat("str")

func get_def() -> int:
	return base_def + seed_bonus["def"] + _get_equipment_stat("def")

func get_int() -> int:
	return base_int + seed_bonus["int"] + _get_equipment_stat("int")

func get_spd() -> int:
	return base_spd + seed_bonus["spd"] + _get_equipment_stat("spd")

func get_luk() -> int:
	return base_luk + seed_bonus["luk"] + _get_equipment_stat("luk")

func get_atk() -> int:
	return get_str() + _get_equipment_stat("atk")

func get_p_def() -> int:
	return get_def()

func get_m_def() -> int:
	return get_int()

func get_eva() -> float:
	return get_spd() * 0.5 + get_luk() * 0.2

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


#region 레벨업
func add_exp(amount: int) -> bool:
	exp += amount
	if exp >= exp_to_next:
		_level_up()
		return true
	return false


func _level_up() -> void:
	level += 1
	exp -= exp_to_next
	exp_to_next = int(100 * pow(level, 1.5))
	
	var growth: Dictionary = DataManager.get_class_growth(class_id)
	base_hp += int(growth.get("hp", 1))
	base_mp += int(growth.get("mp", 1))
	base_str += int(growth.get("str", 1))
	base_def += int(growth.get("def", 1))
	base_int += int(growth.get("int", 1))
	base_spd += int(growth.get("spd", 1))
	base_luk += int(growth.get("luk", 1))
	
	current_hp = get_max_hp()
	current_mp = get_max_mp()
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


func use_mp(amount: int) -> bool:
	if current_mp < amount:
		return false
	current_mp -= amount
	return true


func revive(hp_percent: float = 0.3) -> void:
	if not is_dead:
		return
	is_dead = false
	current_hp = int(get_max_hp() * hp_percent)


func full_restore() -> void:
	current_hp = get_max_hp()
	current_mp = get_max_mp()
	is_dead = false
#endregion


#region 장비
func can_equip(equip_id: String) -> bool:
	var data: Dictionary = DataManager.get_equipment(equip_id)
	if data.is_empty():
		return false
	return DataManager.can_class_equip(class_id, data.get("type", ""))


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
	return skill_toggles.get(skill_id, false)


func get_enabled_skills() -> Array:
	var result: Array = []
	for skill_id in skill_toggles:
		if skill_toggles[skill_id]:
			result.append(skill_id)
	return result
#endregion


func use_seed(stat: String, value: int) -> void:
	if seed_bonus.has(stat):
		seed_bonus[stat] += value


func get_hp_percent() -> float:
	return float(current_hp) / float(get_max_hp())


func get_stat_summary() -> String:
	return "[%s] Lv.%d %s | HP:%d/%d MP:%d/%d | STR:%d DEF:%d INT:%d SPD:%d LUK:%d" % [
		hero_name, level, hero_class_name,
		current_hp, get_max_hp(), current_mp, get_max_mp(),
		get_str(), get_def(), get_int(), get_spd(), get_luk()
	]
