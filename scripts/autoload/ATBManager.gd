extends Node
## ATBManager: 영웅 행동 타이머 중앙 관리 + 액션 시그널 허브
## - 영웅의 행동 타이머를 전투 중에만 중앙에서 충전
## - 적의 행동 타이머는 각 전투창이 독립적으로 관리

signal action_executed  # 액션 실행됨 (RightPartyPanel 쿨다운 업데이트용)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	# 전투 중에만 영웅 행동 타이머 충전 (전투창과 무관하게 중앙 관리)
	if get_tree().paused:
		return
	if not BattleManager or BattleManager.get_active_battle_count() == 0:
		return
	_update_hero_timers(delta)


func _update_hero_timers(delta: float) -> void:
	## 살아있는 영웅의 행동 타이머를 민첩에 비례하여 충전
	if not PartyManager:
		return
	for hero in PartyManager.get_alive_heroes():
		if not hero.is_action_ready():
			var dex_mult: float = hero.get_dex() / 10.0
			hero.action_timer = minf(hero.action_timer + Hero.ACTION_FILL_RATE * dex_mult * delta, Hero.ACTION_INTERVAL)


func initialize_battle() -> void:
	## 레거시 호환
	pass


func reset() -> void:
	## 레거시 호환
	pass


func set_paused(_paused: bool) -> void:
	## 레거시 호환
	pass
