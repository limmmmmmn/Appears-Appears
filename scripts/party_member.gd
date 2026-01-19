extends CharacterBody2D
class_name PartyMember
## 리더(또는 앞 파티원)를 따라다니는 동료
## 이동 시 살짝 벌어지고, 멈추면 다시 붙는 생동감 있는 움직임

@export var hero_id: String = ""
@export var base_distance: float = 22.0  # 기본 간격 (정지 시)
@export var max_gap: float = 5.0  # 이동 시 추가로 벌어지는 최대 간격
@export var move_speed: float = 90.0  # 플레이어보다 살짝 빠르게
@export var catch_up_speed: float = 120.0  # 붙을 때 더 빠르게

var leader: Node2D = null  # 따라갈 대상
var is_active: bool = true
var is_dead: bool = false  # 사망 상태

# 상태 감지용
var leader_was_moving: bool = false
var settle_timer: float = 0.0  # 정지 후 붙기 시작까지 딜레이
const SETTLE_DELAY: float = 0.08  # 멈춘 후 붙기 시작하는 딜레이

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_load_hero_data()
	
	# 사망 시그널 연결
	GameManager.hero_died.connect(_on_hero_died)
	
	# 혹시 이미 죽어있으면 바로 적용
	if not GameManager.is_hero_alive(hero_id):
		_apply_dead_visual()


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
	
	# 죽어도 따라다니긴 함 (드러누운 채로)
	_follow_leader(delta)


func _follow_leader(delta: float) -> void:
	var distance := global_position.distance_to(leader.global_position)
	var leader_moving := _is_leader_moving()
	
	# 리더가 움직이는지에 따라 목표 간격 결정
	var target_distance: float
	var current_speed: float
	
	if leader_moving:
		# 이동 중: 벌어진 간격 유지 (base + max_gap)
		target_distance = base_distance + max_gap
		current_speed = move_speed
		settle_timer = 0.0
		leader_was_moving = true
	else:
		# 정지 상태
		if leader_was_moving:
			# 방금 멈춤 -> 딜레이 시작
			settle_timer += delta
			if settle_timer < SETTLE_DELAY:
				# 아직 딜레이 중, 현재 간격 유지
				target_distance = base_distance + max_gap
				current_speed = move_speed
			else:
				# 딜레이 끝, 붙기 시작
				target_distance = base_distance
				current_speed = catch_up_speed
				if distance <= base_distance + 1.0:
					leader_was_moving = false
		else:
			# 완전 정지 상태, 딱 붙어있기
			target_distance = base_distance
			current_speed = catch_up_speed
	
	# 이동 처리
	if distance > target_distance + 0.5:
		# 너무 멀면 따라가기
		var direction := global_position.direction_to(leader.global_position)
		velocity = direction * current_speed
		if not is_dead:  # 죽으면 방향 안 바꿈
			_update_sprite_direction(direction)
	elif distance < target_distance - 0.5 and not leader_moving:
		# 너무 가까우면 살짝 뒤로 (정지 시에만)
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
	
	# 죽은 상태에서 플립이 바뀌면 회전 방향도 바꿔야 함
	if is_dead and old_flip != sprite.flip_h:
		var target_rotation = -90.0 if not sprite.flip_h else 90.0
		sprite.rotation_degrees = target_rotation


func _on_hero_died(dead_hero_id: String) -> void:
	if dead_hero_id == hero_id:
		_apply_dead_visual()


func _apply_dead_visual() -> void:
	## 사망 비주얼: 흑백 + 90도 회전 (하늘 보고 누움)
	## 스프라이트가 왼쪽 보고 있으므로 -90도 회전 = 하늘 보기
	if is_dead:
		return
	
	is_dead = true
	
	# 애니메이션으로 쓰러지기
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	# 동시에: 흑백 + 회전
	tween.set_parallel(true)
	
	# 흑백 처리 (saturation 0으로)
	tween.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5, 1.0), 0.3)
	
	# -90도 회전 (반시계 방향 = 하늘 보고 누움)
	# flip_h 상태에 따라 회전 방향 조정
	var target_rotation = -90.0 if not sprite.flip_h else 90.0
	tween.tween_property(sprite, "rotation_degrees", target_rotation, 0.3)


func revive() -> void:
	## 부활 시 원래대로
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
	
	# 리더 바로 뒤에서 시작
	global_position = follow_target.global_position
