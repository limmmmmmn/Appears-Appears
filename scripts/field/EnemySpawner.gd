# scripts/field/EnemySpawner.gd
# 뱀서 스타일! 카메라 가장자리에서 스폰!
extends Node2D

# 스폰 설정
@export var spawn_enabled: bool = true
@export var spawn_interval: float = 3.0  # 3초마다 스폰
@export var max_enemies: int = 15  # 최대 적 수
@export var spawn_distance: float = 50.0  # 카메라 밖 거리

# 스폰 가능한 적 목록
@export var enemy_pool: Array = ["enemy_001", "enemy_002", "enemy_003"]

# 내부 변수
var spawn_timer: float = 0.0
var player: Node2D = null
var camera: Camera2D = null
var enemy_scene: PackedScene

func _ready():
	print("[EnemySpawner] Vampire Survivors Style!")
	
	# Enemy 씬 로드
	enemy_scene = preload("res://scenes/enemies/Enemy.tscn")
	
	# 플레이어 & 카메라 찾기
	await get_tree().create_timer(0.5).timeout
	find_player_and_camera()
	
	# 초기 스폰
	if spawn_enabled:
		spawn_initial_enemies()

func _process(delta):
	if not spawn_enabled:
		return
	
	if not player or not camera:
		find_player_and_camera()
		return
	
	# 스폰 타이머
	spawn_timer += delta
	
	if spawn_timer >= spawn_interval:
		spawn_timer = 0.0
		try_spawn_enemy()

# ========================================
# 초기 스폰
# ========================================

func spawn_initial_enemies():
	print("[EnemySpawner] Spawning initial enemies...")
	
	for i in range(5):
		await get_tree().create_timer(0.3).timeout
		try_spawn_enemy()

# ========================================
# 뱀서 스타일 스폰! ⭐
# ========================================

func try_spawn_enemy():
	# 최대 적 수 체크
	var current_count = get_tree().get_nodes_in_group("enemies").size()
	if current_count >= max_enemies:
		return
	
	# 스폰 위치 = 카메라 가장자리!
	var spawn_pos = get_camera_edge_position()
	
	if spawn_pos == Vector2.ZERO:
		return
	
	spawn_enemy_at(spawn_pos)

func get_camera_edge_position() -> Vector2:
	if not camera:
		return Vector2.ZERO
	
	# 카메라 정보
	var camera_pos = camera.get_screen_center_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var zoom = camera.zoom
	
	# 실제 보이는 영역 크기
	var half_width = (viewport_size.x / zoom.x) / 2
	var half_height = (viewport_size.y / zoom.y) / 2
	
	# 카메라 가장자리 4방향 중 랜덤 선택
	var side = randi() % 4
	var spawn_pos = Vector2.ZERO
	
	match side:
		0:  # 위쪽 가장자리
			spawn_pos.x = camera_pos.x + randf_range(-half_width, half_width)
			spawn_pos.y = camera_pos.y - half_height - spawn_distance
		1:  # 아래쪽 가장자리
			spawn_pos.x = camera_pos.x + randf_range(-half_width, half_width)
			spawn_pos.y = camera_pos.y + half_height + spawn_distance
		2:  # 왼쪽 가장자리
			spawn_pos.x = camera_pos.x - half_width - spawn_distance
			spawn_pos.y = camera_pos.y + randf_range(-half_height, half_height)
		3:  # 오른쪽 가장자리
			spawn_pos.x = camera_pos.x + half_width + spawn_distance
			spawn_pos.y = camera_pos.y + randf_range(-half_height, half_height)
	
	return spawn_pos

func spawn_enemy_at(pos: Vector2):
	if enemy_pool.is_empty():
		return
	
	# 랜덤 적 타입
	var enemy_id = enemy_pool.pick_random()
	var enemy_data = DataManager.get_enemy(enemy_id)
	
	if enemy_data.is_empty():
		# 기본 데이터
		enemy_data = {
			"id": enemy_id,
			"name": "Slime",
			"base_stats": {
				"hp": 30,
				"attack": 5,
				"defense": 2,
				"attack_speed": 0.8
			},
			"drop_table": {
				"gold_min": 5,
				"gold_max": 15,
				"item_drop_rate": 0.1,
				"item_pool": []
			}
		}
	
	# Enemy 인스턴스 생성
	var enemy = enemy_scene.instantiate()
	enemy.global_position = pos
	enemy.add_to_group("enemies")
	
	# 필드에 추가
	get_parent().add_child(enemy)
	
	# 데이터 초기화
	if enemy.has_method("init_enemy"):
		enemy.init_enemy(enemy_data)
	
	# 레벨 차이
	var level_diff = GameManager.party_level - 1
	if enemy.has_method("set_level_difference"):
		enemy.set_level_difference(level_diff)
	
	print("[Spawner] %s at (%.0f, %.0f)" % [enemy_data.get("name", "?"), pos.x, pos.y])

# ========================================
# 유틸리티
# ========================================

func find_player_and_camera():
	# 플레이어 찾기
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
		
		# 카메라 찾기 (플레이어 자식)
		camera = player.find_child("Camera2D", true, false)
		
		if camera:
			print("[EnemySpawner] Found player and camera!")

func start_spawning():
	spawn_enabled = true

func stop_spawning():
	spawn_enabled = false

func set_spawn_rate(interval: float, max_count: int):
	spawn_interval = interval
	max_enemies = max_count
