extends Node
## ATBManager: 중앙 ATB 관리 시스템 (자동 공격)
## - 모든 영웅의 ATB를 중앙에서 관리
## - 적 ATB는 각 전투창에서 관리
## - 영웅 ATB가 차면 자동으로 공격

signal hero_atb_ready(hero: Hero)  # 영웅 ATB 충전 완료
signal hero_action_completed(hero: Hero)  # 영웅 행동 완료
signal action_executed  # 액션 실행됨
signal atb_updated  # ATB 업데이트됨 (UI 갱신용)

# ATB 설정
const ATB_MAX: float = 100.0
const ATB_FILL_RATE: float = 30.0  # 기본 충전 속도
const ALLY_SPEED_MULT: float = 2.0  # 아군 속도 배율 (2배)

# 영웅 ATB 상태
var hero_atb: Dictionary = {}  # hero_id -> {hero: Hero, atb: float, speed: int}
var is_paused: bool = false  # 타겟 선택 중 일시정지
var is_processing_action: bool = false  # 액션 처리 중


func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if is_paused or is_processing_action:
		return

	# 활성 전투가 없으면 ATB 충전 안함
	if BattleManager.get_active_battle_count() == 0:
		return

	_update_hero_atb(delta)


func initialize_battle() -> void:
	## 전투 시작 시 영웅 ATB 초기화
	hero_atb.clear()
	is_paused = false
	is_processing_action = false

	var heroes := PartyManager.get_alive_heroes()
	for hero in heroes:
		var hero_dex: int = hero.get_dex()
		var initial_atb: float = randf_range(0, 30) + hero_dex * 0.5
		hero_atb[hero.id] = {
			"hero": hero,
			"atb": minf(initial_atb, ATB_MAX - 1),
			"speed": hero_dex
		}


func reset() -> void:
	## ATB 시스템 리셋
	hero_atb.clear()
	is_paused = false
	is_processing_action = false


func get_hero_atb(hero_id: String) -> float:
	## 특정 영웅의 ATB 값 반환
	if hero_atb.has(hero_id):
		return hero_atb[hero_id]["atb"]
	return 0.0


func get_hero_atb_percent(hero_id: String) -> float:
	## 특정 영웅의 ATB 퍼센트 반환 (0.0 ~ 1.0)
	return get_hero_atb(hero_id) / ATB_MAX


func get_all_hero_atb() -> Dictionary:
	## 모든 영웅 ATB 반환
	return hero_atb


func set_paused(paused: bool) -> void:
	## ATB 일시정지/재개
	is_paused = paused


func _sync_party_heroes() -> void:
	## 파티 영웅과 ATB 목록 동기화 (새 영웅 추가)
	var heroes := PartyManager.get_alive_heroes()
	for hero in heroes:
		if not hero_atb.has(hero.id):
			var hero_dex: int = hero.get_dex()
			var initial_atb: float = randf_range(0, 30) + hero_dex * 0.5
			hero_atb[hero.id] = {
				"hero": hero,
				"atb": minf(initial_atb, ATB_MAX - 1),
				"speed": hero_dex
			}


func _update_hero_atb(delta: float) -> void:
	## 영웅 ATB 업데이트
	# 새 영웅이 파티에 추가되었으면 ATB에 등록
	_sync_party_heroes()

	var ready_hero: Hero = null
	var highest_atb: float = 0.0

	for hero_id in hero_atb:
		var data: Dictionary = hero_atb[hero_id]
		var hero: Hero = data["hero"]

		# 죽은 영웅은 스킵
		if hero.is_dead:
			continue

		# ATB 충전 (아군은 2배 속도)
		if data["atb"] < ATB_MAX:
			var speed: int = data["speed"]
			var fill_amount: float = ATB_FILL_RATE * (speed / 10.0) * ALLY_SPEED_MULT * delta
			data["atb"] = minf(data["atb"] + fill_amount, ATB_MAX)

		# 가장 높은 ATB를 가진 준비된 영웅 찾기
		if data["atb"] >= ATB_MAX and data["atb"] > highest_atb:
			highest_atb = data["atb"]
			ready_hero = hero

	# ATB 업데이트 시그널 발송 (UI 갱신용)
	atb_updated.emit()

	# 준비된 영웅이 있으면 자동 공격
	if ready_hero != null:
		_execute_auto_attack(ready_hero)


func _execute_auto_attack(hero: Hero) -> void:
	## 영웅 자동 공격 실행
	is_processing_action = true

	# 모든 전투창 일시정지
	_pause_all_battle_windows(true)

	# 사용 가능한 스킬 선택
	var skill_id: String = _select_best_skill(hero)
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var target_type: String = skill_data.get("target", "single_enemy")

	# 타겟 타입에 따른 처리
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

	# ATB 리셋
	if hero_atb.has(hero.id):
		hero_atb[hero.id]["atb"] = 0.0

	_finish_action()


func _select_best_skill(hero: Hero) -> String:
	## 사용 가능한 최적 스킬 선택 (쿨타임 체크)
	## 우선순위: 특수 스킬 > 기본 공격
	var skills := hero.get_available_skills()

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
	var heroes := PartyManager.get_alive_heroes()
	for hero in heroes:
		var hp_percent: float = float(hero.current_hp) / float(hero.get_max_hp())
		if hp_percent < 0.5:
			return hero
	return null


func _execute_single_attack(hero: Hero, skill_id: String) -> void:
	## 단일 대상 공격 실행
	# 랜덤 타겟 선택
	var target_data: Dictionary = _find_random_enemy()
	if target_data.is_empty():
		return

	var window: BattleWindow = target_data["window"]
	var enemy: BattleEnemy = target_data["enemy"]

	# 해당 전투창에서 공격 실행
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

	var heroes := PartyManager.get_alive_heroes()
	for target in heroes:
		target.heal(heal_amount)

	BattleManager.battle_log_received.emit(
		"%s -> 전체 +%d HP" % [hero.hero_name, heal_amount],
		Color.LIGHT_GREEN
	)


func _find_lowest_hp_ally() -> Hero:
	## 가장 체력 낮은 아군 찾기
	var heroes := PartyManager.get_alive_heroes()
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

	# 배틀 ID 목록을 먼저 복사 (반복 중 수정 방지)
	var battle_ids: Array = BattleManager.active_battles.keys().duplicate()

	# 모든 전투창의 적 공격
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

			# 적 사망 처리
			if not enemy.is_alive():
				window.on_enemy_defeated(enemy)

	# 로그 전송
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


func _finish_action() -> void:
	## 행동 완료 처리
	is_processing_action = false
	is_paused = false

	# 모든 전투창 재개
	_pause_all_battle_windows(false)

	action_executed.emit()


func _pause_all_battle_windows(paused: bool) -> void:
	## 모든 전투창 일시정지/재개
	var battle_ids: Array = BattleManager.active_battles.keys().duplicate()
	for battle_id in battle_ids:
		if not BattleManager.active_battles.has(battle_id):
			continue

		var battle_data: Dictionary = BattleManager.active_battles[battle_id]
		var window = battle_data.get("window")
		if window and is_instance_valid(window):
			window.set_atb_paused(paused)


func on_hero_died(hero: Hero) -> void:
	## 영웅 사망 시 ATB에서 제거
	if hero_atb.has(hero.id):
		hero_atb[hero.id]["atb"] = 0.0


func on_hero_revived(hero: Hero) -> void:
	## 영웅 부활 시 ATB 재초기화
	if hero_atb.has(hero.id):
		hero_atb[hero.id]["atb"] = 0.0
		hero_atb[hero.id]["speed"] = hero.get_dex()
