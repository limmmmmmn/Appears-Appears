extends Node2D

@onready var sprite = $Sprite2D

# 텍스처를 임시 보관할 변수
var pending_texture: Texture2D = null

func _ready():
	# 게임 시작 시(_ready) 보관해둔 텍스처가 있다면 입힘
	if pending_texture != null:
		sprite.texture = pending_texture

# 외부에서 호출하는 함수
func setup(texture: Texture2D):
	# 1. 일단 변수에 저장
	pending_texture = texture
	
	# 2. 만약 이미 준비된 상태라면 바로 적용 (안전장치)
	if sprite != null:
		sprite.texture = texture

# [중요] 이 함수는 setup 함수 밖으로 나와야 합니다 (들여쓰기 주의!)
# 가장 왼쪽 벽에 붙어서 시작해야 합니다.
func move_to(target_pos: Vector2):
	# 단순히 위치만 이동하는 것이 아니라, 바라보는 방향 처리
	if target_pos.x < global_position.x:
		sprite.flip_h = false # 왼쪽 (원본이 왼쪽이므로)
	elif target_pos.x > global_position.x:
		sprite.flip_h = true # 오른쪽
	
	global_position = target_pos
