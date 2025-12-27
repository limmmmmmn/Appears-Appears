# _scripts/FieldMonster.gd
extends CharacterBody2D

# 몬스터 상태 정의 (가만히 있거나, 쫓거나)
enum State { IDLE, CHASE }
var current_state = State.IDLE

var target_player = null # 쫓아갈 대상
const SPEED = 80.0 # 플레이어보다 조금 느리게 (플레이어는 150)

var is_triggered = false # <--- 1. 이 변수 추가! (중복 충돌 방지용)

func _physics_process(delta):
	match current_state:
		State.IDLE:
			# 가만히 있을 때는 아무것도 안 함 (숨쉬기 운동만)
			velocity = Vector2.ZERO
			
		State.CHASE:
			if target_player:
				# 1. 플레이어 방향 알아내기
				var direction = global_position.direction_to(target_player.global_position)
				
				# 2. 그 방향으로 이동
				velocity = direction * SPEED
				
				# 3. (옵션) 몬스터가 플레이어를 보게 뒤집기
				if direction.x < 0:
					$Sprite2D.flip_h = false # 왼쪽 봄
				else:
					$Sprite2D.flip_h = true  # 오른쪽 봄
	
# _scripts/FieldMonster.gd

# ... (위쪽 코드는 그대로)

	move_and_slide()

# 충돌 체크 부분 수정
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		
		# 플레이어랑 부딪혔고, 아직 처리가 안 된 상태라면?
		if collision.get_collider().name == "PlayerHead" and is_triggered == false:
			
			is_triggered = true # <--- 2. "자, 이제 처리 들어간다!" 하고 깃발 꽂기
			
			print("전투 윈도우 생성 요청! ⚔️")
			BattleManager.start_battle(self)
			queue_free()

# --- 아래는 시야 감지(Area2D) 신호 연결 ---

func _on_detection_area_body_entered(body):
	# 내 시야(원) 안에 누군가 들어왔는데, 그게 플레이어라면?
	if body.name == "PlayerHead":
		current_state = State.CHASE
		target_player = body
		print("발견했다! 쫓아간다!")

func _on_detection_area_body_exited(body):
	# 플레이어가 시야 밖으로 도망치면?
	if body.name == "PlayerHead":
		current_state = State.IDLE
		target_player = null
		print("놓쳤다...")
