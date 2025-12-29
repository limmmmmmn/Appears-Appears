# res://Components/MoveComponent.gd
class_name MoveComponent extends Node

@export var speed: float = 150.0

# 움직일 대상 (CharacterBody2D여야 함)
@onready var body: CharacterBody2D = get_parent()

func handle_move(input_vector: Vector2):
	if input_vector != Vector2.ZERO:
		body.velocity = input_vector * speed
		body.move_and_slide()
		
		# 바라보는 방향 전환 (스프라이트가 있다면)
		var sprite = body.get_node_or_null("Sprite2D")
		if sprite:
			sprite.flip_h = input_vector.x < 0
	else:
		body.velocity = Vector2.ZERO
