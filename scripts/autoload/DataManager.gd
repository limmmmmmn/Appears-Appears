extends Node
## DataManager.gd
## JSON 데이터 로딩 및 관리 싱글톤

# ===== 로드 상태 =====
var is_loaded: bool = false

# ===== 데이터 캐시 =====
var _config: Dictionary = {}
var _characters: Dictionary = {}
var _enemies: Dictionary = {}
var _items: Dictionary = {}
var _skills: Dictionary = {}
var _stages: Dictionary = {}

# ===== 데이터 경로 =====
const DATA_PATH = "res://data/"

# ===== 시그널 =====
signal data_loaded
signal data_load_error(file_name: String, error: String)


func _ready() -> void:
	load_all_data()


# ===== 전체 데이터 로드 =====
func load_all_data() -> void:
	is_loaded = false
	
	# 필수 데이터 로드
	_config = _load_json("config.json")
	_characters = _load_json("characters.json")
	_enemies = _load_json("enemies.json")
	_items = _load_json("items.json")
	_skills = _load_json("skills.json")
	_stages = _load_json("stages.json")
	
	is_loaded = true
	data_loaded.emit()
	print("[DataManager] All data loaded successfully")


# ===== JSON 파일 로드 =====
func _load_json(file_name: String) -> Dictionary:
	var path = DATA_PATH + file_name
	
	if not FileAccess.file_exists(path):
		print("[DataManager] File not found: ", path)
		data_load_error.emit(file_name, "File not found")
		return {}
	
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		var error = FileAccess.get_open_error()
		print("[DataManager] Failed to open: ", path, " Error: ", error)
		data_load_error.emit(file_name, str(error))
		return {}
	
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_text)
	
	if parse_result != OK:
		print("[DataManager] JSON parse error in ", file_name, ": ", json.get_error_message())
		data_load_error.emit(file_name, json.get_error_message())
		return {}
	
	return json.data


# ===== Config 접근 =====
func get_config() -> Dictionary:
	return _config


func get_config_value(section: String, key: String, default = null):
	if _config.has(section) and _config[section].has(key):
		return _config[section][key]
	return default


# ===== 캐릭터 데이터 접근 =====
func get_character(char_id: String) -> Dictionary:
	if _characters.has("characters") and _characters["characters"].has(char_id):
		return _characters["characters"][char_id].duplicate(true)
	return {}


func get_all_characters() -> Dictionary:
	if _characters.has("characters"):
		return _characters["characters"]
	return {}


# ===== 적 데이터 접근 =====
func get_enemy(enemy_id: String) -> Dictionary:
	if _enemies.has("enemies") and _enemies["enemies"].has(enemy_id):
		return _enemies["enemies"][enemy_id].duplicate(true)
	return {}


func get_enemies_by_stage(stage: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _enemies.has("enemies"):
		return result
	
	for enemy_id in _enemies["enemies"]:
		var enemy = _enemies["enemies"][enemy_id]
		var min_stage = enemy.get("min_stage", 1)
		var max_stage = enemy.get("max_stage", 99)
		if stage >= min_stage and stage <= max_stage:
			var enemy_copy = enemy.duplicate(true)
			enemy_copy["id"] = enemy_id
			result.append(enemy_copy)
	
	return result


func get_boss(boss_id: String) -> Dictionary:
	if _enemies.has("bosses") and _enemies["bosses"].has(boss_id):
		return _enemies["bosses"][boss_id].duplicate(true)
	return {}


# ===== 아이템 데이터 접근 =====
func get_item(item_id: String) -> Dictionary:
	if _items.has("items") and _items["items"].has(item_id):
		return _items["items"][item_id].duplicate(true)
	return {}


func get_items_by_type(item_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _items.has("items"):
		return result
	
	for item_id in _items["items"]:
		var item = _items["items"][item_id]
		if item.get("type", "") == item_type:
			var item_copy = item.duplicate(true)
			item_copy["id"] = item_id
			result.append(item_copy)
	
	return result


# ===== 스킬 데이터 접근 =====
func get_skill(skill_id: String) -> Dictionary:
	if _skills.has("skills") and _skills["skills"].has(skill_id):
		return _skills["skills"][skill_id].duplicate(true)
	return {}


func get_skills_by_class(char_class: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _skills.has("skills"):
		return result
	
	for skill_id in _skills["skills"]:
		var skill = _skills["skills"][skill_id]
		var classes = skill.get("classes", [])
		if char_class in classes or "all" in classes:
			var skill_copy = skill.duplicate(true)
			skill_copy["id"] = skill_id
			result.append(skill_copy)
	
	return result


# ===== 스테이지 데이터 접근 =====
func get_stage(stage_num: int) -> Dictionary:
	var stage_key = str(stage_num)
	if _stages.has("stages") and _stages["stages"].has(stage_key):
		return _stages["stages"][stage_key].duplicate(true)
	return {}


func get_stage_nodes(stage_num: int) -> Array:
	var stage = get_stage(stage_num)
	return stage.get("nodes", [])


func get_total_stages() -> int:
	if _stages.has("stages"):
		return _stages["stages"].size()
	return 0


# ===== 유틸리티 =====
func reload_data() -> void:
	load_all_data()


func get_random_enemy_for_stage(stage: int) -> Dictionary:
	var enemies = get_enemies_by_stage(stage)
	if enemies.is_empty():
		return {}
	return enemies[randi() % enemies.size()]


func calculate_exp_for_level(level: int) -> int:
	var base_exp = get_config_value("balance", "base_exp_per_level", 100)
	var growth = get_config_value("balance", "exp_growth_rate", 1.5)
	return int(base_exp * pow(growth, level - 1))
