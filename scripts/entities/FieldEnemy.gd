extends CharacterBody2D
class_name FieldEnemy
## 필드 에너미: 배회 → 감지 → 추적 → 접촉(전투)

signal player_contacted(field_enemy: FieldEnemy)

enum State { IDLE, WANDER, ALERT, CHASE, SPECTATE }

@export var enemy_id: String = "slime"
@export var tile_type: String = "grass"
@export var is_elite: bool = false  # 엘리트 몹 여부
@export var is_boss: bool = false   # 보스 여부

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
var is_despawning: bool = false  # 사라지는 중

# 관전 모드
var is_spectating: bool = false
var spectate_target_pos: Vector2 = Vector2.ZERO
var pre_spectate_state: State = State.IDLE
var spectate_speed: float = 80.0

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
	
	# DEX 기반 이동속도
	var dex: int = int(data.get("stats", {}).get("dex", 5))
	chase_speed = 35.0 + dex * 1.5
	wander_speed = chase_speed * 0.4
	
	# SpriteManager에서 스프라이트 로드
	if SpriteManager:
		var tex: Texture2D = SpriteManager.get_enemy_sprite(enemy_id)
		if tex:
			sprite.texture = tex
			sprite.scale = Vector2(1, 1)
	
	# 이름 라벨 (크기는 동일, 색상만 변경)
	if name_label:
		var enemy_name: String = str(data.get("name", enemy_id))
		if is_boss:
			name_label.text = "👑 " + enemy_name
			name_label.add_theme_color_override("font_color", Color.ORANGE_RED)
		elif is_elite:
			name_label.text = "⭐ " + enemy_name
			name_label.add_theme_color_override("font_color", Color.PURPLE)
		else:
			name_label.text = enemy_name
	
	# 느낌표 아이콘
	if alert_icon and SpriteManager:
		var alert_tex: Texture2D = SpriteManager.get_alert_icon()
		if alert_tex:
			# Label 대신 텍스처 사용
			var alert_sprite: Sprite2D = alert_icon
			alert_sprite.texture = alert_tex


func _physics_process(delta: float) -> void:
	# 사라지는 중에는 이동 정지
	if is_despawning:
		velocity = Vector2.ZERO
		return

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.ALERT:
			pass
		State.CHASE:
			_process_chase(delta)
		State.SPECTATE:
			_process_spectate(delta)


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


func setup(p_enemy_id: String, p_tile_type: String, pos: Vector2, p_is_elite: bool = false) -> void:
	enemy_id = p_enemy_id
	tile_type = p_tile_type
	is_elite = p_is_elite
	global_position = pos
	call_deferred("_setup_from_data")


func despawn() -> void:
	## 적 사라짐 (전투 진입)
	is_despawning = true
	velocity = Vector2.ZERO
	queue_free()


func brief_pause(duration: float = 0.3) -> void:
	## 잠깐 멈칫하는 효과 (전투 시작 시)
	var prev_state := current_state
	velocity = Vector2.ZERO
	current_state = State.IDLE

	await get_tree().create_timer(duration).timeout

	if is_instance_valid(self) and not is_despawning:
		current_state = prev_state


func freeze_and_despawn(duration: float = 0.5) -> void:
	## 제자리에 멈추고 일정 시간 후 사라짐
	is_despawning = true
	velocity = Vector2.ZERO
	current_state = State.IDLE

	# 느낌표 아이콘 숨김
	if alert_icon:
		alert_icon.visible = false

	await get_tree().create_timer(duration).timeout

	if is_instance_valid(self):
		queue_free()


#region 관전 시스템
func _process_spectate(_delta: float) -> void:
	## 관전 위치로 이동
	if not is_spectating:
		return

	var distance := global_position.distance_to(spectate_target_pos)
	if distance < 5.0:
		velocity = Vector2.ZERO
		return

	var direction := (spectate_target_pos - global_position).normalized()
	velocity = direction * spectate_speed
	move_and_slide()
	_update_sprite_direction(direction.x)


func start_spectating(camera_rect: Rect2) -> void:
	## 보스전 관전 시작 - 카메라 가장자리로 이동
	if is_boss:
		return  # 보스는 관전하지 않음

	is_spectating = true
	pre_spectate_state = current_state

	# 화면 가장자리 중 가장 가까운 곳으로 이동
	spectate_target_pos = _find_spectate_position(camera_rect)
	_set_state(State.SPECTATE)

	# 느낌표 숨김
	if alert_icon:
		alert_icon.visible = false


func stop_spectating() -> void:
	## 관전 종료 - 원래 행동으로 복귀
	if not is_spectating:
		return

	is_spectating = false
	_set_state(State.IDLE)


func _find_spectate_position(camera_rect: Rect2) -> Vector2:
	## 카메라 가장자리 중 가장 가까운 위치 계산
	var my_pos := global_position
	var edge_margin: float = 20.0

	# 4개 가장자리 중 가장 가까운 곳 계산
	var left_edge := Vector2(camera_rect.position.x + edge_margin, my_pos.y)
	var right_edge := Vector2(camera_rect.end.x - edge_margin, my_pos.y)
	var top_edge := Vector2(my_pos.x, camera_rect.position.y + edge_margin)
	var bottom_edge := Vector2(my_pos.x, camera_rect.end.y - edge_margin)

	# Y 위치 제한 (화면 안에 있도록)
	left_edge.y = clampf(left_edge.y, camera_rect.position.y + edge_margin, camera_rect.end.y - edge_margin)
	right_edge.y = clampf(right_edge.y, camera_rect.position.y + edge_margin, camera_rect.end.y - edge_margin)
	top_edge.x = clampf(top_edge.x, camera_rect.position.x + edge_margin, camera_rect.end.x - edge_margin)
	bottom_edge.x = clampf(bottom_edge.x, camera_rect.position.x + edge_margin, camera_rect.end.x - edge_margin)

	var edges: Array[Vector2] = [left_edge, right_edge, top_edge, bottom_edge]
	var closest := edges[0]
	var closest_dist := my_pos.distance_to(closest)

	for edge in edges:
		var dist := my_pos.distance_to(edge)
		if dist < closest_dist:
			closest = edge
			closest_dist = dist

	# 약간의 랜덤 오프셋 추가 (겹치지 않도록)
	closest += Vector2(randf_range(-15, 15), randf_range(-15, 15))

	return closest
#endregion
