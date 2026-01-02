extends CharacterBody2D

# --- [1] 데이터 및 설정 ---
@export var enemy_data: BattleStats 

# 이동 설정
@export var wander_radius: float = 50.0
@export var speed: float = 30.0
@export var chase_speed: float = 80.0
@export var attack_range: float = 50.0 

# (스폰 관리용: 전투 끝나고 돌아왔을 때 처리 등을 위함)
var my_spawn_table: Array[SpawnEntry] = [] 

# --- [2] 상태 관리 ---
enum State { IDLE, WANDER, CHASE }
var current_state = State.IDLE
var start_position: Vector2
var target_position: Vector2
var target_player: Node2D = null

# --- [3] 노드 참조 ---
@onready var sprite = $Sprite2D
@onready var wander_timer = $WanderTimer

# (필드에서는 실시간 공격을 안 할 거라면 BattleComponent는 없어도 됩니다. 
# 하지만 쿨타임 시스템을 유지하고 싶다면 두셔도 무방합니다.)
@onready var battle_component = get_node_or_null("BattleComponent")

func _ready():
	start_position = global_position
	
	# 1. 텍스처 적용
	if enemy_data:
		if "texture" in enemy_data and enemy_data.texture:
			sprite.texture = enemy_data.texture
		# 데이터에 이동 속도가 있다면 덮어쓰기
		if "move_speed" in enemy_data: speed = enemy_data.move_speed
		if "chase_speed" in enemy_data: chase_speed = enemy_data.chase_speed
	
	pick_new_state()
	
	# 2. 감지 영역 연결 (플레이어 발견용)
	if has_node("DetectionZone"):
		$DetectionZone.body_entered.connect(_on_detection_zone_body_entered)
		$DetectionZone.body_exited.connect(_on_detection_zone_body_exited)
	
	# 3. [핵심 복구] 전투 트리거 연결 (화면 전환용)
	# BattleTrigger라는 Area2D 노드가 있어야 합니다!
	if has_node("BattleTrigger"):
		$BattleTrigger.body_entered.connect(_on_battle_trigger_body_entered)
		$BattleTrigger.area_entered.connect(_on_battle_trigger_area_entered)
	
	wander_timer.timeout.connect(pick_new_state)

func _physics_process(_delta):
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.WANDER:
			var direction = (target_position - global_position).normalized()
			velocity = direction * speed
			if global_position.distance_to(target_position) < 10:
				current_state = State.IDLE
		State.CHASE:
			if target_player:
				var direction = (target_player.global_position - global_position).normalized()
				velocity = direction * chase_speed
	
	move_and_slide()
	
	if velocity.x != 0:
		sprite.flip_h = velocity.x > 0

# --- [4] 전투 트리거 로직 (여기서 화면 전환!) ---

# 플레이어 몸체(Body)와 부딪혔을 때
func _on_battle_trigger_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		start_battle()

# 파티원 히트박스(Area)와 부딪혔을 때 (선택 사항)
func _on_battle_trigger_area_entered(area):
	if area.is_in_group("party_hitbox"):
		start_battle()

# 전투 시작 신호 보내기
func start_battle():
	# 이미 삭제 대기 중이면 중복 실행 방지
	if is_queued_for_deletion(): return

	print("⚔️ 전투 화면으로 전환 요청! 적: " + str(enemy_data.resource_name))
	
	# [SignalBus] 전투 씬 매니저에게 "전투 시작해!"라고 요청
	# 적 데이터(enemy_data)와 스폰 테이블 정보를 넘겨줍니다.
	SignalBus.request_battle.emit(enemy_data, my_spawn_table)
	
	# 필드 몬스터는 임무를 다했으니 사라집니다.
	queue_free()

# --- 상태 변경 로직 ---
func pick_new_state():
	if current_state == State.CHASE: return

	if randf() > 0.5:
		current_state = State.IDLE
	else:
		current_state = State.WANDER
		target_position = start_position + Vector2(randf_range(-wander_radius, wander_radius), randf_range(-wander_radius, wander_radius))

# --- 감지 로직 ---
func _on_detection_zone_body_entered(body):
	if body.name == "Player" or body.is_in_group("player"):
		target_player = body
		current_state = State.CHASE

func _on_detection_zone_body_exited(body):
	if body == target_player:
		target_player = null
		current_state = State.IDLE
		start_position = global_position
