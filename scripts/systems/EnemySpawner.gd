extends RefCounted
class_name EnemySpawner
## 필드 적 스폰 시스템 (맵 전역 분포 + 무한 리스폰)
## - 맵 전체에 걸쳐 적 분포
## - 처치된 적은 카메라 밖에서 일정 시간 후 리스폰

#=============================================================================
# 스폰 설정
#=============================================================================
const MAX_ENEMIES: int = 15                           # 최대 동시 적 수
const MIN_SPAWN_DISTANCE_BETWEEN: float = 40.0        # 적들 사이 최소 거리
const MIN_DISTANCE_FROM_PLAYER: float = 120.0         # 플레이어로부터 최소 거리 (스폰 시)
const ELITE_SPAWN_CHANCE: float = 0.15
const MAX_SPAWN_ATTEMPTS: int = 80

# 리스폰 설정
const RESPAWN_DELAY_MIN: float = 3.0   # 최소 리스폰 대기 시간
const RESPAWN_DELAY_MAX: float = 6.0   # 최대 리스폰 대기 시간

# 타일 타입 매핑
var tile_type_map: Dictionary = {
	0: "grass",
	1: "forest",
	2: "mountain",
	3: "water",
	4: "cave"
}

var field: Node2D
var tilemap: TileMapLayer
var field_enemy_scene: PackedScene

# 맵 데이터 캐싱
var map_bounds: Rect2 = Rect2()
var walkable_tiles: Array[Vector2] = []  # 스폰 가능한 타일 좌표 목록
var bounds_calculated: bool = false

# 리스폰 큐 (처치된 적 대기열)
var respawn_queue: Array[Dictionary] = []  # [{tile_type, delay_timer, original_pos}]

signal enemy_spawned(enemy: Node2D)
signal enemy_respawned(enemy: Node2D)


func setup(p_field: Node2D, p_tilemap: TileMapLayer) -> void:
	field = p_field
	tilemap = p_tilemap
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	bounds_calculated = false
	walkable_tiles.clear()
	respawn_queue.clear()


func spawn_initial_enemies(field_enemies: Array) -> void:
	## 초기 적 스폰 - 맵 전역에 분포
	if FieldManager.is_boss_field():
		_spawn_boss(field_enemies)
		return

	# 맵 데이터 계산 (최초 1회)
	if not bounds_calculated:
		_calculate_map_data()

	var player_pos: Vector2 = _get_player_position()
	var spawned_positions: Array[Vector2] = []

	# 맵 전역에 적 분포
	for i in range(MAX_ENEMIES):
		var pos: Vector2 = _find_distributed_spawn_position(player_pos, spawned_positions)
		if pos != Vector2.ZERO:
			var tile_type: String = _get_tile_type_at(pos)
			_spawn_enemy_at({"position": pos, "tile_type": tile_type}, field_enemies)
			spawned_positions.append(pos)


func setup_respawn_timer(parent: Node) -> void:
	## 리스폰 타이머는 _process에서 처리
	pass


func update_movement_spawn(field_enemies: Array) -> void:
	## 리스폰 큐 처리 (Field._process에서 호출)
	if FieldManager.is_boss_field():
		return

	var delta: float = field.get_process_delta_time() if field else 0.016
	var player_pos: Vector2 = _get_player_position()
	var camera_rect: Rect2 = _get_camera_rect()

	# 기존 적 위치 수집
	var existing_positions: Array[Vector2] = []
	for enemy in field_enemies:
		if is_instance_valid(enemy):
			existing_positions.append(enemy.global_position)

	# 리스폰 큐 처리
	var to_respawn: Array[int] = []
	for i in range(respawn_queue.size()):
		var entry: Dictionary = respawn_queue[i]
		entry["delay_timer"] -= delta

		if entry["delay_timer"] <= 0:
			# 최대 적 수 체크
			if field_enemies.size() >= MAX_ENEMIES:
				continue

			# 카메라 밖에서 스폰 위치 찾기
			var spawn_pos: Vector2 = _find_respawn_position(camera_rect, player_pos, existing_positions)
			if spawn_pos != Vector2.ZERO:
				to_respawn.append(i)
				var tile_type: String = entry.get("tile_type", "grass")
				_spawn_enemy_at({"position": spawn_pos, "tile_type": tile_type}, field_enemies, false, true)
				existing_positions.append(spawn_pos)

	# 리스폰된 항목 제거 (역순으로)
	to_respawn.reverse()
	for idx in to_respawn:
		respawn_queue.remove_at(idx)


func on_enemy_killed(tile_type: String, _position: Vector2) -> void:
	## 적이 처치되면 리스폰 큐에 추가
	var delay: float = randf_range(RESPAWN_DELAY_MIN, RESPAWN_DELAY_MAX)
	respawn_queue.append({
		"tile_type": tile_type,
		"delay_timer": delay,
		"original_pos": _position
	})


func stop_respawn() -> void:
	## 리스폰 중지 (보스 처치 시 등)
	respawn_queue.clear()


#=============================================================================
# 맵 데이터 계산
#=============================================================================
func _calculate_map_data() -> void:
	## 타일맵에서 스폰 가능한 모든 타일 수집
	walkable_tiles.clear()

	if not tilemap:
		# 타일맵 없으면 기본 영역 사용
		map_bounds = Rect2(0, 0, 800, 600)
		for x in range(0, 800, 32):
			for y in range(0, 600, 32):
				walkable_tiles.append(Vector2(x + 16, y + 16))
		bounds_calculated = true
		return

	var used_rect: Rect2i = tilemap.get_used_rect()
	var tile_size: Vector2 = Vector2(16, 16)

	map_bounds = Rect2(
		Vector2(used_rect.position) * tile_size,
		Vector2(used_rect.size) * tile_size
	)

	# 모든 타일 순회하여 스폰 가능한 타일 수집
	for x in range(used_rect.position.x, used_rect.position.x + used_rect.size.x):
		for y in range(used_rect.position.y, used_rect.position.y + used_rect.size.y):
			var cell := Vector2i(x, y)
			var source_id: int = tilemap.get_cell_source_id(cell)

			if source_id == -1:
				continue

			var tile_type: String = str(tile_type_map.get(source_id, "grass"))
			if FieldManager.can_spawn_on_tile(tile_type):
				var world_pos: Vector2 = tilemap.map_to_local(cell)
				walkable_tiles.append(world_pos)

	# 타일이 없으면 기본 위치들 추가
	if walkable_tiles.is_empty():
		for x in range(int(map_bounds.position.x), int(map_bounds.end.x), 48):
			for y in range(int(map_bounds.position.y), int(map_bounds.end.y), 48):
				walkable_tiles.append(Vector2(x, y))

	bounds_calculated = true


#=============================================================================
# 스폰 위치 찾기
#=============================================================================
func _find_distributed_spawn_position(player_pos: Vector2, existing: Array[Vector2]) -> Vector2:
	## 맵 전역에서 분포된 스폰 위치 찾기
	if walkable_tiles.is_empty():
		return Vector2.ZERO

	# 랜덤하게 타일 선택 시도
	var shuffled_indices: Array[int] = []
	for i in range(walkable_tiles.size()):
		shuffled_indices.append(i)
	shuffled_indices.shuffle()

	var attempts: int = mini(MAX_SPAWN_ATTEMPTS, walkable_tiles.size())
	for i in range(attempts):
		var idx: int = shuffled_indices[i]
		var pos: Vector2 = walkable_tiles[idx]

		# 플레이어와 거리 체크
		if pos.distance_to(player_pos) < MIN_DISTANCE_FROM_PLAYER:
			continue

		# 다른 적들과 거리 체크
		var too_close: bool = false
		for other_pos in existing:
			if pos.distance_to(other_pos) < MIN_SPAWN_DISTANCE_BETWEEN:
				too_close = true
				break

		if not too_close:
			return pos

	return Vector2.ZERO


func _find_respawn_position(camera_rect: Rect2, player_pos: Vector2, existing: Array[Vector2]) -> Vector2:
	## 카메라 밖에서 리스폰 위치 찾기
	if walkable_tiles.is_empty():
		return Vector2.ZERO

	# 카메라 밖 타일만 필터링
	var outside_camera_tiles: Array[Vector2] = []
	for tile_pos in walkable_tiles:
		if not camera_rect.has_point(tile_pos):
			outside_camera_tiles.append(tile_pos)

	if outside_camera_tiles.is_empty():
		return Vector2.ZERO

	# 랜덤하게 선택
	outside_camera_tiles.shuffle()

	var attempts: int = mini(MAX_SPAWN_ATTEMPTS, outside_camera_tiles.size())
	for i in range(attempts):
		var pos: Vector2 = outside_camera_tiles[i]

		# 플레이어와 거리 체크
		if pos.distance_to(player_pos) < MIN_DISTANCE_FROM_PLAYER:
			continue

		# 다른 적들과 거리 체크
		var too_close: bool = false
		for other_pos in existing:
			if pos.distance_to(other_pos) < MIN_SPAWN_DISTANCE_BETWEEN:
				too_close = true
				break

		if not too_close:
			return pos

	return Vector2.ZERO


func _get_camera_rect() -> Rect2:
	## 현재 카메라 뷰 영역 반환 (약간 여유 추가)
	if not field:
		return Rect2()

	var viewport_size: Vector2 = field.get_viewport_rect().size
	var camera: Camera2D = field.get_viewport().get_camera_2d()
	var player_pos: Vector2 = _get_player_position()

	# 카메라 영역보다 약간 크게 (여유 공간)
	var margin: float = 32.0

	if camera:
		var view_size: Vector2 = viewport_size / camera.zoom
		var rect := Rect2(camera.global_position - view_size / 2, view_size)
		return rect.grow(margin)

	return Rect2(player_pos - viewport_size / 2, viewport_size).grow(margin)


#=============================================================================
# 내부 함수
#=============================================================================
func _spawn_boss(field_enemies: Array) -> void:
	var boss_id: String = FieldManager.get_boss_enemy()
	if boss_id.is_empty():
		push_error("[EnemySpawner] 보스 ID 없음!")
		return

	var enemy: Node2D = field_enemy_scene.instantiate()
	field.add_child(enemy)

	# 보스는 맵 중앙 근처에 스폰
	var boss_pos: Vector2 = map_bounds.get_center() if bounds_calculated else Vector2(350, 135)
	enemy.setup(boss_id, "grass", boss_pos, false)
	enemy.is_boss = true
	field_enemies.append(enemy)
	enemy_spawned.emit(enemy)


func _spawn_enemy_at(tile_data: Dictionary, field_enemies: Array, force_elite: bool = false, is_respawn: bool = false) -> void:
	var enemy: Node2D = field_enemy_scene.instantiate()
	field.add_child(enemy)

	var tile_type: String = str(tile_data.get("tile_type", "grass"))
	var enemy_id: String = FieldManager.select_field_enemy_for_tile(tile_type)
	var is_elite: bool = force_elite or (randf() < ELITE_SPAWN_CHANCE)

	enemy.setup(enemy_id, tile_type, tile_data.get("position", Vector2.ZERO), is_elite)
	field_enemies.append(enemy)

	if is_respawn:
		enemy_respawned.emit(enemy)
	else:
		enemy_spawned.emit(enemy)


func _get_player_position() -> Vector2:
	if field and field.party_leader:
		return field.party_leader.global_position
	return Vector2(200, 150)


func _get_tile_type_at(pos: Vector2) -> String:
	## 특정 좌표의 타일 타입 반환
	if not tilemap:
		return "grass"

	var cell: Vector2i = tilemap.local_to_map(pos)
	var source_id: int = tilemap.get_cell_source_id(cell)

	if source_id == -1:
		return "grass"

	return str(tile_type_map.get(source_id, "grass"))
