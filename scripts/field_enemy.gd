extends CharacterBody2D
class_name FieldEnemy

@export var enemy_id: String = "slime"

var is_active: bool = true
var spawn_position: Vector2
var wander_range: float = 48.0
var move_speed: float = 20.0

# 감지 & 추적
var detect_range: float = 60.0  # 플레이어 감지 거리
var chase_speed: float = 45.0  # 추적 속도
var lose_range: float = 90.0  # 추적 포기 거리
var is_chasing: bool = false
var player_ref: Node2D = null

# 배회
var wander_target: Vector2
var wander_timer: float = 0.0
var wander_wait_time: float = 2.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hitbox: Area2D = $Hitbox


func _ready() -> void:
	spawn_position = global_position
	_load_enemy_data()
	_pick_new_wander_target()
	hitbox.add_to_group("enemy_hitbox")
	
	# 플레이어 참조 찾기
	await get_tree().process_frame
	_find_player()


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_ref = players[0]
	else:
		# 그룹이 없으면 클래스로 찾기
		for node in get_tree().get_nodes_in_group(""):
			if node is Player:
				player_ref = node
				break


func _load_enemy_data() -> void:
	var data = DataManager.get_enemy(enemy_id)
	if data.is_empty():
		return
	
	var field_data = data.get("field", {})
	wander_range = float(field_data.get("wander_range", 48))
	move_speed = float(field_data.get("move_speed", 20))
	detect_range = float(field_data.get("detect_range", 60))
	chase_speed = float(field_data.get("chase_speed", 45))
	lose_range = float(field_data.get("lose_range", 90))
	
	var sprite_path = str(field_data.get("sprite", ""))
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)


func _physics_process(delta: float) -> void:
	if not is_active:
		return
	
	_update_chase_state()
	
	if is_chasing:
		_process_chase()
	else:
		_process_wander(delta)


func _update_chase_state() -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		is_chasing = false
		return
	
	var distance_to_player = global_position.distance_to(player_ref.global_position)
	
	if is_chasing:
		# 추적 중: 너무 멀어지면 포기
		if distance_to_player > lose_range:
			is_chasing = false
			_pick_new_wander_target()
	else:
		# 배회 중: 감지 범위 안에 들어오면 추적 시작
		if distance_to_player <= detect_range:
			is_chasing = true


func _process_chase() -> void:
	if player_ref == null:
		return
	
	var direction = global_position.direction_to(player_ref.global_position)
	velocity = direction * chase_speed
	
	_update_sprite_direction(direction)
	move_and_slide()


func _process_wander(delta: float) -> void:
	var distance_to_target = global_position.distance_to(wander_target)
	
	if distance_to_target < 8.0:
		wander_timer += delta
		velocity = Vector2.ZERO
		if wander_timer >= wander_wait_time:
			wander_timer = 0.0
			_pick_new_wander_target()
	else:
		var direction = global_position.direction_to(wander_target)
		var speed_mult = clampf(distance_to_target / 20.0, 0.3, 1.0)
		velocity = direction * move_speed * speed_mult
		
		# 속도가 충분할 때만 방향 업데이트, 더 큰 임계값
		if velocity.length() > 5.0 and absf(direction.x) > 0.5:
			_update_sprite_direction(direction)
	
	move_and_slide()


func _update_sprite_direction(direction: Vector2) -> void:
	if direction.x < -0.1:
		sprite.flip_h = true
	elif direction.x > 0.1:
		sprite.flip_h = false


func _pick_new_wander_target() -> void:
	var angle = randf() * TAU
	var distance = randf() * wander_range
	wander_target = spawn_position + Vector2(cos(angle), sin(angle)) * distance
	wander_wait_time = randf_range(1.0, 3.0)


func on_encountered() -> void:
	if not is_active:
		return
	
	is_active = false
	is_chasing = false
	visible = false
	collision.set_deferred("disabled", true)
	hitbox.set_deferred("monitoring", false)
	await get_tree().create_timer(0.5).timeout
	queue_free()


func setup(id: String, pos: Vector2) -> void:
	enemy_id = id
	global_position = pos
