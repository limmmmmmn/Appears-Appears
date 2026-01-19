extends Node
## 게임 데이터를 로드하고 관리하는 오토로드

# 데이터 저장소
var heroes: Dictionary = {}
var enemies: Dictionary = {}
var skills: Dictionary = {}
var equipment: Dictionary = {}  # 장비 데이터 추가

# 데이터 경로
const DATA_PATH := "res://data/"


func _ready() -> void:
	_load_all_data()


func _load_all_data() -> void:
	heroes = _load_json("heroes.json").get("heroes", {})
	enemies = _load_json("enemies.json").get("enemies", {})
	skills = _load_json("skills.json").get("skills", {})
	
	# 장비 데이터 로드
	var eq_data = _load_json("equipment.json")
	equipment = eq_data.get("equipment", {})
	
	print("[DataManager] 로드 완료 - 영웅: %d, 적: %d, 스킬: %d, 장비: %d" % [
		heroes.size(), enemies.size(), skills.size(), equipment.size()
	])


func _load_json(filename: String) -> Dictionary:
	var path := DATA_PATH + filename
	
	if not FileAccess.file_exists(path):
		push_error("[DataManager] 파일 없음: " + path)
		return {}
	
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[DataManager] 파일 열기 실패: " + path)
		return {}
	
	var json_text := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_text)
	
	if error != OK:
		push_error("[DataManager] JSON 파싱 실패: " + path + " - " + json.get_error_message())
		return {}
	
	return json.data


# === 데이터 접근 함수 ===

func get_hero(id: String) -> Dictionary:
	if not heroes.has(id):
		push_warning("[DataManager] 영웅 없음: " + id)
		return {}
	return heroes[id].duplicate(true)


func get_enemy(id: String) -> Dictionary:
	if not enemies.has(id):
		push_warning("[DataManager] 적 없음: " + id)
		return {}
	return enemies[id].duplicate(true)


func get_skill(id: String) -> Dictionary:
	if not skills.has(id):
		push_warning("[DataManager] 스킬 없음: " + id)
		return {}
	return skills[id].duplicate(true)


func get_equipment(id: String) -> Dictionary:
	## 장비 데이터 반환
	if not equipment.has(id):
		push_warning("[DataManager] 장비 없음: " + id)
		return {}
	return equipment[id].duplicate(true)


func get_all_hero_ids() -> Array:
	return heroes.keys()


func get_all_enemy_ids() -> Array:
	return enemies.keys()


func get_all_equipment_ids() -> Array:
	return equipment.keys()


func get_enemies_by_tag(tag: String) -> Array:
	var result := []
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		if enemy.get("tags", []).has(tag):
			result.append(id)
	return result


func get_equipment_by_slot(slot: String) -> Array:
	## 특정 슬롯의 모든 장비 ID 반환
	var result := []
	for id in equipment:
		var eq: Dictionary = equipment[id]
		if str(eq.get("slot", "")) == slot:
			result.append(id)
	return result


func get_equipment_by_type(eq_type: String) -> Array:
	## 특정 타입의 모든 장비 ID 반환
	var result := []
	for id in equipment:
		var eq: Dictionary = equipment[id]
		if str(eq.get("type", "")) == eq_type:
			result.append(id)
	return result


func get_equipment_by_rarity(rarity: String) -> Array:
	## 특정 등급의 모든 장비 ID 반환
	var result := []
	for id in equipment:
		var eq: Dictionary = equipment[id]
		if str(eq.get("rarity", "")) == rarity:
			result.append(id)
	return result


func can_hero_equip(hero_id: String, equipment_id: String) -> bool:
	## 영웅이 해당 장비를 장착할 수 있는지 확인
	var hero = get_hero(hero_id)
	var eq = get_equipment(equipment_id)
	
	if hero.is_empty() or eq.is_empty():
		return false
	
	var allowed = hero.get("allowed_equipment", [])
	var eq_type = str(eq.get("type", ""))
	
	return allowed.has(eq_type)


func get_rarity_color(rarity: String) -> Color:
	## 등급별 색상 반환
	match rarity:
		"common":
			return Color("aaaaaa")
		"uncommon":
			return Color("44ff44")
		"rare":
			return Color("4444ff")
		"epic":
			return Color("aa44aa")
		"legendary":
			return Color("ffaa00")
		_:
			return Color.WHITE
