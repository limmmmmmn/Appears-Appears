extends Node
## GameManager: 게임 상태 및 스테이지 진행 관리

signal stage_changed(stage: int, field: int)
signal gold_changed(new_gold: int)
signal game_over
signal game_clear

enum GameState { TITLE, FIELD, BATTLE, PAUSED, GAME_OVER, DEN }
var current_state: GameState = GameState.TITLE

var current_stage: int = 1
var current_field: int = 1
var max_fields_per_stage: int = 3

var gold: int = 0
var kill_count: int = 0
var obtained_legendaries: Array = []
var is_paused: bool = false


func _ready() -> void:
	pass


func change_state(new_state: GameState) -> void:
	current_state = new_state


func start_new_game() -> void:
	current_stage = 1
	current_field = 1
	gold = 2000
	kill_count = 0
	obtained_legendaries.clear()
	
	# 파티 및 인벤토리 초기화
	PartyManager.party.clear()
	PartyManager.inventory.clear()
	InventoryManager.clear()
	
	change_state(GameState.FIELD)
	stage_changed.emit(current_stage, current_field)
	gold_changed.emit(gold)


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


func add_kill_count(amount: int = 1) -> void:
	if amount <= 0:
		return
	kill_count += amount
	


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)

	return true


func can_afford(amount: int) -> bool:
	return gold >= amount


func advance_to_next_field() -> void:
	current_field += 1
	stage_changed.emit(current_stage, current_field)


func complete_stage() -> void:
	current_stage += 1
	current_field = 1
	if current_stage > 5:
		game_clear.emit()
		change_state(GameState.GAME_OVER)
		return
	stage_changed.emit(current_stage, current_field)


func is_boss_field() -> bool:
	return current_field > max_fields_per_stage


func get_stage_display() -> String:
	if is_boss_field():
		return "Stage %d - BOSS" % current_stage
	return "Stage %d-%d" % [current_stage, current_field]


func has_legendary(item_id: String) -> bool:
	return item_id in obtained_legendaries


func register_legendary(item_id: String) -> void:
	if item_id not in obtained_legendaries:
		obtained_legendaries.append(item_id)


func trigger_game_over() -> void:
	game_over.emit()
	change_state(GameState.GAME_OVER)


#region 씬 전환
func go_to_field(stage_id: String = "", field_id: String = "") -> void:
	## 필드로 이동
	if stage_id.is_empty():
		stage_id = "stage_" + str(current_stage)
	if field_id.is_empty():
		# 현재 필드 ID 사용
		field_id = "field_%d_%d" % [current_stage, current_field]
	
	# 필드 존재 확인
	FieldManager.set_current_stage(stage_id)
	if not FieldManager.set_current_field(field_id):
		# 필드가 없으면 첫 번째 필드로
		field_id = FieldManager.get_first_field_id(stage_id)
		FieldManager.set_current_field(field_id)
	
	var scene_path: String = FieldManager.get_current_field_scene()
	if scene_path.is_empty():
		scene_path = "res://scenes/field/Field_1_1.tscn"
	
	change_state(GameState.FIELD)
	
	# 자동 저장
	if SaveManager:
		SaveManager.auto_save("필드 진입")
	
	get_tree().change_scene_to_file(scene_path)


func go_to_next_from_field() -> void:
	## 필드 출구 도달 시 호출
	var next: String = FieldManager.get_next_destination()

	if next.begins_with("stage_"):
		# 다음 스테이지
		current_stage += 1
		current_field = 1
		go_to_field(next)
	elif next == "ending":
		game_clear.emit()
		go_to_ending()
	elif next.begins_with("field_"):
		# 같은 스테이지 다음 필드
		current_field += 1
		var new_stage_id: String = "stage_" + str(current_stage)
		go_to_field(new_stage_id, next)
	else:
		# 기본: 다음 필드로 진행
		current_field += 1
		var new_stage_id: String = "stage_" + str(current_stage)
		var new_field_id: String = "field_%d_%d" % [current_stage, current_field]
		go_to_field(new_stage_id, new_field_id)


func go_to_ending() -> void:
	## 엔딩 화면으로 이동
	change_state(GameState.GAME_OVER)  # 게임 종료 상태
	get_tree().change_scene_to_file("res://scenes/main/Ending.tscn")


func go_to_den() -> void:
	## 기지 시스템 제거: 호출 시 필드로 복귀
	change_state(GameState.FIELD)
	if SaveManager:
		SaveManager.save_game()
	go_to_field()
#endregion
