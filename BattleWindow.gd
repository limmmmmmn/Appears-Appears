extends Control

@onready var container = $Panel/HBoxContainer

# setup 함수 수정: void 가 아니라 Rect2를 돌려주도록 변경
func setup(enemy_data: EnemyData, history: Array[Rect2]) -> Rect2:
	# 1. 위치 선정
	pick_best_position(history)
	
	# 2. 적 생성
	var enemy_count = randi_range(1, 3)
	for i in range(enemy_count):
		create_enemy_ui(enemy_data)
		
	# [핵심 변경] 자리를 다 잡은 후, 내 최종 위치와 크기를 포장해서 보고합니다!
	# get_global_rect() 대신 현재 설정된 position과 size를 직접 사용해 정확도를 높입니다.
	var final_rect = Rect2(position, size)
	return final_rect

func pick_best_position(history: Array[Rect2]):
	var viewport_size = get_viewport_rect().size
	
	# 안전구역 (화면 중앙)
	var center_pos = viewport_size / 2
	var safe_area = Rect2(center_pos - Vector2(100, 100), Vector2(200, 200))
	
	# [핵심 수정 1] best_pos를 0,0이 아니라, 일단 '랜덤한 위치' 하나로 잡고 시작합니다.
	# 그래야 계산에 실패해도 구석에 안 박히고 이 위치라도 씁니다.
	var x_init = randf_range(0, viewport_size.x - size.x)
	var y_init = randf_range(0, viewport_size.y - size.y)
	var best_pos = Vector2(x_init, y_init)
	
	var best_score = -1.0 
	
	# 20번 시도해서 더 좋은 자리를 찾습니다.
	for i in range(20):
		# 랜덤 후보 생성
		var x = randf_range(0, viewport_size.x - size.x)
		var y = randf_range(0, viewport_size.y - size.y)
		var candidate_pos = Vector2(x, y)
		var candidate_rect = Rect2(candidate_pos, size)
		
		# 1. 플레이어(가운데)를 가리면? 이번 후보는 탈락! (다음 시도로 넘어감)
		if candidate_rect.intersects(safe_area):
			continue
			
		# 2. 이전에 뜬 창이 하나도 없다면?
		# 가운데만 안 가리면 되니까 이 자리가 최고! 바로 당첨!
		if history.is_empty():
			position = candidate_pos
			return
			
		# 3. 점수 매기기 (기존 창들과의 거리 중 최솟값)
		var min_dist = 99999.0
		for prev_rect in history:
			var dist = candidate_pos.distance_to(prev_rect.position)
			if dist < min_dist:
				min_dist = dist
		
		# 4. 신기록 갱신? (더 멀리 떨어진 자리를 찾았다!)
		if min_dist > best_score:
			best_score = min_dist
			best_pos = candidate_pos
	
	# 반복문이 끝나면 가장 점수가 높았던(멀리 떨어진) 위치 적용
	position = best_pos

# 적 이미지 생성 함수 (기존과 동일)
func create_enemy_ui(data: EnemyData):
	var enemy_texture = TextureRect.new()
	enemy_texture.texture = data.sprite
	enemy_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	container.add_child(enemy_texture)
