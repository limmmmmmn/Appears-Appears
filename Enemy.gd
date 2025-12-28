# res://Scenes/Field/Enemy.gd
class_name Enemy extends CharacterBody2D

# [추가] 전투 요청 신호 (내 데이터를 실어서 보냄)
signal battle_requested(enemy_data)

@onready var sprite = $Sprite2D

# 몬스터 능력치
var stats: EnemyData
var player_ref: Node2D = null # 플레이어가 누군지 기억할 변수

# AI 상태 관리 (서성거림 vs 추격)
enum State { WANDER, CHASE }
var current_state = State.WANDER

# 서성거림(Wander)을 위한 변수들
var wander_target: Vector2
var wander_timer: float = 0.0
const WANDER_INTERVAL = 2.0 # 2초마다 방향 바꿈
const WANDER_RADIUS = 20.0 # 20픽셀 구역 서성거림

func setup(data: EnemyData, target_player: Node2D):
	# 1. 데이터 설정
	stats = data
	if sprite and data.sprite:
		sprite.texture = data.sprite
	
	# 2. 추격 대상(플레이어) 정보 저장
	player_ref = target_player
	
	# 3. 처음 서성거릴 목표지점 설정
	pick_random_wander_target()

func _physics_process(delta):
	if not player_ref:
		return

	# 1. 플레이어와의 거리 계산
	var dist_to_player = global_position.distance_to(player_ref.global_position)
	
	# 2. 상태 결정 (감지 범위: 100픽셀)
	if dist_to_player < 100.0: # 플레이어를 감지함! 
		current_state = State.CHASE
	else:
		current_state = State.WANDER
	
	# 3. 상태에 따른 행동
	match current_state:
		State.CHASE:
			# 플레이어 쪽으로 이동
			var direction = (player_ref.global_position - global_position).normalized()
			velocity = direction * (stats.speed * 20) # 쫓아올 땐 조금 빠르게 (속도 보정)
			
		State.WANDER:
			# 랜덤한 지점으로 천천히 이동 
			var direction = (wander_target - global_position).normalized()
			
			# 목표에 거의 도착했거나, 시간이 되면 새로운 목표 설정
			wander_timer -= delta
			if global_position.distance_to(wander_target) < 5.0 or wander_timer <= 0:
				pick_random_wander_target()
				velocity = Vector2.ZERO # 잠시 멈춤
			else:
				velocity = direction * (stats.speed * 5) # 서성거릴 땐 천천히

# 4. 실제 이동 적용
	move_and_slide()
	
	# [추가] 충돌 감지: 플레이어와 닿았는지 확인 
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		
		# 부딪힌 게 내가 쫓던 플레이어라면?
		if collision.get_collider() == player_ref:
			# 전투 신호 발송!
			battle_requested.emit(stats)
			
			# 필드 위의 적은 사라짐
			queue_free()
			return # 나는 사라지니까 더 이상 코드 실행 X
	
	# 5. 바라보는 방향 전환 (스프라이트 뒤집기)
	if velocity.x < 0:
		sprite.flip_h = false
	elif velocity.x > 0:
		sprite.flip_h = true

# 랜덤한 근처 위치를 찍는 함수
func pick_random_wander_target():
	var random_x = randf_range(-WANDER_RADIUS, WANDER_RADIUS)
	var random_y = randf_range(-WANDER_RADIUS, WANDER_RADIUS)
	wander_target = global_position + Vector2(random_x, random_y)
	wander_timer = randf_range(1.0, 3.0) # 1~3초 동안 이동
