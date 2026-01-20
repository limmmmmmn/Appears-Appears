extends Node
## BattleManager: 동시다발 전투 관리

signal battle_started(battle_id: int)
signal battle_ended(battle_id: int, victory: bool)

var active_battles: Dictionary = {}  # battle_id -> BattleData
var _battle_id_counter: int = 0


func _ready() -> void:
	print("[BattleManager] 초기화 완료")


func start_battle(enemy_ids: Array) -> int:
	_battle_id_counter += 1
	var battle_id := _battle_id_counter
	
	# TODO: BattleWindow 생성 및 전투 데이터 초기화
	active_battles[battle_id] = {
		"enemies": enemy_ids,
		"is_boss": _check_boss_battle(enemy_ids)
	}
	
	battle_started.emit(battle_id)
	return battle_id


func end_battle(battle_id: int, victory: bool) -> void:
	if active_battles.has(battle_id):
		active_battles.erase(battle_id)
	battle_ended.emit(battle_id, victory)


func get_active_battle_count() -> int:
	return active_battles.size()


func has_boss_battle() -> bool:
	for battle_id in active_battles:
		if active_battles[battle_id].get("is_boss", false):
			return true
	return false


func _check_boss_battle(enemy_ids: Array) -> bool:
	for enemy_id in enemy_ids:
		var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
		if enemy_data.get("type", "") == "boss":
			return true
	return false


func force_end_all_non_boss() -> void:
	## 보스전 진입 시 모든 잡몹 전투 강제 종료
	var to_remove: Array = []
	for battle_id in active_battles:
		if not active_battles[battle_id].get("is_boss", false):
			to_remove.append(battle_id)
	
	for battle_id in to_remove:
		end_battle(battle_id, false)
