extends CharacterBody2D
class_name PartyLeader
## 파티 리더: 플레이어 조작, 팔로워들이 따라옴

signal moved(new_position: Vector2)
signal direction_changed(facing_right: bool)

@export var move_speed: float = 60.0

var facing_right: bool = false  # 기본 스프라이트가 왼쪽을 봄
var position_history: Array[Vector2] = []  # 팔로워용 위치 기록
var history_max_size: int = 100  # 기록 최대 길이

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("party_leader")
	position_history.append(global_position)


func _physics_process(_delta: float) -> void:
	var input_dir := _get_input_direction()
	
	if input_dir != Vector2.ZERO:
		velocity = input_dir * move_speed
		_update_facing(input_dir.x)
		_record_position()
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	dir.x = Input.get_axis("ui_left", "ui_right")
	dir.y = Input.get_axis("ui_up", "ui_down")
	return dir.normalized()


func _update_facing(x_direction: float) -> void:
	var was_facing_right := facing_right
	
	if x_direction > 0.1:
		facing_right = true
		sprite.flip_h = true  # 기본이 왼쪽이라 오른쪽 볼 때 플립
	elif x_direction < -0.1:
		facing_right = false
		sprite.flip_h = false
	
	if was_facing_right != facing_right:
		direction_changed.emit(facing_right)


func _record_position() -> void:
	# 일정 거리 이동했을 때만 기록
	if position_history.is_empty() or global_position.distance_to(position_history[-1]) > 4.0:
		position_history.append(global_position)
		moved.emit(global_position)
		
		# 기록 크기 제한
		while position_history.size() > history_max_size:
			position_history.pop_front()


func get_position_at_offset(offset: int) -> Vector2:
	## 팔로워가 따라갈 위치 반환
	## offset: 몇 프레임 뒤를 따라갈지 (1 = 바로 뒤, 2 = 두 번째 등)
	var index := position_history.size() - 1 - (offset * 8)  # 8프레임 간격
	index = clampi(index, 0, position_history.size() - 1)
	return position_history[index]


func get_facing_right() -> bool:
	return facing_right
