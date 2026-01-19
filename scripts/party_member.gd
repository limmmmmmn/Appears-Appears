extends CharacterBody2D
class_name PartyMember
## 리더(또는 앞 파티원)를 따라다니는 동료
## 이동 시 살짝 벌어지고, 멈추면 다시 붙는 생동감 있는 움직임

@export var hero_id: String = ""
@export var base_distance: float = 22.0
@export var max_gap: float = 5.0
@export var move_speed: float = 90.0
@export var catch_up_speed: float = 120.0

var leader: Node2D = null
var is_active: bool = true
var is_dead: bool = false

var leader_was_moving: bool = false
var settle_timer: float = 0.0
const SETTLE_DELAY: float = 0.08

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_load_hero_data()
	
	# 사망 시그널 연결
	GameManager.hero_died.connect(_on_hero_died)
	
	# 혹시 이미 죽어있으면 바로 적용 (애니메이션 없이)
	if not hero_id.is_empty() and not GameManager.is_hero_alive(hero_id):
		_apply_dead_visual_instant()


func _load_hero_data() -> void:
	if hero_id.is_empty():
		return
	
	var data := DataManager.get_hero(hero_id)
	if data.is_empty():
		return
	
	var sprite_path: String = data.get("visuals", {}).get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	
	sprite.flip_h = false


func _physics_process(delta: float) -> void:
	if not is_active or leader == null:
		return
	
	_follow_leader(delta)


func _follow_leader(delta: float) -> void:
	var distance := global_position.distance_to(leader.global_position)
	var leader_moving := _is_leader_moving()
	
	var target_distance: float
	var current_speed: float
	
	if leader_moving:
		target_distance = base_distance + max_gap
		current_speed = move_speed
		settle_timer = 0.0
		leader_was_moving = true
	else:
		if leader_was_moving:
			settle_timer += delta
			if settle_timer < SETTLE_DELAY:
				target_distance = base_distance + max_gap
				current_speed = move_speed
			else:
				target_distance = base_distance
				current_speed = catch_up_speed
				if distance <= base_distance + 1.0:
					leader_was_moving = false
		else:
			target_distance = base_distance
			current_speed = catch_up_speed
	
	if distance > target_distance + 0.5:
		var direction := global_position.direction_to(leader.global_position)
		velocity = direction * current_speed
		_update_sprite_direction(direction)
	elif distance < target_distance - 0.5 and not leader_moving:
		var direction := leader.global_position.direction_to(global_position)
		velocity = direction * (current_speed * 0.5)
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()


func _is_leader_moving() -> bool:
	if leader is CharacterBody2D:
		return leader.velocity.length() > 5.0
	elif leader.has_method("get_velocity"):
		return leader.get_velocity().length() > 5.0
	return false


func _update_sprite_direction(direction: Vector2) -> void:
	var old_flip = sprite.flip_h
	
	if direction.x > 0.1:
		sprite.flip_h = true
	elif direction.x < -0.1:
		sprite.flip_h = false
	
	# 죽은 상태에서 플립이 바뀌면 회전 방향도 업데이트
	if is_dead and old_flip != sprite.flip_h:
		_update_dead_rotation()


func _on_hero_died(dead_hero_id: String) -> void:
	if dead_hero_id == hero_id:
		_apply_dead_visual()


func _apply_dead_visual() -> void:
	## 사망 비주얼: 흑백 + 회전 (하늘 보고 누움)
	if is_dead:
		return
	
	is_dead = true
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	
	tween.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5, 1.0), 0.3)
	
	# flip_h = false (왼쪽 봄) → 90도 = 하늘 보기
	# flip_h = true (오른쪽 봄) → -90도 = 하늘 보기
	var target_rotation = 90.0 if not sprite.flip_h else -90.0
	tween.tween_property(sprite, "rotation_degrees", target_rotation, 0.3)


func _apply_dead_visual_instant() -> void:
	## 즉시 사망 비주얼 (애니메이션 없이)
	is_dead = true
	sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)
	_update_dead_rotation()


func _update_dead_rotation() -> void:
	# flip_h = false (왼쪽 봄) → 90도 (시계방향) = 하늘 보기
	# flip_h = true (오른쪽 봄) → -90도 (반시계방향) = 하늘 보기
	var target_rotation = 90.0 if not sprite.flip_h else -90.0
	sprite.rotation_degrees = target_rotation


func revive() -> void:
	if not is_dead:
		return
	
	is_dead = false
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	tween.tween_property(sprite, "rotation_degrees", 0.0, 0.3)


func setup(id: String, follow_target: Node2D, distance: float = 22.0) -> void:
	hero_id = id
	leader = follow_target
	base_distance = distance
	global_position = follow_target.global_position
