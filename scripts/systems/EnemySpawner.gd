extends RefCounted
class_name EnemySpawner
## 필드 적 스폰 시스템 (단순 배치 + 오프스크린 리스폰)
## - 시작 시 맵 곳곳에 적 배치
## - 처치된 적은 카메라에서 벗어난 뒤 리스폰

#=============================================================================
# 스폰 설정
#=============================================================================
const DEFAULT_MAX_ENEMIES: int = 6                    # 최대 동시 적 수(기본값)
const FIELD_ENEMY_COUNT_MULTIPLIER: float = 1.35      # 필드 적 수 증폭 계수
const MIN_SPAWN_DISTANCE_BETWEEN: float = 24.0        # 적들 사이 최소 거리
const EDGE_SPAWN_PADDING: float = 32.0                # 맵 가장자리 여유
const MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER: float = 120.0  # 초기 스폰 시 플레이어와 최소 거리
const ELITE_SPAWN_CHANCE: float = 0.15
const MAX_SPAWN_ATTEMPTS: int = 50

# 리스폰 설정
const RESPAWN_DELAY_MIN: float = 1.0   # 최소 리스폰 대기 시간
const RESPAWN_DELAY_MAX: float = 2.5   # 최대 리스폰 대기 시간
const FIELD_ENEMY_Z: int = 48

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
var target_enemy_count_cached: int = -1

# 리스폰 큐 (처치된 적 대기열)
var respawn_queue: Array[Dictionary] = []  # [{tile_type, delay_timer, original_pos}]

signal enemy_spawned(enemy: Node2D)
signal enemy_respawned(enemy: Node2D)


func setup(p_field: Node2D, p_tilemap: TileMapLayer) -> void:
	field = p_field
	tilemap = p_tilemap
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	bounds_calculated = false
	target_enemy_count_cached = -1
	respawn_queue.clear()


func spawn_initial_enemies(field_enemies: Array) -> void:
	## 초기 적 스폰 - 맵 곳곳에 분산 배치
	if FieldManager.is_boss_field():
		_spawn_boss(field_enemies)
		return

	# 맵 데이터 계산 (최초 1회)
	if not bounds_calculated:
		_calculate_map_data()

	var player_pos: Vector2 = _get_player_position()
	var spawned_positions: Array[Vector2] = []
	if target_enemy_count_cached <= 0:
		target_enemy_count_cached = _roll_target_enemy_count()
	var target_enemy_count: int = target_enemy_count_cached
	for enemy in field_enemies:
		if is_instance_valid(enemy):
			spawned_positions.append(enemy.global_position)

	# 초기 배치: 카메라 안/밖 모두 허용, 대신 플레이어와 충분히 떨어뜨림
	for i in range(target_enemy_count):
		var pos: Vector2 = _find_spawn_position_on_map(
			spawned_positions,
			Rect2(),
			false,
			player_pos,
			MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER
		)
		if pos == Vector2.ZERO:
			# 맵이 작아 자리가 부족하면 최소 거리만 완화해서 보완 배치
			pos = _find_spawn_position_on_map(
				spawned_positions,
				Rect2(),
				false,
				player_pos,
				MIN_INITIAL_SPAWN_DISTANCE_FROM_PLAYER * 0.6
			)
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
	## 리스폰 큐 처리 (카메라 밖에서만 리스폰)
	if FieldManager.is_boss_field():
		return

	var delta: float = field.get_process_delta_time() if field else 0.016
	var camera_rect: Rect2 = _get_camera_rect()
	if target_enemy_count_cached <= 0:
		target_enemy_count_cached = _roll_target_enemy_count()
	var target_enemy_count: int = target_enemy_count_cached

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
			if _get_non_boss_enemy_count(field_enemies) >= target_enemy_count:
				continue

			# 원래 자리 우선, 카메라에 보이면 대기
			var original_pos: Vector2 = entry.get("original_pos", Vector2.ZERO)
			var spawn_pos: Vector2 = Vector2.ZERO
			if _is_spawn_position_valid(original_pos, existing_positions) and not camera_rect.has_point(original_pos):
				spawn_pos = original_pos
			elif camera_rect.has_point(original_pos):
				continue
			else:
				# 원래 자리가 부적합하면 맵 내 카메라 바깥 위치 재선정
				spawn_pos = _find_spawn_position_on_map(existing_positions, camera_rect, true)

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
func _find_spawn_position_on_map(
	existing: Array[Vector2],
	avoid_rect: Rect2 = Rect2(),
	require_outside_avoid_rect: bool = false,
	player_pos: Vector2 = Vector2.ZERO,
	min_player_distance: float = 0.0
) -> Vector2:
	## 맵 전체에서 랜덤 스폰 위치 탐색
	if not bounds_calculated:
		_calculate_map_data()

	var x_min: float = map_bounds.position.x + EDGE_SPAWN_PADDING
	var x_max: float = map_bounds.end.x - EDGE_SPAWN_PADDING
	var y_min: float = map_bounds.position.y + EDGE_SPAWN_PADDING
	var y_max: float = map_bounds.end.y - EDGE_SPAWN_PADDING

	if x_min >= x_max or y_min >= y_max:
		return Vector2.ZERO

	for _i in range(MAX_SPAWN_ATTEMPTS):
		var pos := Vector2(
			randf_range(x_min, x_max),
			randf_range(y_min, y_max)
		)
		if require_outside_avoid_rect and avoid_rect.size.x > 0.0 and avoid_rect.has_point(pos):
			continue
		if not _is_spawn_position_valid(pos, existing, player_pos, min_player_distance):
			continue
		return pos

	return Vector2.ZERO


func _is_spawn_position_valid(
	pos: Vector2,
	existing: Array[Vector2],
	player_pos: Vector2 = Vector2.ZERO,
	min_player_distance: float = 0.0
) -> bool:
	if pos == Vector2.ZERO:
		return false
	if bounds_calculated and not map_bounds.has_point(pos):
		return false
	if min_player_distance > 0.0 and pos.distance_to(player_pos) < min_player_distance:
		return false

	var tile_type: String = _get_tile_type_at(pos)
	if not FieldManager.can_spawn_on_tile(tile_type):
		return false

	for other_pos in existing:
		if pos.distance_to(other_pos) < MIN_SPAWN_DISTANCE_BETWEEN:
			return false
	return true


func _get_non_boss_enemy_count(field_enemies: Array) -> int:
	var count: int = 0
	for enemy in field_enemies:
		if is_instance_valid(enemy) and not enemy.is_boss:
			count += 1
	return count


func _roll_target_enemy_count() -> int:
	if FieldManager and not FieldManager.current_field_data.is_empty():
		var enemy_count: Dictionary = FieldManager.current_field_data.get("enemy_count", {}) as Dictionary
		var min_count: int = int(enemy_count.get("min", DEFAULT_MAX_ENEMIES))
		var max_count: int = int(enemy_count.get("max", min_count))
		if max_count < min_count:
			max_count = min_count
		var rolled: int = randi_range(min_count, max_count)
		var boosted: int = int(round(float(rolled) * FIELD_ENEMY_COUNT_MULTIPLIER))
		return maxi(1, boosted)
	return DEFAULT_MAX_ENEMIES


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
	enemy.z_index = FIELD_ENEMY_Z
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

	var boss_id: String = FieldManager.get_field_boss_enemy()
	if boss_id.is_empty():
		boss_id = "slime"

	var enemy: Node2D = field_enemy_scene.instantiate()
	enemy.z_index = FIELD_ENEMY_Z
	field.add_child(enemy)

	# 기본은 맵 중앙, 테스트 필드는 커스텀 보스 위치 사용
	var boss_pos: Vector2 = map_bounds.get_center() if bounds_calculated else Vector2(480, 270)
	if field and field.has_method("get_test_field_boss_position"):
		var custom_pos: Variant = field.call("get_test_field_boss_position")
		if custom_pos is Vector2 and custom_pos != Vector2.ZERO:
			boss_pos = custom_pos as Vector2

	# 시작 위치와 충분히 떨어지도록 한 번 더 보정
	var player_pos: Vector2 = _get_player_position()
	if boss_pos.distance_to(player_pos) < 280.0:
		if bounds_calculated:
			boss_pos = Vector2(map_bounds.end.x - 96.0, map_bounds.position.y + 96.0)
		else:
			boss_pos = player_pos + Vector2(320.0, -180.0)
	enemy.setup(boss_id, "grass", boss_pos, false)
	enemy.is_boss = true
	enemy.add_to_group("field_boss")
	enemy.add_to_group("field_enemy")

	# 3배 크기 + 정지형 보스
	enemy.scale = Vector2(3, 3)

	# 보스는 움직이지 않음 - _setup_from_data 이후 덮어쓰기
	enemy.set_deferred("wander_speed", 0.0)
	enemy.set_deferred("chase_speed", 0.0)
	enemy.set_deferred("detection_range", 0.0)

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
	enemy.z_index = FIELD_ENEMY_Z
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
