extends CharacterBody2D
class_name FieldEnemy

# [설계도 133, 134] 데이터 카드
@export var host_unit_data: UnitData
@export var loot_table: LootTable

# 배회 로직용 변수
var move_direction: Vector2 = Vector2.ZERO
var move_speed: float = 60.0

func _ready() -> void:
	# 랜덤 움직임 타이머 설정
	var timer = $MoveTimer
	timer.wait_time = 2.0
	timer.timeout.connect(_on_move_timer_timeout)
	timer.autostart = true
	timer.start()
	
	# 시작 시 즉시 움직임 결정
	_on_move_timer_timeout()

func _physics_process(_delta: float) -> void:
	velocity = move_direction * move_speed
	move_and_slide()
	
	# 스프라이트 반전
	if velocity.x != 0:
		$Sprite2D.flip_h = (velocity.x > 0)

func _on_move_timer_timeout() -> void:
	# 랜덤 방향 결정 (멈추거나, 걷거나)
	if randf() > 0.5:
		move_direction = Vector2.ZERO # 멈춤
	else:
		var angle = randf() * TAU
		move_direction = Vector2(cos(angle), sin(angle)) # 이동
