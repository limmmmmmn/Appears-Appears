# _scripts/characters/player_head.gd
extends CharacterBody2D
class_name PlayerHead

const SPEED = 120.0

# 발자국을 저장할 리스트 (Breadcrumbs)
var position_history: Array[Vector2] = []

# 발자국 사이의 간격 (픽셀) - 촘촘할수록 부드럽지만 데이터가 많아짐
# 5~10 정도가 적당해 (도트 크기에 따라 조절)
@export var record_threshold: float = 1.0 

# 저장할 최대 발자국 개수 (동료가 많으면 더 길어야 함)
@export var max_history_size: int = 500

func _physics_process(delta):
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * SPEED
	move_and_slide()
	
	# --- [여기 추가!] 발자국 코드 위에 넣으면 돼 ---
	
	# 왼쪽으로 가고 있으면?
	if velocity.x < 0:
		$Sprite2D.flip_h = true  # 뒤집어서 왼쪽 보게 함
		
	# 오른쪽으로 가고 있으면?
	elif velocity.x > 0:
		$Sprite2D.flip_h = false # 원래대로 오른쪽 보게 함
	
	# ----------------------------------------
	# --- [발자국 기록 로직] ---
	# 1. 움직였을 때만 기록한다.
	if velocity.length() > 0:
		# 2. 마지막으로 기록한 위치랑 비교해서, 일정 거리(5px) 이상 멀어졌을 때만 저장!
		if position_history.is_empty() or position_history[0].distance_to(global_position) > record_threshold:
			position_history.push_front(global_position)
			
			# 너무 많이 쌓이면 옛날 발자국 삭제
			if position_history.size() > max_history_size:
				position_history.pop_back()
