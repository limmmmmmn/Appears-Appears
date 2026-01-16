extends Character
class_name Player
## Player.gd
## 플레이어 캐릭터 - 파티 리더, 입력 처리, 파티원 관리

# ===== 파티원 =====
var party_members: Array[PartyMember] = []
const MAX_PARTY_SIZE = 4  # 리더 포함

# ===== 파티원 따라오기 설정 =====
const FOLLOW_DISTANCE = 18.0  # 파티원 간 거리
const POSITION_HISTORY_SIZE = 60  # 위치 히스토리 크기

# ===== 위치 히스토리 (파티원 따라오기용) =====
var position_history: Array[Vector2] = []

# ===== 경험치 =====
var current_exp: int = 0
var exp_to_next_level: int = 100

# ===== 상태 =====
var can_move: bool = true

# ===== 시그널 =====
signal exp_gained(amount: int, total: int)
signal level_up(new_level: int)
signal party_member_added(member: PartyMember)
signal party_member_removed(index: int)


func _setup_character() -> void:
	# 기본 Hero 데이터 로드
	var hero_data = DataManager.get_character("hero")
	if hero_data:
		hero_data["id"] = "hero"
		init_from_data(hero_data)
	
	move_speed = 80.0
	add_to_group("player")


func _ready() -> void:
	super._ready()
	# 위치 히스토리 초기화
	for i in range(POSITION_HISTORY_SIZE):
		position_history.append(global_position)


func _physics_process(delta: float) -> void:
	if not can_move or is_in_battle:
		_stop_all_movement()
		return
	
	_handle_input()
	super._physics_process(delta)
	
	# 위치 히스토리 업데이트 (이동 중일 때만)
	if is_moving:
		_update_position_history()
		_update_party_members_position()


func _handle_input() -> void:
	var input_dir = Vector2.ZERO
	
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1
	
	set_move_direction(input_dir)


func _stop_all_movement() -> void:
	stop_movement()
	for member in party_members:
		member.stop_movement()


func _update_position_history() -> void:
	# 새 위치 추가
	position_history.push_front(global_position)
	
	# 오래된 위치 제거
	if position_history.size() > POSITION_HISTORY_SIZE:
		position_history.pop_back()


func _update_party_members_position() -> void:
	for i in range(party_members.size()):
		var member = party_members[i]
		var history_index = (i + 1) * int(FOLLOW_DISTANCE / 2)
		
		if history_index < position_history.size():
			var target_pos = position_history[history_index]
			member.follow_to(target_pos)


# ===== 파티원 관리 =====
func add_party_member(member: PartyMember) -> bool:
	if party_members.size() >= MAX_PARTY_SIZE - 1:  # 리더 제외 3명까지
		return false
	
	party_members.append(member)
	member.set_leader(self)
	member.set_party_index(party_members.size())  # 1부터 시작
	
	# 초기 위치 설정 (플레이어 뒤)
	var offset = Vector2(-FOLLOW_DISTANCE * party_members.size(), 0)
	member.global_position = global_position + offset
	
	party_member_added.emit(member)
	EventBus.party_member_joined.emit(member.get_save_data())
	
	return true


func remove_party_member(index: int) -> void:
	if index < 0 or index >= party_members.size():
		return
	
	var member = party_members[index]
	party_members.remove_at(index)
	
	# 인덱스 재정렬
	for i in range(party_members.size()):
		party_members[i].set_party_index(i + 1)
	
	party_member_removed.emit(index)
	EventBus.party_member_left.emit(index)


func get_party_member(index: int) -> PartyMember:
	if index >= 0 and index < party_members.size():
		return party_members[index]
	return null


func get_all_party() -> Array:
	var all: Array = [self]
	all.append_array(party_members)
	return all


func get_alive_party() -> Array:
	var alive: Array = []
	if is_alive:
		alive.append(self)
	for member in party_members:
		if member.is_alive:
			alive.append(member)
	return alive


# ===== 경험치/레벨업 =====
func gain_exp(amount: int) -> void:
	current_exp += amount
	exp_gained.emit(amount, current_exp)
	
	while current_exp >= exp_to_next_level:
		_level_up()


func _level_up() -> void:
	current_exp -= exp_to_next_level
	level += 1
	
	# 스탯 성장
	var hero_data = DataManager.get_character("hero")
	if hero_data and hero_data.has("growth_per_level"):
		var growth = hero_data["growth_per_level"]
		max_hp += int(growth.get("max_hp", 10))
		max_mp += int(growth.get("max_mp", 3))
		attack += int(growth.get("attack", 2))
		defense += int(growth.get("defense", 1))
		magic += int(growth.get("magic", 1))
		magic_defense += int(growth.get("magic_defense", 1))
		speed += int(growth.get("speed", 1))
		critical += growth.get("critical", 0.5)
		evasion += growth.get("evasion", 0.2)
	
	# HP/MP 회복
	current_hp = max_hp
	current_mp = max_mp
	
	# 다음 레벨 필요 경험치 계산
	exp_to_next_level = DataManager.calculate_exp_for_level(level + 1)
	
	level_up.emit(level)
	EventBus.party_level_up.emit(0, level)
	AudioManager.play_level_up()


# ===== 전투 진입/종료 =====
func enter_battle() -> void:
	is_in_battle = true
	can_move = false
	stop_movement()
	
	for member in party_members:
		member.enter_battle()


func exit_battle() -> void:
	is_in_battle = false
	can_move = true
	
	for member in party_members:
		member.exit_battle()


# ===== 파티 전체 적용 =====
func heal_all_party(amount: int) -> void:
	heal(amount)
	for member in party_members:
		member.heal(amount)


func damage_all_party(amount: int) -> void:
	take_raw_damage(amount)
	for member in party_members:
		member.take_raw_damage(amount)


func is_party_alive() -> bool:
	if is_alive:
		return true
	for member in party_members:
		if member.is_alive:
			return true
	return false


# ===== 저장/로드 =====
func get_full_save_data() -> Dictionary:
	var data = get_save_data()
	data["current_exp"] = current_exp
	data["exp_to_next_level"] = exp_to_next_level
	
	var members_data: Array[Dictionary] = []
	for member in party_members:
		members_data.append(member.get_save_data())
	data["party_members"] = members_data
	
	return data


func load_full_save_data(data: Dictionary) -> void:
	init_from_saved_data(data)
	current_exp = data.get("current_exp", 0)
	exp_to_next_level = data.get("exp_to_next_level", 100)
