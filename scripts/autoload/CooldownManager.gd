extends Node
## CooldownManager: 스킬 쿨다운 상태 조회 래퍼
## 실제 타이머는 Hero.skill_cooldowns + ATBManager가 관리


func _process(_delta: float) -> void:
	# 쿨다운 틱은 ATBManager가 담당, 여기선 아무것도 안 함
	pass


func start_cooldown(hero_id: String, skill_id: String) -> void:
	## 스킬 사용 후 쿨다운 시작
	if PartyManager == null:
		return
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero == null:
		return
	hero.start_skill_cooldown(skill_id)


func is_skill_ready(hero_id: String, skill_id: String) -> bool:
	## 스킬 쿨다운 완료 여부
	if PartyManager == null:
		return true
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero == null:
		return true
	return hero.is_skill_off_cooldown(skill_id)


func get_remaining_cooldown(hero_id: String, skill_id: String) -> float:
	## 남은 쿨다운 시간 (초)
	if PartyManager == null:
		return 0.0
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero == null:
		return 0.0
	return float(hero.skill_cooldowns.get(skill_id, 0.0))


func get_cooldown_percent(hero_id: String, skill_id: String) -> float:
	## 쿨다운 진행률 반전 (0.0 = 준비완료, 1.0 = 쿨다운 시작)
	if PartyManager == null:
		return 0.0
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero == null:
		return 0.0
	return 1.0 - hero.get_skill_cooldown_percent(skill_id)


func reset_all_cooldowns() -> void:
	## 모든 쿨타임 초기화
	if PartyManager == null:
		return
	for hero in PartyManager.get_party():
		if hero != null:
			hero.reset_all_skill_cooldowns()


func reset_hero_cooldowns(hero_id: String) -> void:
	## 특정 용사의 쿨타임 초기화
	if PartyManager == null:
		return
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero != null:
		hero.reset_all_skill_cooldowns()
