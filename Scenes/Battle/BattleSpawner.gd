extends Node
class_name BattleSpawner  # <--- 이름 변경!

# 적 슬롯 씬 (외부에서 받아오거나 여기서 로드)
var enemy_slot_scene: PackedScene
var container: Control
var background_panel: Control

# 초기화 (BattleScene이 호출해줌)
func setup(_container: Control, _panel: Control, _slot_scene: PackedScene):
	container = _container
	background_panel = _panel
	enemy_slot_scene = _slot_scene

# 적 생성 및 배치
func spawn_enemies(main_enemy: EnemyData, spawn_table: Array[SpawnEntry]) -> Array:
	var active_enemies = []
	
	# 1. 팝업창 위치 랜덤 설정
	_set_window_position()
	
	# 2. 적 명단 작성 (메인 적 + 랜덤 친구들)
	var count = randi_range(1, 3)
	var enemies_to_spawn = [main_enemy]
	
	for i in range(count - 1):
		if not spawn_table.is_empty() and randf() > 0.3:
			enemies_to_spawn.append(spawn_table.pick_random().enemy)
		else:
			enemies_to_spawn.append(main_enemy)
	
	# 3. 슬롯(UI) 생성
	for data in enemies_to_spawn:
		if enemy_slot_scene:
			var slot = enemy_slot_scene.instantiate()
			container.add_child(slot)
			if slot.has_method("setup"):
				slot.setup(data)
			active_enemies.append(slot)
			
	return active_enemies

# 내부 함수: 전투 창(팝업)의 위치를 랜덤으로 잡는 함수
func _set_window_position():
	# 1. 현재 게임 화면의 전체 크기(해상도)를 가져옵니다.
	var viewport_rect = get_viewport().get_visible_rect()
	
	# 2. 화면의 정중앙 좌표를 계산합니다. (보통 플레이어가 여기에 서있으니까요)
	var center = viewport_rect.size / 2
	
	# 3. 중앙으로부터의 안전 거리입니다. (이 반경 50px 안에는 창을 띄우지 않습니다)
	var safe_zone = 100.0 
	
	# 4. 우리가 띄울 전투 창(검은 패널)의 크기를 가져옵니다.
	var panel_size = background_panel.size
	
	# 5. 적절한 위치를 찾을 때까지 최대 10번 시도합니다. (운이 나빠 겹칠 경우를 대비)
	for i in range(10):
		# 화면 밖으로 나가지 않도록 여백(20px)을 두고 랜덤 좌표(X, Y)를 생성합니다.
		var pos = Vector2(
			randf_range(-10, viewport_rect.size.x - panel_size.x - 0),
			randf_range(-10, viewport_rect.size.y - panel_size.y - 0)
		)
		
		# 생성된 위치의 중심점(pos + panel_size/2)이 화면 중앙(center)과 너무 가깝지 않은지 확인합니다.
		if (pos + panel_size/2).distance_to(center) > safe_zone:
			background_panel.position = pos  # 안전하면 위치 확정!
			return # 함수 종료 (성공)
	
