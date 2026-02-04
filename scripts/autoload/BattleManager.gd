extends Node
## BattleManager: 전투창 증식 시스템
## - 필드 적 1마리 = 전투창 적 1마리 (1:1 대응)
## - 전투창 하나에 최대 MAX_ENEMIES_PER_WINDOW 마리
## - 전투창 최대 MAX_BATTLE_WINDOWS 개

const BATTLE_WINDOW_SCENE = preload("res://scenes/battle/BattleWindow.tscn")

signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, victory: bool)
signal all_battles_ended
signal battle_log_received(message: String, color: Color)
signal party_hp_changed
signal elite_victory(battle_id: int)
signal boss_victory(battle_id: int)
signal beat_occurred(beat_index: int)  # 비트 발생 시그널
signal battle_speed_changed(bpm: float, tempo_name: String)
signal hero_attacked(hero_id: String)
signal loot_animation_requested(item_id: String, start_pos: Vector2)
signal global_kill_count_changed(count: int, danger_level: int)
signal accumulated_rewards_changed(exp: int, gold: int, items: Array)
signal danger_level_up(new_level: int)  # 원념 레벨업 시 (선택창 표시용)

# === 전투창 증식 시스템 설정 ===
const MAX_ENEMIES_PER_WINDOW: int = 3  # 전투창 하나당 최대 적 수
const MAX_BATTLE_WINDOWS: int = 5      # 최대 전투창 개수

# === 글로벌 킬카운트 (원념) 시스템 ===
var global_kill_count: int = 0  # 전체 적 처치 횟수
const DANGER_LEVEL_INTERVAL: int = 5  # 위험도 1레벨당 킬 수 (5킬마다 레벨업)
const STAT_SCALE_PER_LEVEL: float = 0.05  # 위험도 1레벨당 스탯 증가율 (5%)

# === 누적 보상 시스템 ===
var accumulated_exp: int = 0
var accumulated_gold: int = 0
var accumulated_items: Array = []  # [{id, type, rarity, identified}]

# === 창 생성 효과 (비워둠) ===
signal window_created(window_count: int)      # 새 전투창 생성 시
signal threshold_reached(window_count: int)   # 임계치 도달 시

var active_battles: Dictionary = {}  # battle_id -> {window, is_boss, is_elite}
var _battle_id_counter: int = 0

# === 전투 속도 (BPM 기반) ===
# 음악적 템포: Largo → Andante → Moderato → Allegro → Presto
const TEMPO_BPM: Array[int] = [60, 80, 110, 140, 180]
const TEMPO_NAMES: Dictionary = {
	60: "Largo",      # 느리게
	80: "Andante",    # 걷는 속도 (기본)
	110: "Moderato",  # 보통
	140: "Allegro",   # 빠르게
	180: "Presto"     # 매우 빠르게
}
const TEMPO_KOREAN: Dictionary = {
	60: "느리게",
	80: "보통",
	110: "조금 빠르게",
	140: "빠르게",
	180: "매우 빠르게"
}
var current_bpm: int = 80  # 기본값: Andante
var _current_tempo_index: int = 1  # Andante가 기본

# === Charm 효과 ===
var extra_enemy_slots: int = 0  # 추가 적 슬롯 (charm1 효과)

# 전투창 배치 설정
const WINDOW_SIZE := Vector2(280, 200)
const CENTER_SAFE_SIZE: float = 100.0
const WINDOW_MARGIN: float = 20.0  # 화면 가장자리 여유

var battle_container: CanvasLayer = null


func _ready() -> void:
	pass


#region 전투창 증식 시스템 - 핵심 로직
func add_enemy_to_battle(enemy_id: String, parent_node: Node = null, is_elite: bool = false, collision_pos: Vector2 = Vector2.ZERO) -> int:
	## 필드에서 적 1마리와 충돌 시 호출
	## 기존 전투창에 추가하거나 새 전투창 생성
	
	var is_boss := _check_boss_enemy(enemy_id)
	
	# 보스전 시작 시 다른 전투 모두 강제 종료
	if is_boss:
		force_end_all_non_boss()
		return _create_new_battle([enemy_id], parent_node, is_elite, is_boss, collision_pos)
	
	# 기존 전투창 중 여유 있는 곳 찾기
	var available_window: BattleWindow = _find_available_window()
	
	if available_window != null:
		# 기존 전투창에 적 추가
		available_window.add_enemy(enemy_id, is_elite)
		return available_window.battle_id
	else:
		# 새 전투창 필요
		if get_active_battle_count() >= MAX_BATTLE_WINDOWS:
			# 최대 전투창 도달 - 오버플로 처리 (현재는 가장 오래된 창에 강제 추가)
			var oldest_window: BattleWindow = _get_oldest_non_boss_window()
			if oldest_window:
				oldest_window.add_enemy(enemy_id, is_elite)
				return oldest_window.battle_id
			# 그래도 없으면 무시 (보스전만 있는 경우)
			return -1
		
		# 새 전투창 생성
		return _create_new_battle([enemy_id], parent_node, is_elite, false, collision_pos)


func _find_available_window() -> BattleWindow:
	## 적을 추가할 수 있는 전투창 찾기 (보스 제외, 여유 있는 창)
	for battle_id in active_battles:
		var battle_data: Dictionary = active_battles[battle_id]
		if battle_data.get("is_boss", false):
			continue

		var window_ref = battle_data.get("window")
		if window_ref == null or not is_instance_valid(window_ref):
			continue

		var window: BattleWindow = window_ref as BattleWindow
		if window:
			# charm 효과로 인한 동적 최대 적 수 사용
			if window.get_enemy_count() < window.get_max_enemies():
				return window

	return null


func _get_oldest_non_boss_window() -> BattleWindow:
	## 가장 먼저 생성된 비보스 전투창 반환
	var oldest_id: int = -1
	var oldest_window: BattleWindow = null

	for battle_id in active_battles:
		var battle_data: Dictionary = active_battles[battle_id]
		if battle_data.get("is_boss", false):
			continue

		var window_ref = battle_data.get("window")
		if window_ref == null or not is_instance_valid(window_ref):
			continue

		if oldest_id == -1 or battle_id < oldest_id:
			oldest_id = battle_id
			oldest_window = window_ref as BattleWindow

	return oldest_window


func _create_new_battle(enemy_ids: Array, parent_node: Node, is_elite: bool, is_boss: bool, _collision_pos: Vector2) -> int:
	## 새 전투창 생성
	_battle_id_counter += 1
	var battle_id := _battle_id_counter
	
	# 적 조우 사운드 재생
	if SoundManager:
		SoundManager.play_encounter()
	
	# 첫 전투 시작 체크
	var is_first_battle := active_battles.is_empty()
	
	# BattleWindow 씬 인스턴스 생성
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	
	# 컨테이너 설정
	if battle_container == null:
		_create_battle_container(parent_node)
	
	battle_container.add_child(window)
	
	# 최종 목표 위치
	var target_pos := _calculate_window_position()
	
	# 시작 위치: 화면 중앙
	var viewport_size := Vector2(480, 270)
	var tree := get_tree()
	if tree:
		viewport_size = tree.root.get_visible_rect().size
	
	var start_pos: Vector2 = viewport_size / 2 - WINDOW_SIZE / 2
	
	# 시작 위치에 배치 (중앙, 투명, 작은 크기)
	window.position = start_pos
	window.modulate.a = 0.0
	window.scale = Vector2(0.5, 0.5)
	
	# 전투 초기화 (새 시스템용)
	window.setup_new(battle_id, enemy_ids, is_elite, is_boss)
	window.battle_ended.connect(_on_battle_window_ended)
	window.battle_log.connect(_on_battle_log)
	window.party_updated.connect(_on_party_updated)
	window.loot_drop_requested.connect(_on_loot_drop_requested)
	
	# 등장 애니메이션
	_animate_window_appear(window, target_pos)
	
	# 등록
	active_battles[battle_id] = {
		"window": window,
		"is_boss": is_boss,
		"is_elite": is_elite
	}

	# === 창 생성 효과 (비워둠) ===
	var window_count := get_active_battle_count()
	window_created.emit(window_count)
	_on_window_created_effect(window_count)
	
	# 임계치 체크
	_check_threshold(window_count)
	
	battle_started.emit(battle_id)
	return battle_id


func _on_window_created_effect(_window_count: int) -> void:
	## 전투창 생성 시 발동하는 효과 (현재 비워둠)
	## TODO: 파티 보호막, 힐 토큰, 디버프, 보상 배율 등
	pass


func _check_threshold(window_count: int) -> void:
	## 전투창 개수 임계치 체크 및 효과 발동 (현재 비워둠)
	if window_count == 3:
		threshold_reached.emit(3)
		_on_threshold_3_effect()
	elif window_count == 5:
		threshold_reached.emit(5)
		_on_threshold_5_effect()
	elif window_count == MAX_BATTLE_WINDOWS:
		threshold_reached.emit(MAX_BATTLE_WINDOWS)
		_on_threshold_max_effect()


func _on_threshold_3_effect() -> void:
	## 전투창 3개 도달 효과 (비워둠)
	pass


func _on_threshold_5_effect() -> void:
	## 전투창 5개 도달 효과 (비워둠)
	pass


func _on_threshold_max_effect() -> void:
	## 전투창 최대치 도달 효과 (비워둠)
	pass
#endregion


#region 레거시 호환 - start_battle
func start_battle(enemy_ids: Array, parent_node: Node = null, is_elite: bool = false, collision_pos: Vector2 = Vector2.ZERO) -> int:
	## 레거시 호환용: 여러 적을 한번에 전투에 추가
	## 새 시스템에서는 add_enemy_to_battle 사용 권장
	
	if enemy_ids.is_empty():
		return -1
	
	var first_enemy_id: String = str(enemy_ids[0])
	var is_boss := _check_boss_enemy(first_enemy_id)
	
	# 보스전은 별도 창으로 처리
	if is_boss:
		force_end_all_non_boss()
		return _create_new_battle(enemy_ids, parent_node, is_elite, true, collision_pos)
	
	# 첫 번째 적으로 전투 시작/추가
	var battle_id: int = add_enemy_to_battle(first_enemy_id, parent_node, is_elite, collision_pos)
	
	# 나머지 적들 추가 (1:1 대응이므로 순차 추가)
	for i in range(1, enemy_ids.size()):
		var enemy_id: String = str(enemy_ids[i])
		add_enemy_to_battle(enemy_id, parent_node, false, collision_pos)
	
	return battle_id
#endregion


#region 전투창 등장 애니메이션
func _animate_window_appear(window: BattleWindow, target_pos: Vector2) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	
	tween.tween_property(window, "position", target_pos, 0.35)
	tween.tween_property(window, "modulate:a", 1.0, 0.2)
	tween.tween_property(window, "scale", Vector2.ONE, 0.3)
#endregion


#region 전투 종료
func end_battle(battle_id: int, victory: bool) -> void:
	if not active_battles.has(battle_id):
		return

	var battle_data: Dictionary = active_battles[battle_id]
	var window_ref = battle_data.get("window")

	if window_ref != null and is_instance_valid(window_ref):
		window_ref.queue_free()

	active_battles.erase(battle_id)
	battle_ended.emit(battle_id, victory)
	
	if active_battles.is_empty():
		all_battles_ended.emit()


func _on_battle_window_ended(battle_id: int, victory: bool) -> void:
	var was_elite: bool = false
	var was_boss: bool = false
	if active_battles.has(battle_id):
		was_elite = active_battles[battle_id].get("is_elite", false)
		was_boss = active_battles[battle_id].get("is_boss", false)
	
	end_battle(battle_id, victory)
	
	if victory and was_boss:
		boss_victory.emit(battle_id)
	elif victory and was_elite:
		elite_victory.emit(battle_id)
	
	if victory and SaveManager:
		SaveManager.auto_save("전투 승리")
	
	if not victory and PartyManager.is_party_wiped():
		GameManager.trigger_game_over()


func _on_battle_log(message: String, color: Color) -> void:
	battle_log_received.emit(message, color)


func _on_party_updated() -> void:
	party_hp_changed.emit()


func _on_loot_drop_requested(item_id: String, start_pos: Vector2) -> void:
	loot_animation_requested.emit(item_id, start_pos)
#endregion


#region 누적 보상 시스템
func add_accumulated_reward(exp: int, gold: int, items: Array = []) -> void:
	## 전투창에서 보상 누적
	accumulated_exp += exp
	accumulated_gold += gold

	# 아이템은 미감정 상태로 추가
	for item_id in items:
		# 장비 데이터 먼저 확인, 없으면 일반 아이템 확인
		var item_data: Dictionary = DataManager.get_equipment(item_id)
		if item_data.is_empty():
			item_data = DataManager.get_item(item_id)
		if item_data.is_empty():
			continue

		var unidentified_item := {
			"id": item_id,
			"type": item_data.get("type", "unknown"),
			"slot": item_data.get("slot", ""),
			"rarity": item_data.get("rarity", "common"),
			"identified": false
		}
		accumulated_items.append(unidentified_item)

	accumulated_rewards_changed.emit(accumulated_exp, accumulated_gold, accumulated_items)


func increment_global_kill_count() -> void:
	## 글로벌 킬카운트 증가 및 원념 레벨 체크
	var old_level: int = global_kill_count / DANGER_LEVEL_INTERVAL
	global_kill_count += 1
	var new_level: int = global_kill_count / DANGER_LEVEL_INTERVAL

	global_kill_count_changed.emit(global_kill_count, new_level)

	# 원념 레벨업 시 선택창 표시
	if new_level > old_level and new_level > 0:
		danger_level_up.emit(new_level)


func claim_accumulated_rewards() -> void:
	## 누적 보상 수령 (스톱 선택 시)
	if accumulated_exp > 0:
		PartyManager.distribute_exp(accumulated_exp)
	if accumulated_gold > 0:
		GameManager.add_gold(accumulated_gold)

	# 아이템은 인벤토리에 추가 (미감정 상태)
	for item in accumulated_items:
		InventoryManager.add_unidentified_item(item.id, 1)

	# 로그
	battle_log_received.emit("보상 획득! EXP +%d, Gold +%d" % [accumulated_exp, accumulated_gold], Color.CYAN)

	# 초기화
	reset_accumulated_rewards()


func reset_accumulated_rewards() -> void:
	## 보상 및 원념 초기화
	accumulated_exp = 0
	accumulated_gold = 0
	accumulated_items.clear()
	global_kill_count = 0
	accumulated_rewards_changed.emit(0, 0, [])
	global_kill_count_changed.emit(0, 0)


func get_accumulated_rewards() -> Dictionary:
	return {
		"exp": accumulated_exp,
		"gold": accumulated_gold,
		"items": accumulated_items,
		"danger_level": get_danger_level()
	}
#endregion


#region 전투창 컨테이너
func _create_battle_container(parent: Node) -> void:
	battle_container = CanvasLayer.new()
	battle_container.name = "BattleContainer"
	battle_container.layer = 10
	
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
# HUD 영역 설정
const HUD_TOP_HEIGHT: float = 32.0  # TopBar 높이 + 여유
const HUD_BOTTOM_HEIGHT: float = 60.0  # BottomPartyPanel 높이 + 여유

func _calculate_window_position() -> Vector2:
	var viewport_size := Vector2(640, 360)
	var tree := get_tree()
	if tree:
		viewport_size = tree.root.get_visible_rect().size

	# HUD를 피한 안전 영역 계산
	var safe_left: float = WINDOW_MARGIN
	var safe_top: float = HUD_TOP_HEIGHT
	var safe_right: float = viewport_size.x - WINDOW_SIZE.x - WINDOW_MARGIN
	var safe_bottom: float = viewport_size.y - WINDOW_SIZE.y - HUD_BOTTOM_HEIGHT

	# 화면을 벗어나지 않도록 클램프
	safe_left = maxf(safe_left, 0)
	safe_top = maxf(safe_top, 0)
	safe_right = maxf(safe_right, safe_left)
	safe_bottom = maxf(safe_bottom, safe_top)

	# 현재 전투창 개수
	var window_count: int = active_battles.size()

	# 첫 2개는 고정 위치 (좌상단, 우상단)
	if window_count == 0:
		return Vector2(safe_left, safe_top)  # 좌상단
	elif window_count == 1:
		return Vector2(safe_right, safe_top)  # 우상단

	# 3개째부터는 랜덤 위치 (겹쳐도 됨, 단 중앙은 피함)
	var center := viewport_size / 2
	var center_avoid := Rect2(center.x - 50, center.y - 30, 100, 60)  # 가로100 세로60 영역

	for _i in range(20):
		var x := randf_range(safe_left, safe_right)
		var y := randf_range(safe_top, safe_bottom)
		var window_rect := Rect2(x, y, WINDOW_SIZE.x, WINDOW_SIZE.y)

		# 중앙 영역과 겹치지 않으면 사용
		if not window_rect.intersects(center_avoid):
			return Vector2(x, y)

	# 못 찾으면 상단 영역에 배치
	return Vector2(randf_range(safe_left, safe_right), safe_top)


func _is_position_available(pos: Vector2) -> bool:
	## 해당 위치에 다른 전투창이 없는지 확인
	for bid in active_battles:
		var battle_data: Dictionary = active_battles[bid]
		var window_ref = battle_data.get("window")
		if window_ref != null and is_instance_valid(window_ref):
			if pos.distance_to(window_ref.position) < WINDOW_SIZE.x * 0.8:
				return false
	return true
#endregion


#region Charm 시스템
func set_extra_enemy_slots(slots: int) -> void:
	## Charm 효과: 추가 적 슬롯 설정
	extra_enemy_slots = maxi(0, slots)


func get_extra_enemy_slots() -> int:
	return extra_enemy_slots


func get_max_enemies_per_window() -> int:
	## 전투창당 최대 적 수 반환 (기본값 + charm 효과)
	return MAX_ENEMIES_PER_WINDOW + extra_enemy_slots
#endregion


#region 글로벌 킬카운트 (원념) 시스템
func add_global_kill_count(amount: int = 1) -> void:
	## 글로벌 킬카운트 증가
	global_kill_count += amount
	global_kill_count_changed.emit(global_kill_count, get_danger_level())


func get_global_kill_count() -> int:
	return global_kill_count


func get_danger_level() -> int:
	## 위험도 레벨 반환 (킬카운트 / 10)
	return global_kill_count / DANGER_LEVEL_INTERVAL


func get_enemy_stat_multiplier() -> float:
	## 위험도에 따른 적 스탯 배율 반환
	var danger_level := get_danger_level()
	return 1.0 + (danger_level * STAT_SCALE_PER_LEVEL)


func reset_global_kill_count() -> void:
	## 킬카운트 초기화 (새 게임 시작 시)
	global_kill_count = 0
	global_kill_count_changed.emit(0, 0)
#endregion


#region 유틸리티
func get_active_battle_count() -> int:
	return active_battles.size()


func get_total_enemy_count() -> int:
	## 모든 전투창의 적 수 합계
	var total: int = 0
	for battle_id in active_battles:
		var window: BattleWindow = active_battles[battle_id].get("window")
		if window and is_instance_valid(window):
			total += window.get_enemy_count()
	return total


func has_boss_battle() -> bool:
	for battle_id in active_battles:
		if active_battles[battle_id].get("is_boss", false):
			return true
	return false


func _check_boss_enemy(enemy_id: String) -> bool:
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	return enemy_data.get("type", "") == "boss"


func force_end_all_non_boss() -> void:
	var to_remove: Array = []
	for battle_id in active_battles:
		if not active_battles[battle_id].get("is_boss", false):
			to_remove.append(battle_id)

	for battle_id in to_remove:
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window_ref = battle_data.get("window")
		if window_ref != null and is_instance_valid(window_ref):
			window_ref.queue_free()
		active_battles.erase(battle_id)
		battle_ended.emit(battle_id, false)


func close_all_battles() -> void:
	var to_remove: Array = active_battles.keys().duplicate()

	for battle_id in to_remove:
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window_ref = battle_data.get("window")
		if window_ref != null and is_instance_valid(window_ref):
			window_ref.queue_free()
		active_battles.erase(battle_id)


func toggle_battle_speed() -> int:
	## 다음 템포로 전환, BPM 반환
	_current_tempo_index = (_current_tempo_index + 1) % TEMPO_BPM.size()
	current_bpm = TEMPO_BPM[_current_tempo_index]
	battle_speed_changed.emit(current_bpm, get_tempo_name())
	return current_bpm


func set_battle_bpm(bpm: int) -> void:
	## 특정 BPM으로 설정
	current_bpm = bpm
	for i in range(TEMPO_BPM.size()):
		if TEMPO_BPM[i] == bpm:
			_current_tempo_index = i
			break
	battle_speed_changed.emit(current_bpm, get_tempo_name())


func get_current_bpm() -> int:
	return current_bpm


func get_tempo_name() -> String:
	## 현재 템포의 영문 이름 반환
	return TEMPO_NAMES.get(current_bpm, "Andante")


func get_tempo_korean() -> String:
	## 현재 템포의 한글 이름 반환
	return TEMPO_KOREAN.get(current_bpm, "보통")


func get_beat_interval() -> float:
	## 현재 BPM에 따른 비트 간격 (초)
	return 60.0 / float(current_bpm)


func get_battle_speed() -> float:
	## 레거시 호환: 기본 80 BPM 대비 속도 배율
	return float(current_bpm) / 80.0
#endregion
