# _scripts/managers/BattleManager.gd
extends Node

var battle_window_scene = preload("res://scenes/ui/battle_window.tscn")
var battle_canvas: CanvasLayer

# --- [설정값] ---
const SAFE_ZONE_RADIUS = 100.0
const PREV_WINDOW_RADIUS = 100.0

# [수정] 화면 밖으로 얼마나 나갈 수 있나? (40px 정도는 잘려도 됨)
const OUT_MARGIN = 10.0 

var last_battle_pos: Vector2 = Vector2.ZERO
var is_first_battle: bool = true

func _ready():
	battle_canvas = CanvasLayer.new()
	battle_canvas.layer = 10 
	add_child(battle_canvas)

func start_battle(monster_ref): 
	var new_window = battle_window_scene.instantiate()
	battle_canvas.add_child(new_window)
	
	var final_pos = Vector2.ZERO
	var screen_size = get_viewport().get_visible_rect().size
	
	# 플레이어 위치 찾기
	var player_screen_pos = screen_size / 2 
	var player_node = get_tree().get_first_node_in_group("Player")
	if player_node:
		player_screen_pos = player_node.get_global_transform_with_canvas().origin

	# 위치 찾기 시도
	for i in range(100):
		# [핵심 수정] 범위를 과감하게 넓힘!
		# -40 부터 (화면 크기 - 120) 까지 -> 양옆 위아래로 살짝씩 잘릴 수 있음
		# (창 크기가 160x140 정도라고 가정했을 때의 계산)
		
		var min_x = -OUT_MARGIN
		var max_x = screen_size.x - 160 + OUT_MARGIN # 오른쪽으로도 삐져나감
		
		var min_y = -OUT_MARGIN
		var max_y = screen_size.y - 140 + OUT_MARGIN # 아래로도 삐져나감
		
		var random_x = randf_range(min_x, max_x)
		var random_y = randf_range(min_y, max_y)
		
		var candidate_pos = Vector2(random_x, random_y)
		var window_center = candidate_pos + Vector2(80, 70) 
		
		# 2. 플레이어 피하기 (유지)
		var dist_to_player = window_center.distance_to(player_screen_pos)
		if dist_to_player < SAFE_ZONE_RADIUS:
			continue
			
		# 3. 직전 창 피하기 (유지)
		if not is_first_battle:
			var dist_to_last = candidate_pos.distance_to(last_battle_pos)
			if dist_to_last < PREV_WINDOW_RADIUS:
				continue 
		
		final_pos = candidate_pos
		break 
	
	new_window.position = final_pos
	last_battle_pos = final_pos
	is_first_battle = false
