# scripts/enemies/Enemy.gd
extends CharacterBody2D

var enemy_data: Dictionary = {}
var enemy_id: String = ""

var current_hp: int = 30
var max_hp: int = 30
var attack: int = 5
var defense: int = 2
var move_speed: float = 80.0

enum State { IDLE, WANDER, CHASE, FLEE }
var current_state: State = State.WANDER

var player: Node2D = null
var detection_range: float = 150.0
var flee_range: float = 200.0

var wander_timer: float = 0.0
var wander_direction: Vector2 = Vector2.ZERO

var level_difference: int = 0
var battle_started: bool = false

@onready var hitbox: Area2D = $Hitbox

func _ready():
	print("[Enemy] Spawned: ", enemy_id if enemy_id else "unnamed")
	
	# ⭐ 시그널 중복 연결 방지
	if hitbox and not hitbox.body_entered.is_connected(_on_hitbox_body_entered):
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

func start_wandering():
	var angle = randf() * TAU
	wander_direction = Vector2(cos(angle), sin(angle))
	wander_timer = randf_range(2.0, 4.0)

func _on_hitbox_body_entered(body):
	if battle_started:
		return
	if body.is_in_group("player") or body.name == "Player":
		start_battle(body)

func start_battle(player_body):
	if battle_started:
		return
	
	battle_started = true
	print("\n[Enemy] Battle started with ", enemy_data.get("name", "Unknown"))
	
	EventBus.battle_started.emit(enemy_id)
	
	var battle_window = preload("res://scenes/ui/BattleWindow.tscn").instantiate()
	battle_window.name = "BattleWindow_" + str(get_instance_id())
	
	var canvas = get_tree().root.get_node_or_null("BattleCanvas")
	if not canvas:
		canvas = CanvasLayer.new()
		canvas.name = "BattleCanvas"
		canvas.layer = 100
		get_tree().root.add_child(canvas)
	
	canvas.add_child(battle_window)
	battle_window.init_battle(enemy_data, str(get_instance_id()))
	
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	var random_x = randf_range(50, viewport_size.x - 450)
	var random_y = randf_range(50, viewport_size.y - 350)
	battle_window.position = Vector2(random_x, random_y)
	
	# ⭐ 시그널 중복 연결 방지
	if not EventBus.battle_victory.is_connected(_on_battle_victory):
		EventBus.battle_victory.connect(_on_battle_victory, CONNECT_ONE_SHOT)
	
	queue_free()

func _on_battle_victory():
	pass

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
		player = get_tree().root.find_child("Player", true, false)

func set_level_difference(diff: int):
	level_difference = diff
