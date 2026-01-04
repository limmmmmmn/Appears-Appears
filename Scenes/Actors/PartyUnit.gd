extends CharacterBody2D
class_name PartyUnit

const SPEED = 200.0

@onready var sprite: Sprite2D = $Sprite2D

# [설계도 116] 충돌 감지 (Area2D의 body_entered 시그널 연결 필요)
func _on_hitbox_body_entered(body: Node2D) -> void:
	# 부딪힌 물체가 'FieldEnemy'라면 전투 시작
	if body is FieldEnemy:
		print("💥 적과 접촉! 전투 요청.")
		BattleManager.start_battle(body)

func _physics_process(_delta: float) -> void:
	# 이동 입력
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	if direction:
		velocity = direction * SPEED
	else:
		velocity = Vector2.ZERO

	move_and_slide()
	
	# [설계도 106-111] 비주얼 로직 (좌우 반전)
	if velocity.x > 0:
		sprite.flip_h = true  # 오른쪽 이동 시 반전
	elif velocity.x < 0:
		sprite.flip_h = false # 왼쪽 이동 시 원본 유지
