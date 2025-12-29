# res://Components/SimpleAIComponent.gd
class_name SimpleAIComponent extends Node

# 이동을 시키기 위해 MoveComponent가 필요합니다.
@export var move_component: MoveComponent
@onready var actor = get_parent()

var move_direction: Vector2 = Vector2.ZERO
var timer: float = 0.0

func _process(delta):
	# 2초마다 랜덤한 방향으로 방향 전환
	timer -= delta
	if timer <= 0:
		timer = randf_range(1.0, 3.0)
		move_direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	
	# MoveComponent에게 명령 내리기 (플레이어의 Input과 똑같은 역할!)
	if move_component:
		move_component.handle_move(move_direction)
