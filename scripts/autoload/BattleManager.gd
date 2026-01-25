extends Node
## BattleManager: 동시다발 전투 관리 + 전역 Hero ATB
## - 여러 전투창을 동시에 관리
## - 영웅 ATB는 전역으로 관리 (전투창 공유)
## - ATB 풀 차면 열려있는 전투창 중 하나에 공격 명령

const BATTLE_WINDOW_SCENE = preload("res://scenes/battle/BattleWindow.tscn")

signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, victory: bool)
signal all_battles_ended
signal battle_log_received(message: String, color: Color)
signal party_hp_changed
signal elite_victory(battle_id: int)
signal boss_victory(battle_id: int)
signal hero_atb_changed(hero_id: String, value: float)  # HUD 업데이트용
signal battle_speed_changed(speed: float)  # 전투 속도 변경
signal hero_attacked(hero_id: String)  # 영웅 공격 시 (이펙트용)

var active_battles: Dictionary = {}  # battle_id -> {window, is_boss, is_elite}
var _battle_id_counter: int = 0

# === 전역 Hero ATB 시스템 ===
var hero_atb: Dictionary = {}  # hero_id -> atb_value (0.0 ~ 1.0)
var _atb_active: bool = false  # 전투 중일 때만 ATB 진행

# === 전투 속도 ===
var battle_speed: float = 1.0  # 1x, 2x, 3x
const BATTLE_SPEEDS: Array[float] = [1.0, 2.0, 3.0]
var _current_speed_index: int = 0

# ATB 설정
const ATB_BASE_SPEED: float = 0.12  # 기본 ATB 충전 속도 (초당)
const ATB_SPD_FACTOR: float = 0.01  # SPD 1당 추가 충전 속도
const ATB_MAX: float = 1.0

# 전투창 배치 설정
const WINDOW_SIZE := Vector2(280, 200)
const CENTER_SAFE_SIZE: float = 100.0
const WINDOW_MARGIN: float = 10.0

var battle_container: CanvasLayer = null


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	# 비전투 중에도 HUD 표시용 ATB 업데이트 (공격은 각 BattleWindow에서 처리)
	if active_battles.is_empty():
		_update_hero_atb_for_hud(delta)


#region HUD용 Hero ATB (비전투 시)
func _update_hero_atb_for_hud(delta: float) -> void:
	## 비전투 중 HUD 표시용 ATB 업데이트 (공격 없음)
	var speed_delta: float = delta * battle_speed
	
	for hero in PartyManager.get_alive_heroes():
		if not hero_atb.has(hero.id):
			hero_atb[hero.id] = 0.0
		
		var charge_rate: float = ATB_BASE_SPEED + (hero.get_spd() * ATB_SPD_FACTOR)
		hero_atb[hero.id] = minf(hero_atb[hero.id] + charge_rate * speed_delta, ATB_MAX)
		
		# HUD 업데이트 시그널
		hero_atb_changed.emit(hero.id, hero_atb[hero.id])


func get_hero_atb(hero_id: String) -> float:
	## HUD에서 호출 - 영웅 ATB 조회
	return hero_atb.get(hero_id, 0.0)


func init_hero_atb() -> void:
	## 전투 시작 시 Hero ATB 초기화
	hero_atb.clear()
	for hero in PartyManager.get_alive_heroes():
		hero_atb[hero.id] = 0.0
		hero_atb_changed.emit(hero.id, 0.0)


func on_hero_died(hero_id: String) -> void:
	## 영웅 사망 시 ATB 제거
	hero_atb.erase(hero_id)
	hero_atb_changed.emit(hero_id, 0.0)
#endregion


#region 전투 시작/종료
func start_battle(enemy_ids: Array, parent_node: Node = null, is_elite: bool = false) -> int:
	_battle_id_counter += 1
	var battle_id := _battle_id_counter
	
	var is_boss := _check_boss_battle(enemy_ids)
	
	# 보스전 시작 시 다른 전투 모두 강제 종료
	if is_boss:
		force_end_all_non_boss()
	
	# 첫 전투 시작 시 ATB 초기화
	if active_battles.is_empty():
		init_hero_atb()
	
	# BattleWindow 씬 인스턴스 생성
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	
	# 컨테이너 설정
	if battle_container == null:
		_create_battle_container(parent_node)
	
	battle_container.add_child(window)
	
	# 위치 배정
	var pos := _calculate_window_position()
	window.position = pos
	
	# 전투 초기화
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
	
	# ATB 활성화
	_atb_active = true
	
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
		_atb_active = false
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
	
	# 사망한 영웅 ATB 정리
	for hero_id in hero_atb.keys():
		var hero = PartyManager.get_hero_by_id(hero_id)
		if hero == null or hero.is_dead:
			on_hero_died(hero_id)
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
	_atb_active = false
	hero_atb.clear()
#endregion


#region 전투창 위치 계산
func _calculate_window_position() -> Vector2:
	var viewport_size := Vector2(640, 360)
	var tree := get_tree()
	if tree:
		viewport_size = tree.root.get_visible_rect().size
	
	var available_rect := Rect2(
		WINDOW_MARGIN,
		WINDOW_MARGIN,
		viewport_size.x - WINDOW_SIZE.x - WINDOW_MARGIN * 2,
		viewport_size.y - WINDOW_SIZE.y - WINDOW_MARGIN * 2
	)
	
	var center := viewport_size / 2
	var center_safe_rect := Rect2(
		center.x - 50, center.y - 50, 100, 100
	)
	
	for _i in range(20):
		var x := randf_range(available_rect.position.x, available_rect.position.x + available_rect.size.x)
		var y := randf_range(available_rect.position.y, available_rect.position.y + available_rect.size.y)
		var candidate := Vector2(x, y)
		
		var window_rect := Rect2(candidate, WINDOW_SIZE)
		if window_rect.intersects(center_safe_rect):
			continue
		
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
	var to_remove: Array = active_battles.keys().duplicate()
	
	for battle_id in to_remove:
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window = battle_data.get("window")
		if is_instance_valid(window):
			window.queue_free()
		active_battles.erase(battle_id)
	
	_atb_active = false
	hero_atb.clear()


func toggle_battle_speed() -> float:
	## 전투 속도 토글 (1x -> 2x -> 3x -> 1x)
	_current_speed_index = (_current_speed_index + 1) % BATTLE_SPEEDS.size()
	battle_speed = BATTLE_SPEEDS[_current_speed_index]
	battle_speed_changed.emit(battle_speed)
	return battle_speed


func set_battle_speed(speed: float) -> void:
	## 전투 속도 직접 설정
	battle_speed = speed
	for i in range(BATTLE_SPEEDS.size()):
		if is_equal_approx(BATTLE_SPEEDS[i], speed):
			_current_speed_index = i
			break
	battle_speed_changed.emit(battle_speed)


func get_battle_speed() -> float:
	return battle_speed
#endregion
