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
