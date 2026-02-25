extends Node
## ATBManager: 영웅 + 적 행동 타이머 중앙 관리 + 액션 시그널 허브
## - 영웅의 행동 타이머를 전투 여부와 무관하게 상시 충전
## - 적의 행동 타이머도 BattleWindow로부터 위임받아 충전

signal action_executed  # 액션 실행됨 (RightPartyPanel 쿨다운 업데이트용)
var BATTLE_ATB_FILL_RATE: float = 0.85


func _ready() -> void:
	set_process(true)
	# formulas.json에서 ATB 충전율 로드
	var atb_f: Dictionary = DataManager.get_formula("atb") as Dictionary
	BATTLE_ATB_FILL_RATE = float(atb_f.get("battle_fill_rate", 0.85))


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_update_hero_timers(delta)


func _update_hero_timers(delta: float) -> void:
	## 살아있는 영웅의 기본공격 타이머를 액션 딜레이 기준으로 충전
	## (스킬은 ATB 무관, 쿨타임만 사용)
	if not PartyManager:
		return
	var has_active_battle: bool = BattleManager != null and BattleManager.get_active_battle_count() > 0
	for hero in PartyManager.get_alive_heroes():
		var delay: float = maxf(0.001, hero.get_action_delay())
		if has_active_battle:
			var battle_delta: float = delta * BATTLE_ATB_FILL_RATE
			if not hero.is_action_ready():
				hero.action_timer = minf(hero.action_timer + battle_delta, delay)
		else:
			# 필드에서는 UI 표현용으로 ATB를 순환시킨다.
			hero.action_timer += delta
			if hero.action_timer >= delay:
				hero.action_timer = fmod(hero.action_timer, delay)


func reset() -> void:
	## 전투 종료 시 영웅 타이머 초기화 (필드 순환 모드로 복귀)
	if PartyManager:
		for hero in PartyManager.get_alive_heroes():
			hero.action_timer = 0.0


func update_enemy_timers(battle_enemies: Array, delta: float, is_paused: bool) -> void:
	## 적 행동 타이머를 중앙에서 충전 (각 BattleWindow가 매 프레임 호출)
	if is_paused:
		return
	var battle_delta: float = delta * BATTLE_ATB_FILL_RATE
	for enemy in battle_enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if not enemy.is_action_ready():
			enemy.action_timer = minf(enemy.action_timer + battle_delta, enemy.get_action_delay())
