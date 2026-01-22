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
const ACTION_DELAY: float = 0.35

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
func setup(p_battle_id: int, enemy_ids: Array) -> void:
	if not _ui_built:
		_build_ui()
	
	battle_id = p_battle_id
	enemy_data_list = enemy_ids.duplicate()
	
	is_boss_battle = _check_is_boss_battle(enemy_ids)
	run_button.disabled = is_boss_battle
	
	_spawn_enemies(enemy_ids)
	
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
	_calculate_turn_order()
	current_turn_index = 0
	_process_next_turn()


func _calculate_turn_order() -> void:
	turn_order.clear()
	
	var party := PartyManager.get_alive_heroes()
	for hero in party:
		turn_order.append({"type": "hero", "ref": hero, "spd": hero.get_spd()})
	
	for enemy in enemies:
		if enemy.is_alive():
			turn_order.append({"type": "enemy", "ref": enemy, "spd": enemy.get_spd()})
	
	turn_order.sort_custom(func(a, b):
		if a["spd"] != b["spd"]:
			return a["spd"] > b["spd"]
		return randf() > 0.5
	)


func _process_next_turn() -> void:
	if _check_battle_end():
		return
	
	if current_turn_index >= turn_order.size():
		await get_tree().create_timer(ACTION_DELAY).timeout
		_start_round()
		return
	
	var turn_data: Dictionary = turn_order[current_turn_index]
	current_turn_index += 1
	
	if turn_data["type"] == "hero":
		await _process_hero_turn(turn_data["ref"])
	else:
		await _process_enemy_turn(turn_data["ref"])
	
	await get_tree().create_timer(ACTION_DELAY).timeout
	_process_next_turn()


func _process_hero_turn(hero: Hero) -> void:
	if hero.is_dead:
		return
	
	current_state = BattleState.PLAYER_PHASE
	
	var alive_enemies := enemies.filter(func(e): return e.is_alive())
	if alive_enemies.is_empty():
		return
	
	var target: BattleEnemy = _select_smart_target(hero, alive_enemies)
	await _execute_hero_action(hero, target)


func _process_enemy_turn(enemy: BattleEnemy) -> void:
	if not enemy.is_alive():
		return
	
	current_state = BattleState.ENEMY_PHASE
	
	var alive_heroes := PartyManager.get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	var target: Hero = alive_heroes[randi() % alive_heroes.size()]
	await _execute_enemy_action(enemy, target)
#endregion


#region 전투 행동
func _select_smart_target(hero: Hero, alive_enemies: Array) -> BattleEnemy:
	var atk := hero.get_atk()
	
	for enemy in alive_enemies:
		var expected_damage := _calculate_damage(atk, enemy.get_p_def())
		if expected_damage >= enemy.current_hp:
			return enemy
	
	return alive_enemies[randi() % alive_enemies.size()]


func _execute_hero_action(hero: Hero, target: BattleEnemy) -> void:
	var atk := hero.get_atk()
	var is_crit := randf() * 100 < hero.get_crit()
	var is_evaded := randf() * 100 < target.get_eva()
	
	if is_evaded:
		_send_log("%s → %s 회피!" % [hero.hero_name, target.enemy_name], Color.GRAY)
		target.play_evade_effect()
	else:
		var damage := _calculate_damage(atk, target.get_p_def(), is_crit)
		target.take_damage(damage)
		
		if is_crit:
			_send_log("%s → %s에게 %d! (크리티컬)" % [hero.hero_name, target.enemy_name, damage], Color.ORANGE)
			target.play_hit_effect(true)
		else:
			_send_log("%s → %s에게 %d" % [hero.hero_name, target.enemy_name, damage], Color.WHITE)
			target.play_hit_effect(false)
		
		if not target.is_alive():
			await _on_enemy_defeated(target)


func _execute_enemy_action(enemy: BattleEnemy, target: Hero) -> void:
	var atk := enemy.get_atk()
	var is_crit := randf() * 100 < enemy.get_crit()
	var is_evaded := randf() * 100 < target.get_eva()
	
	if is_evaded:
		_send_log("%s → %s 회피!" % [enemy.enemy_name, target.hero_name], Color.GRAY)
	else:
		var damage := _calculate_damage(atk, target.get_p_def(), is_crit)
		target.take_damage(damage)
		party_updated.emit()  # HP 변경 알림
		
		if is_crit:
			_send_log("%s → %s에게 %d! (강타)" % [enemy.enemy_name, target.hero_name, damage], Color.RED)
		else:
			_send_log("%s → %s에게 %d" % [enemy.enemy_name, target.hero_name, damage], Color.YELLOW)
		
		if target.is_dead:
			_send_log("%s 쓰러짐!" % target.hero_name, Color.DARK_RED)
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
	
	enemy.play_death_effect()


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
	
	_send_log("승리! EXP +%d, Gold +%d" % [total_exp, total_gold], Color.CYAN)
	
	for item_id in drop_items:
		var item_data: Dictionary = DataManager.get_item(item_id)
		_send_log("%s 획득!" % str(item_data.get("name", item_id)), Color.YELLOW)
	
	# 보상 지급
	PartyManager.distribute_exp(total_exp)
	GameManager.add_gold(total_gold)
	for item_id in drop_items:
		InventoryManager.add_item(item_id)
	
	party_updated.emit()
	
	run_button.visible = false
	close_button.visible = true
	
	battle_ended.emit(battle_id, true)


func _end_battle_defeat() -> void:
	current_state = BattleState.DEFEAT
	
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
	battle_log.emit(msg, color)


func _on_close_pressed() -> void:
	current_state = BattleState.ENDED
	queue_free()
#endregion
