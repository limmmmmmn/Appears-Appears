# _scripts/managers/BattleManager.gd
extends Node

var battle_window_scene = preload("res://scenes/ui/battle_window.tscn")
var battle_canvas: CanvasLayer

# 안전지대 설정 (픽셀 단위)
const SAFE_ZONE_RADIUS = 120.0 

func _ready():
	battle_canvas = CanvasLayer.new()
	battle_canvas.layer = 10 
	add_child(battle_canvas)

func start_battle(monster_data): # monster_data는 지금은 안 쓰지만 나중에 쓸 예정
	var new_window = battle_window_scene.instantiate()
	battle_canvas.add_child(new_window)
	
	# --- [수정된 위치 선정 로직] ---
	var final_pos = Vector2.ZERO
	var screen_size = get_viewport().get_visible_rect().size
	
	# 플레이어 위치 찾기 (화면 상의 위치)
	var player_screen_pos = screen_size / 2 # 기본값: 화면 중앙
	var player_node = get_tree().get_first_node_in_group("Player")
	if player_node:
		# 월드 좌표를 화면(Canvas) 좌표로 변환
		player_screen_pos = player_node.get_global_transform_with_canvas().origin

	# 적절한 위치를 찾을 때까지 최대 100번 시도 (무한 루프 방지)
	for i in range(100):
		# 1. 랜덤 좌표 생성 (창 크기 160x140 고려해서 화면 밖으로 안 나가게)
		var random_x = randf_range(20, screen_size.x - 180)
		var random_y = randf_range(20, screen_size.y - 160)
		var candidate_pos = Vector2(random_x, random_y)
		
		# 2. 플레이어와의 거리 계산
		# (창의 중심점과 플레이어 사이의 거리)
		var window_center = candidate_pos + Vector2(80, 70) # 창 크기의 절반
		var distance = window_center.distance_to(player_screen_pos)
		
		# 3. 안전지대(120px)보다 멀리 떨어져 있으면 OK!
		if distance > SAFE_ZONE_RADIUS:
			final_pos = candidate_pos
			break # 위치 찾았으니 반복문 탈출!
	
	# (만약 100번 다 실패하면 마지막에 뽑힌 곳에 그냥 띄움 - 화면이 꽉 찼을 때)
	new_window.position = final_pos
