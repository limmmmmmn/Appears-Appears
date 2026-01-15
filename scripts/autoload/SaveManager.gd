# scripts/autoload/SaveManager.gd
extends Node

const SAVE_PATH = "user://hyper_quest_save.json"

signal save_completed
signal load_completed
signal save_failed
signal load_failed

func _ready():
	print("[SaveManager] Ready")

# ========================================
# 세이브
# ========================================

func save_game() -> bool:
	print("[SaveManager] Saving...")
	
	var save_data = {
		"version": "1.0",
		"timestamp": Time.get_datetime_string_from_system(),
		
		# GameManager 데이터
		"party": serialize_party(),
		"inventory": serialize_inventory(),
		"gold": GameManager.gold,
		"party_level": GameManager.party_level,
		"current_exp": GameManager.current_exp,
		"exp_to_next_level": GameManager.exp_to_next_level,
		"total_kills": GameManager.total_kills,
		"total_gold_earned": GameManager.total_gold_earned,
		"total_items_found": GameManager.total_items_found,
		
		# StageManager 데이터
		"current_stage": StageManager.current_stage,
		"kills_this_stage": StageManager.kills_this_stage,
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open save file!")
		save_failed.emit()
		return false
	
	var json_string = JSON.stringify(save_data, "\t")
	file.store_string(json_string)
	file.close()
	
	print("[SaveManager] Saved successfully!")
	save_completed.emit()
	return true

func serialize_party() -> Array:
	var result = []
	for hero in GameManager.party:
		result.append({
			"id": hero.id,
			"current_hp": hero.current_hp,
			"level": hero.level,
			"equipped": hero.get("equipped", {})
		})
	return result

func serialize_inventory() -> Array:
	var result = []
	for item in GameManager.inventory:
		result.append(item.id)
	return result

# ========================================
# 로드
# ========================================

func load_game() -> bool:
	print("[SaveManager] Loading...")
	
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveManager] No save file found")
		load_failed.emit()
		return false
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to open save file!")
		load_failed.emit()
		return false
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("Failed to parse save file!")
		load_failed.emit()
		return false
	
	var save_data = json.data
	
	# GameManager 복원
	GameManager.gold = save_data.get("gold", 1000)
	GameManager.party_level = save_data.get("party_level", 1)
	GameManager.current_exp = save_data.get("current_exp", 0)
	GameManager.exp_to_next_level = save_data.get("exp_to_next_level", 100)
	GameManager.total_kills = save_data.get("total_kills", 0)
	GameManager.total_gold_earned = save_data.get("total_gold_earned", 0)
	GameManager.total_items_found = save_data.get("total_items_found", 0)
	
	# 파티 복원
	deserialize_party(save_data.get("party", []))
	
	# 인벤토리 복원
	deserialize_inventory(save_data.get("inventory", []))
	
	# StageManager 복원
	StageManager.current_stage = save_data.get("current_stage", 1)
	StageManager.kills_this_stage = save_data.get("kills_this_stage", 0)
	
	print("[SaveManager] Loaded successfully!")
	print("  Party: %d heroes" % GameManager.party.size())
	print("  Gold: %d" % GameManager.gold)
	print("  Stage: %d" % StageManager.current_stage)
	
	load_completed.emit()
	return true

func deserialize_party(party_data: Array):
	GameManager.party.clear()
	
	for hero_save in party_data:
		var hero_id = hero_save.get("id", "")
		var hero_template = DataManager.get_hero(hero_id)
		
		if hero_template.is_empty():
			continue
		
		var hero = hero_template.duplicate(true)
		hero["current_hp"] = hero_save.get("current_hp", hero.base_stats.hp)
		hero["level"] = hero_save.get("level", 1)
		hero["equipped"] = hero_save.get("equipped", {})
		
		# 레벨에 따른 스탯 조정
		var level = hero.level
		if level > 1:
			var growth = hero.growth_rates
			hero.base_stats.hp += growth.hp * (level - 1)
			hero.base_stats.attack += growth.attack * (level - 1)
			hero.base_stats.defense += growth.defense * (level - 1)
		
		GameManager.party.append(hero)

func deserialize_inventory(inventory_data: Array):
	GameManager.inventory.clear()
	
	for item_id in inventory_data:
		var item = DataManager.get_item(item_id)
		if not item.is_empty():
			GameManager.inventory.append(item)

# ========================================
# 세이브 파일 관리
# ========================================

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
		print("[SaveManager] Save deleted")

func get_save_info() -> Dictionary:
	if not has_save():
		return {}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) != OK:
		return {}
	
	var data = json.data
	return {
		"timestamp": data.get("timestamp", "Unknown"),
		"party_level": data.get("party_level", 1),
		"stage": data.get("current_stage", 1),
		"gold": data.get("gold", 0)
	}
