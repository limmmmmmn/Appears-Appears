extends Node
## 게임 전역 상태를 관리하는 오토로드

signal battle_started(enemy_id: String)
signal battle_ended(enemy_id: String, victory: bool)

# 현재 파티 구성 (영웅 id 배열)
var party: Array[String] = ["warrior", "mage", "cleric", "thief"]

# 활성 전투 목록
var active_battles: Array = []

# 게임 상태
var is_paused: bool = false


func _ready() -> void:
	print("[GameManager] 초기화 완료")


func start_battle(enemy_id: String) -> void:
	active_battles.append(enemy_id)
	battle_started.emit(enemy_id)
	print("[GameManager] 전투 시작: " + enemy_id + " (활성 전투: %d)" % active_battles.size())


func end_battle(enemy_id: String, victory: bool) -> void:
	active_battles.erase(enemy_id)
	battle_ended.emit(enemy_id, victory)
	print("[GameManager] 전투 종료: " + enemy_id + " (승리: %s)" % str(victory))


func get_active_battle_count() -> int:
	return active_battles.size()
