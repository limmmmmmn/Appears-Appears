extends Node
## 게임 전역 상태를 관리하는 오토로드

signal battle_started(enemy_id: String)
signal battle_ended(enemy_id: String, victory: bool)
signal party_status_changed()
signal hero_ready_to_attack(hero_id: String)

# 현재 파티 구성 (영웅 id 배열)
var party: Array[String] = ["warrior", "mage", "cleric", "thief"]

# 파티 상태 (전역으로 관리)
var party_hp: Dictionary = {}
var party_max_hp: Dictionary = {}
var party_cooldowns: Dictionary = {}
var party_max_cooldowns: Dictionary = {}

# 활성 전투 목록
var active_battles: Array = []

# 게임 상태
var is_paused: bool = false


func _ready() -> void:
	_init_party_status()
	print("[GameManager] 초기화 완료")


func _init_party_status() -> void:
	for hero_id in party:
		var hero_data = DataManager.get_hero(hero_id)
		if hero_data.is_empty():
			continue
		
		var max_hp = int(hero_data.get("stats", {}).get("max_hp", 100))
		var base_cd = float(hero_data.get("combat", {}).get("base_cooldown", 2.0))
		
		party_hp[hero_id] = max_hp
		party_max_hp[hero_id] = max_hp
		party_cooldowns[hero_id] = 0.0  # 시작할 때 바로 공격 가능
		party_max_cooldowns[hero_id] = base_cd


func _process(delta: float) -> void:
	if is_paused:
		return
	
	_process_party_cooldowns(delta)


func _process_party_cooldowns(delta: float) -> void:
	for hero_id in party_cooldowns:
		# 죽은 영웅은 스킵
		if int(party_hp.get(hero_id, 0)) <= 0:
			continue
		
		var current_cd = float(party_cooldowns[hero_id])
		
		if current_cd > 0:
			party_cooldowns[hero_id] = maxf(0, current_cd - delta)
		
		# 쿨다운 완료 & 전투 중이면 공격 가능 시그널
		if float(party_cooldowns[hero_id]) <= 0 and active_battles.size() > 0:
			hero_ready_to_attack.emit(hero_id)
			# 쿨다운 리셋
			party_cooldowns[hero_id] = float(party_max_cooldowns[hero_id])


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


func damage_hero(hero_id: String, damage: int) -> void:
	if party_hp.has(hero_id):
		party_hp[hero_id] = maxi(0, int(party_hp[hero_id]) - damage)
		party_status_changed.emit()


func heal_hero(hero_id: String, amount: int) -> void:
	if party_hp.has(hero_id):
		var max_hp = int(party_max_hp.get(hero_id, 100))
		party_hp[hero_id] = mini(max_hp, int(party_hp[hero_id]) + amount)
		party_status_changed.emit()


func is_hero_alive(hero_id: String) -> bool:
	return int(party_hp.get(hero_id, 0)) > 0


func get_alive_heroes() -> Array:
	var alive = []
	for hero_id in party:
		if is_hero_alive(hero_id):
			alive.append(hero_id)
	return alive


func is_party_dead() -> bool:
	return get_alive_heroes().is_empty()


func get_cooldown_percent(hero_id: String) -> float:
	var current = float(party_cooldowns.get(hero_id, 0))
	var max_cd = float(party_max_cooldowns.get(hero_id, 1))
	return (max_cd - current) / max_cd
