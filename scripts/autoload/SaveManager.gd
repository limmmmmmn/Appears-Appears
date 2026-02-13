extends Node
## SaveManager: 완전 자동 저장 시스템

signal save_completed(success: bool)
signal load_completed(success: bool)

const SAVE_PATH: String = "user://hyperquest_save.json"
const SAVE_VERSION: int = 1

# 자동 저장 설정
var auto_save_enabled: bool = true
var _save_cooldown: float = 0.0
const SAVE_COOLDOWN_TIME: float = 0.5  # 연속 저장 방지

# 필드 위치 저장용
var last_field_position: Vector2 = Vector2.ZERO
var last_field_stage: String = ""
var last_field_id: String = ""


func _ready() -> void:
	# 게임 종료 시 자동 저장
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()
		get_tree().quit()


func _process(delta: float) -> void:
	if _save_cooldown > 0:
		_save_cooldown -= delta


#region 자동 저장
func auto_save(reason: String = "") -> void:
	## 자동 저장 (쿨다운 적용)
	if not auto_save_enabled:
		return
	
	if _save_cooldown > 0:
		return
	
	_save_cooldown = SAVE_COOLDOWN_TIME
	
	save_game()


func save_field_position(pos: Vector2, stage_id: String, field_id: String) -> void:
	## 필드 위치 저장
	last_field_position = pos
	last_field_stage = stage_id
	last_field_id = field_id
#endregion


#region 세이브
func save_game() -> bool:
	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"timestamp": Time.get_datetime_string_from_system(),
		"game": _serialize_game_state(),
		"party": _serialize_party(),
		"inventory": _serialize_inventory(),
		"field_position": _serialize_field_position()
	}
	
	var json_string: String = JSON.stringify(save_data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	
	if file == null:
		push_error("[SaveManager] 세이브 파일 생성 실패")
		save_completed.emit(false)
		return false
	
	file.store_string(json_string)
	file.close()
	
	save_completed.emit(true)
	return true


func _serialize_game_state() -> Dictionary:
	return {
		"current_stage": GameManager.current_stage,
		"current_field": GameManager.current_field,
		"gold": GameManager.gold,
		"obtained_legendaries": GameManager.obtained_legendaries.duplicate(),
		"current_state": GameManager.current_state
	}


func _serialize_party() -> Array:
	var party_data: Array = []
	for hero in PartyManager.get_party():
		party_data.append({
			"id": hero.id,
			"level": hero.level,
			"current_exp": hero.current_exp,
			"level_stats": hero.level_stats.duplicate(),
			"current_hp": hero.current_hp,
			"is_dead": hero.is_dead,
			"seed_bonus": hero.seed_bonus.duplicate(),
			"equipment": hero.equipment.duplicate(),
			"skill_toggles": hero.skill_toggles.duplicate(),
			"unlocked_skills": hero.unlocked_skills.duplicate()
		})
	return party_data


func _serialize_inventory() -> Dictionary:
	return InventoryManager.items.duplicate()


func _serialize_field_position() -> Dictionary:
	return {
		"position_x": last_field_position.x,
		"position_y": last_field_position.y,
		"stage_id": last_field_stage,
		"field_id": last_field_id
	}


#endregion


#region 로드
func load_game() -> bool:
	if not has_save():
		load_completed.emit(false)
		return false
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		load_completed.emit(false)
		return false
	
	var json_string: String = file.get_as_text()
	file.close()
	
	var json := JSON.new()
	if json.parse(json_string) != OK:
		load_completed.emit(false)
		return false
	
	var save_data: Dictionary = json.data
	
	_deserialize_game_state(save_data.get("game", {}))
	_deserialize_party(save_data.get("party", []))
	_deserialize_inventory(save_data.get("inventory", {}))
	_deserialize_field_position(save_data.get("field_position", {}))
	
	load_completed.emit(true)
	return true


func _deserialize_game_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	GameManager.current_stage = int(data.get("current_stage", 1))
	GameManager.current_field = int(data.get("current_field", 1))
	GameManager.gold = int(data.get("gold", 0))
	GameManager.obtained_legendaries = data.get("obtained_legendaries", [])
	
	# current_state 복원 (enum은 int로 저장됨)
	var saved_state: int = int(data.get("current_state", GameManager.GameState.FIELD))
	GameManager.current_state = saved_state as GameManager.GameState
	
	GameManager.gold_changed.emit(GameManager.gold)


func _deserialize_party(data: Array) -> void:
	if data.is_empty():
		return
	PartyManager.party.clear()
	
	for hero_data in data:
		var hero_id: String = str(hero_data.get("id", ""))
		if hero_id.is_empty():
			continue
		
		var hero := Hero.create_from_id(hero_id)
		if hero.id.is_empty():
			continue
		
		hero.current_hp = int(hero_data.get("current_hp", hero.get_max_hp()))
		hero.is_dead = bool(hero_data.get("is_dead", false))

		var saved_seed: Dictionary = hero_data.get("seed_bonus", {})
		for stat in saved_seed:
			var stat_key: String = str(stat)
			var normalized_stat: String = stat_key
			if stat_key == "int":
				normalized_stat = "wis"
			elif stat_key == "dex":
				normalized_stat = "agi"
			elif stat_key == "def":
				normalized_stat = "def"
			if normalized_stat == "def":
				continue
			if hero.seed_bonus.has(normalized_stat):
				hero.seed_bonus[normalized_stat] = mini(Hero.SEED_CAP, int(saved_seed[stat]))

		var saved_level: int = int(hero_data.get("level", 1))
		var saved_exp: int = int(hero_data.get("current_exp", 0))
		var saved_level_stats: Dictionary = hero_data.get("level_stats", {})
		var saved_unlocked_skills: Array = hero_data.get("unlocked_skills", [])
		hero.set_progress(saved_level, saved_exp, saved_level_stats, saved_unlocked_skills)

		var saved_equip: Dictionary = hero_data.get("equipment", {})
		_apply_saved_equipment(hero, saved_equip)
		
		var saved_toggles: Dictionary = hero_data.get("skill_toggles", {})
		for skill_id in saved_toggles:
			hero.skill_toggles[skill_id] = bool(saved_toggles[skill_id])

		# 세이브 데이터를 모두 적용한 뒤 체력 안전 보정
		hero.current_hp = mini(hero.current_hp, hero.get_max_hp())
		
		PartyManager.party.append(hero)
	
	PartyManager.party_changed.emit()


func _deserialize_inventory(data: Dictionary) -> void:
	InventoryManager.items.clear()
	for item_id in data:
		InventoryManager.items[item_id] = int(data[item_id])
	InventoryManager.inventory_changed.emit()


func _apply_saved_equipment(hero: Hero, saved_equip: Dictionary) -> void:
	for slot in hero.equipment.keys():
		hero.equipment[slot] = ""
	if saved_equip.is_empty():
		return

	var accessory_queue: Array[String] = []
	for old_slot in ["acc1", "acc2", "ring1", "ring2", "necklace", "boots", "shoes", "gloves", "hands", "feet", "acc", "ring"]:
		var id: String = str(saved_equip.get(old_slot, ""))
		if not id.is_empty():
			accessory_queue.append(id)

	for old_slot in ["main_hand", "off_hand", "head", "body"]:
		var id: String = str(saved_equip.get(old_slot, ""))
		if id.is_empty():
			continue
		hero.equipment[old_slot] = id

	var acc_idx: int = 0
	for acc_slot in ["acc1", "acc2"]:
		while acc_idx < accessory_queue.size():
			var equip_id: String = accessory_queue[acc_idx]
			acc_idx += 1
			if not equip_id.is_empty():
				hero.equipment[acc_slot] = equip_id
				break


func _deserialize_field_position(data: Dictionary) -> void:
	if data.is_empty():
		return
	last_field_position = Vector2(
		float(data.get("position_x", 0)),
		float(data.get("position_y", 0))
	)
	last_field_stage = str(data.get("stage_id", ""))
	last_field_id = str(data.get("field_id", ""))


#endregion


#region 유틸리티
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> bool:
	if not has_save():
		return false
	DirAccess.remove_absolute(SAVE_PATH)
	return true


func get_save_info() -> Dictionary:
	if not has_save():
		return {}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return {}
	file.close()
	
	var save_data: Dictionary = json.data
	var game_data: Dictionary = save_data.get("game", {})
	var party_data: Array = save_data.get("party", [])
	
	return {
		"timestamp": save_data.get("timestamp", ""),
		"stage": int(game_data.get("current_stage", 1)),
		"field": int(game_data.get("current_field", 1)),
		"gold": int(game_data.get("gold", 0)),
		"party_size": party_data.size()
	}


func get_saved_field_position() -> Vector2:
	return last_field_position


func get_saved_field_info() -> Dictionary:
	return {
		"stage_id": last_field_stage,
		"field_id": last_field_id,
		"position": last_field_position
	}
#endregion
