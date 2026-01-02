extends Node2D

@onready var sprite = $Sprite2D

# 초기화 함수 (Player가 호출해줌)
func setup(data: UnitData, index: int):
	# 1. 텍스처 설정
	if data.texture:
		sprite.texture = data.texture
	else:
		sprite.texture = load("res://icon.svg")
	
	# 2. 크기 및 색상 설정 (기존 로직 이식)
	scale = Vector2(1, 1)
	

# 이동 함수 (Player가 매 프레임 호출)
func move_to(target_pos: Vector2):
	# 1. 방향 전환 (Flip)
	if target_pos.x < global_position.x:
		sprite.flip_h = false # 왼쪽
	elif target_pos.x > global_position.x:
		sprite.flip_h = true  # 오른쪽
	
	# 2. 위치 이동
	global_position = target_pos
