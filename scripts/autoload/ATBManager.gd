extends Node
## ATBManager: 영웅 행동 타이머 중앙 관리 + 액션 시그널 허브
## - 영웅의 행동 타이머를 전투 여부와 무관하게 상시 충전
## - 적의 행동 타이머는 각 전투창이 독립적으로 관리

signal action_executed  # 액션 실행됨 (RightPartyPanel 쿨다운 업데이트용)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	# 전투 유무와 무관하게 영웅 행동 타이머 충전
	if get_tree().paused:
		return
	_update_hero_timers(delta)


func _update_hero_timers(delta: float) -> void:
	## 살아있는 영웅의 행동 타이머를 액션 딜레이 기준으로 충전
	if not PartyManager:
		return
	var has_active_battle: bool = BattleManager != null and BattleManager.get_active_battle_count() > 0
	for hero in PartyManager.get_alive_heroes():
		var delay: float = maxf(0.001, hero.get_action_delay())
		var skill_delay: float = maxf(0.001, hero.get_skill_action_delay())
		if has_active_battle:
			if not hero.is_action_ready():
				hero.action_timer = minf(hero.action_timer + delta, delay)
			if not hero.is_skill_action_ready():
				hero.skill_action_timer = minf(hero.skill_action_timer + delta, skill_delay)
		else:
			# 필드에서는 UI 표현용으로 ATB를 순환시킨다.
			hero.action_timer += delta
			if hero.action_timer >= delay:
				hero.action_timer = fmod(hero.action_timer, delay)
			hero.skill_action_timer += delta
			if hero.skill_action_timer >= skill_delay:
				hero.skill_action_timer = fmod(hero.skill_action_timer, skill_delay)


func initialize_battle() -> void:
	## 레거시 호환
	pass


func reset() -> void:
	## 레거시 호환
	pass


func set_paused(_paused: bool) -> void:
	## 레거시 호환
	pass
