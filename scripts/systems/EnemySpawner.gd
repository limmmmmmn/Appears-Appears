extends RefCounted
class_name EnemySpawner
## 필드 적 스폰 시스템 (이동 기반 점진적 스폰)
## - 플레이어가 이동할 때만 적 스폰
## - 가만히 있으면 스폰 안 함

#=============================================================================
# 스폰 설정
#=============================================================================
const MAX_ENEMIES: int = 12                        # 최대 동시 적 수
const MIN_SPAWN_DISTANCE_FROM_PLAYER: float = 100.0  # 플레이어로부터 최소 거리
const MAX_SPAWN_DISTANCE_FROM_PLAYER: float = 250.0  # 플레이어로부터 최대 거리 (카메라 밖)
const MIN_SPAWN_DISTANCE_BETWEEN: float = 32.0     # 적들 사이 최소 거리
const ELITE_SPAWN_CHANCE: float = 0.15
const MAX_SPAWN_ATTEMPTS: int = 50

# 이동 기반 스폰 설정
const DISTANCE_PER_SPAWN: float = 60.0   # 이 거리 이동할 때마다 스폰 체크
const SPAWN_CHANCE_PER_CHECK: float = 0.7  # 체크 시 스폰 확률 (70%)
const INITIAL_ENEMY_COUNT: int = 3       # 시작 시 적 수

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

# 맵 경계 캐싱
var map_bounds: Rect2 = Rect2()
var bounds_calculated: bool = false

# 이동 추적
var last_player_pos: Vector2 = Vector2.ZERO
var accumulated_distance: float = 0.0

signal enemy_spawned(enemy: Node2D)


func setup(p_field: Node2D, p_tilemap: TileMapLayer) -> void:
	field = p_field
	tilemap = p_tilemap
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	bounds_calculated = false
	accumulated_distance = 0.0
	last_player_pos = Vector2.ZERO


func spawn_initial_enemies(field_enemies: Array) -> void:
	## 초기 적 스폰 (소수만)
	if FieldManager.is_boss_field():
		_spawn_boss(field_enemies)
		return
	
	# 맵 경계 계산 (최초 1회)
	if not bounds_calculated:
		_calculate_map_bounds()
	
	var player_pos: Vector2 = _get_player_position()
	last_player_pos = player_pos
	
	var spawned_positions: Array[Vector2] = []
	
	# 시작 시 카메라 밖에 몇 마리만 스폰
	for i in range(INITIAL_ENEMY_COUNT):
		var pos: Vector2 = _find_spawn_position_around_player(player_pos, spawned_positions)
		if pos != Vector2.ZERO:
			var tile_type: String = _get_tile_type_at(pos)
			_spawn_enemy_at({"position": pos, "tile_type": tile_type}, field_enemies)
			spawned_positions.append(pos)


func setup_respawn_timer(parent: Node) -> void:
	## 타이머 대신 이동 기반 스폰 사용 - 빈 함수
	pass


func on_respawn_timer(field_enemies: Array) -> void:
	## 타이머 기반 리스폰은 사용 안 함
	pass


func update_movement_spawn(field_enemies: Array) -> void:
	## 플레이어 이동에 따른 스폰 체크 (Field._process에서 호출)
	if FieldManager.is_boss_field():
		return
	
	if field_enemies.size() >= MAX_ENEMIES:
		return
	
	var player_pos: Vector2 = _get_player_position()
	
	# 첫 호출 시 초기화
	if last_player_pos == Vector2.ZERO:
		last_player_pos = player_pos
		return
	
	# 이동 거리 누적
	var moved: float = player_pos.distance_to(last_player_pos)
	if moved < 1.0:  # 거의 안 움직임
		return
	
	accumulated_distance += moved
	last_player_pos = player_pos
	
	# 일정 거리 이동했으면 스폰 체크
	if accumulated_distance >= DISTANCE_PER_SPAWN:
		accumulated_distance = 0.0
		
		# 확률 체크
		if randf() < SPAWN_CHANCE_PER_CHECK:
			_try_spawn_enemy(field_enemies, player_pos)


func stop_respawn() -> void:
	## 호환성을 위해 유지
	pass


#=============================================================================
# 스폰 로직
#=============================================================================
func _try_spawn_enemy(field_enemies: Array, player_pos: Vector2) -> void:
	## 적 1마리 스폰 시도
	var existing_positions: Array[Vector2] = []
	for enemy in field_enemies:
		if is_instance_valid(enemy):
			existing_positions.append(enemy.global_position)
	
	var pos: Vector2 = _find_spawn_position_around_player(player_pos, existing_positions)
	if pos != Vector2.ZERO:
		var tile_type: String = _get_tile_type_at(pos)
		_spawn_enemy_at({"position": pos, "tile_type": tile_type}, field_enemies)


func _find_spawn_position_around_player(player_pos: Vector2, existing: Array[Vector2]) -> Vector2:
	## 플레이어 주변 (카메라 밖)에서 스폰 위치 찾기
	for _i in range(MAX_SPAWN_ATTEMPTS):
		# 랜덤 방향, 랜덤 거리
		var angle: float = randf() * TAU
		var distance: float = randf_range(MIN_SPAWN_DISTANCE_FROM_PLAYER, MAX_SPAWN_DISTANCE_FROM_PLAYER)
		var offset: Vector2 = Vector2(cos(angle), sin(angle)) * distance
		var random_pos: Vector2 = player_pos + offset
		
		if _is_valid_spawn_position(random_pos, player_pos, existing):
			return random_pos
	
	return Vector2.ZERO


func _is_valid_spawn_position(pos: Vector2, player_pos: Vector2, existing: Array[Vector2]) -> bool:
	## 스폰 가능한 위치인지 검증
	# 1. 맵 경계 안인지 확인
	if bounds_calculated and not map_bounds.has_point(pos):
		return false
	
	# 2. 카메라 안이면 스폰 안 함
	var camera_rect: Rect2 = _get_camera_rect()
	if camera_rect.has_point(pos):
		return false
	
	# 3. 플레이어와의 거리
	var dist_to_player: float = pos.distance_to(player_pos)
	if dist_to_player < MIN_SPAWN_DISTANCE_FROM_PLAYER:
		return false
	
	# 4. 다른 적들과의 거리
	for other_pos in existing:
		if pos.distance_to(other_pos) < MIN_SPAWN_DISTANCE_BETWEEN:
			return false
	
	# 5. 타일 스폰 가능 여부
	if not tilemap:
		return true
	
	var tile_type: String = _get_tile_type_at(pos)
	return FieldManager.can_spawn_on_tile(tile_type)


func _get_camera_rect() -> Rect2:
	## 현재 카메라 뷰 영역 반환
	if not field:
		return Rect2()
	
	var viewport_size: Vector2 = field.get_viewport_rect().size
	var camera: Camera2D = field.get_viewport().get_camera_2d()
	var player_pos: Vector2 = _get_player_position()
	
	if camera:
		var view_size: Vector2 = viewport_size / camera.zoom
		return Rect2(camera.global_position - view_size / 2, view_size)
	return Rect2(player_pos - viewport_size / 2, viewport_size)


#=============================================================================
# 맵 경계 계산
#=============================================================================
func _calculate_map_bounds() -> void:
	## 타일맵의 실제 사용 영역 계산 (1회만)
	if not tilemap:
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
# 내부 함수
#=============================================================================
func _spawn_boss(field_enemies: Array) -> void:
	var boss_id: String = FieldManager.get_boss_enemy()
	if boss_id.is_empty():
		push_error("[EnemySpawner] 보스 ID 없음!")
		return
	
	var enemy: Node2D = field_enemy_scene.instantiate()
	field.add_child(enemy)
	enemy.setup(boss_id, "grass", Vector2(350, 135), false)
	enemy.is_boss = true
	field_enemies.append(enemy)
	enemy_spawned.emit(enemy)


func _spawn_enemy_at(tile_data: Dictionary, field_enemies: Array, force_elite: bool = false) -> void:
	var enemy: Node2D = field_enemy_scene.instantiate()
	field.add_child(enemy)
	
	var tile_type: String = str(tile_data.get("tile_type", "grass"))
	var enemy_id: String = FieldManager.select_field_enemy_for_tile(tile_type)
	var is_elite: bool = force_elite or (randf() < ELITE_SPAWN_CHANCE)
	
	enemy.setup(enemy_id, tile_type, tile_data.get("position", Vector2.ZERO), is_elite)
	field_enemies.append(enemy)
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
	
	# 빈 타일이면 grass로 처리
	if source_id == -1:
		return "grass"
	
	return str(tile_type_map.get(source_id, "grass"))
