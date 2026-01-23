extends Node
## DataManager: JSON 데이터 로드 및 접근 담당

var classes: Dictionary = {}
var heroes: Dictionary = {}
var enemies: Dictionary = {}
var skills: Dictionary = {}
var equipment: Dictionary = {}
var items: Dictionary = {}
var shops: Dictionary = {}
var town_events: Dictionary = {}

const DATA_PATH := "res://data/"


func _ready() -> void:
	_load_all_data()


func _load_all_data() -> void:
	classes = _load_json("classes.json")
	heroes = _load_json("heroes.json")
	enemies = _load_json("enemies.json")
	skills = _load_json("skills.json")
	equipment = _load_json("equipment.json")
	items = _load_json("items.json")
	shops = _load_json("shops.json")
	town_events = _load_json("town_events.json")
	
	print("[DataManager] 데이터 로드 완료")
	print("  - Classes: ", classes.size())
	print("  - Heroes: ", heroes.size())
	print("  - Enemies: ", enemies.size())
	print("  - Skills: ", skills.size())
	print("  - Equipment: ", equipment.size())
	print("  - Items: ", items.size())
	print("  - Shops: ", shops.size())
	print("  - TownEvents: ", town_events.get("events", []).size())


func _load_json(filename: String) -> Dictionary:
	var path := DATA_PATH + filename
	if not FileAccess.file_exists(path):
		push_error("[DataManager] 파일 없음: " + path)
		return {}
	
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	
	if error != OK:
		push_error("[DataManager] JSON 파싱 실패: " + path)
		return {}
	return json.data


# 직업 (get_class -> get_class_data로 변경, Godot 내장 함수와 충돌 방지)
func get_class_data(class_id: String) -> Dictionary:
	return classes.get(class_id, {})

func get_class_base_stats(class_id: String) -> Dictionary:
	return get_class_data(class_id).get("base_stats", {})

func get_class_growth(class_id: String) -> Dictionary:
	return get_class_data(class_id).get("growth", {})

func can_class_dual_wield(class_id: String) -> bool:
	var c := get_class_data(class_id)
	return c.get("equip_restrictions", {}).get("dual_wield", false)

func can_class_equip(class_id: String, equip_type: String) -> bool:
	var c := get_class_data(class_id)
	var can_equip: Array = c.get("equip_restrictions", {}).get("can_equip", [])
	return equip_type in can_equip


# 영웅
func get_hero(hero_id: String) -> Dictionary:
	return heroes.get(hero_id, {})

func get_all_hero_ids() -> Array:
	return heroes.keys()


# 적
func get_enemy(enemy_id: String) -> Dictionary:
	return enemies.get(enemy_id, {})

func get_enemies_by_type(enemy_type: String) -> Array:
	var result: Array = []
	for id in enemies:
		if enemies[id].get("type", "") == enemy_type:
			result.append(enemies[id])
	return result


# 스킬
func get_skill(skill_id: String) -> Dictionary:
	return skills.get(skill_id, {})

func get_skill_mp_cost(skill_id: String) -> int:
	return int(get_skill(skill_id).get("mp_cost", 0))


# 장비
func get_equipment(equip_id: String) -> Dictionary:
	return equipment.get(equip_id, {})

func get_equipment_by_slot(slot: String) -> Array:
	var result: Array = []
	for id in equipment:
		if equipment[id].get("slot", "") == slot:
			result.append(equipment[id])
	return result

func get_equipment_by_rarity(rarity: String) -> Array[String]:
	## 특정 등급의 장비 ID 목록 반환
	var result: Array[String] = []
	for id in equipment:
		if str(equipment[id].get("rarity", "")) == rarity:
			result.append(str(id))
	return result

func get_equipment_by_rarities(rarities: Array[String]) -> Array[String]:
	## 여러 등급의 장비 ID 목록 반환 (magic, legendary 등)
	var result: Array[String] = []
	for id in equipment:
		var item_rarity: String = str(equipment[id].get("rarity", ""))
		if item_rarity in rarities:
			result.append(str(id))
	return result


# 아이템
func get_item(item_id: String) -> Dictionary:
	if items.has(item_id):
		return items[item_id]
	if equipment.has(item_id):
		return equipment[item_id]
	return {}


# 상점
func get_shop(shop_id: String) -> Dictionary:
	return shops.get(shop_id, {})


func get_shop_items(shop_id: String) -> Array:
	var shop: Dictionary = get_shop(shop_id)
	return shop.get("items", [])


# 마을 이벤트
func get_town_events() -> Array:
	return town_events.get("events", [])
