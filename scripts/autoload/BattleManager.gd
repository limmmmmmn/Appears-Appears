extends Node
## BattleManager: 동시다발 전투 관리
## - 여러 전투창을 동시에 관리
## - 전투창 위치 배정 (HUD/리더 영역 제외)

signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, victory: bool)
signal all_battles_ended
signal battle_log_received(message: String, color: Color)  # FieldHUD 연결용
signal party_hp_changed  # 파티 HP 변경 알림
signal elite_victory(battle_id: int)  # 엘리트 전투 승리 시
signal boss_victory(battle_id: int)   # 보스 전투 승리 시

var active_battles: Dictionary = {}  # battle_id -> {window: BattleWindow, is_boss: bool}
var _battle_id_counter: int = 0

# 전투창 배치 설정
const WINDOW_SIZE := Vector2(280, 200)
const HUD_RIGHT_WIDTH: float = 200.0  # 우측 HUD 영역
const HUD_TOP_HEIGHT: float = 40.0    # 상단 HUD 영역
const LEADER_SAFE_RADIUS: float = 100.0  # 리더 주변 안전 영역
const WINDOW_MARGIN: float = 10.0

var battle_container: CanvasLayer = null


func _ready() -> void:
	pass


#region 전투 시작/종료
func start_battle(enemy_ids: Array, parent_node: Node = null, is_elite: bool = false) -> int:
	_battle_id_counter += 1
	var battle_id := _battle_id_counter
	
	var is_boss := _check_boss_battle(enemy_ids)
	
	# 보스전 시작 시 다른 전투 모두 강제 종료
	if is_boss:
		force_end_all_non_boss()
	
	# BattleWindow 생성
	var window := BattleWindow.new()
	
	# 컨테이너 설정
	if battle_container == null:
		_create_battle_container(parent_node)
	
	battle_container.add_child(window)
	
	# 위치 배정
	var pos := _calculate_window_position()
	window.position = pos
	
	# 전투 초기화 (엘리트 정보 전달)
	window.setup(battle_id, enemy_ids, is_elite)
	window.battle_ended.connect(_on_battle_window_ended)
	window.battle_log.connect(_on_battle_log)
	window.party_updated.connect(_on_party_updated)
	
	# 등록
	active_battles[battle_id] = {
		"window": window,
		"enemies": enemy_ids,
		"is_boss": is_boss,
		"is_elite": is_elite
	}
	
	battle_started.emit(battle_id)
	return battle_id


func end_battle(battle_id: int, victory: bool) -> void:
	if not active_battles.has(battle_id):
		return
	
	var battle_data: Dictionary = active_battles[battle_id]
	var window: BattleWindow = battle_data.get("window")
	
	if window and is_instance_valid(window):
		window.queue_free()
	
	active_battles.erase(battle_id)
	battle_ended.emit(battle_id, victory)
	
	if active_battles.is_empty():
		all_battles_ended.emit()


func _on_battle_window_ended(battle_id: int, victory: bool) -> void:
	# 엘리트/보스 전투 승리 체크 (end_battle 전에)
	var was_elite: bool = false
	var was_boss: bool = false
	if active_battles.has(battle_id):
		was_elite = active_battles[battle_id].get("is_elite", false)
		was_boss = active_battles[battle_id].get("is_boss", false)
	
	end_battle(battle_id, victory)
	
	# 보스 전투 승리 시 시그널
	if victory and was_boss:
		boss_victory.emit(battle_id)
	# 엘리트 전투 승리 시 시그널
	elif victory and was_elite:
		elite_victory.emit(battle_id)
	
	# 전투 승리 시 자동 저장
	if victory and SaveManager:
		SaveManager.auto_save("전투 승리")
	
	# 패배 시 게임오버 체크
	if not victory and PartyManager.is_party_wiped():
		GameManager.trigger_game_over()


func _on_battle_log(message: String, color: Color) -> void:
	battle_log_received.emit(message, color)


func _on_party_updated() -> void:
	party_hp_changed.emit()
#endregion


#region 전투창 컨테이너
func _create_battle_container(parent: Node) -> void:
	battle_container = CanvasLayer.new()
	battle_container.name = "BattleContainer"
	battle_container.layer = 10  # HUD 위
	
	if parent:
		parent.add_child(battle_container)
	else:
		var tree := get_tree()
		if tree and tree.current_scene:
			tree.current_scene.add_child(battle_container)


func clear_battle_container() -> void:
	if battle_container and is_instance_valid(battle_container):
		battle_container.queue_free()
		battle_container = null
	active_battles.clear()
#endregion


#region 전투창 위치 계산
func _calculate_window_position() -> Vector2:
	var viewport_size := Vector2(640, 360)
	var tree := get_tree()
	if tree:
		viewport_size = tree.root.get_visible_rect().size
	
	var available_rect := Rect2(
		WINDOW_MARGIN,
		HUD_TOP_HEIGHT + WINDOW_MARGIN,
		viewport_size.x - HUD_RIGHT_WIDTH - WINDOW_SIZE.x - WINDOW_MARGIN * 2,
		viewport_size.y - HUD_TOP_HEIGHT - WINDOW_SIZE.y - WINDOW_MARGIN * 2
	)
	
	var leader_pos := Vector2(-1000, -1000)
	var field := _find_current_field()
	if field and field.has_method("get_party_leader"):
		var party_leader = field.get_party_leader()
		if party_leader and is_instance_valid(party_leader):
			leader_pos = party_leader.global_position
	
	for _i in range(10):
		var x := randf_range(available_rect.position.x, available_rect.position.x + available_rect.size.x)
		var y := randf_range(available_rect.position.y, available_rect.position.y + available_rect.size.y)
		var candidate := Vector2(x, y)
		
		var window_center := candidate + WINDOW_SIZE / 2
		if window_center.distance_to(leader_pos) > LEADER_SAFE_RADIUS:
			var overlaps := false
			for bid in active_battles:
				var battle_data: Dictionary = active_battles[bid]
				if battle_data.has("window"):
					var other_window = battle_data.get("window")
					if is_instance_valid(other_window):
						if candidate.distance_to(other_window.position) < 50:
							overlaps = true
							break
			if not overlaps:
				return candidate
	
	return Vector2(available_rect.position.x, available_rect.position.y)


func _find_current_field() -> Node:
	var tree := get_tree()
	if tree and tree.current_scene:
		if tree.current_scene.has_method("get_party_leader"):
			return tree.current_scene
	return null
#endregion


#region 유틸리티
func get_active_battle_count() -> int:
	return active_battles.size()


func has_boss_battle() -> bool:
	for battle_id in active_battles:
		if active_battles[battle_id].get("is_boss", false):
			return true
	return false


func _check_boss_battle(enemy_ids: Array) -> bool:
	for enemy_id in enemy_ids:
		var enemy_data: Dictionary = DataManager.get_enemy(str(enemy_id))
		if enemy_data.get("type", "") == "boss":
			return true
	return false


func force_end_all_non_boss() -> void:
	var to_remove: Array = []
	for battle_id in active_battles:
		if not active_battles[battle_id].get("is_boss", false):
			to_remove.append(battle_id)
	
	for battle_id in to_remove:
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window = battle_data.get("window")
		if is_instance_valid(window):
			window.queue_free()
		active_battles.erase(battle_id)
		battle_ended.emit(battle_id, false)


func close_all_battles() -> void:
	## 모든 전투창 강제 종료 (게임오버 시 사용)
	var to_remove: Array = active_battles.keys().duplicate()
	
	for battle_id in to_remove:
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window = battle_data.get("window")
		if is_instance_valid(window):
			window.queue_free()
		active_battles.erase(battle_id)
#endregion
