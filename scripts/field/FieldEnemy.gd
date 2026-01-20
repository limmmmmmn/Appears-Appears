extends CharacterBody2D
class_name FieldEnemy
## 필드 에너미: 배회 → 감지 → 추적 → 접촉(전투)

signal player_contacted(field_enemy: FieldEnemy)

enum State { IDLE, WANDER, ALERT, CHASE }

@export var enemy_id: String = "slime"
@export var tile_type: String = "grass"

@export_group("Movement")
@export var wander_speed: float = 25.0
@export var chase_speed: float = 50.0
@export var detection_range: float = 60.0
@export var lose_range: float = 120.0

@export_group("Wander")
@export var wander_interval_min: float = 1.5
@export var wander_interval_max: float = 3.5
@export var wander_distance: float = 40.0

var current_state: State = State.IDLE
var target_player: Node2D = null
var wander_target: Vector2 = Vector2.ZERO
var wander_timer: float = 0.0
var is_contacted: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var alert_icon: Sprite2D = $AlertIcon
@onready var detection_area: Area2D = $DetectionArea
@onready var contact_area: Area2D = $ContactArea
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	_setup_from_data()
	_set_state(State.IDLE)
	
	if detection_area.has_node("CollisionShape2D"):
		var shape = detection_area.get_node("CollisionShape2D").shape
		if shape is CircleShape2D:
			shape.radius = detection_range
	
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)
	contact_area.body_entered.connect(_on_contact_body_entered)


func _setup_from_data() -> void:
	var data: Dictionary = DataManager.get_enemy(enemy_id)
	if data.is_empty():
		return
	
	# 스피드 기반 이동속도
	var spd: int = int(data.get("base_stats", {}).get("spd", 5))
	chase_speed = 35.0 + spd * 1.5
	wander_speed = chase_speed * 0.4
	
	# SpriteManager에서 스프라이트 로드
	if SpriteManager:
		var tex: Texture2D = SpriteManager.get_enemy_sprite(enemy_id)
		if tex:
			sprite.texture = tex
			sprite.scale = Vector2(1, 1)
	
	# 이름 라벨
	if name_label:
		name_label.text = str(data.get("name", enemy_id))
	
	# 느낌표 아이콘
	if alert_icon and SpriteManager:
		var alert_tex: Texture2D = SpriteManager.get_alert_icon()
		if alert_tex:
			# Label 대신 텍스처 사용
			var alert_sprite: Sprite2D = alert_icon
			alert_sprite.texture = alert_tex


func _physics_process(delta: float) -> void:
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.ALERT:
			pass
		State.CHASE:
			_process_chase(delta)


func _process_idle(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0:
		_start_wander()


func _process_wander(delta: float) -> void:
	var direction := (wander_target - global_position).normalized()
	velocity = direction * wander_speed
	move_and_slide()
	_update_sprite_direction(direction.x)
	
	if global_position.distance_to(wander_target) < 8.0:
		_set_state(State.IDLE)


func _process_chase(delta: float) -> void:
	if not is_instance_valid(target_player):
		_set_state(State.IDLE)
		return
	
	var distance := global_position.distance_to(target_player.global_position)
	
	if distance > lose_range:
		target_player = null
		_set_state(State.IDLE)
		return
	
	var direction := (target_player.global_position - global_position).normalized()
	velocity = direction * chase_speed
	move_and_slide()
	_update_sprite_direction(direction.x)


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
			get_tree().create_timer(0.4).timeout.connect(_on_alert_finished)
		State.CHASE:
			alert_icon.visible = true


func _start_wander() -> void:
	var angle := randf() * TAU
	wander_target = global_position + Vector2(cos(angle), sin(angle)) * wander_distance
	_set_state(State.WANDER)


func _on_alert_finished() -> void:
	if current_state == State.ALERT:
		_set_state(State.CHASE)


func _on_detection_body_entered(body: Node2D) -> void:
	if body.is_in_group("party_leader") and current_state != State.CHASE:
		target_player = body
		_set_state(State.ALERT)


func _on_detection_body_exited(body: Node2D) -> void:
	pass


func _on_contact_body_entered(body: Node2D) -> void:
	if is_contacted:
		return
	if body.is_in_group("party_leader") or body.is_in_group("party"):
		is_contacted = true
		player_contacted.emit(self)


func _update_sprite_direction(x_direction: float) -> void:
	if x_direction > 0.1:
		sprite.flip_h = true
	elif x_direction < -0.1:
		sprite.flip_h = false


func setup(p_enemy_id: String, p_tile_type: String, pos: Vector2) -> void:
	enemy_id = p_enemy_id
	tile_type = p_tile_type
	global_position = pos
	call_deferred("_setup_from_data")


func despawn() -> void:
	queue_free()
