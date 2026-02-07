extends Node
## CooldownManager: 글로벌 스킬 쿨타임 관리
## 전투창과 무관하게 공용으로 쿨타임이 흐름

# 쿨타임 데이터: {hero_id: {skill_id: remaining_time}}
var cooldowns: Dictionary = {}


func _process(delta: float) -> void:
	_update_cooldowns(delta)


func _update_cooldowns(delta: float) -> void:
	## 모든 쿨타임 감소
	for hero_id in cooldowns.keys():
		var hero_cooldowns: Dictionary = cooldowns[hero_id]
		var skills_to_remove: Array = []

		for skill_id in hero_cooldowns.keys():
			hero_cooldowns[skill_id] -= delta
			if hero_cooldowns[skill_id] <= 0:
				skills_to_remove.append(skill_id)

		for skill_id in skills_to_remove:
			hero_cooldowns.erase(skill_id)


func start_cooldown(hero_id: String, skill_id: String) -> void:
	## 스킬 쿨타임 시작
	var cooldown_time: float = DataManager.get_skill_cooldown(skill_id)
	if cooldown_time <= 0:
		return

	if not cooldowns.has(hero_id):
		cooldowns[hero_id] = {}

	cooldowns[hero_id][skill_id] = cooldown_time


func is_skill_ready(hero_id: String, skill_id: String) -> bool:
	## 스킬 사용 가능 여부 (쿨타임 없음)
	if not cooldowns.has(hero_id):
		return true
	if not cooldowns[hero_id].has(skill_id):
		return true
	return cooldowns[hero_id][skill_id] <= 0


func get_remaining_cooldown(hero_id: String, skill_id: String) -> float:
	## 남은 쿨타임 반환
	if not cooldowns.has(hero_id):
		return 0.0
	if not cooldowns[hero_id].has(skill_id):
		return 0.0
	return maxf(0.0, cooldowns[hero_id][skill_id])


func get_cooldown_percent(hero_id: String, skill_id: String) -> float:
	## 쿨타임 진행률 (0.0 = 준비완료, 1.0 = 막 시작)
	var remaining := get_remaining_cooldown(hero_id, skill_id)
	if remaining <= 0:
		return 0.0
	var total: float = DataManager.get_skill_cooldown(skill_id)
	if total <= 0:
		return 0.0
	return remaining / total


func reset_all_cooldowns() -> void:
	## 모든 쿨타임 초기화
	cooldowns.clear()


func reset_hero_cooldowns(hero_id: String) -> void:
	## 특정 영웅의 쿨타임 초기화
	if cooldowns.has(hero_id):
		cooldowns.erase(hero_id)
