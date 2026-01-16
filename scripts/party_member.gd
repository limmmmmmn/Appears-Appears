extends CharacterBody2D
class_name PartyMember
## 리더(또는 앞 파티원)를 따라다니는 동료

@export var hero_id: String = ""
@export var follow_distance: float = 20.0  # 앞 유닛과 유지할 거리
@export var move_speed: float = 85.0  # 플레이어보다 살짝 빠르게

var leader: Node2D = null  # 따라갈 대상
var is_active: bool = true

# 위치 기록 (스네이크 이동용)
var position_history: Array[Vector2] = []
const HISTORY_SIZE := 60  # 기록할 프레임 수

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	_load_hero_data()


func _load_hero_data() -> void:
	if hero_id.is_empty():
		return
	
	var data := DataManager.get_hero(hero_id)
	if data.is_empty():
		return
	
	# 스프라이트 로드
	var sprite_path: String = data.get("visuals", {}).get("sprite", "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)


func _physics_process(_delta: float) -> void:
	if not is_active or leader == null:
		return
	
	_follow_leader()


func _follow_leader() -> void:
	# 리더와의 거리 계산
	var distance := global_position.distance_to(leader.global_position)
	
	if distance > follow_distance:
		# 리더를 향해 이동
		var direction := global_position.direction_to(leader.global_position)
		velocity = direction * move_speed
		
		# 스프라이트 방향
		if direction.x < 0:
			sprite.flip_h = true
		elif direction.x > 0:
			sprite.flip_h = false
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()


func setup(id: String, follow_target: Node2D, distance: float = 20.0) -> void:
	hero_id = id
	leader = follow_target
	follow_distance = distance
	
	# 리더 뒤에 초기 위치
	global_position = follow_target.global_position - Vector2(distance, 0)
