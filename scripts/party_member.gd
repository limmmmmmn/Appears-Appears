extends CharacterBody2D
class_name PartyMember
## 리더(또는 앞 파티원)를 따라다니는 동료
## 이동 시 살짝 벌어지고, 멈추면 다시 붙는 생동감 있는 움직임

@export var hero_id: String = ""
@export var base_distance: float = 20.0  # 기본 간격 (정지 시)
@export var max_gap: float = 12.0  # 이동 시 추가로 벌어지는 최대 간격
@export var move_speed: float = 80.0  # 플레이어보다 살짝 빠르게
@export var catch_up_speed: float = 50.0  # 붙을 때 더 빠르게

var leader: Node2D = null  # 따라갈 대상
var is_active: bool = true

# 상태 감지용
var leader_was_moving: bool = false
var settle_timer: float = 0.0  # 정지 후 붙기 시작까지 딜레이
const SETTLE_DELAY: float = 0.0  # 멈춘 후 붙기 시작하는 딜레이

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_load_hero_data()


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
	if direction.x > 0.1:
		sprite.flip_h = true
	elif direction.x < -0.1:
		sprite.flip_h = false


func setup(id: String, follow_target: Node2D, distance: float = 22.0) -> void:
	hero_id = id
	leader = follow_target
	base_distance = distance
	
	# 리더 바로 뒤에서 시작
	global_position = follow_target.global_position
