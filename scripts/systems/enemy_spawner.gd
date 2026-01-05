class_name EnemySpawner extends Node2D
# [Blueprint v1.4] 5. 액터 카드 - EnemySpawner Logic

# --- 인스펙터 설정 (Inspector Controls) ---
@export_group("Spawn Settings")
@export var enemy_scene: PackedScene
@export var spawn_interval: float = 2.0
@export var spawn_radius_padding: float = 100.0

@export_group("Data")
@export var spawn_table: SpawnTable # 변경: 단순 리스트 -> 스폰 테이블

# --- 내부 변수 ---
var _timer: Timer
var _player: Player # 타겟 참조용

func _ready() -> void:
	# 플레이어 찾기 (그룹이나 클래스로 검색)
	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		# Player 스크립트에 class_name Player가 있으므로 타입으로 검색 가능
		var players = get_tree().get_nodes_in_group("player") # 혹은 직접 탐색
		if players.size() > 0: _player = players[0]
	
	# 타이머 설정
	_timer = Timer.new()
	_timer.wait_time = spawn_interval
	_timer.autostart = true
	_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_timer)

func _on_spawn_timer_timeout() -> void:
	# spawn_table 검사 추가
	if not _player or not spawn_table or not enemy_scene:
		return
	_spawn_enemy()

func _spawn_enemy() -> void:
	# 1. 테이블에서 가중치 기반으로 뽑기
	var random_data = spawn_table.pick_unit()
	if not random_data: return # 데이터가 비었으면 패스
	
	# 2. 카메라 밖 위치 계산
	var spawn_pos = _get_random_position_outside_camera()
	var enemy_instance = enemy_scene.instantiate() as FieldEnemy
	get_parent().add_child(enemy_instance)
	enemy_instance.setup(random_data, spawn_pos, _player, spawn_table)

# 카메라 뷰포트 사각형 밖의 랜덤 좌표를 구하는 로직
func _get_random_position_outside_camera() -> Vector2:
	var viewport = get_viewport()
	var camera = viewport.get_camera_2d()
	var center_pos = Vector2.ZERO
	
	if camera:
		center_pos = camera.get_screen_center_position()
	elif _player:
		center_pos = _player.global_position

	# 화면 크기 + 패딩
	var v_size = viewport.get_visible_rect().size / 2
	var spawn_dist_x = v_size.x + spawn_radius_padding
	var spawn_dist_y = v_size.y + spawn_radius_padding

	# 상하좌우 중 랜덤 방향 선택
	var side = randi() % 4
	var pos = Vector2.ZERO
	
	match side:
		0: # 위 (Top)
			pos.x = randf_range(-spawn_dist_x, spawn_dist_x)
			pos.y = -spawn_dist_y
		1: # 아래 (Bottom)
			pos.x = randf_range(-spawn_dist_x, spawn_dist_x)
			pos.y = spawn_dist_y
		2: # 왼쪽 (Left)
			pos.x = -spawn_dist_x
			pos.y = randf_range(-spawn_dist_y, spawn_dist_y)
		3: # 오른쪽 (Right)
			pos.x = spawn_dist_x
			pos.y = randf_range(-spawn_dist_y, spawn_dist_y)
			
	return center_pos + pos
