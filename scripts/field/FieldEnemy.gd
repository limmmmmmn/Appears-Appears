extends CharacterBody2D
class_name FieldEnemy
## 필드 에너미: 배회 → 감지 → 추적 → 접촉(전투)

signal player_contacted(field_enemy: FieldEnemy)

enum State { IDLE, WANDER, ALERT, CHASE }

@export var enemy_id: String = "slime"
@export var tile_type: String = "grass"  # 스폰된 타일 타입 (전투 생성에 사용)

@export_group("Movement")
@export var wander_speed: float = 20.0
@export var chase_speed: float = 40.0
@export var detection_range: float = 48.0  # 3타일 정도
@export var lose_range: float = 80.0  # 5타일 - 이 이상 멀어지면 추적 포기

@export_group("Wander")
@export var wander_interval_min: float = 2.0
@export var wander_interval_max: float = 4.0
@export var wander_distance: float = 32.0

var current_state: State = State.IDLE
var target_player: Node2D = null
var wander_target: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var alert_icon: Sprite2D = $AlertIcon  # 느낌표 아이콘
@onready var detection_area: Area2D = $DetectionArea
@onready var contact_area: Area2D = $ContactArea


func _ready() -> void:
	_setup_from_data()
	_set_state(State.IDLE)
	
	# 감지 범위 설정
	var detection_shape: CircleShape2D = detection_area.get_node("CollisionShape2D").shape
	detection_shape.radius = detection_range
	
	# 시그널 연결
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	contact_area.body_entered.connect(_on_contact_body_entered)


func _setup_from_data() -> void:
	var data: Dictionary = DataManager.get_enemy(enemy_id)
	if data.is_empty():
		push_warning("[FieldEnemy] 데이터 없음: " + enemy_id)
		return
	
	# 스프라이트 설정 (나중에 실제 스프라이트로 교체)
	# sprite.texture = load("res://assets/enemies/" + data.get("sprite", "default") + ".png")
	
	# SPD에 따른 속도 조정
	var spd: int = data.get("base_stats", {}).get("spd", 5)
	chase_speed = 30.0 + spd * 2.0  # 기본 30 + SPD 보너스
	wander_speed = chase_speed * 0.5


func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.ALERT:
			_process_alert(delta)
		State.CHASE:
			_process_chase(delta)


#region State Processing
func _process_idle(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0:
		_start_wander()


func _process_wander(delta: float) -> void:
	var direction := (wander_target - global_position).normalized()
	velocity = direction * wander_speed
	move_and_slide()
	
	_update_sprite_direction(direction.x)
	
	# 목표 도달 체크
	if global_position.distance_to(wander_target) < 4.0:
		_set_state(State.IDLE)


func _process_alert(delta: float) -> void:
	# 잠깐 멈추고 느낌표 표시 후 추적 시작
	# AlertIcon 애니메이션 끝나면 CHASE로 전환
	pass


func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player):
		_set_state(State.IDLE)
		return
	
	var distance := global_position.distance_to(target_player.global_position)
	
	# 추적 포기
	if distance > lose_range:
		target_player = null
		_set_state(State.IDLE)
		return
	
	# 추적
	var direction := (target_player.global_position - global_position).normalized()
	velocity = direction * chase_speed
	move_and_slide()
	
	_update_sprite_direction(direction.x)
#endregion


#region State Management
func _set_state(new_state: State) -> void:
	current_state = new_state
	
	match new_state:
		State.IDLE:
			velocity = Vector2.ZERO
			alert_icon.visible = false
			wander_timer = randf_range(wander_interval_min, wander_interval_max)
		
		State.WANDER:
			alert_icon.visible = false
		
		State.ALERT:
			velocity = Vector2.ZERO
			alert_icon.visible = true
			# 0.5초 후 추적 시작
			get_tree().create_timer(0.5).timeout.connect(_on_alert_finished)
		
		State.CHASE:
			alert_icon.visible = true


func _start_wander() -> void:
	var angle := randf() * TAU
	wander_target = global_position + Vector2(cos(angle), sin(angle)) * wander_distance
	_set_state(State.WANDER)


func _on_alert_finished() -> void:
	if current_state == State.ALERT:
		_set_state(State.CHASE)
#endregion


#region Detection & Contact
func _on_detection_body_entered(body: Node2D) -> void:
	if body.is_in_group("party_leader") and current_state != State.CHASE:
		target_player = body
		_set_state(State.ALERT)


func _on_detection_body_exited(body: Node2D) -> void:
	if body == target_player and current_state == State.CHASE:
		# lose_range 체크는 _process_chase에서 처리
		pass


func _on_contact_body_entered(body: Node2D) -> void:
	if body.is_in_group("party_leader"):
		# 전투 시작!
		player_contacted.emit(self)
#endregion


#region Visual
func _update_sprite_direction(x_direction: float) -> void:
	# 스프라이트가 왼쪽을 보고 있으므로
	# 오른쪽으로 이동 시 flip
	if x_direction > 0.1:
		sprite.flip_h = true
	elif x_direction < -0.1:
		sprite.flip_h = false
#endregion


#region Public Methods
func setup(p_enemy_id: String, p_tile_type: String, pos: Vector2) -> void:
	enemy_id = p_enemy_id
	tile_type = p_tile_type
	global_position = pos
	_setup_from_data()


func despawn() -> void:
	## 전투 후 또는 도주 시 필드에서 제거
	queue_free()
#endregion
