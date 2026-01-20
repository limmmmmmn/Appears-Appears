extends Node
## GameManager: 게임 상태 및 스테이지 진행 관리

signal stage_changed(stage: int, field: int)
signal gold_changed(new_gold: int)
signal game_over
signal game_clear

enum GameState { TITLE, FIELD, TOWN, BATTLE, PAUSED, GAME_OVER }
var current_state: GameState = GameState.TITLE

var current_stage: int = 1
var current_field: int = 1
var max_fields_per_stage: int = 3

var gold: int = 0
var obtained_legendaries: Array = []
var is_paused: bool = false


func _ready() -> void:
	print("[GameManager] 초기화 완료")


func change_state(new_state: GameState) -> void:
	current_state = new_state


func start_new_game() -> void:
	current_stage = 1
	current_field = 1
	gold = 2000
	obtained_legendaries.clear()
	change_state(GameState.FIELD)
	stage_changed.emit(current_stage, current_field)
	gold_changed.emit(gold)


func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


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
		field_id = FieldManager.get_first_field_id(stage_id)
	
	FieldManager.set_current_stage(stage_id)
	FieldManager.set_current_field(field_id)
	
	var scene_path: String = FieldManager.get_current_field_scene()
	if scene_path.is_empty():
		scene_path = "res://scenes/field/Field_1_1.tscn"
	
	print("[GameManager] 필드 이동: ", scene_path)
	change_state(GameState.FIELD)
	get_tree().change_scene_to_file(scene_path)


func go_to_town() -> void:
	## 마을로 이동
	print("[GameManager] 마을 이동")
	change_state(GameState.TOWN)
	get_tree().change_scene_to_file("res://scenes/town/Town.tscn")


func go_to_next_from_field() -> void:
	## 필드 출구 도달 시 호출
	var next: String = FieldManager.get_next_destination()
	
	if next == "town":
		go_to_town()
	elif next.begins_with("stage_"):
		# 다음 스테이지
		current_stage += 1
		current_field = 1
		go_to_field(next)
	elif next == "ending":
		print("[GameManager] 게임 클리어!")
		game_clear.emit()
		# TODO: 엔딩 씬
	else:
		# 같은 스테이지 다음 필드
		current_field += 1
		var new_stage_id: String = "stage_" + str(current_stage)
		var new_field_id: String = "field_%d_%d" % [current_stage, current_field]
		go_to_field(new_stage_id, new_field_id)
#endregion
