extends Character
class_name FieldEnemy
## FieldEnemy.gd
## 필드의 적 - 이동, 플레이어 추적, 접촉시 전투 발생

# ===== 적 정보 =====
var enemy_id: String = ""
var enemy_data: Dictionary = {}

# ===== AI 상태 =====
enum AIState { IDLE, WANDER, CHASE, RETURN }
var ai_state: AIState = AIState.WANDER

# ===== 이동 설정 =====
const WANDER_SPEED = 30.0
const CHASE_SPEED = 50.0
const DETECTION_RANGE = 80.0  # 플레이어 감지 범위
const CHASE_RANGE = 120.0  # 추적 포기 거리
const WANDER_CHANGE_TIME = 2.0  # 방향 전환 시간

# ===== 타이머 =====
var wander_timer: float = 0.0
var wander_direction: Vector2 = Vector2.ZERO

# ===== 시작 위치 =====
var spawn_position: Vector2 = Vector2.ZERO
const MAX_WANDER_DISTANCE = 100.0  # 스폰 지점에서 최대 거리

# ===== 플레이어 참조 =====
var player: Player = null

# ===== 상태 =====
var is_active: bool = true

# ===== 시그널 =====
signal player_touched(enemy_data: Dictionary)


func _setup_character() -> void:
	move_speed = WANDER_SPEED
	add_to_group("field_enemy")


func _ready() -> void:
	super._ready()
	spawn_position = global_position
	_randomize_wander_direction()
	
	# 플레이어 찾기
	await get_tree().process_frame
	_find_player()


func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as Player


func _physics_process(delta: float) -> void:
	if not is_active or is_in_battle:
		return
	
	if player == null:
		_find_player()
		return
	
	_update_ai_state()
	_process_ai(delta)
	super._physics_process(delta)


# ===== AI 상태 업데이트 =====
func _update_ai_state() -> void:
	if player == null or not player.is_alive:
		ai_state = AIState.WANDER
		return
	
	var distance_to_player = global_position.distance_to(player.global_position)
	var distance_to_spawn = global_position.distance_to(spawn_position)
	
	match ai_state:
		AIState.IDLE:
			if distance_to_player < DETECTION_RANGE:
				ai_state = AIState.CHASE
			else:
				ai_state = AIState.WANDER
		
		AIState.WANDER:
			if distance_to_player < DETECTION_RANGE:
				ai_state = AIState.CHASE
			elif distance_to_spawn > MAX_WANDER_DISTANCE:
				ai_state = AIState.RETURN
		
		AIState.CHASE:
			if distance_to_player > CHASE_RANGE:
				ai_state = AIState.RETURN
		
		AIState.RETURN:
			if distance_to_player < DETECTION_RANGE:
				ai_state = AIState.CHASE
			elif distance_to_spawn < 10.0:
				ai_state = AIState.WANDER


# ===== AI 처리 =====
func _process_ai(delta: float) -> void:
	match ai_state:
		AIState.IDLE:
			_process_idle(delta)
		AIState.WANDER:
			_process_wander(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.RETURN:
			_process_return(delta)


func _process_idle(delta: float) -> void:
	set_move_direction(Vector2.ZERO)


func _process_wander(delta: float) -> void:
	move_speed = WANDER_SPEED
	
	wander_timer -= delta
	if wander_timer <= 0:
		_randomize_wander_direction()
	
	set_move_direction(wander_direction)


func _process_chase(delta: float) -> void:
	move_speed = CHASE_SPEED
	
	if player == null:
		return
	
	var direction = (player.global_position - global_position).normalized()
	set_move_direction(direction)


func _process_return(delta: float) -> void:
	move_speed = WANDER_SPEED
	
	var direction = (spawn_position - global_position).normalized()
	set_move_direction(direction)


func _randomize_wander_direction() -> void:
	wander_timer = WANDER_CHANGE_TIME + randf() * WANDER_CHANGE_TIME
	
	# 랜덤 방향 또는 멈춤
	if randf() < 0.3:  # 30% 확률로 멈춤
		wander_direction = Vector2.ZERO
	else:
		var angle = randf() * TAU
		wander_direction = Vector2(cos(angle), sin(angle))


# ===== 적 초기화 =====
func init_enemy(id: String) -> void:
	enemy_id = id
	enemy_data = DataManager.get_enemy(id)
	
	if enemy_data.is_empty():
		push_error("Enemy data not found: " + id)
		return
	
	char_id = id
	char_name = enemy_data.get("name", "Enemy")
	
	var stats = enemy_data.get("stats", {})
	level = stats.get("level", 1)
	max_hp = stats.get("max_hp", 30)
	current_hp = max_hp
	attack = stats.get("attack", 5)
	defense = stats.get("defense", 2)
	magic = stats.get("magic", 3)
	magic_defense = stats.get("magic_defense", 3)
	speed = stats.get("speed", 5)
	critical = stats.get("critical", 1.0)
	evasion = stats.get("evasion", 2.0)
	
	# 스프라이트 로드
	_load_enemy_sprite()


func get_enemy_data() -> Dictionary:
	var data = enemy_data.duplicate(true)
	data["id"] = enemy_id
	data["current_hp"] = current_hp
	return data


func _load_enemy_sprite() -> void:
	if sprite == null:
		await ready
	
	var sprite_file = enemy_data.get("sprite", "")
	
	if sprite_file != "":
		load_sprite(sprite_file, "enemies")


# ===== 충돌 처리 =====
func _on_body_entered(body: Node2D) -> void:
	if body is Player and is_active:
		_trigger_battle()


func _trigger_battle() -> void:
	if not is_active:
		return
	
	is_active = false
	stop_movement()
	
	# 전투 시작 이벤트 발생
	var battle_data = get_enemy_data()
	player_touched.emit(battle_data)
	EventBus.enemy_touched.emit(battle_data)


# ===== 전투 후 처리 =====
func on_battle_victory() -> void:
	# 적 제거
	queue_free()


func on_battle_escape() -> void:
	# 도주 성공 시 일정 시간 후 다시 활성화
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(self):
		is_active = true
		ai_state = AIState.RETURN


# ===== 활성화/비활성화 =====
func set_active(active: bool) -> void:
	is_active = active
	if not active:
		stop_movement()


func deactivate() -> void:
	is_active = false
	visible = false
	set_physics_process(false)


func activate() -> void:
	is_active = true
	visible = true
	set_physics_process(true)
