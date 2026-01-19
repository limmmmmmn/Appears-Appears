extends Node
## 게임 전역 상태를 관리하는 오토로드

signal battle_started(enemy_id: String)
signal battle_ended(enemy_id: String, victory: bool)
signal party_status_changed()
signal hero_died(hero_id: String)
signal hero_leveled_up(hero_id: String, new_level: int, stat_changes: Dictionary, new_skills: Array)
signal exp_gained(hero_id: String, amount: int, total: int)
signal party_order_changed(new_order: Array)
signal game_over()
signal equipment_changed(hero_id: String, slot: String)

# 현재 파티 구성 (영웅 id 배열)
var party: Array[String] = ["warrior", "mage", "cleric", "thief"]

# 파티 상태 (전역으로 관리)
var party_hp: Dictionary = {}
var party_max_hp: Dictionary = {}
var party_cooldowns: Dictionary = {}
var party_max_cooldowns: Dictionary = {}

# 레벨/경험치 시스템
var party_level: Dictionary = {}
var party_exp: Dictionary = {}
var party_base_stats: Dictionary = {}  # 기본 스탯 (레벨업으로 증가된 값)
var party_equipment: Dictionary = {}   # 장착 장비 {hero_id: {slot: equipment_id}}

# 활성 전투 목록
var active_battles: Array = []

# 배틀 매니저 참조
var battle_manager: Node = null

# 플레이어 참조
var player_node: Node2D = null

# 게임 상태
var is_paused: bool = false


func _ready() -> void:
	_init_party_status()
	_load_attack_icons()  # ← 이거 추가!
	print("[GameManager] 초기화 완료")


func _init_party_status() -> void:
	for hero_id in party:
		var hero_data = DataManager.get_hero(hero_id)
		if hero_data.is_empty():
			continue
		
		var base_stats = hero_data.get("stats", {})
		var max_hp = int(base_stats.get("max_hp", 100))
		var base_cd = float(hero_data.get("combat", {}).get("base_cooldown", 2.0))
		
		party_hp[hero_id] = max_hp
		party_max_hp[hero_id] = max_hp
		party_cooldowns[hero_id] = 0.0
		party_max_cooldowns[hero_id] = base_cd
		
		# 레벨/경험치 초기화
		party_level[hero_id] = 1
		party_exp[hero_id] = 0
		
		# 기본 스탯 복사 (새 스탯 시스템)
		party_base_stats[hero_id] = {
			"max_hp": max_hp,
			"atk": int(base_stats.get("atk", 10)),
			"def": int(base_stats.get("def", 5)),
			"dex": int(base_stats.get("dex", 5)),
			"int": int(base_stats.get("int", 5)),
			"luk": int(base_stats.get("luk", 5))
		}
		
		# 장비 초기화 (빈 슬롯)
		party_equipment[hero_id] = {
			"weapon_left": "",
			"weapon_right": "",
			"helmet": "",
			"armor": "",
			"accessory1": "",
			"accessory2": ""
		}


#region 스탯 계산 (기본 + 장비)
func get_hero_total_stats(hero_id: String) -> Dictionary:
	## 기본 스탯 + 장비 스탯 = 최종 스탯
	var base = party_base_stats.get(hero_id, {})
	var total = base.duplicate()
	
	# 장비 스탯 추가
	var equipment = party_equipment.get(hero_id, {})
	for slot in equipment:
		var eq_id = str(equipment[slot])
		if eq_id == "":
			continue
		
		var eq_data = DataManager.get_equipment(eq_id)
		if eq_data.is_empty():
			continue
		
		var eq_stats = eq_data.get("stats", {})
		for stat_name in eq_stats:
			var value = int(eq_stats[stat_name])
			total[stat_name] = int(total.get(stat_name, 0)) + value
	
	return total


func get_hero_stat(hero_id: String, stat_name: String) -> int:
	var total = get_hero_total_stats(hero_id)
	return int(total.get(stat_name, 0))
#endregion


#region 장비 시스템
func equip_item(hero_id: String, equipment_id: String) -> bool:
	## 장비 장착
	var eq_data = DataManager.get_equipment(equipment_id)
	if eq_data.is_empty():
		push_warning("[GameManager] 장비 없음: " + equipment_id)
		return false
	
	var hero_data = DataManager.get_hero(hero_id)
	if hero_data.is_empty():
		return false
	
	# 장착 가능 여부 확인
	var eq_type = str(eq_data.get("type", ""))
	var allowed = hero_data.get("allowed_equipment", [])
	if not allowed.has(eq_type):
		push_warning("[GameManager] %s는 %s 장착 불가" % [hero_id, eq_type])
		return false
	
	var slot = str(eq_data.get("slot", ""))
	if slot == "" or slot == "consumable":
		return false
	
	# 기존 장비 해제
	var old_eq = str(party_equipment[hero_id].get(slot, ""))
	
	# 새 장비 장착
	party_equipment[hero_id][slot] = equipment_id
	
	# max_hp 변경 시 현재 HP 조정
	_update_max_hp(hero_id)
	
	equipment_changed.emit(hero_id, slot)
	party_status_changed.emit()
	
	print("[GameManager] %s 장착: %s → %s" % [hero_id, slot, equipment_id])
	return true


func unequip_item(hero_id: String, slot: String) -> String:
	## 장비 해제, 해제된 장비 ID 반환
	if not party_equipment.has(hero_id):
		return ""
	
	var old_eq = str(party_equipment[hero_id].get(slot, ""))
	if old_eq == "":
		return ""
	
	party_equipment[hero_id][slot] = ""
	
	_update_max_hp(hero_id)
	
	equipment_changed.emit(hero_id, slot)
	party_status_changed.emit()
	
	print("[GameManager] %s 해제: %s" % [hero_id, slot])
	return old_eq


func _update_max_hp(hero_id: String) -> void:
	## 장비 변경 시 max_hp 재계산
	var total = get_hero_total_stats(hero_id)
	var new_max_hp = int(total.get("max_hp", 100))
	var old_max_hp = int(party_max_hp.get(hero_id, 100))
	
	party_max_hp[hero_id] = new_max_hp
	
	# 현재 HP가 새 max_hp 초과하면 조정
	if int(party_hp[hero_id]) > new_max_hp:
		party_hp[hero_id] = new_max_hp


func get_equipped_item(hero_id: String, slot: String) -> String:
	## 특정 슬롯의 장비 ID 반환
	if not party_equipment.has(hero_id):
		return ""
	return str(party_equipment[hero_id].get(slot, ""))


func get_all_equipment(hero_id: String) -> Dictionary:
	## 영웅의 모든 장비 반환
	return party_equipment.get(hero_id, {}).duplicate()
#endregion


func register_player(player: Node2D) -> void:
	player_node = player
	print("[GameManager] Player 등록됨")


func register_battle_manager(manager: Node) -> void:
	battle_manager = manager
	print("[GameManager] BattleManager 등록됨")


func _process(delta: float) -> void:
	if is_paused:
		return
	
	_process_party_cooldowns(delta)


func _process_party_cooldowns(delta: float) -> void:
	for hero_id in party_cooldowns:
		if int(party_hp.get(hero_id, 0)) <= 0:
			continue
		
		var current_cd = float(party_cooldowns[hero_id])
		
		if current_cd > 0:
			party_cooldowns[hero_id] = maxf(0, current_cd - delta)
		
		if float(party_cooldowns[hero_id]) <= 0:
			if active_battles.size() > 0:
				_execute_hero_attack(hero_id)
			# 다음 쿨다운 계산 (DEX/INT 기반)
			party_cooldowns[hero_id] = _calculate_cooldown(hero_id)


func _calculate_cooldown(hero_id: String) -> float:
	## ATB 쿨다운 계산: base_cooldown * (100 / (100 + stat))
	var hero_data = DataManager.get_hero(hero_id)
	var base_cd = float(hero_data.get("combat", {}).get("base_cooldown", 2.0))
	
	# 스킬 타입에 따라 DEX 또는 INT 사용
	var skill_ids = hero_data.get("combat", {}).get("skills", [])
	if skill_ids.is_empty():
		return base_cd
	
	var skill_data = DataManager.get_skill(skill_ids[0])
	var cooldown_stat = str(skill_data.get("cooldown_stat", "dex"))
	
	var stat_value = get_hero_stat(hero_id, cooldown_stat)
	var multiplier = 100.0 / (100.0 + float(stat_value))
	
	return base_cd * multiplier


func _execute_hero_attack(hero_id: String) -> void:
	if battle_manager == null:
		return
	
	var hero_data = DataManager.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	var skill_ids = hero_data.get("combat", {}).get("skills", [])
	if skill_ids.is_empty():
		return
	
	var skill_id = skill_ids[0]
	var skill_data = DataManager.get_skill(skill_id)
	
	# 스킬 타겟 타입 (새 JSON 구조: target 필드)
	var target_type = str(skill_data.get("target", "single_enemy"))
	
	match target_type:
		"single_enemy":
			_attack_single(hero_id, skill_data)
		"all_enemies":
			_attack_all(hero_id, skill_data)
		"single_ally", "all_allies":
			_use_support_skill(hero_id, skill_data, target_type)
		_:
			_attack_single(hero_id, skill_data)


func _attack_single(hero_id: String, skill_data: Dictionary) -> void:
	var windows = _get_active_windows()
	if windows.is_empty():
		return
	
	var target_window = windows[randi() % windows.size()]
	target_window.receive_hero_attack(hero_id, skill_data, "single")


func _attack_all(hero_id: String, skill_data: Dictionary) -> void:
	var windows = _get_active_windows()
	for window in windows:
		window.receive_hero_attack(hero_id, skill_data, "multi")


func _use_support_skill(hero_id: String, skill_data: Dictionary, target_type: String) -> void:
	## 힐/버프 스킬 처리
	var effects = skill_data.get("effects", [])
	
	for effect in effects:
		var effect_type = str(effect.get("type", ""))
		
		if effect_type == "heal":
			var base_value = int(effect.get("base_value", 0))
			var scaling = effect.get("stat_scaling", {})
			var stat_name = str(scaling.get("stat", "int"))
			var ratio = float(scaling.get("ratio", 1.0))
			
			var stat_value = get_hero_stat(hero_id, stat_name)
			var heal_amount = base_value + int(float(stat_value) * ratio)
			
			if target_type == "single_ally":
				# 가장 HP 비율 낮은 아군 치유
				var target_id = _get_lowest_hp_hero()
				if target_id != "":
					heal_hero(target_id, heal_amount)
					_send_log("%s → %s 힐 %d!" % [
						DataManager.get_hero(hero_id).get("name", hero_id),
						DataManager.get_hero(target_id).get("name", target_id),
						heal_amount
					])
			else:
				# 전체 치유
				for ally_id in get_alive_heroes():
					heal_hero(ally_id, heal_amount)
				_send_log("%s 전체 힐 %d!" % [
					DataManager.get_hero(hero_id).get("name", hero_id),
					heal_amount
				])


func _get_lowest_hp_hero() -> String:
	## HP 비율이 가장 낮은 살아있는 영웅 반환
	var lowest_id = ""
	var lowest_ratio = 2.0
	
	for hero_id in get_alive_heroes():
		var hp = float(party_hp.get(hero_id, 0))
		var max_hp = float(party_max_hp.get(hero_id, 1))
		var ratio = hp / max_hp
		
		if ratio < lowest_ratio:
			lowest_ratio = ratio
			lowest_id = hero_id
	
	return lowest_id


func _get_active_windows() -> Array:
	if battle_manager == null:
		return []
	
	var valid_windows = []
	for w in battle_manager.active_windows:
		if is_instance_valid(w) and w.is_battle_active:
			valid_windows.append(w)
	return valid_windows


func start_battle(enemy_id: String) -> void:
	active_battles.append(enemy_id)
	battle_started.emit(enemy_id)
	print("[GameManager] 전투 시작: " + enemy_id + " (활성 전투: %d)" % active_battles.size())


func end_battle(enemy_id: String, victory: bool) -> void:
	active_battles.erase(enemy_id)
	battle_ended.emit(enemy_id, victory)
	print("[GameManager] 전투 종료: " + enemy_id + " (승리: %s)" % str(victory))


func get_active_battle_count() -> int:
	return active_battles.size()


func damage_hero(hero_id: String, damage: int) -> void:
	if party_hp.has(hero_id):
		# 방어력 적용
		var defense = get_hero_stat(hero_id, "def")
		var actual_damage = maxi(1, damage - defense)
		
		var was_alive = int(party_hp[hero_id]) > 0
		party_hp[hero_id] = maxi(0, int(party_hp[hero_id]) - actual_damage)
		party_status_changed.emit()
		
		if was_alive and int(party_hp[hero_id]) <= 0:
			hero_died.emit(hero_id)
			_show_dead_popup(hero_id)
			
			if is_party_dead():
				_trigger_game_over()
			else:
				_reorder_party()


func _show_dead_popup(hero_id: String) -> void:
	var hero_data = DataManager.get_hero(hero_id)
	var hero_name = str(hero_data.get("name", hero_id))
	
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	get_tree().root.add_child(canvas)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = hero_name
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var dead_label = Label.new()
	dead_label.text = "DEAD"
	dead_label.add_theme_font_size_override("font_size", 32)
	dead_label.add_theme_color_override("font_color", Color.RED)
	dead_label.add_theme_color_override("font_outline_color", Color.BLACK)
	dead_label.add_theme_constant_override("outline_size", 4)
	dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(dead_label)
	
	vbox.modulate.a = 0.0
	vbox.scale = Vector2(0.5, 0.5)
	vbox.pivot_offset = vbox.size / 2
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(vbox, "modulate:a", 1.0, 0.15)
	tween.tween_property(vbox, "scale", Vector2(1.2, 1.2), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	tween.set_parallel(false)
	tween.tween_property(vbox, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(0.8)
	tween.tween_property(vbox, "modulate:a", 0.0, 0.3)
	tween.tween_callback(canvas.queue_free)


func heal_hero(hero_id: String, amount: int) -> void:
	if party_hp.has(hero_id):
		var max_hp = int(party_max_hp.get(hero_id, 100))
		party_hp[hero_id] = mini(max_hp, int(party_hp[hero_id]) + amount)
		party_status_changed.emit()


func is_hero_alive(hero_id: String) -> bool:
	return int(party_hp.get(hero_id, 0)) > 0


func get_alive_heroes() -> Array:
	var alive = []
	for hero_id in party:
		if is_hero_alive(hero_id):
			alive.append(hero_id)
	return alive


func is_party_dead() -> bool:
	return get_alive_heroes().is_empty()


func _trigger_game_over() -> void:
	game_over.emit()
	
	await get_tree().create_timer(0.8).timeout
	_show_game_over()


func _show_game_over() -> void:
	get_tree().paused = true
	is_paused = true
	
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(canvas)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.RED)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var retry_btn = Button.new()
	retry_btn.text = "다시하기"
	retry_btn.add_theme_font_size_override("font_size", 20)
	retry_btn.custom_minimum_size = Vector2(150, 50)
	retry_btn.pressed.connect(_on_retry_pressed.bind(canvas))
	vbox.add_child(retry_btn)
	
	vbox.modulate.a = 0.0
	vbox.scale = Vector2(0.5, 0.5)
	vbox.pivot_offset = vbox.size / 2
	
	var tween = canvas.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(vbox, "modulate:a", 1.0, 0.3)
	tween.tween_property(vbox, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _on_retry_pressed(canvas: CanvasLayer) -> void:
	canvas.queue_free()
	get_tree().paused = false
	is_paused = false
	_reset_game_state()
	get_tree().reload_current_scene()


func _reset_game_state() -> void:
	active_battles.clear()
	party = ["warrior", "mage", "cleric", "thief"]
	party_hp.clear()
	party_max_hp.clear()
	party_cooldowns.clear()
	party_max_cooldowns.clear()
	party_level.clear()
	party_exp.clear()
	party_base_stats.clear()
	party_equipment.clear()
	_init_party_status()


func _reorder_party() -> void:
	var alive_members: Array[String] = []
	var dead_members: Array[String] = []
	
	for hero_id in party:
		if is_hero_alive(hero_id):
			alive_members.append(hero_id)
		else:
			dead_members.append(hero_id)
	
	var new_order: Array[String] = []
	new_order.append_array(alive_members)
	new_order.append_array(dead_members)
	
	if new_order != party:
		party = new_order
		party_order_changed.emit(party)
		print("[GameManager] 파티 재정렬: ", party)


func get_current_leader() -> String:
	for hero_id in party:
		if is_hero_alive(hero_id):
			return hero_id
	return ""


func get_cooldown_percent(hero_id: String) -> float:
	var current = float(party_cooldowns.get(hero_id, 0))
	var max_cd = float(party_max_cooldowns.get(hero_id, 1))
	if max_cd <= 0:
		return 1.0
	return (max_cd - current) / max_cd


#region 레벨/경험치 시스템
func get_required_exp(level: int) -> int:
	return int(100 * pow(level, 1.5))


func add_exp_to_party(total_exp: int) -> void:
	var alive_heroes = get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	var exp_per_hero = total_exp
	
	for hero_id in alive_heroes:
		_add_exp_to_hero(hero_id, exp_per_hero)


func _add_exp_to_hero(hero_id: String, amount: int) -> void:
	if not party_exp.has(hero_id):
		return
	
	party_exp[hero_id] = int(party_exp[hero_id]) + amount
	exp_gained.emit(hero_id, amount, int(party_exp[hero_id]))
	
	_check_level_up(hero_id)


func _check_level_up(hero_id: String) -> void:
	var current_level = int(party_level[hero_id])
	var current_exp = int(party_exp[hero_id])
	var required_exp = get_required_exp(current_level)
	
	while current_exp >= required_exp:
		current_level += 1
		party_level[hero_id] = current_level
		
		var result = _apply_level_up(hero_id, current_level)
		hero_leveled_up.emit(hero_id, current_level, result["stat_changes"], result["new_skills"])
		
		_show_level_up_effect(hero_id, current_level, result["stat_changes"], result["new_skills"])
		
		required_exp = get_required_exp(current_level)


func _apply_level_up(hero_id: String, new_level: int) -> Dictionary:
	## 레벨업 적용: JSON의 growth 값 사용
	var hero_data = DataManager.get_hero(hero_id)
	var growth = hero_data.get("growth", {})
	var skill_unlocks = hero_data.get("skill_unlocks", {})
	
	var stat_changes = {}
	var new_skills = []
	
	# 스탯 증가 (growth 값 그대로 사용)
	var stats = party_base_stats[hero_id]
	for stat_name in growth.keys():
		var increase = int(growth[stat_name])
		if increase == 0:
			continue
		var old_value = int(stats.get(stat_name, 0))
		var new_value = old_value + increase
		stats[stat_name] = new_value
		stat_changes[stat_name] = {"old": old_value, "new": new_value, "increase": increase}
	
	# max_hp 증가 시 현재 HP도 증가
	if stat_changes.has("max_hp"):
		var hp_increase = int(stat_changes["max_hp"]["increase"])
		party_max_hp[hero_id] = get_hero_stat(hero_id, "max_hp")
		party_hp[hero_id] = int(party_hp[hero_id]) + hp_increase
	
	# 스킬 해금 확인
	var level_str = str(new_level)
	if skill_unlocks.has(level_str):
		var skills_to_unlock = skill_unlocks[level_str]
		for skill_id in skills_to_unlock:
			new_skills.append(skill_id)
			_unlock_skill(hero_id, skill_id)
	
	party_status_changed.emit()
	
	return {"stat_changes": stat_changes, "new_skills": new_skills}


func _unlock_skill(hero_id: String, skill_id: String) -> void:
	print("[GameManager] %s 스킬 해금: %s" % [hero_id, skill_id])


func _show_level_up_effect(hero_id: String, new_level: int, stat_changes: Dictionary, new_skills: Array) -> void:
	var hero_data = DataManager.get_hero(hero_id)
	var hero_name = str(hero_data.get("name", hero_id))
	
	_send_log("[%s] Lv.%d 도달!" % [hero_name, new_level])
	
	# 새 스탯 이름
	var stat_names = {
		"max_hp": "HP", 
		"atk": "공격력", 
		"def": "방어력", 
		"dex": "민첩", 
		"int": "지능",
		"luk": "행운"
	}
	for stat_key in stat_changes.keys():
		var change = stat_changes[stat_key]
		var display_name = stat_names.get(stat_key, stat_key)
		_send_log("  %s +%d (%d → %d)" % [display_name, change["increase"], change["old"], change["new"]])
	
	for skill_id in new_skills:
		var skill_data = DataManager.get_skill(skill_id)
		var skill_name = str(skill_data.get("name", skill_id))
		_send_log("[%s] 스킬 해금: %s" % [hero_name, skill_name])
	
	_show_floating_text(hero_id, "Lv UP!", Color.YELLOW, new_skills)


func _send_log(text: String) -> void:
	if battle_manager and battle_manager.hud:
		battle_manager.hud.add_log(text)
	else:
		print(text)


func _show_floating_text(hero_id: String, text: String, color: Color, new_skills: Array) -> void:
	if player_node == null:
		return
	
	var target_node: Node2D = _get_field_unit(hero_id)
	
	if target_node == null:
		return
	
	_create_floating_label(target_node, text, color, 0.0)
	
	# 스킬 해금 시 각 스킬 이름 표시
	var delay = 0.4
	for skill_id in new_skills:
		var skill_data = DataManager.get_skill(skill_id)
		var skill_name = str(skill_data.get("name", skill_id))
		_create_floating_label(target_node, skill_name + "!", Color.CYAN, delay)
		delay += 0.3


func _get_field_unit(hero_id: String) -> Node2D:
	## 필드 위의 영웅 노드 찾기 (리더 또는 파티원)
	if player_node == null:
		return null
	
	# 리더인 경우
	if player_node.current_leader_id == hero_id:
		return player_node
	
	# 파티원인 경우
	if player_node.has_method("get_party_member_by_id"):
		return player_node.get_party_member_by_id(hero_id)
	
	return null


func _create_floating_label(target: Node2D, text: String, color: Color, delay: float) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	
	label.position = Vector2(-20, -30)
	label.modulate.a = 0.0
	
	target.add_child(label)
	
	var tween = target.create_tween()
	
	if delay > 0:
		tween.tween_interval(delay)
	
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 15, 0.8).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	
	tween.tween_interval(0.3)
	
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(label.queue_free)


func get_hero_level(hero_id: String) -> int:
	return int(party_level.get(hero_id, 1))


func get_hero_exp(hero_id: String) -> int:
	return int(party_exp.get(hero_id, 0))
#endregion

# ===== 이 코드를 game_manager.gd 하단에 추가하세요 =====

#region 필드 공격 아이콘 이펙트
var sword_icon_texture: Texture2D = null
var wand_icon_texture: Texture2D = null


func _load_attack_icons() -> void:
	## 공격 아이콘 텍스처 로드 (_ready에서 호출)
	var sword_path = "res://assets/icons/sword_icon.png"
	var wand_path = "res://assets/icons/wand_icon.png"
	
	if ResourceLoader.exists(sword_path):
		sword_icon_texture = load(sword_path)
	if ResourceLoader.exists(wand_path):
		wand_icon_texture = load(wand_path)


func show_attack_icon(hero_id: String, skill_type: String) -> void:
	## 필드에서 파티원 머리 위에 공격 아이콘 표시
	if player_node == null:
		return
	
	var target_node: Node2D = null
	
	# 유닛 찾기
	if player_node.has_method("get_unit_by_id"):
		target_node = player_node.get_unit_by_id(hero_id)
	
	if target_node == null:
		return
	
	# 스킬 타입에 따라 아이콘 선택
	var icon_texture: Texture2D = null
	var is_magic = skill_type in ["magic", "magical", "heal", "support"]
	
	if is_magic:
		icon_texture = wand_icon_texture
	else:
		icon_texture = sword_icon_texture
	
	if icon_texture == null:
		return
	
	# 아이콘 생성
	var icon = Sprite2D.new()
	icon.texture = icon_texture
	icon.position = Vector2(0, -20)  # 머리 위
	icon.z_index = 100
	icon.modulate.a = 0.0
	
	target_node.add_child(icon)
	
	# 애니메이션 분기
	if is_magic:
		_animate_wand_icon(icon)
	else:
		_animate_sword_icon(icon)


func _animate_sword_icon(icon: Sprite2D) -> void:
	## 검 아이콘: 휘두르는 애니메이션 (45도 회전)
	var tween = icon.create_tween()
	
	# 초기 상태: 왼쪽 위에서 시작, 기울어진 상태
	icon.rotation_degrees = -45
	icon.position += Vector2(-5, -5)
	
	# 나타남
	tween.tween_property(icon, "modulate:a", 1.0, 0.05)
	
	# 휘두르기: 오른쪽 아래로 회전하며 이동
	tween.set_parallel(true)
	tween.tween_property(icon, "rotation_degrees", 45.0, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(icon, "position", icon.position + Vector2(10, 5), 0.12).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	
	# 잠깐 유지
	tween.tween_interval(0.08)
	
	# 페이드아웃
	tween.tween_property(icon, "modulate:a", 0.0, 0.1)
	tween.tween_callback(icon.queue_free)


func _animate_wand_icon(icon: Sprite2D) -> void:
	## 완드 아이콘: 위로 솟는 애니메이션
	var tween = icon.create_tween()
	
	var start_pos = icon.position
	
	# 나타남
	tween.tween_property(icon, "modulate:a", 1.0, 0.05)
	
	# 위로 솟음 + 약간 흔들림
	tween.set_parallel(true)
	tween.tween_property(icon, "position:y", start_pos.y - 8, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(icon, "scale", Vector2(1.2, 1.2), 0.1).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	
	# 반짝임 효과
	tween.tween_property(icon, "modulate", Color(1.5, 1.5, 2.0, 1.0), 0.05)
	tween.tween_property(icon, "modulate", Color(1, 1, 1, 1), 0.05)
	
	# 원래 크기로
	tween.tween_property(icon, "scale", Vector2(1.0, 1.0), 0.1)
	
	# 잠깐 유지
	tween.tween_interval(0.05)
	
	# 페이드아웃하며 위로
	tween.set_parallel(true)
	tween.tween_property(icon, "modulate:a", 0.0, 0.15)
	tween.tween_property(icon, "position:y", start_pos.y - 15, 0.15)
	tween.set_parallel(false)
	
	tween.tween_callback(icon.queue_free)
#endregion
