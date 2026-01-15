# scripts/enemies/Enemy.gd
extends CharacterBody2D

# 적 데이터
var enemy_data: Dictionary = {}
var enemy_id: String = ""

# 스탯
var current_hp: int = 30
var max_hp: int = 30
var attack: int = 5
var defense: int = 2
var move_speed: float = 80.0

# AI 상태
enum State { IDLE, WANDER, CHASE, FLEE }
var current_state: State = State.WANDER

# 플레이어 참조
var player: Node2D = null
var detection_range: float = 150.0
var flee_range: float = 200.0

# 배회 관련
var wander_timer: float = 0.0
var wander_direction: Vector2 = Vector2.ZERO

# 레벨 차이
var level_difference: int = 0

# 전투 시작 여부
var battle_started: bool = false

# Area2D 참조
@onready var hitbox: Area2D = $Hitbox

func _ready():
	print("[Enemy] Spawned: ", enemy_id if enemy_id else "unnamed")
	
	# Area2D 시그널 연결
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	await get_tree().create_timer(0.1).timeout
	find_player()
	start_wandering()

func _physics_process(delta):
	if battle_started:
		return
	
	match current_state:
		State.IDLE:
			_idle_state(delta)
		State.WANDER:
			_wander_state(delta)
		State.CHASE:
			_chase_state(delta)
		State.FLEE:
			_flee_state(delta)
	
	move_and_slide()
	check_state_transitions()

# ========================================
# 상태별 행동
# ========================================

func _idle_state(delta):
	velocity = Vector2.ZERO
	wander_timer -= delta
	
	if wander_timer <= 0:
		change_state(State.WANDER)

func _wander_state(delta):
	velocity = wander_direction * move_speed * 0.5
	
	wander_timer -= delta
	if wander_timer <= 0:
		change_state(State.IDLE)
		wander_timer = randf_range(1.0, 2.0)

func _chase_state(delta):
	if player:
		var direction = (player.global_position - global_position).normalized()
		velocity = direction * move_speed

func _flee_state(delta):
	if player:
		var direction = (global_position - player.global_position).normalized()
		velocity = direction * move_speed * 1.2

# ========================================
# 상태 전환
# ========================================

func check_state_transitions():
	if not player:
		return
	
	var distance = global_position.distance_to(player.global_position)
	
	if level_difference >= 5:
		if current_state != State.FLEE:
			change_state(State.FLEE)
		return
	
	if distance < detection_range:
		if current_state != State.CHASE:
			change_state(State.CHASE)
	elif distance > flee_range:
		if current_state == State.CHASE:
			change_state(State.WANDER)

func change_state(new_state: State):
	if current_state == new_state:
		return
	
	current_state = new_state
	
	match new_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.WANDER:
			start_wandering()
		State.CHASE:
			print("  [Enemy] Chasing player!")
		State.FLEE:
			print("  [Enemy] Fleeing!")

func start_wandering():
	var angle = randf() * TAU
	wander_direction = Vector2(cos(angle), sin(angle))
	wander_timer = randf_range(2.0, 4.0)

# ========================================
# 충돌 & 전투 (Area2D 방식!) ⭐
# ========================================

func _on_hitbox_body_entered(body):
	if battle_started:
		return
	
	# 플레이어 체크
	if body.is_in_group("player") or body.name == "Player":
		start_battle(body)

func start_battle(player_body):
	if battle_started:
		return
	
	battle_started = true
	
	print("\n[Enemy] Battle started with ", enemy_data.get("name", "Unknown"))
	
	# 시그널 발송
	EventBus.battle_started.emit(enemy_id)
	
	# 전투창 생성
	var battle_window = preload("res://scenes/ui/BattleWindow.tscn").instantiate()
	battle_window.name = "BattleWindow_" + str(get_instance_id())
	
	# Canvas Layer에 추가
	var canvas = get_tree().root.get_node_or_null("BattleCanvas")
	if not canvas:
		canvas = CanvasLayer.new()
		canvas.name = "BattleCanvas"
		canvas.layer = 100
		get_tree().root.add_child(canvas)
	
	canvas.add_child(battle_window)
	
	# 전투 초기화
	battle_window.init_battle(enemy_data, str(get_instance_id()))
	
	# 전투창 위치 (랜덤)
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	var random_x = randf_range(50, viewport_size.x - 450)
	var random_y = randf_range(50, viewport_size.y - 350)
	battle_window.position = Vector2(random_x, random_y)
	
	print("  [Enemy] Disappeared from field")
	
	# 전투 종료 대기
	EventBus.battle_victory.connect(_on_battle_victory, CONNECT_ONE_SHOT)
	
	# 적 즉시 사라짐!
	queue_free()

func _on_battle_victory():
	pass  # 이미 queue_free() 호출됨

# ========================================
# 초기화
# ========================================

func init_enemy(data: Dictionary):
	enemy_data = data
	enemy_id = data.get("id", "")
	
	if data.has("base_stats"):
		var stats = data.base_stats
		max_hp = stats.get("hp", 30)
		current_hp = max_hp
		attack = stats.get("attack", 5)
		defense = stats.get("defense", 2)
		move_speed = stats.get("attack_speed", 0.8) * 100.0
	
	print("  Initialized: ", data.get("name", "?"), " HP:", max_hp)

func find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]
	else:
		var root = get_tree().root
		player = root.find_child("Player", true, false)

func set_level_difference(diff: int):
	level_difference = diff
	if diff >= 5:
		print("  [Enemy] Player too strong! Will flee.")
