extends RefCounted
class_name EnemySpawner
## 필드 적 스폰 시스템 (플레이어 근처 + 무한 리스폰)
## - 플레이어 카메라 바로 바깥에 적 스폰
## - 처치된 적은 카메라 밖에서 일정 시간 후 리스폰

#=============================================================================
# 스폰 설정
#=============================================================================
const MAX_ENEMIES: int = 5                            # 최대 동시 적 수
const MIN_SPAWN_DISTANCE_BETWEEN: float = 24.0        # 적들 사이 최소 거리
const MIN_DISTANCE_FROM_PLAYER: float = 40.0          # 플레이어로부터 최소 거리
const MAX_DISTANCE_FROM_PLAYER: float = 150.0         # 플레이어로부터 최대 거리
const ELITE_SPAWN_CHANCE: float = 0.15
const MAX_SPAWN_ATTEMPTS: int = 50

# 리스폰 설정
const RESPAWN_DELAY_MIN: float = 1.0   # 최소 리스폰 대기 시간
const RESPAWN_DELAY_MAX: float = 2.5   # 최대 리스폰 대기 시간

# 적 재배치 설정
const MAX_DISTANCE_FROM_CAMERA: float = 250.0  # 카메라에서 이 거리 이상이면 재배치

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
	respawn_queue.clear()


func spawn_initial_enemies(field_enemies: Array) -> void:
	## 초기 적 스폰 - 플레이어 주변에 분포
	if FieldManager.is_boss_field():
		_spawn_boss(field_enemies)
		return

	# 맵 데이터 계산 (최초 1회)
	if not bounds_calculated:
		_calculate_map_data()

	var player_pos: Vector2 = _get_player_position()
	var spawned_positions: Array[Vector2] = []

	# 플레이어 주변에 적 스폰
	for i in range(MAX_ENEMIES):
		var pos: Vector2 = _find_spawn_position_around_player(player_pos, spawned_positions)
		if pos != Vector2.ZERO:
			var tile_type: String = _get_tile_type_at(pos)
			_spawn_enemy_at({"position": pos, "tile_type": tile_type}, field_enemies)
			spawned_positions.append(pos)

	# 필드 보스 스폰 (일반 필드에도 하나씩)
	spawn_field_boss(field_enemies)


func setup_respawn_timer(parent: Node) -> void:
	## 리스폰 타이머는 _process에서 처리
	pass


func update_movement_spawn(field_enemies: Array) -> void:
	## 리스폰 큐 처리 및 멀리 떨어진 적 재배치 (Field._process에서 호출)
	if FieldManager.is_boss_field():
		return

	var delta: float = field.get_process_delta_time() if field else 0.016
	var player_pos: Vector2 = _get_player_position()
	var camera_rect: Rect2 = _get_camera_rect()
	var camera_center: Vector2 = camera_rect.get_center()

	# 기존 적 위치 수집 및 멀리 떨어진 적 재배치
	var existing_positions: Array[Vector2] = []
	for enemy in field_enemies:
		if is_instance_valid(enemy) and not enemy.is_boss:
			var dist_from_camera: float = enemy.global_position.distance_to(camera_center)

			# 카메라에서 너무 멀리 떨어진 적은 카메라 근처로 재배치
			if dist_from_camera > MAX_DISTANCE_FROM_CAMERA:
				var new_pos: Vector2 = _find_spawn_position_near_camera(camera_rect, player_pos, existing_positions)
				if new_pos != Vector2.ZERO:
					enemy.global_position = new_pos
					existing_positions.append(new_pos)
				else:
					existing_positions.append(enemy.global_position)
			else:
				existing_positions.append(enemy.global_position)
		elif is_instance_valid(enemy):
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

			# 카메라 근처에서 스폰 위치 찾기
			var spawn_pos: Vector2 = _find_spawn_position_near_camera(camera_rect, player_pos, existing_positions)
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
	## 맵 경계 계산
	if not tilemap:
		# 타일맵 없으면 기본 영역 사용
		map_bounds = Rect2(0, 0, 800, 600)
		bounds_calculated = true
		return

	var used_rect: Rect2i = tilemap.get_used_rect()
	var tile_size: Vector2 = Vector2(16, 16)

	map_bounds = Rect2(
		Vector2(used_rect.position) * tile_size,
		Vector2(used_rect.size) * tile_size
	)

	bounds_calculated = true


#=============================================================================
# 스폰 위치 찾기
#=============================================================================
func _find_spawn_position_around_player(player_pos: Vector2, existing: Array[Vector2]) -> Vector2:
	## 플레이어 주변 (카메라 내부)에서 스폰 위치 찾기
	var camera_rect: Rect2 = _get_camera_rect()

	for _i in range(MAX_SPAWN_ATTEMPTS):
		# 랜덤 방향, 플레이어 근처 거리 (카메라 안)
		var angle: float = randf() * TAU
		var distance: float = randf_range(MIN_DISTANCE_FROM_PLAYER, MAX_DISTANCE_FROM_PLAYER)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
		var pos: Vector2 = player_pos + offset

		# 맵 경계 체크
		if bounds_calculated and not map_bounds.has_point(pos):
			continue

		# 걸을 수 있는 타일인지 체크
		var tile_type: String = _get_tile_type_at(pos)
		if not FieldManager.can_spawn_on_tile(tile_type):
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


func _find_spawn_position_near_camera(camera_rect: Rect2, player_pos: Vector2, existing: Array[Vector2]) -> Vector2:
	## 카메라 가장자리 또는 바로 바깥에서 스폰 위치 찾기
	var camera_center: Vector2 = camera_rect.get_center()
	var half_width: float = camera_rect.size.x / 2
	var half_height: float = camera_rect.size.y / 2

	for _i in range(MAX_SPAWN_ATTEMPTS):
		# 카메라 가장자리 근처에서 스폰 (안쪽 또는 바깥쪽 약간)
		var edge: int = randi() % 4  # 0: 상, 1: 하, 2: 좌, 3: 우
		var pos: Vector2

		match edge:
			0:  # 상단
				pos = Vector2(
					camera_center.x + randf_range(-half_width * 0.8, half_width * 0.8),
					camera_center.y - half_height * randf_range(0.5, 1.2)
				)
			1:  # 하단
				pos = Vector2(
					camera_center.x + randf_range(-half_width * 0.8, half_width * 0.8),
					camera_center.y + half_height * randf_range(0.5, 1.2)
				)
			2:  # 좌측
				pos = Vector2(
					camera_center.x - half_width * randf_range(0.5, 1.2),
					camera_center.y + randf_range(-half_height * 0.8, half_height * 0.8)
				)
			3:  # 우측
				pos = Vector2(
					camera_center.x + half_width * randf_range(0.5, 1.2),
					camera_center.y + randf_range(-half_height * 0.8, half_height * 0.8)
				)

		# 플레이어에서 너무 가까우면 스킵
		if pos.distance_to(player_pos) < MIN_DISTANCE_FROM_PLAYER:
			continue

		# 맵 경계 체크
		if bounds_calculated and not map_bounds.has_point(pos):
			continue

		# 걸을 수 있는 타일인지 체크
		var tile_type: String = _get_tile_type_at(pos)
		if not FieldManager.can_spawn_on_tile(tile_type):
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
	enemy.add_to_group("field_boss")
	enemy.add_to_group("field_enemy")
	field_enemies.append(enemy)
	enemy_spawned.emit(enemy)


func spawn_field_boss(field_enemies: Array) -> void:
	## 필드 보스 스폰 (일반 필드에도 하나씩)
	if not bounds_calculated:
		_calculate_map_data()

	# 랜덤 적 선택
	var tile_types: Array = ["grass", "forest", "mountain"]
	var random_tile: String = tile_types[randi() % tile_types.size()]
	var boss_id: String = FieldManager.select_field_enemy_for_tile(random_tile)

	if boss_id.is_empty():
		boss_id = "slime"  # 기본값

	var enemy: Node2D = field_enemy_scene.instantiate()
	field.add_child(enemy)

	# 맵 중앙 근처에 스폰 (찾기 쉽게)
	var boss_pos: Vector2
	if bounds_calculated:
		boss_pos = map_bounds.get_center() + Vector2(randf_range(-100, 100), randf_range(-50, 50))
	else:
		boss_pos = Vector2(350, 200)

	enemy.setup(boss_id, random_tile, boss_pos, false)
	enemy.is_boss = true
	enemy.add_to_group("field_boss")
	enemy.add_to_group("field_enemy")

	# 10배 크기로 확대
	enemy.scale = Vector2(10, 10)

	# 보스는 움직이지 않음 - _ready 이후에 적용되도록 deferred
	enemy.set_deferred("wander_speed", 0.0)
	enemy.set_deferred("chase_speed", 0.0)

	field_enemies.append(enemy)
	enemy_spawned.emit(enemy)

	print("[EnemySpawner] 필드 보스 스폰: %s at %s" % [boss_id, boss_pos])


func _find_random_far_position(player_pos: Vector2) -> Vector2:
	## 플레이어에서 먼 랜덤 위치 찾기
	var attempts: int = 0
	while attempts < MAX_SPAWN_ATTEMPTS:
		var random_pos: Vector2
		if bounds_calculated:
			random_pos = Vector2(
				randf_range(map_bounds.position.x + 50, map_bounds.end.x - 50),
				randf_range(map_bounds.position.y + 50, map_bounds.end.y - 50)
			)
		else:
			random_pos = Vector2(
				randf_range(100, 600),
				randf_range(100, 400)
			)

		# 플레이어에서 최소 200픽셀 떨어진 곳
		if player_pos.distance_to(random_pos) >= 200:
			return random_pos

		attempts += 1

	# 실패 시 맵 구석
	return map_bounds.end - Vector2(100, 100) if bounds_calculated else Vector2(500, 300)


func _spawn_enemy_at(tile_data: Dictionary, field_enemies: Array, force_elite: bool = false, is_respawn: bool = false) -> void:
	var enemy: Node2D = field_enemy_scene.instantiate()
	field.add_child(enemy)

	var tile_type: String = str(tile_data.get("tile_type", "grass"))
	var enemy_id: String = FieldManager.select_field_enemy_for_tile(tile_type)
	var is_elite: bool = force_elite

	enemy.setup(enemy_id, tile_type, tile_data.get("position", Vector2.ZERO), is_elite)
	enemy.add_to_group("field_enemy")
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
