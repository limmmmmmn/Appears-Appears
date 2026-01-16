extends Node
## GameManager.gd
## 전역 게임 상태 관리 싱글톤

# ===== 게임 상태 =====
enum GameState { TITLE, WORLD_MAP, FIELD, BATTLE, TOWN, PAUSED, GAME_OVER }
var current_state: GameState = GameState.TITLE
var previous_state: GameState = GameState.TITLE

# ===== 플레이어 데이터 =====
var player_data: Dictionary = {}
var party: Array[Dictionary] = []  # 파티원들 데이터
var inventory: Array[Dictionary] = []

# ===== 진행 상태 =====
var current_stage: int = 1
var current_node_index: int = 0
var current_node_type: String = "FIELD"
var gold: int = 0
var total_kills: int = 0
var stage_kills: int = 0
var stage_kill_target: int = 20

# ===== 전투 상태 =====
var is_in_battle: bool = false
var current_battle_enemies: Array[Dictionary] = []
var last_battle_position: Vector2 = Vector2.ZERO

# ===== 설정값 (config.json에서 로드) =====
var config: Dictionary = {}

# ===== 화면 크기 =====
const SCREEN_SIZE = Vector2(640, 360)
const BATTLE_WINDOW_SIZE = Vector2(180, 130)
const CENTER_PROTECTED = Rect2(295, 155, 50, 50)
const MIN_DISTANCE_FROM_LAST = 60

# ===== 시그널 =====
signal state_changed(new_state: GameState, old_state: GameState)
signal gold_changed(new_amount: int)
signal kills_changed(current: int, target: int)
signal stage_changed(new_stage: int)
signal party_updated()


func _ready() -> void:
	# config 로드는 DataManager가 준비된 후
	call_deferred("_load_config")


func _load_config() -> void:
	if DataManager.is_loaded:
		config = DataManager.get_config()
		_apply_config()


func _apply_config() -> void:
	if config.is_empty():
		return
	# config에서 값 적용 (필요시)


# ===== 상태 관리 =====
func change_state(new_state: GameState) -> void:
	if current_state == new_state:
		return
	
	previous_state = current_state
	current_state = new_state
	state_changed.emit(new_state, previous_state)
	
	match new_state:
		GameState.BATTLE:
			is_in_battle = true
			get_tree().paused = false
		GameState.PAUSED:
			get_tree().paused = true
		_:
			is_in_battle = false
			get_tree().paused = false


func resume_previous_state() -> void:
	change_state(previous_state)


# ===== 파티 관리 =====
func init_party(starting_characters: Array[String]) -> void:
	party.clear()
	for char_id in starting_characters:
		var char_data = DataManager.get_character(char_id)
		if char_data:
			var member = char_data.duplicate(true)
			member["current_hp"] = member.get("max_hp", 100)
			member["current_mp"] = member.get("max_mp", 50)
			member["current_exp"] = 0
			party.append(member)
	party_updated.emit()


func get_party_member(index: int) -> Dictionary:
	if index >= 0 and index < party.size():
		return party[index]
	return {}


func heal_party_member(index: int, amount: int) -> void:
	if index >= 0 and index < party.size():
		var member = party[index]
		member["current_hp"] = mini(member["current_hp"] + amount, member["max_hp"])
		party_updated.emit()


func damage_party_member(index: int, amount: int) -> bool:
	if index >= 0 and index < party.size():
		var member = party[index]
		member["current_hp"] = maxi(member["current_hp"] - amount, 0)
		party_updated.emit()
		return member["current_hp"] <= 0  # 사망 여부 반환
	return false


func is_party_alive() -> bool:
	for member in party:
		if member.get("current_hp", 0) > 0:
			return true
	return false


# ===== 골드 관리 =====
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false


# ===== 킬 카운트 =====
func add_kill(count: int = 1) -> void:
	total_kills += count
	stage_kills += count
	kills_changed.emit(stage_kills, stage_kill_target)
	
	if stage_kills >= stage_kill_target:
		EventBus.stage_clear_ready.emit()


func reset_stage_kills() -> void:
	stage_kills = 0
	kills_changed.emit(stage_kills, stage_kill_target)


# ===== 스테이지 관리 =====
func advance_stage() -> void:
	current_stage += 1
	reset_stage_kills()
	stage_kill_target = 20 + (current_stage - 1) * 5  # 스테이지마다 +5
	stage_changed.emit(current_stage)


func set_current_node(node_type: String, node_index: int) -> void:
	current_node_type = node_type
	current_node_index = node_index


# ===== 전투창 위치 계산 =====
func get_valid_battle_position() -> Vector2:
	var margin = 15
	var attempts = 20
	
	for i in range(attempts):
		var x = randf_range(margin, SCREEN_SIZE.x - BATTLE_WINDOW_SIZE.x - margin)
		var y = randf_range(25, SCREEN_SIZE.y - BATTLE_WINDOW_SIZE.y - 55)
		var pos = Vector2(x, y)
		var rect = Rect2(pos, BATTLE_WINDOW_SIZE)
		
		# 규칙 1: 중앙 보호 영역 체크
		if rect.intersects(CENTER_PROTECTED):
			continue
		
		# 규칙 2: 이전 위치와 거리 체크
		if last_battle_position != Vector2.ZERO:
			if pos.distance_to(last_battle_position) < MIN_DISTANCE_FROM_LAST:
				continue
		
		# 유효한 위치 찾음
		last_battle_position = pos
		return pos
	
	# 실패 시 기본 위치
	last_battle_position = Vector2(margin, 30)
	return last_battle_position


# ===== 게임 시작/리셋 =====
func start_new_game() -> void:
	# 초기화
	current_stage = 1
	current_node_index = 0
	current_node_type = "FIELD"
	gold = 0
	total_kills = 0
	stage_kills = 0
	stage_kill_target = 20
	is_in_battle = false
	last_battle_position = Vector2.ZERO
	inventory.clear()
	
	# 기본 파티 생성
	init_party(["hero"])
	
	# 상태 변경
	change_state(GameState.FIELD)


func game_over() -> void:
	change_state(GameState.GAME_OVER)


# ===== 세이브/로드 (나중에 구현) =====
func save_game() -> Dictionary:
	return {
		"current_stage": current_stage,
		"current_node_index": current_node_index,
		"current_node_type": current_node_type,
		"gold": gold,
		"total_kills": total_kills,
		"stage_kills": stage_kills,
		"party": party.duplicate(true),
		"inventory": inventory.duplicate(true)
	}


func load_game(data: Dictionary) -> void:
	current_stage = data.get("current_stage", 1)
	current_node_index = data.get("current_node_index", 0)
	current_node_type = data.get("current_node_type", "FIELD")
	gold = data.get("gold", 0)
	total_kills = data.get("total_kills", 0)
	stage_kills = data.get("stage_kills", 0)
	party = data.get("party", [])
	inventory = data.get("inventory", [])
	
	party_updated.emit()
	gold_changed.emit(gold)
	kills_changed.emit(stage_kills, stage_kill_target)
