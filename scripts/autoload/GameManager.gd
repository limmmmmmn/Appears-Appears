extends Node
## GameManager: 게임 상태 및 액트 진행 관리

signal act_changed(act_id: String, area_id: String)
signal gold_changed(new_gold: int)
signal trinkets_changed(ids: Array)
signal game_over
signal game_clear

enum GameState { TITLE, FIELD, BATTLE, PAUSED, GAME_OVER, TOWN, NODE_SELECT }
var current_state: GameState = GameState.TITLE
const ACT_NODE_SELECT_SCENE_PATH: String = "res://scenes/main/ActNodeSelect.tscn"

var current_act_id: String = "act_1"
var current_area_id: String = ""
var pending_node_travel: Dictionary = {}

var gold: int = 0
var kill_count: int = 0
var obtained_legendaries: Array = []
var obtained_trinkets: Array[String] = []
var starting_trinket_id: String = ""
var is_paused: bool = false


func _ready() -> void:
	pass


func change_state(new_state: GameState) -> void:
	current_state = new_state


func start_new_game() -> void:
	current_act_id = "act_1"
	current_area_id = ""
	gold = 2000
	kill_count = 0
	obtained_legendaries.clear()
	obtained_trinkets.clear()
	starting_trinket_id = ""
	pending_node_travel.clear()

	PartyManager.party.clear()
	PartyManager.inventory.clear()
	InventoryManager.clear()

	if BattleManager:
		BattleManager.reset_loot_gauge()

	FieldManager.generate_runtime_acts()
	change_state(GameState.NODE_SELECT)
	_emit_progress_changed()
	gold_changed.emit(gold)
	trinkets_changed.emit(obtained_trinkets.duplicate())


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


func is_boss_field() -> bool:
	return FieldManager.is_boss_field()


func get_act_display() -> String:
	var act_num: String = _extract_numeric_suffix(current_act_id)
	if act_num.is_empty():
		act_num = "1"
	return "Act %s" % act_num


func has_legendary(item_id: String) -> bool:
	return item_id in obtained_legendaries


func register_legendary(item_id: String) -> void:
	if item_id not in obtained_legendaries:
		obtained_legendaries.append(item_id)


func choose_starting_trinket(trinket_id: String) -> bool:
	if trinket_id.is_empty():
		return false
	if not starting_trinket_id.is_empty():
		return false
	if not obtain_trinket(trinket_id, "start"):
		return false
	starting_trinket_id = trinket_id
	return true


func obtain_trinket(trinket_id: String, source: String) -> bool:
	if trinket_id.is_empty():
		return false
	if trinket_id in obtained_trinkets:
		return false
	var data: Dictionary = DataManager.get_trinket(trinket_id)
	if data.is_empty():
		return false
	if source != "start":
		var allowed_sources: Array = data.get("sources", []) as Array
		if source not in allowed_sources:
			return false

	obtained_trinkets.append(trinket_id)
	trinkets_changed.emit(obtained_trinkets.duplicate())
	if SaveManager != null:
		SaveManager.auto_save("트링캣 획득")
	return true


func grant_random_trinket(source: String) -> String:
	var candidates: Array[String] = DataManager.get_trinkets_for_source(source)
	var available: Array[String] = []
	for tid in candidates:
		if tid not in obtained_trinkets:
			available.append(tid)
	if available.is_empty():
		return ""
	available.shuffle()
	var picked: String = available[0]
	if obtain_trinket(picked, source):
		return picked
	return ""


func get_trinket_choices(source: String, count: int = 3, include_obtained: bool = false) -> Array[String]:
	var result: Array[String] = []
	if count <= 0 or DataManager == null:
		return result

	var candidates: Array[String] = DataManager.get_trinkets_for_source(source)
	if not include_obtained:
		var filtered: Array[String] = []
		for tid in candidates:
			if tid not in obtained_trinkets:
				filtered.append(tid)
		candidates = filtered

	if candidates.is_empty():
		return result

	candidates.shuffle()
	var pick_count: int = mini(count, candidates.size())
	for i in range(pick_count):
		result.append(candidates[i])
	return result


func get_obtained_trinkets() -> Array[String]:
	return obtained_trinkets.duplicate()


func get_trinket_enemy_stat_multiplier() -> float:
	var mult: float = 1.0
	for tid in obtained_trinkets:
		var data: Dictionary = DataManager.get_trinket(tid)
		mult *= float(data.get("enemy_stat_multiplier", 1.0))
	return maxf(0.1, mult)


func get_trinket_reward_gold_multiplier() -> float:
	var mult: float = 1.0
	for tid in obtained_trinkets:
		var data: Dictionary = DataManager.get_trinket(tid)
		mult *= float(data.get("reward_gold_multiplier", 1.0))
	return maxf(0.1, mult)


func get_trinket_reward_exp_multiplier() -> float:
	var mult: float = 1.0
	for tid in obtained_trinkets:
		var data: Dictionary = DataManager.get_trinket(tid)
		mult *= float(data.get("reward_exp_multiplier", 1.0))
	return maxf(0.1, mult)


func get_trinket_field_enemy_count_multiplier() -> float:
	var mult: float = 1.0
	for tid in obtained_trinkets:
		var data: Dictionary = DataManager.get_trinket(tid)
		mult *= float(data.get("field_enemy_count_multiplier", 1.0))
	return maxf(0.1, mult)


func get_trinket_battle_enemy_bonus() -> int:
	var bonus: int = 0
	for tid in obtained_trinkets:
		var data: Dictionary = DataManager.get_trinket(tid)
		bonus += int(data.get("battle_enemy_bonus", 0))
	return maxi(0, bonus)


func get_trinket_max_enemies_per_window_bonus() -> int:
	var bonus: int = 0
	for tid in obtained_trinkets:
		var data: Dictionary = DataManager.get_trinket(tid)
		bonus += int(data.get("max_enemies_per_window_bonus", 0))
	return maxi(0, bonus)


func get_trinket_loot_multiplier(kill_count: int) -> float:
	var mult: float = 1.0
	for tid in obtained_trinkets:
		var data: Dictionary = DataManager.get_trinket(tid)
		var min_enemies: int = int(data.get("loot_mult_min_enemies", 0))
		if min_enemies > 0 and kill_count >= min_enemies:
			mult *= float(data.get("loot_mult_value", 1.0))
	return mult


func trigger_game_over() -> void:
	game_over.emit()
	change_state(GameState.GAME_OVER)


#region 씬 전환
func go_to_area(act_id: String = "", area_id: String = "") -> void:
	if act_id.is_empty():
		act_id = current_act_id
	if act_id.is_empty():
		act_id = "act_1"

	if FieldManager.ensure_runtime_acts().is_empty():
		push_error("[GameManager] runtime acts 가 비어 있음")
		return

	if not FieldManager.set_current_act(act_id):
		var first_acts: Array[Dictionary] = FieldManager.get_runtime_acts()
		if first_acts.is_empty():
			push_error("[GameManager] 이동 가능한 액트가 없음")
			return
		act_id = str((first_acts[0] as Dictionary).get("id", ""))
		if not FieldManager.set_current_act(act_id):
			push_error("[GameManager] 액트 설정 실패: " + act_id)
			return

	if area_id.is_empty():
		if not current_area_id.is_empty() and FieldManager.get_runtime_area(act_id, current_area_id).size() > 0:
			area_id = current_area_id
		else:
			area_id = FieldManager.get_first_area_id(act_id)

	if not FieldManager.set_current_area(area_id):
		area_id = FieldManager.get_first_area_id(act_id)
		if area_id.is_empty() or not FieldManager.set_current_area(area_id):
			push_error("[GameManager] 에어리어 설정 실패: " + act_id + "/" + area_id)
			return

	current_act_id = FieldManager.current_act_id
	current_area_id = FieldManager.current_area_id
	pending_node_travel.clear()
	_emit_progress_changed()

	var scene_path: String = FieldManager.get_current_area_scene()
	if scene_path.is_empty():
		push_error("[GameManager] 에어리어 씬 경로를 찾을 수 없음: " + act_id + "/" + area_id)
		return

	var area_type: String = FieldManager.get_current_area_type()
	if area_type == "town":
		change_state(GameState.TOWN)
	else:
		change_state(GameState.FIELD)
	if SaveManager:
		SaveManager.auto_save("에어리어 진입")
	get_tree().change_scene_to_file(scene_path)


func go_to_next_from_area() -> void:
	var next_ids: Array[String] = FieldManager.get_next_area_ids()
	if not next_ids.is_empty():
		queue_node_travel(current_act_id, current_area_id, next_ids[0])
		return

	# 임시 규칙: Act 1 마지막 노드 이후 바로 엔딩으로 이동
	if current_act_id == "act_1":
		game_clear.emit()
		go_to_ending()
		return

	var next_act_id: String = FieldManager.get_next_act_id(current_act_id)
	if not next_act_id.is_empty():
		var next_area_id: String = FieldManager.get_first_area_id(next_act_id)
		queue_node_travel(next_act_id, current_area_id, next_area_id)
		return

	# 다음 노드/다음 액트가 없으면 게임 클리어
	game_clear.emit()
	go_to_ending()


func go_to_ending() -> void:
	pending_node_travel.clear()
	change_state(GameState.GAME_OVER)
	get_tree().change_scene_to_file("res://scenes/main/Ending.tscn")


func go_to_town() -> void:
	pending_node_travel.clear()
	change_state(GameState.TOWN)
	if SaveManager:
		SaveManager.auto_save("마을 이동")
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/town/Town.tscn")


func go_to_den() -> void:
	go_to_town()
#endregion


func queue_node_travel(act_id: String, from_area_id: String, to_area_id: String) -> void:
	if to_area_id.is_empty():
		return
	var resolved_act_id: String = act_id
	if resolved_act_id.is_empty():
		resolved_act_id = current_act_id
	if resolved_act_id.is_empty():
		resolved_act_id = "act_1"

	pending_node_travel = {
		"act_id": resolved_act_id,
		"from_area_id": from_area_id,
		"to_area_id": to_area_id,
	}
	change_state(GameState.NODE_SELECT)
	get_tree().change_scene_to_file(ACT_NODE_SELECT_SCENE_PATH)


func has_pending_node_travel() -> bool:
	return not pending_node_travel.is_empty()


func get_pending_node_travel() -> Dictionary:
	return pending_node_travel.duplicate(true)


func clear_pending_node_travel() -> void:
	pending_node_travel.clear()


func _emit_progress_changed() -> void:
	act_changed.emit(current_act_id, current_area_id)


func _extract_numeric_suffix(raw_id: String) -> String:
	if raw_id.is_empty():
		return ""
	var digits: String = ""
	for i in range(raw_id.length() - 1, -1, -1):
		var ch: String = raw_id.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		elif not digits.is_empty():
			break
	return digits
