extends Node
## ATBManager: 턴제 전투 관리 시스템
## - 모든 유닛(영웅+적)의 턴을 DEX 기반으로 정렬
## - 높은 DEX = 먼저 행동
## - 매 라운드 턴 순서 재계산

signal action_executed  # 액션 실행됨
signal round_started(round_number: int)  # 새 라운드 시작

# 턴 설정
const TURN_DELAY: float = 0.4  # 턴 사이 딜레이 (초)

# 턴 상태
var turn_queue: Array = []  # [{type, unit, window, dex}]
var current_turn_index: int = 0
var current_round: int = 0
var is_processing_turn: bool = false
var is_active: bool = false


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	if not is_active or is_processing_turn:
		return

	if BattleManager.get_active_battle_count() == 0:
		return

	_process_next_turn()


func initialize_battle() -> void:
	## 전투 시작 시 턴 시스템 초기화
	is_active = true
	is_processing_turn = false
	current_round = 0
	_start_new_round()


func reset() -> void:
	## 턴 시스템 리셋
	turn_queue.clear()
	current_turn_index = 0
	current_round = 0
	is_processing_turn = false
	is_active = false


func set_paused(paused: bool) -> void:
	## 턴 시스템 일시정지/재개
	is_active = not paused


func _start_new_round() -> void:
	## 새 라운드 시작: 턴 순서 재계산
	current_round += 1
	_build_turn_order()
	current_turn_index = 0
	round_started.emit(current_round)


func _build_turn_order() -> void:
	## 모든 유닛의 턴 순서를 DEX 기반으로 정렬
	turn_queue.clear()

	# 살아있는 영웅 추가
	var heroes: Array = PartyManager.get_alive_heroes()
	for hero in heroes:
		turn_queue.append({
			"type": "hero",
			"unit": hero,
			"window": null,
			"dex": hero.get_dex()
		})

	# 모든 전투창의 살아있는 적 추가
	var battle_ids: Array = BattleManager.active_battles.keys().duplicate()
	for battle_id in battle_ids:
		if not BattleManager.active_battles.has(battle_id):
			continue
		var battle_data: Dictionary = BattleManager.active_battles[battle_id]
		var window = battle_data.get("window")
		if window == null or not is_instance_valid(window):
			continue
		var enemies: Array = window.get_alive_enemies()
		for enemy in enemies:
			if enemy != null and is_instance_valid(enemy):
				turn_queue.append({
					"type": "enemy",
					"unit": enemy,
					"window": window,
					"dex": enemy.get_dex()
				})

	# DEX 기준 내림차순 정렬 (동률이면 랜덤)
	turn_queue.sort_custom(_compare_turn_priority)


func _compare_turn_priority(a: Dictionary, b: Dictionary) -> bool:
	## DEX 높은 순으로 정렬
	if a["dex"] != b["dex"]:
		return a["dex"] > b["dex"]
	return randf() > 0.5


func _process_next_turn() -> void:
	## 다음 턴 처리
	if turn_queue.is_empty() or current_turn_index >= turn_queue.size():
		_start_new_round()
		return

	is_processing_turn = true
	var turn_data: Dictionary = turn_queue[current_turn_index]
	current_turn_index += 1

	if turn_data["type"] == "hero":
		var hero: Hero = turn_data["unit"]
		if hero == null or hero.is_dead:
			is_processing_turn = false
			return
		await _execute_hero_turn(hero)
	else:
		var enemy: BattleEnemy = turn_data["unit"]
		var window: BattleWindow = turn_data["window"]
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			is_processing_turn = false
			return
		if window == null or not is_instance_valid(window):
			is_processing_turn = false
			return
		await _execute_enemy_turn(enemy, window)

	# 전투가 끝났는지 확인
	if BattleManager.get_active_battle_count() == 0:
		is_processing_turn = false
		return

	# 턴 사이 딜레이
	await get_tree().create_timer(TURN_DELAY).timeout
	is_processing_turn = false
	action_executed.emit()


func _execute_hero_turn(hero: Hero) -> void:
	## 영웅 턴 실행
	BattleManager.turn_changed.emit(hero.hero_name, true)

	var skill_id: String = _select_best_skill(hero)
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var target_type: String = skill_data.get("target", "single_enemy")

	match target_type:
		"single_ally":
			_execute_ally_heal(hero, skill_id)
		"all_allies":
			_execute_ally_heal_all(hero, skill_id)
		"all_enemies":
			_execute_aoe_attack(hero, skill_id)
		_:  # single_enemy
			await _execute_single_attack(hero, skill_id)

	# 쿨타임 시작
	CooldownManager.start_cooldown(hero.id, skill_id)


func _execute_enemy_turn(enemy: BattleEnemy, window: BattleWindow) -> void:
	## 적 턴 실행 (해당 전투창에서 처리)
	if window.current_state != BattleWindow.BattleState.RUNNING:
		return
	BattleManager.turn_changed.emit(enemy.enemy_name, false)
	await window.execute_enemy_turn(enemy)


func _select_best_skill(hero: Hero) -> String:
	## 사용 가능한 최적 스킬 선택 (쿨타임 체크)
	## 우선순위: 특수 스킬 > 기본 공격
	var skills: Array = hero.get_available_skills()

	# 힐러 클래스면 아군 체력 체크
	if hero.class_id in ["cleric"]:
		var low_hp_ally := _find_low_hp_ally()
		if low_hp_ally != null:
			# 힐 스킬 찾기
			for skill_id in skills:
				var cooldown: float = CooldownManager.get_remaining_cooldown(hero.id, skill_id)
				if cooldown > 0:
					continue

				var skill_data: Dictionary = DataManager.get_skill(skill_id)
				if skill_data.get("type", "") == "heal":
					return skill_id

	# 1차: 특수 스킬 우선 (기본 공격 제외, 쿨타임 없는 것)
	for skill_id in skills:
		if skill_id == "basic_attack":
			continue
		# 토글 OFF면 스킵
		if not hero.is_skill_enabled(skill_id):
			continue
		var cooldown: float = CooldownManager.get_remaining_cooldown(hero.id, skill_id)
		if cooldown <= 0:
			return skill_id

	# 2차: 기본 공격 (쿨타임 체크)
	var basic_cooldown: float = CooldownManager.get_remaining_cooldown(hero.id, "basic_attack")
	if basic_cooldown <= 0:
		return "basic_attack"

	# 모두 쿨타임이면 기본 공격 강제 사용 (대기 방지)
	return "basic_attack"


func _find_low_hp_ally() -> Hero:
	## HP가 50% 이하인 아군 찾기
	var heroes: Array = PartyManager.get_alive_heroes()
	for hero in heroes:
		var hp_percent: float = float(hero.current_hp) / float(hero.get_max_hp())
		if hp_percent < 0.5:
			return hero
	return null


func _execute_single_attack(hero: Hero, skill_id: String) -> void:
	## 단일 대상 공격 실행
	var target_data: Dictionary = _find_random_enemy()
	if target_data.is_empty():
		return

	var window: BattleWindow = target_data["window"]
	var enemy: BattleEnemy = target_data["enemy"]

	await window.execute_hero_attack(hero, skill_id, enemy)


func _find_random_enemy() -> Dictionary:
	## 모든 전투창에서 랜덤 적 찾기
	var all_enemies: Array = []

	var battle_ids: Array = BattleManager.active_battles.keys().duplicate()
	for battle_id in battle_ids:
		if not BattleManager.active_battles.has(battle_id):
			continue

		var battle_data: Dictionary = BattleManager.active_battles[battle_id]
		var window = battle_data.get("window")
		if window == null or not is_instance_valid(window):
			continue

		var enemies: Array = window.get_alive_enemies()
		for enemy in enemies:
			if enemy != null and is_instance_valid(enemy):
				all_enemies.append({"window": window, "enemy": enemy})

	if all_enemies.is_empty():
		return {}

	return all_enemies[randi() % all_enemies.size()]


func _execute_ally_heal(hero: Hero, skill_id: String) -> void:
	## 아군 힐 (가장 체력 낮은 대상)
	var target: Hero = _find_lowest_hp_ally()
	if target == null:
		return

	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var base_value: int = int(skill_data.get("base_damage", 20))
	var scaling: float = skill_data.get("scaling", 1.0)
	var int_stat: int = hero.get_int()
	var heal_amount: int = int(base_value + int_stat * scaling)

	target.heal(heal_amount)

	BattleManager.battle_log_received.emit(
		"%s -> %s +%d HP" % [hero.hero_name, target.hero_name, heal_amount],
		Color.LIGHT_GREEN
	)


func _execute_ally_heal_all(hero: Hero, skill_id: String) -> void:
	## 전체 아군 힐
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var base_value: int = int(skill_data.get("base_damage", 20))
	var scaling: float = skill_data.get("scaling", 1.0)
	var int_stat: int = hero.get_int()
	var heal_amount: int = int(base_value + int_stat * scaling)

	var heroes: Array = PartyManager.get_alive_heroes()
	for target in heroes:
		target.heal(heal_amount)

	BattleManager.battle_log_received.emit(
		"%s -> 전체 +%d HP" % [hero.hero_name, heal_amount],
		Color.LIGHT_GREEN
	)


func _find_lowest_hp_ally() -> Hero:
	## 가장 체력 낮은 아군 찾기
	var heroes: Array = PartyManager.get_alive_heroes()
	var lowest_hero: Hero = null
	var lowest_percent: float = 1.0

	for hero in heroes:
		var hp_percent: float = float(hero.current_hp) / float(hero.get_max_hp())
		if hp_percent < lowest_percent:
			lowest_percent = hp_percent
			lowest_hero = hero

	return lowest_hero


func _execute_aoe_attack(hero: Hero, skill_id: String) -> void:
	## 전체 공격 스킬 실행 (모든 전투창의 적에게)
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var total_damage: int = 0
	var enemies_hit: int = 0

	var battle_ids: Array = BattleManager.active_battles.keys().duplicate()

	for battle_id in battle_ids:
		if not BattleManager.active_battles.has(battle_id):
			continue

		var battle_data: Dictionary = BattleManager.active_battles[battle_id]
		var window = battle_data.get("window")
		if window == null or not is_instance_valid(window):
			continue

		var enemies: Array = window.get_alive_enemies()
		for enemy in enemies:
			if enemy == null or not is_instance_valid(enemy):
				continue

			var damage: int = _calculate_damage(hero, enemy, skill_data)
			enemy.take_damage(damage)
			total_damage += damage
			enemies_hit += 1

			if not enemy.is_alive():
				window.on_enemy_defeated(enemy)

	if enemies_hit > 0:
		BattleManager.battle_log_received.emit(
			"%s %s! %d x %d" % [
				hero.hero_name,
				skill_data.get("name", "공격"),
				enemies_hit,
				total_damage / maxi(1, enemies_hit)
			],
			Color.ORANGE
		)


func _calculate_damage(attacker: Hero, target: BattleEnemy, skill_data: Dictionary) -> int:
	## 데미지 계산
	var damage_type: String = skill_data.get("damage_type", "physical")
	var base_damage: int = int(skill_data.get("base_damage", 10))
	var scaling: float = skill_data.get("scaling", 1.0)

	var atk_stat: int = 0
	var def_stat: int = target.get_p_def()

	if damage_type == "magic":
		atk_stat = attacker.get_int()
		def_stat = target.get_m_def()
	else:
		atk_stat = attacker.get_str()

	var raw_damage: int = int(base_damage + atk_stat * scaling)
	var final_damage: int = maxi(1, raw_damage - def_stat / 2)

	# 크리티컬 체크
	var crit_chance: float = attacker.get_luk() / 100.0
	if randf() < crit_chance:
		final_damage = int(final_damage * 1.5)

	return final_damage


func on_hero_died(_hero: Hero) -> void:
	## 영웅 사망 시 처리 (턴 큐에서 자동 스킵됨)
	pass


func on_hero_revived(_hero: Hero) -> void:
	## 영웅 부활 시 처리 (다음 라운드에 자동 포함)
	pass
