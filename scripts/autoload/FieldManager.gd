extends Node
## FieldManager: 필드 스폰 및 전투 생성 관리
## - 타일 기반 적 스폰
## - 필드 에너미 접촉 시 전투 에너미 생성 (필드 에너미가 최다/동률)
## - 가중치 1.5제곱 적용

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
	print("[FieldManager] 초기화 완료")


func _load_stage_data() -> void:
	var path := DATA_PATH + "stages.json"
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
	
	var data: Dictionary = json.data
	tile_types = data.get("tile_types", {})
	battle_config = data.get("battle_config", {})
	
	# stages 배열을 Dictionary로 변환 (id로 접근)
	for stage in data.get("stages", []):
		stages[stage["id"]] = stage
	
	print("[FieldManager] 스테이지 로드: ", stages.size())


#region 스테이지/필드 설정
func set_current_stage(stage_id: String) -> bool:
	if not stages.has(stage_id):
		push_error("[FieldManager] 존재하지 않는 스테이지: " + stage_id)
		return false
	
	current_stage_id = stage_id
	current_stage_data = stages[stage_id]
	print("[FieldManager] 스테이지 설정: ", current_stage_data.get("name", stage_id))
	return true


func set_current_field(field_id: String) -> bool:
	if current_stage_data.is_empty():
		push_error("[FieldManager] 스테이지가 설정되지 않음")
		return false
	
	for field in current_stage_data.get("fields", []):
		if field["id"] == field_id:
			current_field_id = field_id
			current_field_data = field
			print("[FieldManager] 필드 설정: ", field.get("name", field_id))
			return true
	
	push_error("[FieldManager] 존재하지 않는 필드: " + field_id)
	return false


func get_current_field_scene() -> String:
	return current_field_data.get("scene", "")


func is_boss_field() -> bool:
	return current_field_data.get("is_boss_field", false)
#endregion


#region 타일 기반 스폰
func can_spawn_on_tile(tile_type: String) -> bool:
	return tile_types.get(tile_type, {}).get("can_spawn", false)


func is_tile_walkable(tile_type: String) -> bool:
	return tile_types.get(tile_type, {}).get("walkable", true)


func get_enemy_pool_for_tile(tile_type: String) -> Dictionary:
	## 현재 스테이지의 해당 타일 적 풀 반환
	## 반환: { "slime": 50, "bat": 35, ... }
	var terrain_enemies: Dictionary = current_stage_data.get("terrain_enemies", {})
	return terrain_enemies.get(tile_type, {})


func select_field_enemy_for_tile(tile_type: String) -> String:
	## 타일 타입에 맞는 필드 에너미 1마리 선택 (가중치 기반)
	var pool := get_enemy_pool_for_tile(tile_type)
	if pool.is_empty():
		return ""
	return _weighted_random_select(pool)
#endregion


#region 전투 에너미 생성
func generate_battle_enemies(field_enemy_id: String, tile_type: String) -> Array:
	## 필드 에너미 접촉 시 전투 에너미 배열 생성
	## 규칙: 필드 에너미가 최다 또는 동률
	
	var min_enemies: int = battle_config.get("min_enemies", 1)
	var max_enemies: int = battle_config.get("max_enemies", 3)
	var battle_size: int = randi_range(min_enemies, max_enemies)
	
	var enemies: Array = [field_enemy_id]  # 필드 에너미 먼저 추가
	var field_enemy_count: int = 1
	
	var pool := get_enemy_pool_for_tile(tile_type)
	if pool.is_empty():
		return enemies
	
	# 나머지 슬롯 채우기
	while enemies.size() < battle_size:
		var new_enemy := _weighted_random_select_battle(pool)
		
		if new_enemy == field_enemy_id:
			# 같은 적이면 그냥 추가
			enemies.append(new_enemy)
			field_enemy_count += 1
		else:
			# 다른 적은 필드 에너미보다 적어야 함
			var other_count := enemies.count(new_enemy)
			if other_count + 1 < field_enemy_count:
				enemies.append(new_enemy)
			else:
				# 조건 안 맞으면 필드 에너미 추가
				enemies.append(field_enemy_id)
				field_enemy_count += 1
	
	battle_generated.emit(field_enemy_id, enemies)
	return enemies


func _weighted_random_select(pool: Dictionary) -> String:
	## 가중치 기반 랜덤 선택 (필드 스폰용 - 원본 가중치)
	var total_weight: float = 0.0
	for enemy_id in pool:
		total_weight += float(pool[enemy_id])
	
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	
	for enemy_id in pool:
		cumulative += float(pool[enemy_id])
		if roll <= cumulative:
			return enemy_id
	
	# 폴백
	return pool.keys()[0]


func _weighted_random_select_battle(pool: Dictionary) -> String:
	## 가중치 기반 랜덤 선택 (전투 추가용 - 1.5제곱 가중치)
	var exponent: float = battle_config.get("weight_exponent", 1.5)
	var total_weight: float = 0.0
	var adjusted_weights: Dictionary = {}
	
	for enemy_id in pool:
		var adjusted: float = pow(float(pool[enemy_id]), exponent)
		adjusted_weights[enemy_id] = adjusted
		total_weight += adjusted
	
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	
	for enemy_id in adjusted_weights:
		cumulative += adjusted_weights[enemy_id]
		if roll <= cumulative:
			return enemy_id
	
	return pool.keys()[0]
#endregion


#region 필드 적 스폰 (맵 로드 시 호출)
func spawn_field_enemies(spawn_tiles: Array) -> Array:
	## 스폰 가능한 타일 목록에서 적 배치
	## spawn_tiles: [{ "position": Vector2, "tile_type": String }, ...]
	## 반환: [{ "enemy_id": String, "position": Vector2 }, ...]
	
	var enemy_count_range: Dictionary = current_field_data.get("enemy_count", {"min": 3, "max": 5})
	var count: int = randi_range(
		int(enemy_count_range.get("min", 3)),
		int(enemy_count_range.get("max", 5))
	)
	
	# 스폰 가능한 타일만 필터링
	var valid_tiles: Array = []
	for tile_data in spawn_tiles:
		if can_spawn_on_tile(tile_data["tile_type"]):
			valid_tiles.append(tile_data)
	
	if valid_tiles.is_empty():
		push_warning("[FieldManager] 스폰 가능한 타일 없음!")
		return []
	
	# 랜덤하게 타일 선택 & 적 배치
	valid_tiles.shuffle()
	var spawned: Array = []
	
	for i in range(mini(count, valid_tiles.size())):
		var tile_data: Dictionary = valid_tiles[i]
		var enemy_id := select_field_enemy_for_tile(tile_data["tile_type"])
		
		if enemy_id.is_empty():
			continue
		
		var spawn_data := {
			"enemy_id": enemy_id,
			"position": tile_data["position"],
			"tile_type": tile_data["tile_type"]
		}
		spawned.append(spawn_data)
		field_enemy_spawned.emit(enemy_id, tile_data["position"])
	
	print("[FieldManager] 필드 에너미 스폰: ", spawned.size(), "마리")
	return spawned


func should_spawn_elite() -> bool:
	## 엘리트 스폰 여부 판정
	var chance: float = current_field_data.get("elite_chance", 0.0)
	return randf() < chance


func get_elite_enemy() -> String:
	## 현재 스테이지의 엘리트 풀에서 랜덤 선택
	var elite_pool: Array = current_stage_data.get("elite_pool", [])
	if elite_pool.is_empty():
		return ""
	return elite_pool[randi() % elite_pool.size()]


func get_boss_enemy() -> String:
	## 현재 스테이지의 보스 ID
	return current_stage_data.get("boss_id", "")
#endregion


#region 유틸리티
func get_stage_data(stage_id: String) -> Dictionary:
	return stages.get(stage_id, {})


func get_all_stage_ids() -> Array:
	return stages.keys()


func get_field_data(stage_id: String, field_id: String) -> Dictionary:
	var stage := get_stage_data(stage_id)
	for field in stage.get("fields", []):
		if field["id"] == field_id:
			return field
	return {}


func get_next_destination() -> String:
	## 현재 필드 클리어 후 다음 목적지
	return current_field_data.get("next", "")
#endregion
