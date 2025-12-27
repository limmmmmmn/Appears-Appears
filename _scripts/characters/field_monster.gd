# _scripts/characters/field_monster.gd
extends CharacterBody2D

enum State { IDLE, CHASE }
var current_state = State.IDLE

var target_player = null
var is_triggered = false

# --- 배회 변수 ---
@onready var origin_position = global_position 
var wander_target = Vector2.ZERO 
var is_resting = false 
var move_speed = 30.0  
var chase_speed = 80.0 

# [수정 1] 느낌표의 원래 위치를 기억할 변수 추가
var emote_start_pos = Vector2.ZERO 

func _ready():
	if has_node("Emote"):
		$Emote.visible = false
		# [수정 2] 에디터에서 잡아둔 위치를 변수에 저장!
		emote_start_pos = $Emote.position 
		
	origin_position = global_position
	start_rest()

func _physics_process(delta):
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_chase(delta)
	
	move_and_slide()
	
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		if collision.get_collider().name == "PlayerHead" and is_triggered == false:
			is_triggered = true
			print("전투 윈도우 생성 요청! ⚔️")
			BattleManager.start_battle(self)
			queue_free()

# --- 배회 로직 ---
func _process_idle(delta):
	if is_resting:
		velocity = Vector2.ZERO
		return

	var direction = global_position.direction_to(wander_target)
	velocity = direction * move_speed
	
	if velocity.x < 0: $Sprite2D.flip_h = true
	elif velocity.x > 0: $Sprite2D.flip_h = false

	if global_position.distance_to(wander_target) < 2.0:
		start_rest()

func start_rest():
	is_resting = true
	velocity = Vector2.ZERO
	var wait_time = randf_range(1.0, 3.0)
	await get_tree().create_timer(wait_time).timeout
	pick_new_target()

func pick_new_target():
	var random_x = randf_range(-30, 30)
	var random_y = randf_range(-30, 30)
	wander_target = origin_position + Vector2(random_x, random_y)
	is_resting = false

# --- 추격 로직 ---
func _process_chase(delta):
	if target_player:
		var direction = global_position.direction_to(target_player.global_position)
		velocity = direction * chase_speed
		if velocity.x < 0: $Sprite2D.flip_h = true
		else: $Sprite2D.flip_h = false

# --- 시야 감지 ---
func _on_detection_area_body_entered(body):
	if body.name == "PlayerHead":
		if current_state == State.CHASE:
			return
		current_state = State.CHASE
		target_player = body
		is_resting = false 
		show_emote()

func _on_detection_area_body_exited(body):
	if body.name == "PlayerHead":
		current_state = State.IDLE
		target_player = null
		start_rest()

# --- [수정 3] 느낌표 연출 함수 ---
func show_emote():
	if not has_node("Emote"): return
	
	var emote = $Emote
	emote.visible = true       
	emote.modulate.a = 1.0     
	
	# [핵심 변경] 강제로 -50 하지 말고, 아까 기억해둔 위치(emote_start_pos)로 되돌리기!
	emote.position = emote_start_pos     
	emote.scale = Vector2(1, 1)

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC) 
	tween.set_ease(Tween.EASE_OUT)
	
	# 기억해둔 위치에서 위로 20만큼만 더 튀어오름
	tween.tween_property(emote, "position", emote_start_pos + Vector2(0, -20), 0.5)
	tween.parallel().tween_property(emote, "scale", Vector2(1.5, 1.5), 0.5)
	
	var tween_fade = create_tween()
	tween_fade.tween_interval(1.0) 
	tween_fade.tween_property(emote, "modulate:a", 0.0, 0.5) 
	
	tween_fade.tween_callback(emote.hide)
