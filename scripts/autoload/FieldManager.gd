extends Node
## FieldManager: 필드 스폰 및 전투 생성 관리

signal field_loaded(field_id: String)
signal field_enemy_spawned(enemy_id: String, position: Vector2)
signal battle_generated(field_enemy_id: String, battle_enemies: Array)

var stages: Dictionary = {}
var tile_types: Dictionary = {}
var battle_config: Dictionary = {}

var current_stage_id: String = ""
var current_field_id: String = ""
var current_stage_data: Dictionary = {}
var current_field_data: Dictionary = {}

const DATA_PATH := "res://data/"


func _ready() -> void:
	_load_stage_data()


func _load_stage_data() -> void:
	var path: String = DATA_PATH + "stages.json"
	if not FileAccess.file_exists(path):
		push_error("[FieldManager] stages.json 없음!")
		return
	
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	
	if error != OK:
		push_error("[FieldManager] JSON 파싱 실패")
		return
	
	var data: Dictionary = json.data as Dictionary
	tile_types = data.get("tile_types", {}) as Dictionary
	battle_config = data.get("battle_config", {}) as Dictionary
	
	var stages_array: Array = data.get("stages", []) as Array
	for stage in stages_array:
		var stage_dict: Dictionary = stage as Dictionary
		var stage_id: String = str(stage_dict.get("id", ""))
		stages[stage_id] = stage_dict
	


#region 스테이지/필드 설정
func set_current_stage(stage_id: String) -> bool:
	if not stages.has(stage_id):
		push_error("[FieldManager] 존재하지 않는 스테이지: " + stage_id)
		return false
	
	current_stage_id = stage_id
	current_stage_data = stages[stage_id] as Dictionary
	return true


func set_current_field(field_id: String) -> bool:
	if current_stage_data.is_empty():
		push_error("[FieldManager] 스테이지가 설정되지 않음")
		return false
	
	var fields: Array = current_stage_data.get("fields", []) as Array
	for field in fields:
		var field_dict: Dictionary = field as Dictionary
		if str(field_dict.get("id", "")) == field_id:
			current_field_id = field_id
			current_field_data = field_dict
			field_loaded.emit(field_id)
			return true
	
	push_error("[FieldManager] 존재하지 않는 필드: " + field_id)
	return false


func get_current_field_scene() -> String:
	return str(current_field_data.get("scene", ""))


func get_current_field_name() -> String:
	return str(current_field_data.get("name", ""))


func get_current_stage_name() -> String:
	return str(current_stage_data.get("name", ""))


func is_boss_field() -> bool:
	return current_field_data.get("is_boss_field", false) as bool


func get_first_field_id(stage_id: String) -> String:
	if not stages.has(stage_id):
		return ""
	var stage: Dictionary = stages[stage_id] as Dictionary
	var fields: Array = stage.get("fields", []) as Array
	if fields.is_empty():
		return ""
	var first_field: Dictionary = fields[0] as Dictionary
	return str(first_field.get("id", ""))


func get_display_name() -> String:
	## HUD 표시용 "Stage 1-1"
	var stage_num: String = current_stage_id.replace("stage_", "")
	var field_parts: PackedStringArray = current_field_id.split("_")
	var field_num: String = field_parts[-1] if field_parts.size() > 0 else "1"
	return "Stage %s-%s" % [stage_num, field_num]
#endregion


#region 타일 기반 스폰
func can_spawn_on_tile(tile_type: String) -> bool:
	if not tile_types.has(tile_type):
		return false
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return tile_data.get("can_spawn", false) as bool


func is_tile_walkable(tile_type: String) -> bool:
	if not tile_types.has(tile_type):
		return true
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return tile_data.get("walkable", true) as bool


func is_exit_tile(tile_type: String) -> bool:
	## 출구 타일인지 확인
	if not tile_types.has(tile_type):
		return false
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return tile_data.get("is_exit", false) as bool


func get_exit_type(tile_type: String) -> String:
	## 출구 타일의 목적지 타입 반환 (stage, field, etc)
	if not tile_types.has(tile_type):
		return ""
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return str(tile_data.get("exit_type", ""))


func get_enemy_pool_for_tile(tile_type: String) -> Dictionary:
	var terrain_enemies: Dictionary = current_stage_data.get("terrain_enemies", {}) as Dictionary
	if not terrain_enemies.has(tile_type):
		return {}
	return terrain_enemies[tile_type] as Dictionary


func select_field_enemy_for_tile(tile_type: String) -> String:
	var pool: Dictionary = get_enemy_pool_for_tile(tile_type)
	if pool.is_empty():
		var terrain_enemies: Dictionary = current_stage_data.get("terrain_enemies", {}) as Dictionary
		if terrain_enemies.has("grass"):
			pool = terrain_enemies["grass"] as Dictionary
	if pool.is_empty():
		return "slime"
	return _weighted_random_select(pool)
#endregion


#region 전투 에너미 생성
func generate_battle_enemies(field_enemy_id: String, tile_type: String) -> Array:
	## 필드 에너미 접촉 시 전투 에너미 배열 생성

	var min_enemies: int = int(battle_config.get("min_enemies", 1))
	var max_enemies: int = int(battle_config.get("max_enemies", 3))
	var battle_size: int = randi_range(min_enemies, max_enemies)

	var enemies: Array = [field_enemy_id]

	var pool: Dictionary = get_enemy_pool_for_tile(tile_type)
	if pool.is_empty():
		var terrain_enemies: Dictionary = current_stage_data.get("terrain_enemies", {}) as Dictionary
		if terrain_enemies.has("grass"):
			pool = terrain_enemies["grass"] as Dictionary
	if pool.is_empty():
		return enemies

	# 가중치 내림차순 정렬하여 서열 결정
	var sorted_enemies: Array = pool.keys()
	sorted_enemies.sort_custom(func(a, b): return float(pool[a]) > float(pool[b]))

	# 필드 적의 서열 인덱스
	var field_rank: int = sorted_enemies.find(field_enemy_id)
	if field_rank == -1:
		battle_generated.emit(field_enemy_id, enemies)
		return enemies

	# 인접 서열 적만 추가 풀에 포함
	var add_pool: Dictionary = {}
	if field_rank > 0:
		var prev_id: String = sorted_enemies[field_rank - 1]
		add_pool[prev_id] = pool[prev_id]
	if field_rank < sorted_enemies.size() - 1:
		var next_id: String = sorted_enemies[field_rank + 1]
		add_pool[next_id] = pool[next_id]

	if add_pool.is_empty():
		battle_generated.emit(field_enemy_id, enemies)
		return enemies

	while enemies.size() < battle_size:
		var new_enemy: String = _weighted_random_select(add_pool)
		enemies.append(new_enemy)

	battle_generated.emit(field_enemy_id, enemies)
	return enemies


func _weighted_random_select(pool: Dictionary) -> String:
	var total_weight: float = 0.0
	for enemy_id in pool:
		total_weight += float(pool[enemy_id])
	
	if total_weight <= 0:
		var keys: Array = pool.keys()
		if keys.is_empty():
			return "slime"
		return str(keys[0])
	
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	
	for enemy_id in pool:
		cumulative += float(pool[enemy_id])
		if roll <= cumulative:
			return str(enemy_id)
	
	var keys: Array = pool.keys()
	return str(keys[0]) if not keys.is_empty() else "slime"
#endregion


#region 필드 적 스폰
func spawn_field_enemies(spawn_tiles: Array) -> Array:
	var enemy_count_data: Dictionary = current_field_data.get("enemy_count", {}) as Dictionary
	var min_count: int = int(enemy_count_data.get("min", 3))
	var max_count: int = int(enemy_count_data.get("max", 5))
	var count: int = randi_range(min_count, max_count)
	
	var valid_tiles: Array = []
	for tile_data in spawn_tiles:
		var tile_dict: Dictionary = tile_data as Dictionary
		var tile_type: String = str(tile_dict.get("tile_type", "grass"))
		if can_spawn_on_tile(tile_type):
			valid_tiles.append(tile_dict)
	
	if valid_tiles.is_empty():
		for i in range(count):
			valid_tiles.append({
				"position": Vector2(150 + i * 80, 120 + randf() * 60),
				"tile_type": "grass"
			})
	
	valid_tiles.shuffle()
	var spawned: Array = []
	
	for i in range(mini(count, valid_tiles.size())):
		var tile_dict: Dictionary = valid_tiles[i] as Dictionary
		var tile_type: String = str(tile_dict.get("tile_type", "grass"))
		var enemy_id: String = select_field_enemy_for_tile(tile_type)
		
		if enemy_id.is_empty():
			continue
		
		var spawn_data: Dictionary = {
			"enemy_id": enemy_id,
			"position": tile_dict.get("position", Vector2.ZERO),
			"tile_type": tile_type
		}
		spawned.append(spawn_data)
		field_enemy_spawned.emit(enemy_id, spawn_data["position"])
	
	return spawned


func should_spawn_elite() -> bool:
	var chance: float = float(current_field_data.get("elite_chance", 0.0))
	return randf() < chance


func get_elite_enemy() -> String:
	var elite_pool: Array = current_stage_data.get("elite_pool", []) as Array
	if elite_pool.is_empty():
		return ""
	return str(elite_pool[randi() % elite_pool.size()])


func get_boss_enemy() -> String:
	return str(current_stage_data.get("boss_id", ""))


func get_next_destination() -> String:
	return str(current_field_data.get("next", ""))
#endregion
