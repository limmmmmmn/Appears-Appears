extends CharacterBody2D
class_name PartyFollower
## 파티 팔로워: 리더의 이동 경로를 Snake처럼 따라감

@export var follow_index: int = 1  # 1 = 첫 번째 팔로워, 2 = 두 번째...
@export var follow_speed: float = 65.0  # 리더보다 약간 빠르게 (따라잡기 위해)

var leader: PartyLeader = null
var target_position: Vector2 = Vector2.ZERO
var facing_right: bool = false

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	add_to_group("party_follower")


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(leader):
		return
	
	target_position = leader.get_position_at_offset(follow_index)
	
	var distance := global_position.distance_to(target_position)
	
	if distance > 2.0:  # 약간의 여유
		var direction := (target_position - global_position).normalized()
		velocity = direction * follow_speed
		_update_facing(direction.x)
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()


func _update_facing(x_direction: float) -> void:
	if x_direction > 0.1:
		facing_right = true
		sprite.flip_h = true
	elif x_direction < -0.1:
		facing_right = false
		sprite.flip_h = false


func setup(p_leader: PartyLeader, p_index: int) -> void:
	leader = p_leader
	follow_index = p_index
	
	# 초기 위치 설정
	global_position = leader.get_position_at_offset(follow_index)
	
	# 리더 방향 동기화
	leader.direction_changed.connect(_on_leader_direction_changed)
	facing_right = leader.get_facing_right()
	sprite.flip_h = facing_right


func _on_leader_direction_changed(is_facing_right: bool) -> void:
	# 리더 방향 변경 시 즉시 반영하지 않고, 이동 시 자연스럽게 변경
	pass
