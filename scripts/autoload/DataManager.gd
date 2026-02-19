extends Node
## DataManager: 데이터 로드 및 접근 담당

var classes: Dictionary = {}
var heroes: Dictionary = {}
var enemies: Dictionary = {}
var skills: Dictionary = {}
var equipment: Dictionary = {}
var items: Dictionary = {}
var traits: Dictionary = {}
var dialogues: Dictionary = {}
var trinkets: Dictionary = {}

const CLASS_RESOURCE_PATH := "res://data/classes"
const HERO_RESOURCE_PATH := "res://data/heroes"
const ENEMY_RESOURCE_PATH := "res://data/enemies"
const SKILL_RESOURCE_PATH := "res://data/skills"
const EQUIPMENT_RESOURCE_PATH := "res://data/equipment"
const ITEM_RESOURCE_PATH := "res://data/items"
const TRAIT_RESOURCE_PATH := "res://data/traits"
const DIALOGUE_JSON_DIR_PATH := "res://data/dialogues"
const TRINKET_RESOURCE_PATH := "res://data/trinkets"


func _ready() -> void:
	_load_all_data()


func _load_all_data() -> void:
	classes = _load_class_data()
	heroes = _load_hero_data()
	enemies = _load_enemy_data()
	skills = _load_skill_data()
	equipment = _load_equipment_data()
	items = _load_item_data()
	traits = _load_trait_data()
	dialogues = _load_dialogue_data()
	trinkets = _load_trinket_data()
	


func _load_enemy_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(ENEMY_RESOURCE_PATH, "Enemy")
	if loaded.is_empty():
		push_error("[DataManager] Enemy resources are empty: " + ENEMY_RESOURCE_PATH)
	return loaded


func _load_class_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(CLASS_RESOURCE_PATH, "Class")
	if loaded.is_empty():
		push_error("[DataManager] Class resources are empty: " + CLASS_RESOURCE_PATH)
	return loaded


func _load_hero_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(HERO_RESOURCE_PATH, "Hero")
	if loaded.is_empty():
		push_error("[DataManager] Hero resources are empty: " + HERO_RESOURCE_PATH)
	return loaded


func _load_skill_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(SKILL_RESOURCE_PATH, "Skill")
	if loaded.is_empty():
		push_error("[DataManager] Skill resources are empty: " + SKILL_RESOURCE_PATH)
	return loaded


func _load_equipment_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(EQUIPMENT_RESOURCE_PATH, "Equipment")
	if loaded.is_empty():
		push_error("[DataManager] Equipment resources are empty: " + EQUIPMENT_RESOURCE_PATH)
	return loaded


func _load_item_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(ITEM_RESOURCE_PATH, "Item")
	if loaded.is_empty():
		push_error("[DataManager] Item resources are empty: " + ITEM_RESOURCE_PATH)
	return loaded


func _load_trait_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(TRAIT_RESOURCE_PATH, "Trait")
	if loaded.is_empty():
		push_error("[DataManager] Trait resources are empty: " + TRAIT_RESOURCE_PATH)
	return loaded


func _load_trinket_data() -> Dictionary:
	var loaded: Dictionary = _load_resource_dict(TRINKET_RESOURCE_PATH, "Trinket")
	if loaded.is_empty():
		push_error("[DataManager] Trinket resources are empty: " + TRINKET_RESOURCE_PATH)
	return loaded


func _load_dialogue_data() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(DIALOGUE_JSON_DIR_PATH)
	if dir == null:
		push_error("[DataManager] Dialogue directory not found: " + DIALOGUE_JSON_DIR_PATH)
		return out

	dir.list_dir_begin()
	while true:
		var filename: String = dir.get_next()
		if filename.is_empty():
			break
		if dir.current_is_dir() or not filename.ends_with(".json"):
			continue

		var file_path: String = DIALOGUE_JSON_DIR_PATH.path_join(filename)
		var parsed: Dictionary = _load_json_dictionary(file_path)
		if parsed.is_empty():
			continue

		var category_id: String = filename.get_basename()
		var entries: Dictionary = parsed
		var has_entries_container: bool = parsed.has("entries") and parsed.get("entries", {}) is Dictionary
		if has_entries_container:
			category_id = str(parsed.get("category", category_id))
			entries = parsed.get("entries", {}) as Dictionary
		if entries.is_empty():
			continue

		var cleaned: Dictionary = {}
		for trigger_key in entries.keys():
			var trigger_id: String = str(trigger_key)
			if trigger_id.begins_with("_"):
				continue
			cleaned[trigger_id] = entries[trigger_key]
		if cleaned.is_empty():
			continue

		var current: Dictionary = out.get(category_id, {}) as Dictionary
		for trigger_id in cleaned.keys():
			current[trigger_id] = cleaned[trigger_id]
		out[category_id] = current

	dir.list_dir_end()
	if out.is_empty():
		push_error("[DataManager] Dialogue JSON files are empty: " + DIALOGUE_JSON_DIR_PATH)
	return out


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[DataManager] JSON file not found: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DataManager] Failed to open JSON file: " + path)
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[DataManager] JSON parse failed: " + path)
		return {}
	if not (json.data is Dictionary):
		push_error("[DataManager] JSON root must be Dictionary: " + path)
		return {}
	return json.data as Dictionary


func _load_resource_dict(dir_path: String, label: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out

	dir.list_dir_begin()
	while true:
		var filename: String = dir.get_next()
		if filename.is_empty():
			break
		if dir.current_is_dir() or not filename.ends_with(".tres"):
			continue

		var resource_path: String = dir_path.path_join(filename)
		var loaded: Resource = load(resource_path)
		if loaded == null:
			push_error("[DataManager] %s resource load failed: %s" % [label, resource_path])
			continue
		if not loaded.has_method("to_dict"):
			push_warning("[DataManager] %s resource missing to_dict(): %s" % [label, resource_path])
			continue

		var entry_data: Dictionary = loaded.call("to_dict") as Dictionary
		if entry_data.is_empty():
			continue
		var entry_id: String = str(entry_data.get("id", ""))
		if entry_id.is_empty():
			entry_id = filename.get_basename()
			entry_data["id"] = entry_id
		out[entry_id] = entry_data

	dir.list_dir_end()
	return out


# 직업 (get_class -> get_class_data로 변경, Godot 내장 함수와 충돌 방지)
func get_class_data(class_id: String) -> Dictionary:
	return classes.get(class_id, {})

func get_class_base_stats(class_id: String) -> Dictionary:
	return get_class_data(class_id).get("base_stats", {})

func get_class_growth(class_id: String) -> Dictionary:
	return get_class_data(class_id).get("growth", {})

func can_class_dual_wield(class_id: String) -> bool:
	var c: Dictionary = get_class_data(class_id)
	return c.get("equip_restrictions", {}).get("dual_wield", false)

func can_class_equip(class_id: String, equip_type: String) -> bool:
	var c: Dictionary = get_class_data(class_id)
	var can_equip: Array = c.get("equip_restrictions", {}).get("can_equip", [])
	# 악세사리 타입 통합: ring/necklace/shoes/gloves → acc
	var check_type := equip_type
	if equip_type in ["ring", "necklace", "shoes", "gloves"]:
		check_type = "acc"
	return check_type in can_equip


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

func get_skill_cooldown(skill_id: String) -> float:
	return float(get_skill(skill_id).get("cooldown", 2.0))

func get_class_skills(class_id: String) -> Array:
	## 클래스의 스킬 목록 반환
	var class_data: Dictionary = get_class_data(class_id)
	return class_data.get("skills", ["basic_attack"])


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
		var data = equipment[id]
		if data is Dictionary and str(data.get("rarity", "")) == rarity:
			result.append(str(id))
	return result

func get_equipment_by_rarities(rarities: Array[String]) -> Array[String]:
	## 여러 등급의 장비 ID 목록 반환 (magic, legendary 등)
	var result: Array[String] = []
	for id in equipment:
		var data = equipment[id]
		if data is Dictionary:
			var item_rarity: String = str(data.get("rarity", ""))
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


# 특성
func get_trait(trait_id: String) -> Dictionary:
	return traits.get(trait_id, {})

func get_hero_traits(hero_id: String) -> Array:
	## 영웅의 특성 ID 목록 반환
	var hero_data: Dictionary = get_hero(hero_id)
	return hero_data.get("traits", [])


# 트링켓
func get_trinket(trinket_id: String) -> Dictionary:
	return trinkets.get(trinket_id, {})


func get_all_trinket_ids() -> Array[String]:
	var ids: Array[String] = []
	for tid in trinkets.keys():
		ids.append(str(tid))
	ids.sort()
	return ids


func get_trinkets_for_source(source: String) -> Array[String]:
	var result: Array[String] = []
	if source.is_empty():
		return result
	for tid in get_all_trinket_ids():
		var data: Dictionary = get_trinket(tid)
		var sources: Array = data.get("sources", []) as Array
		if source in sources:
			result.append(tid)
	return result


# 대사
func get_dialogues() -> Dictionary:
	return dialogues


func get_dialogue_lines(category: String, trigger: String, speaker_id: String = "") -> Array[String]:
	var result: Array[String] = []
	if category.is_empty() or trigger.is_empty():
		return result
	if dialogues.is_empty():
		return result

	var category_data: Dictionary = dialogues.get(category, {}) as Dictionary
	if category_data.is_empty():
		return result
	var trigger_data: Dictionary = category_data.get(trigger, {}) as Dictionary
	if trigger_data.is_empty():
		return result

	if not speaker_id.is_empty():
		var speakers_data: Dictionary = trigger_data.get("speakers", trigger_data.get("heroes", {})) as Dictionary
		var speaker_lines_variant: Variant = speakers_data.get(speaker_id, [])
		if speaker_lines_variant is Array:
			for v in speaker_lines_variant:
				result.append(str(v))
			if not result.is_empty():
				return result

	var global_lines_variant: Variant = trigger_data.get("global", [])
	if global_lines_variant is Array:
		for v in global_lines_variant:
			result.append(str(v))
	return result
