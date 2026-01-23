extends PanelContainer
class_name BattleWindow
## BattleWindow: 드래곤퀘스트 스타일 1인칭 전투창
## - 적만 보이는 1인칭 뷰 (로그는 FieldHUD로 전달)
## - 라운드 기반 자동 턴제 전투

signal battle_ended(battle_id: int, victory: bool)
signal battle_log(message: String, color: Color)  # FieldHUD로 로그 전달
signal party_updated  # 파티 HP/MP 변경 알림

enum BattleState { STARTING, PLAYER_PHASE, ENEMY_PHASE, VICTORY, DEFEAT, ESCAPED, ENDED }

# === 전투 식별 ===
var battle_id: int = -1
var is_boss_battle: bool = false

# === 전투 상태 ===
var current_state: BattleState = BattleState.STARTING
var current_round: int = 0
var turn_order: Array = []
var current_turn_index: int = 0

# === 전투 참가자 ===
var enemies: Array = []
var enemy_data_list: Array = []

# === 보상 ===
var total_exp: int = 0
var total_gold: int = 0
var drop_items: Array = []

# === UI 참조 ===
var enemy_container: HBoxContainer
var run_button: Button
var close_button: Button

# === 설정 ===
const BASE_ESCAPE_RATE: float = 40.0
const ACTION_DELAY: float = 1.0  # 0.35 → 0.5 (모션 보이게)

var _ui_built: bool = false


func _ready() -> void:
	if not _ui_built:
		_build_ui()
	visible = false


#region UI 구성
func _build_ui() -> void:
	if _ui_built:
		return
	_ui_built = true
	
	custom_minimum_size = Vector2(240, 140)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 4)
	add_child(main_vbox)
	
	# 상단: 닫기 버튼만
	var top_bar := HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(top_bar)
	
	close_button = Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(24, 24)
	close_button.visible = false
	close_button.pressed.connect(_on_close_pressed)
	top_bar.add_child(close_button)
	
	# 전투 영역 (적 표시)
	var battle_area := PanelContainer.new()
	battle_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(battle_area)
	
	enemy_container = HBoxContainer.new()
	enemy_container.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_container.add_theme_constant_override("separation", 12)
	battle_area.add_child(enemy_container)
	
	# 하단: 도주 버튼
	var bottom_bar := HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(bottom_bar)
	
	run_button = Button.new()
	run_button.text = "도주"
	run_button.custom_minimum_size = Vector2(50, 24)
	run_button.pressed.connect(_on_run_pressed)
	bottom_bar.add_child(run_button)
#endregion


#region 전투 초기화
var is_elite_battle: bool = false

func setup(p_battle_id: int, enemy_ids: Array, p_is_elite: bool = false) -> void:
	if not _ui_built:
		_build_ui()
	
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	is_elite_battle = p_is_elite
	
	is_boss_battle = _check_is_boss_battle(enemy_ids)
	run_button.disabled = is_boss_battle
	
	_spawn_enemies(enemy_ids)
	
	# 엘리트 전투면 배경색 변경
	if is_elite_battle:
		var bg: Panel = get_node_or_null("Panel")
		if bg:
			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.1, 0.3, 0.95)  # 보라색 배경
			bg.add_theme_stylebox_override("panel", style)
	
	visible = true
	current_state = BattleState.STARTING
	
	# 바로 전투 시작
	await get_tree().create_timer(0.3).timeout
	_start_round()


func _check_is_boss_battle(enemy_ids: Array) -> bool:
	for enemy_id in enemy_ids:
		var data: Dictionary = DataManager.get_enemy(str(enemy_id))
		if data.get("type", "") == "boss":
			return true
	return false


func _spawn_enemies(enemy_ids: Array) -> void:
	for child in enemy_container.get_children():
		child.queue_free()
	enemies.clear()
	
	var spawned_elite: bool = false
	
	for enemy_id in enemy_ids:
		var battle_enemy := BattleEnemy.new()
		
		# 엘리트 전투에서 첫 번째 적은 엘리트 버전으로
		if is_elite_battle and not spawned_elite:
			battle_enemy.setup(str(enemy_id), true)  # 엘리트로 스폰
			spawned_elite = true
		else:
			battle_enemy.setup(str(enemy_id), false)
		
		enemy_container.add_child(battle_enemy)
		enemies.append(battle_enemy)


func _get_enemy_name(enemy_id: String) -> String:
	var data: Dictionary = DataManager.get_enemy(enemy_id)
	return str(data.get("name", enemy_id))
#endregion


#region 라운드 진행
var _battle_timer: Timer


func _start_round() -> void:
	current_round += 1
	_calculate_turn_order()
	current_turn_index = 0
	_schedule_next_turn()


func _schedule_next_turn() -> void:
	# Timer를 사용하여 다음 턴 예약 (while+await 대신)
	if _battle_timer == null:
		_battle_timer = Timer.new()
		_battle_timer.one_shot = true
		_battle_timer.timeout.connect(_process_scheduled_turn)
		add_child(_battle_timer)
	
	_battle_timer.start(ACTION_DELAY)


func _stop_battle_timer() -> void:
	# 타이머 정지 및 정리
	if _battle_timer != null and is_instance_valid(_battle_timer):
		_battle_timer.stop()


func _process_scheduled_turn() -> void:
	print("[BattleWindow] _process_scheduled_turn 시작 - state:", current_state, " turn:", current_turn_index)
	
	# 이미 종료된 전투면 무시
	if current_state == BattleState.VICTORY or current_state == BattleState.DEFEAT or current_state == BattleState.ENDED:
		print("[BattleWindow] 이미 종료됨, 리턴")
		return
	
	# 전투 종료 체크
	if _check_battle_end():
		print("[BattleWindow] 전투 종료됨")
		return
	
	# 라운드 끝 체크 - 새 라운드 시작
	if current_turn_index >= turn_order.size():
		print("[BattleWindow] 새 라운드 시작")
		current_round += 1
		_calculate_turn_order()
		current_turn_index = 0
	
	# 참가자가 없으면 종료
	if turn_order.is_empty():
		print("[BattleWindow] turn_order 비어있음")
		_check_battle_end()  # 강제로 종료 체크
		return
	
	# 인덱스 범위 체크
	if current_turn_index >= turn_order.size():
		print("[BattleWindow] 인덱스 초과")
		return
	
	# 현재 턴 처리
	var turn_data: Dictionary = turn_order[current_turn_index]
	current_turn_index += 1
	print("[BattleWindow] 턴 처리:", turn_data["type"])
	
	if turn_data["type"] == "hero":
		_process_hero_turn(turn_data["ref"])
	else:
		_process_enemy_turn(turn_data["ref"])
	
	print("[BattleWindow] 턴 처리 완료, 다음 턴 예약")
	
	# 다음 턴 예약 (아직 전투 중일 때만)
	if current_state != BattleState.VICTORY and current_state != BattleState.DEFEAT:
		_schedule_next_turn()
	
	print("[BattleWindow] _process_scheduled_turn 끝")


func _calculate_turn_order() -> void:
	turn_order.clear()
	
	var party := PartyManager.get_alive_heroes()
	for hero in party:
		turn_order.append({
			"type": "hero", 
			"ref": hero, 
			"spd": hero.get_spd(),
			"sort_key": hero.get_spd() * 10000 + randi() % 10000  # 정수 정렬키
		})
	
	for enemy in enemies:
		if enemy.is_alive():
			turn_order.append({
				"type": "enemy", 
				"ref": enemy, 
				"spd": enemy.get_spd(),
				"sort_key": enemy.get_spd() * 10000 + randi() % 10000
			})
	
	# 빈 배열이면 정렬 스킵
	if turn_order.size() <= 1:
		return
	
	# 정수 키로 정렬 (내림차순)
	turn_order.sort_custom(_compare_turn_order)


func _compare_turn_order(a: Dictionary, b: Dictionary) -> bool:
	# 정수 비교만 사용 (부동소수점 문제 방지)
	return a["sort_key"] > b["sort_key"]


func _process_hero_turn(hero: Hero) -> void:
	print("[BattleWindow] _process_hero_turn 시작 - hero:", hero.hero_name if hero else "null")
	if hero == null or hero.is_dead:
		print("[BattleWindow] hero가 null이거나 사망함, 리턴")
		return
	
	current_state = BattleState.PLAYER_PHASE
	
	print("[BattleWindow] 살아있는 적 필터링...")
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)
	print("[BattleWindow] 살아있는 적 수:", alive_enemies.size())
	
	if alive_enemies.is_empty():
		print("[BattleWindow] 적이 없음, 리턴")
		return
	
	print("[BattleWindow] 타겟 선택...")
	var target: BattleEnemy = _select_smart_target(hero, alive_enemies)
	print("[BattleWindow] 타겟:", target.enemy_name if target else "null")
	_execute_hero_action(hero, target)
	print("[BattleWindow] _process_hero_turn 끝")


func _process_enemy_turn(enemy: BattleEnemy) -> void:
	if not enemy.is_alive():
		return
	
	current_state = BattleState.ENEMY_PHASE
	
	var alive_heroes := PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	var target: Hero = alive_heroes[randi() % alive_heroes.size()]
	_execute_enemy_action(enemy, target)
#endregion


#region 전투 행동
func _select_smart_target(hero: Hero, alive_enemies: Array) -> BattleEnemy:
	print("[BattleWindow] _select_smart_target 시작")
	var atk := hero.get_atk()
	print("[BattleWindow] hero atk:", atk)
	
	for enemy in alive_enemies:
		if enemy == null:
			continue
		var expected_damage := _calculate_damage(atk, enemy.get_p_def())
		print("[BattleWindow] 적:", enemy.enemy_name, "예상 데미지:", expected_damage, "적 HP:", enemy.current_hp)
		if expected_damage >= enemy.current_hp:
			print("[BattleWindow] 처치 가능한 적 발견")
			return enemy
	
	var idx := randi() % alive_enemies.size()
	print("[BattleWindow] 랜덤 타겟 선택, idx:", idx)
	return alive_enemies[idx]


func _execute_hero_action(hero: Hero, target: BattleEnemy) -> void:
	print("[BattleWindow] _execute_hero_action 시작")
	if hero == null or target == null:
		print("[BattleWindow] hero 또는 target이 null!")
		return
	
	var atk := hero.get_atk()
	print("[BattleWindow] hero atk:", atk)
	var is_crit := randf() * 100 < hero.get_crit()
	print("[BattleWindow] is_crit:", is_crit)
	var is_evaded := randf() * 100 < target.get_eva()
	print("[BattleWindow] is_evaded:", is_evaded)
	
	if is_evaded:
		print("[BattleWindow] 회피 처리")
		_send_log("%s → %s 회피!" % [hero.hero_name, target.enemy_name], Color.GRAY)
		print("[BattleWindow] play_evade_effect 호출")
		target.play_evade_effect()
		target.show_miss_text()
		print("[BattleWindow] play_evade_effect 완료")
	else:
		print("[BattleWindow] 데미지 계산")
		var damage := _calculate_damage(atk, target.get_p_def(), is_crit)
		print("[BattleWindow] damage:", damage)
		target.take_damage(damage)
		print("[BattleWindow] take_damage 완료")
		
		# 데미지 숫자 표시
		target.show_damage_number(damage, is_crit)
		
		if is_crit:
			_send_log("%s → %s에게 %d! (크리티컬)" % [hero.hero_name, target.enemy_name, damage], Color.ORANGE)
			print("[BattleWindow] play_hit_effect(crit) 호출")
			target.play_hit_effect(true)
		else:
			_send_log("%s → %s에게 %d" % [hero.hero_name, target.enemy_name, damage], Color.WHITE)
			print("[BattleWindow] play_hit_effect 호출")
			target.play_hit_effect(false)
		print("[BattleWindow] play_hit_effect 완료")
		
		if not target.is_alive():
			print("[BattleWindow] 적 처치!")
			_on_enemy_defeated(target)
	
	print("[BattleWindow] _execute_hero_action 끝")


func _execute_enemy_action(enemy: BattleEnemy, target: Hero) -> void:
	print("[BattleWindow] _execute_enemy_action 시작")
	
	# 적 공격 모션
	enemy.play_attack_effect()
	
	var atk := enemy.get_atk()
	print("[BattleWindow] atk:", atk)
	var is_crit := randf() * 100 < enemy.get_crit()
	print("[BattleWindow] is_crit:", is_crit)
	var is_evaded := randf() * 100 < target.get_eva()
	print("[BattleWindow] is_evaded:", is_evaded)
	
	if is_evaded:
		print("[BattleWindow] 회피 처리")
		_send_log("%s → %s 회피!" % [enemy.enemy_name, target.hero_name], Color.GRAY)
	else:
		print("[BattleWindow] 데미지 계산")
		var damage := _calculate_damage(atk, target.get_p_def(), is_crit)
		print("[BattleWindow] damage:", damage)
		
		# PartyManager를 통해 데미지 처리 (party_wiped 시그널 발생)
		PartyManager.on_hero_damaged(target, damage)
		print("[BattleWindow] on_hero_damaged 완료")
		
		# 직접 emit 대신 deferred로 호출
		call_deferred("_emit_party_updated")
		print("[BattleWindow] party_updated deferred 예약")
		
		if is_crit:
			_send_log("%s → %s에게 %d! (강타)" % [enemy.enemy_name, target.hero_name, damage], Color.RED)
		else:
			_send_log("%s → %s에게 %d" % [enemy.enemy_name, target.hero_name, damage], Color.YELLOW)
		print("[BattleWindow] _send_log 완료")
		
		if target.is_dead:
			_send_log("%s 쓰러짐!" % target.hero_name, Color.DARK_RED)
			print("[BattleWindow] 영웅 사망: ", target.hero_name)
			call_deferred("_emit_party_updated")
	
	print("[BattleWindow] _execute_enemy_action 끝")


func _emit_party_updated() -> void:
	party_updated.emit()


func _calculate_damage(atk: int, p_def: int, is_crit: bool = false) -> int:
	if is_crit:
		return maxi(1, atk)
	return maxi(1, atk - int(p_def / 2))
#endregion


#region 적 처치/전투 종료
func _on_enemy_defeated(enemy: BattleEnemy) -> void:
	_send_log("%s 처치!" % enemy.enemy_name, Color.LIME)
	
	total_exp += enemy.exp_reward
	total_gold += enemy.get_gold_reward()
	drop_items.append_array(enemy.roll_drops())
	
	# play_death_effect()는 await을 사용하므로 호출만 하고 기다리지 않음
	# (대기하면 전투 흐름이 너무 느려짐)
	enemy.play_death_effect()


func _check_battle_end() -> bool:
	var alive_enemies: Array = []
	for e in enemies:
		if e != null and e.is_alive():
			alive_enemies.append(e)
	
	var alive_heroes := PartyManager.get_alive_heroes()
	
	if alive_enemies.is_empty():
		_end_battle_victory()
		return true
	
	if alive_heroes.is_empty():
		_end_battle_defeat()
		return true
	
	return false


func _end_battle_victory() -> void:
	current_state = BattleState.VICTORY
	_stop_battle_timer()  # 타이머 정지!
	
	_send_log("승리! EXP +%d, Gold +%d" % [total_exp, total_gold], Color.CYAN)
	
	for item_id in drop_items:
		# 장비인지 소비 아이템인지 구분
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if not equip_data.is_empty():
			var rarity: String = str(equip_data.get("rarity", "common"))
			var item_name: String = str(equip_data.get("name", item_id))
			var color: Color = Color.WHITE
			match rarity:
				"magic": color = Color(0.4, 0.6, 1.0)
				"legendary": color = Color(1.0, 0.7, 0.2)
			_send_log("⚔️ %s 획득!" % item_name, color)
		else:
			var item_data: Dictionary = DataManager.get_item(item_id)
			_send_log("%s 획득!" % str(item_data.get("name", item_id)), Color.YELLOW)
	
	# 보상 지급
	PartyManager.distribute_exp(total_exp)
	GameManager.add_gold(total_gold)
	for item_id in drop_items:
		InventoryManager.add_item(item_id)
	
	call_deferred("_emit_party_updated")
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, true)


func _end_battle_defeat() -> void:
	current_state = BattleState.DEFEAT
	_stop_battle_timer()  # 타이머 정지!
	
	_send_log("전멸...", Color.DARK_RED)
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, false)
#endregion


#region 도주 시스템
func _on_run_pressed() -> void:
	if is_boss_battle or current_state == BattleState.VICTORY or current_state == BattleState.DEFEAT:
		return
	
	run_button.disabled = true
	
	var escape_chance := _calculate_escape_chance()
	var roll := randf() * 100
	
	if roll < escape_chance:
		current_state = BattleState.ESCAPED
		_stop_battle_timer()  # 타이머 정지!
		_send_log("도주 성공!", Color.CYAN)
		run_button.visible = false
		close_button.visible = true
		battle_ended.emit(battle_id, false)
	else:
		_send_log("도주 실패!", Color.GRAY)
		run_button.disabled = false


func _calculate_escape_chance() -> float:
	var party_avg_spd := PartyManager.get_party_average_spd()
	
	var enemy_total_spd: float = 0.0
	var alive_count: int = 0
	for enemy in enemies:
		if enemy.is_alive():
			enemy_total_spd += enemy.get_spd()
			alive_count += 1
	var enemy_avg_spd: float = enemy_total_spd / maxf(1.0, float(alive_count))
	
	var chance := BASE_ESCAPE_RATE + (party_avg_spd - enemy_avg_spd) * 2.0
	return clampf(chance, 5.0, 95.0)
#endregion


#region 로그/이벤트
func _send_log(msg: String, color: Color = Color.WHITE) -> void:
	# 직접 emit (deferred 제거)
	battle_log.emit(msg, color)


func _on_close_pressed() -> void:
	current_state = BattleState.ENDED
	queue_free()
#endregion
