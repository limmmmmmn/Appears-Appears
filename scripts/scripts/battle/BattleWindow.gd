extends PanelContainer
class_name BattleWindow
## BattleWindow: 드래곤퀘스트 스타일 1인칭 전투창
## - 적만 보이는 1인칭 뷰
## - 라운드 기반 자동 턴제 전투
## - 동시다발 전투 지원 (여러 창 동시 존재)

signal battle_ended(battle_id: int, victory: bool)
signal battle_rewards(battle_id: int, exp: int, gold: int, drops: Array)

enum BattleState { STARTING, PLAYER_PHASE, ENEMY_PHASE, VICTORY, DEFEAT, ESCAPED, ENDED }

# === 전투 식별 ===
var battle_id: int = -1
var is_boss_battle: bool = false

# === 전투 상태 ===
var current_state: BattleState = BattleState.STARTING
var current_round: int = 0
var turn_order: Array = []  # [{type: "hero"/"enemy", ref: Hero/Enemy, spd: int}, ...]
var current_turn_index: int = 0

# === 전투 참가자 ===
var enemies: Array = []  # Array of BattleEnemy
var enemy_data_list: Array = []  # 원본 적 ID 목록

# === 보상 ===
var total_exp: int = 0
var total_gold: int = 0
var drop_items: Array = []

# === UI 참조 ===
var enemy_container: HBoxContainer
var message_label: RichTextLabel
var run_button: Button
var round_label: Label
var close_button: Button

# === 설정 ===
const BASE_ESCAPE_RATE: float = 40.0
const MESSAGE_DELAY: float = 0.6
const ACTION_DELAY: float = 0.4

var message_queue: Array = []
var is_processing_messages: bool = false


func _ready() -> void:
	_build_ui()
	visible = false


#region UI 구성
func _build_ui() -> void:
	# 패널 스타일
	custom_minimum_size = Vector2(280, 200)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 4)
	add_child(main_vbox)
	
	# 상단: 라운드 표시 + 닫기 버튼
	var top_bar := HBoxContainer.new()
	main_vbox.add_child(top_bar)
	
	round_label = Label.new()
	round_label.text = "Round 1"
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(round_label)
	
	close_button = Button.new()
	close_button.text = "×"
	close_button.custom_minimum_size = Vector2(24, 24)
	close_button.visible = false  # 전투 종료 후에만 표시
	close_button.pressed.connect(_on_close_pressed)
	top_bar.add_child(close_button)
	
	# 전투 영역 (적 표시)
	var battle_area := PanelContainer.new()
	battle_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_area.custom_minimum_size.y = 80
	main_vbox.add_child(battle_area)
	
	# 적 컨테이너 (가로 배치)
	enemy_container = HBoxContainer.new()
	enemy_container.alignment = BoxContainer.ALIGNMENT_CENTER
	enemy_container.add_theme_constant_override("separation", 16)
	battle_area.add_child(enemy_container)
	
	# 메시지 영역
	var message_panel := PanelContainer.new()
	message_panel.custom_minimum_size.y = 50
	main_vbox.add_child(message_panel)
	
	message_label = RichTextLabel.new()
	message_label.bbcode_enabled = true
	message_label.scroll_active = false
	message_label.fit_content = true
	message_label.add_theme_font_size_override("normal_font_size", 11)
	message_panel.add_child(message_label)
	
	# 하단: 도주 버튼
	var bottom_bar := HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(bottom_bar)
	
	run_button = Button.new()
	run_button.text = "도주"
	run_button.custom_minimum_size = Vector2(60, 28)
	run_button.pressed.connect(_on_run_pressed)
	bottom_bar.add_child(run_button)
#endregion


#region 전투 초기화
func setup(p_battle_id: int, enemy_ids: Array) -> void:
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	
	# 보스 체크
	is_boss_battle = _check_is_boss_battle(enemy_ids)
	run_button.disabled = is_boss_battle
	run_button.tooltip_text = "보스전에서는 도주할 수 없다!" if is_boss_battle else ""
	
	# 적 생성
	_spawn_enemies(enemy_ids)
	
	# 초기 메시지
	var first_enemy_name := _get_enemy_name(enemy_ids[0])
	if enemy_ids.size() == 1:
		_queue_message("%s이(가) 나타났다!" % first_enemy_name)
	else:
		_queue_message("%s 외 %d마리가 나타났다!" % [first_enemy_name, enemy_ids.size() - 1])
	
	visible = true
	current_state = BattleState.STARTING
	
	# 첫 라운드 시작
	await get_tree().create_timer(0.5).timeout
	_start_round()


func _check_is_boss_battle(enemy_ids: Array) -> bool:
	for enemy_id in enemy_ids:
		var data: Dictionary = DataManager.get_enemy(str(enemy_id))
		if data.get("type", "") == "boss":
			return true
	return false


func _spawn_enemies(enemy_ids: Array) -> void:
	# 기존 적 제거
	for child in enemy_container.get_children():
		child.queue_free()
	enemies.clear()
	
	# 새 적 생성
	for enemy_id in enemy_ids:
		var battle_enemy := BattleEnemy.new()
		battle_enemy.setup(str(enemy_id))
		enemy_container.add_child(battle_enemy)
		enemies.append(battle_enemy)


func _get_enemy_name(enemy_id: String) -> String:
	var data: Dictionary = DataManager.get_enemy(enemy_id)
	return str(data.get("name", enemy_id))
#endregion


#region 라운드 진행
func _start_round() -> void:
	current_round += 1
	round_label.text = "Round %d" % current_round
	
	# 행동 순서 결정 (SPD 기준)
	_calculate_turn_order()
	current_turn_index = 0
	
	_queue_message("[color=yellow]--- 라운드 %d ---[/color]" % current_round)
	
	await _process_message_queue()
	_process_next_turn()


func _calculate_turn_order() -> void:
	turn_order.clear()
	
	# 파티 추가
	var party := PartyManager.get_alive_heroes()
	for hero in party:
		turn_order.append({
			"type": "hero",
			"ref": hero,
			"spd": hero.get_spd()
		})
	
	# 적 추가
	for enemy in enemies:
		if enemy.is_alive():
			turn_order.append({
				"type": "enemy",
				"ref": enemy,
				"spd": enemy.get_spd()
			})
	
	# SPD 내림차순 정렬 (동률 시 랜덤)
	turn_order.sort_custom(func(a, b):
		if a["spd"] != b["spd"]:
			return a["spd"] > b["spd"]
		return randf() > 0.5
	)


func _process_next_turn() -> void:
	# 승리/패배 체크
	if _check_battle_end():
		return
	
	# 모든 턴 완료 → 다음 라운드
	if current_turn_index >= turn_order.size():
		await get_tree().create_timer(ACTION_DELAY).timeout
		_start_round()
		return
	
	var turn_data: Dictionary = turn_order[current_turn_index]
	current_turn_index += 1
	
	if turn_data["type"] == "hero":
		_process_hero_turn(turn_data["ref"])
	else:
		_process_enemy_turn(turn_data["ref"])


func _process_hero_turn(hero: Hero) -> void:
	if hero.is_dead:
		_process_next_turn()
		return
	
	current_state = BattleState.PLAYER_PHASE
	
	# 타겟 선택 (살아있는 적 중 랜덤)
	var alive_enemies := enemies.filter(func(e): return e.is_alive())
	if alive_enemies.is_empty():
		_process_next_turn()
		return
	
	# 스마트 타겟팅: 처치 가능한 적 우선
	var target: BattleEnemy = _select_smart_target(hero, alive_enemies)
	var skill_id: String = _select_skill(hero, target)
	
	# 행동 실행
	await _execute_hero_action(hero, target, skill_id)
	
	await get_tree().create_timer(ACTION_DELAY).timeout
	_process_next_turn()


func _process_enemy_turn(enemy: BattleEnemy) -> void:
	if not enemy.is_alive():
		_process_next_turn()
		return
	
	current_state = BattleState.ENEMY_PHASE
	
	# 타겟 선택 (살아있는 영웅 중 랜덤)
	var alive_heroes := PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		_process_next_turn()
		return
	
	var target: Hero = alive_heroes[randi() % alive_heroes.size()]
	
	# 공격 실행
	await _execute_enemy_action(enemy, target)
	
	await get_tree().create_timer(ACTION_DELAY).timeout
	_process_next_turn()
#endregion


#region 전투 행동
func _select_smart_target(hero: Hero, alive_enemies: Array) -> BattleEnemy:
	## 스마트 타겟팅: 한 방에 처치 가능한 적 우선
	var atk := hero.get_atk()
	
	for enemy in alive_enemies:
		var expected_damage := _calculate_physical_damage(atk, enemy.get_p_def())
		if expected_damage >= enemy.current_hp:
			return enemy
	
	# 처치 불가 → 랜덤
	return alive_enemies[randi() % alive_enemies.size()]


func _select_skill(hero: Hero, _target: BattleEnemy) -> String:
	## ON 상태인 스킬 중 선택 (현재는 기본 공격만)
	var enabled_skills := hero.get_enabled_skills()
	
	if "basic_attack" in enabled_skills:
		return "basic_attack"
	
	# 모든 스킬 OFF → 대기
	return ""


func _execute_hero_action(hero: Hero, target: BattleEnemy, skill_id: String) -> void:
	if skill_id.is_empty():
		_queue_message("%s은(는) 대기했다." % hero.hero_name)
		await _process_message_queue()
		return
	
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var skill_name: String = str(skill_data.get("name", "공격"))
	
	# MP 체크
	var mp_cost: int = int(skill_data.get("mp_cost", 0))
	if mp_cost > 0 and hero.current_mp < mp_cost:
		_queue_message("%s: MP가 부족하다!" % hero.hero_name)
		await _process_message_queue()
		return
	
	# MP 소모
	if mp_cost > 0:
		hero.use_mp(mp_cost)
	
	# 데미지 계산
	var atk := hero.get_atk()
	var target_def := target.get_p_def()
	var is_crit := randf() * 100 < hero.get_crit()
	var damage := _calculate_physical_damage(atk, target_def, is_crit)
	
	# 회피 판정
	var is_evaded := randf() * 100 < target.get_eva()
	
	if is_evaded:
		_queue_message("%s의 공격! %s은(는) 피했다!" % [hero.hero_name, target.enemy_name])
		target.play_evade_effect()
	elif is_crit:
		_queue_message("[color=orange]%s의 회심의 일격! %s에게 %d 데미지![/color]" % [hero.hero_name, target.enemy_name, damage])
		target.take_damage(damage)
		target.play_hit_effect(true)
	else:
		_queue_message("%s의 공격! %s에게 %d 데미지!" % [hero.hero_name, target.enemy_name, damage])
		target.take_damage(damage)
		target.play_hit_effect(false)
	
	await _process_message_queue()
	
	# 적 처치 체크
	if not target.is_alive():
		await _on_enemy_defeated(target)


func _execute_enemy_action(enemy: BattleEnemy, target: Hero) -> void:
	var atk := enemy.get_atk()
	var target_def := target.get_p_def()
	var is_crit := randf() * 100 < enemy.get_crit()
	var damage := _calculate_physical_damage(atk, target_def, is_crit)
	
	# 회피 판정
	var is_evaded := randf() * 100 < target.get_eva()
	
	if is_evaded:
		_queue_message("%s의 공격! %s은(는) 피했다!" % [enemy.enemy_name, target.hero_name])
	elif is_crit:
		_queue_message("[color=red]%s의 강력한 일격! %s에게 %d 데미지![/color]" % [enemy.enemy_name, target.hero_name, damage])
		target.take_damage(damage)
	else:
		_queue_message("%s의 공격! %s에게 %d 데미지!" % [enemy.enemy_name, target.hero_name, damage])
		target.take_damage(damage)
	
	await _process_message_queue()
	
	# 영웅 사망 체크
	if target.is_dead:
		_queue_message("[color=gray]%s이(가) 쓰러졌다...[/color]" % target.hero_name)
		await _process_message_queue()
		PartyManager.party_changed.emit()


func _calculate_physical_damage(atk: int, p_def: int, is_crit: bool = false) -> int:
	if is_crit:
		return maxi(1, atk)  # 크리티컬: 방어 무시
	return maxi(1, atk - int(p_def / 2))
#endregion


#region 적 처치/전투 종료
func _on_enemy_defeated(enemy: BattleEnemy) -> void:
	_queue_message("[color=lime]%s을(를) 쓰러뜨렸다![/color]" % enemy.enemy_name)
	
	# 보상 누적
	total_exp += enemy.exp_reward
	total_gold += enemy.get_gold_reward()
	
	# 드랍 처리
	var drops := enemy.roll_drops()
	drop_items.append_array(drops)
	
	enemy.play_death_effect()
	await _process_message_queue()


func _check_battle_end() -> bool:
	var alive_enemies := enemies.filter(func(e): return e.is_alive())
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
	
	_queue_message("[color=cyan]===== 승리! =====[/color]")
	_queue_message("경험치 %d 획득!" % total_exp)
	_queue_message("골드 %d 획득!" % total_gold)
	
	for item_id in drop_items:
		var item_data: Dictionary = DataManager.get_item(item_id)
		_queue_message("[color=yellow]%s을(를) 얻었다![/color]" % str(item_data.get("name", item_id)))
	
	await _process_message_queue()
	
	# 보상 지급
	PartyManager.distribute_exp(total_exp)
	GameManager.add_gold(total_gold)
	for item_id in drop_items:
		InventoryManager.add_item(item_id)
	
	run_button.visible = false
	close_button.visible = true
	
	battle_rewards.emit(battle_id, total_exp, total_gold, drop_items)


func _end_battle_defeat() -> void:
	current_state = BattleState.DEFEAT
	
	_queue_message("[color=red]===== 전멸... =====[/color]")
	await _process_message_queue()
	
	run_button.visible = false
	close_button.visible = true
	
	# 게임 오버 처리는 외부에서
	battle_ended.emit(battle_id, false)
#endregion


#region 도주 시스템
func _on_run_pressed() -> void:
	if is_boss_battle:
		_queue_message("[color=red]보스전에서는 도주할 수 없다![/color]")
		await _process_message_queue()
		return
	
	if current_state != BattleState.PLAYER_PHASE and current_state != BattleState.ENEMY_PHASE:
		return
	
	run_button.disabled = true
	
	var escape_chance := _calculate_escape_chance()
	var roll := randf() * 100
	
	_queue_message("도주를 시도한다... (성공률: %d%%)" % int(escape_chance))
	await _process_message_queue()
	
	await get_tree().create_timer(0.5).timeout
	
	if roll < escape_chance:
		_escape_success()
	else:
		_escape_failed()


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


func _escape_success() -> void:
	current_state = BattleState.ESCAPED
	
	_queue_message("[color=cyan]도주에 성공했다![/color]")
	await _process_message_queue()
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, false)


func _escape_failed() -> void:
	_queue_message("[color=gray]도주에 실패했다! 이번 턴 행동 불가![/color]")
	await _process_message_queue()
	
	run_button.disabled = false
	
	# 남은 파티원 턴 스킵 (현재 라운드)
	# 적 턴은 계속 진행
#endregion


#region 메시지 시스템
func _queue_message(msg: String) -> void:
	message_queue.append(msg)


func _process_message_queue() -> void:
	if is_processing_messages:
		return
	
	is_processing_messages = true
	
	while not message_queue.is_empty():
		var msg: String = message_queue.pop_front()
		message_label.text = "[center]%s[/center]" % msg
		await get_tree().create_timer(MESSAGE_DELAY).timeout
	
	is_processing_messages = false
#endregion


#region 이벤트 핸들러
func _on_close_pressed() -> void:
	current_state = BattleState.ENDED
	battle_ended.emit(battle_id, current_state == BattleState.VICTORY)
	queue_free()
#endregion
