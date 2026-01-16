extends Character
class_name PartyMember
## PartyMember.gd
## 파티원 캐릭터 - 플레이어 뒤따라 이동

# ===== 파티 정보 =====
var leader: Player = null
var party_index: int = 0  # 파티 내 순서 (1, 2, 3)

# ===== 따라가기 설정 =====
const FOLLOW_SPEED_MULTIPLIER = 1.2  # 약간 빠르게 따라감
const MIN_DISTANCE = 8.0  # 이 거리 이내면 이동 안 함
const SMOOTH_FACTOR = 8.0  # 부드러운 이동 계수

# ===== 목표 위치 =====
var target_position: Vector2 = Vector2.ZERO
var is_following: bool = false


func _setup_character() -> void:
	move_speed = 80.0 * FOLLOW_SPEED_MULTIPLIER
	add_to_group("party_member")


func _physics_process(delta: float) -> void:
	if is_in_battle or leader == null:
		return
	
	if is_following:
		_follow_movement(delta)


func _follow_movement(delta: float) -> void:
	var distance = global_position.distance_to(target_position)
	
	if distance < MIN_DISTANCE:
		stop_movement()
		return
	
	# 방향 계산
	var direction = (target_position - global_position).normalized()
	
	# 부드러운 이동
	velocity = direction * move_speed
	move_and_slide()
	
	# 방향에 따라 스프라이트 플립
	_update_facing_to_target(direction)
	is_moving = true


func _update_facing_to_target(direction: Vector2) -> void:
	if sprite == null:
		return
	
	# 기본 스프라이트가 왼쪽을 봄
	if direction.x > 0.1:
		sprite.flip_h = true
		facing_left = false
	elif direction.x < -0.1:
		sprite.flip_h = false
		facing_left = true


# ===== 리더 설정 =====
func set_leader(new_leader: Player) -> void:
	leader = new_leader


func set_party_index(index: int) -> void:
	party_index = index


# ===== 따라가기 =====
func follow_to(pos: Vector2) -> void:
	target_position = pos
	is_following = true


func stop_following() -> void:
	is_following = false
	stop_movement()


# ===== 캐릭터 초기화 =====
func init_as_character(char_id_param: String) -> void:
	var char_data = DataManager.get_character(char_id_param)
	if char_data:
		char_data["id"] = char_id_param
		init_from_data(char_data)


# ===== 전투 진입/종료 =====
func enter_battle() -> void:
	is_in_battle = true
	is_following = false
	stop_movement()


func exit_battle() -> void:
	is_in_battle = false
	is_following = true


# ===== 경험치/레벨업 =====
func gain_exp(amount: int) -> void:
	# 파티원도 경험치 획득
	var char_data = DataManager.get_character(char_id)
	if char_data == null:
		return
	
	var exp_to_next = DataManager.calculate_exp_for_level(level + 1)
	var total_exp = amount
	
	while total_exp >= exp_to_next:
		total_exp -= exp_to_next
		_level_up_member()
		exp_to_next = DataManager.calculate_exp_for_level(level + 1)


func _level_up_member() -> void:
	level += 1
	
	var char_data = DataManager.get_character(char_id)
	if char_data and char_data.has("growth_per_level"):
		var growth = char_data["growth_per_level"]
		max_hp += int(growth.get("max_hp", 8))
		max_mp += int(growth.get("max_mp", 5))
		attack += int(growth.get("attack", 1))
		defense += int(growth.get("defense", 1))
		magic += int(growth.get("magic", 1))
		magic_defense += int(growth.get("magic_defense", 1))
		speed += int(growth.get("speed", 0.5))
		critical += growth.get("critical", 0.3)
		evasion += growth.get("evasion", 0.2)
	
	current_hp = max_hp
	current_mp = max_mp
	
	EventBus.party_level_up.emit(party_index, level)
