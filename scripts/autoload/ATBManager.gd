extends Node
## ATBManager: Will 충전 중앙 관리 + 액션 시그널 허브
## - 영웅의 Will 게이지를 전투 중에만 중앙에서 충전
## - 적의 Will은 각 전투창이 독립적으로 관리

signal action_executed  # 액션 실행됨 (RightPartyPanel 쿨다운 업데이트용)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	# 전투 중에만 영웅 Will 충전 (전투창과 무관하게 중앙 관리)
	if get_tree().paused:
		return
	if not BattleManager or BattleManager.get_active_battle_count() == 0:
		return
	_update_hero_will(delta)


func _update_hero_will(delta: float) -> void:
	## 살아있는 영웅의 Will을 동일 속도로 충전
	if not PartyManager:
		return
	for hero in PartyManager.get_alive_heroes():
		if hero.will_value < float(Hero.WILL_MAX):
			hero.will_value = minf(hero.will_value + Hero.WILL_FILL_PER_SEC * delta, float(Hero.WILL_MAX))


func initialize_battle() -> void:
	## 레거시 호환 (각 전투창이 자체적으로 턴 시작)
	pass


func reset() -> void:
	## 레거시 호환
	pass


func set_paused(_paused: bool) -> void:
	## 레거시 호환
	pass
