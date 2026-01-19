extends Node
## 게임 전역 상태를 관리하는 오토로드

signal battle_started(enemy_id: String)
signal battle_ended(enemy_id: String, victory: bool)
signal party_status_changed()
signal hero_died(hero_id: String)
signal hero_leveled_up(hero_id: String, new_level: int, stat_changes: Dictionary, new_skills: Array)
signal exp_gained(hero_id: String, amount: int, total: int)
signal party_order_changed(new_order: Array)
signal game_over()  # 전멸 시그널

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
var party_stats: Dictionary = {}  # 현재 스탯 (레벨업으로 증가된 값 포함)

# 활성 전투 목록
var active_battles: Array = []

# 배틀 매니저 참조 (전투창 직접 관리용)
var battle_manager: Node = null

# 플레이어 참조 (레벨업 연출용)
var player_node: Node2D = null

# 게임 상태
var is_paused: bool = false


func _ready() -> void:
	_init_party_status()
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
		
		# 스탯 복사
		party_stats[hero_id] = {
			"max_hp": max_hp,
			"attack": int(base_stats.get("attack", 10)),
			"defense": int(base_stats.get("defense", 5)),
			"speed": int(base_stats.get("speed", 5)),
			"luck": int(base_stats.get("luck", 5))
		}


func register_player(player: Node2D) -> void:
	## Player 노드 등록 (레벨업 연출용)
	player_node = player
	print("[GameManager] Player 등록됨")


func register_battle_manager(manager: Node) -> void:
	## BattleManager 등록 (전투창 직접 접근용)
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
			party_cooldowns[hero_id] = float(party_max_cooldowns[hero_id])


func _execute_hero_attack(hero_id: String) -> void:
	## 영웅 공격 실행 - 스킬 타입에 따라 분기
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
	
	# 스킬 타겟 타입 확인 (기본: single)
	var target_type = str(skill_data.get("target_type", "single"))
	
	match target_type:
		"single":
			_attack_single(hero_id, skill_data)
		"multi":
			_attack_multi(hero_id, skill_data)
		"all":
			_attack_all(hero_id, skill_data)
		_:
			_attack_single(hero_id, skill_data)


func _attack_single(hero_id: String, skill_data: Dictionary) -> void:
	## 단일 공격: 전투창 하나의 적 하나
	var windows = _get_active_windows()
	if windows.is_empty():
		return
	
	var target_window = windows[randi() % windows.size()]
	target_window.receive_hero_attack(hero_id, skill_data, "single")


func _attack_multi(hero_id: String, skill_data: Dictionary) -> void:
	## 범위 공격: 전투창 하나의 모든 적
	var windows = _get_active_windows()
	if windows.is_empty():
		return
	
	var target_window = windows[randi() % windows.size()]
	target_window.receive_hero_attack(hero_id, skill_data, "multi")


func _attack_all(hero_id: String, skill_data: Dictionary) -> void:
	## 전체 공격: 모든 전투창의 모든 적
	var windows = _get_active_windows()
	for window in windows:
		window.receive_hero_attack(hero_id, skill_data, "multi")


func _get_active_windows() -> Array:
	## 활성화된 전투창 목록 반환
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
		var was_alive = int(party_hp[hero_id]) > 0
		party_hp[hero_id] = maxi(0, int(party_hp[hero_id]) - damage)
		party_status_changed.emit()
		
		if was_alive and int(party_hp[hero_id]) <= 0:
			hero_died.emit(hero_id)
			_show_dead_popup(hero_id)
			
			# 전멸 체크
			if is_party_dead():
				_trigger_game_over()
			else:
				# 파티 재정렬 (죽은 멤버 뒤로)
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
	## 게임오버 처리
	game_over.emit()
	
	# 잠시 대기 후 게임오버 화면
	await get_tree().create_timer(0.8).timeout
	_show_game_over()


func _show_game_over() -> void:
	## 게임오버 UI 표시
	get_tree().paused = true
	is_paused = true
	
	var canvas = CanvasLayer.new()
	canvas.layer = 100
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(canvas)
	
	# 어두운 배경
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	
	# 중앙 컨테이너
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	center.add_child(vbox)
	
	# GAME OVER 텍스트
	var title = Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.RED)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# 다시하기 버튼
	var retry_btn = Button.new()
	retry_btn.text = "다시하기"
	retry_btn.add_theme_font_size_override("font_size", 20)
	retry_btn.custom_minimum_size = Vector2(150, 50)
	retry_btn.pressed.connect(_on_retry_pressed.bind(canvas))
	vbox.add_child(retry_btn)
	
	# 등장 애니메이션
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
	## 게임 상태 초기화
	active_battles.clear()
	party = ["warrior", "mage", "cleric", "thief"]
	party_hp.clear()
	party_max_hp.clear()
	party_cooldowns.clear()
	party_max_cooldowns.clear()
	party_level.clear()
	party_exp.clear()
	party_stats.clear()
	_init_party_status()


func _reorder_party() -> void:
	## 파티 재정렬: 살아있는 멤버 앞, 죽은 멤버 뒤
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
	
	# 순서가 바뀌었으면 시그널 발생
	if new_order != party:
		party = new_order
		party_order_changed.emit(party)
		print("[GameManager] 파티 재정렬: ", party)


func get_current_leader() -> String:
	## 현재 리더 (파티 첫 번째, 살아있는 멤버)
	for hero_id in party:
		if is_hero_alive(hero_id):
			return hero_id
	return ""


func get_cooldown_percent(hero_id: String) -> float:
	var current = float(party_cooldowns.get(hero_id, 0))
	var max_cd = float(party_max_cooldowns.get(hero_id, 1))
	return (max_cd - current) / max_cd


#region 레벨/경험치 시스템
func get_required_exp(level: int) -> int:
	## 다음 레벨에 필요한 총 경험치 (공식 방식)
	return int(100 * pow(level, 1.5))


func add_exp_to_party(total_exp: int) -> void:
	## 살아있는 파티원에게 경험치 분배 (균등 분배, 죽은 멤버 제외)
	var alive_heroes = get_alive_heroes()
	if alive_heroes.is_empty():
		return
	
	var exp_per_hero = total_exp  # 각자 전체 경험치 받음 (비율 아님)
	
	for hero_id in alive_heroes:
		_add_exp_to_hero(hero_id, exp_per_hero)


func _add_exp_to_hero(hero_id: String, amount: int) -> void:
	## 개별 영웅에게 경험치 추가
	if not party_exp.has(hero_id):
		return
	
	party_exp[hero_id] = int(party_exp[hero_id]) + amount
	exp_gained.emit(hero_id, amount, int(party_exp[hero_id]))
	
	# 레벨업 체크
	_check_level_up(hero_id)


func _check_level_up(hero_id: String) -> void:
	## 레벨업 가능한지 확인하고 처리
	var current_level = int(party_level[hero_id])
	var current_exp = int(party_exp[hero_id])
	var required_exp = get_required_exp(current_level)
	
	while current_exp >= required_exp:
		current_level += 1
		party_level[hero_id] = current_level
		
		var result = _apply_level_up(hero_id, current_level)
		hero_leveled_up.emit(hero_id, current_level, result["stat_changes"], result["new_skills"])
		
		# 연출
		_show_level_up_effect(hero_id, current_level, result["stat_changes"], result["new_skills"])
		
		required_exp = get_required_exp(current_level)


func _apply_level_up(hero_id: String, new_level: int) -> Dictionary:
	## 레벨업 적용: 스탯 증가 + 스킬 해금
	var hero_data = DataManager.get_hero(hero_id)
	var growth = hero_data.get("growth", {})
	var skill_unlocks = hero_data.get("skill_unlocks", {})
	
	var stat_changes = {}
	var new_skills = []
	
	# 스탯 증가
	var stats = party_stats[hero_id]
	for stat_name in growth.keys():
		var increase = int(growth[stat_name])
		var old_value = int(stats.get(stat_name, 0))
		var new_value = old_value + increase
		stats[stat_name] = new_value
		stat_changes[stat_name] = {"old": old_value, "new": new_value, "increase": increase}
	
	# max_hp 증가 시 현재 HP도 증가
	if stat_changes.has("max_hp"):
		var hp_increase = int(stat_changes["max_hp"]["increase"])
		party_max_hp[hero_id] = int(stats["max_hp"])
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
	## 스킬 해금 (combat.skills에 추가)
	# 현재는 JSON 기반이라 런타임에 추가하려면 별도 관리 필요
	# 일단 로그만 출력
	print("[GameManager] %s 스킬 해금: %s" % [hero_id, skill_id])


func _show_level_up_effect(hero_id: String, new_level: int, stat_changes: Dictionary, new_skills: Array) -> void:
	## 레벨업 연출 + 로그
	var hero_data = DataManager.get_hero(hero_id)
	var hero_name = str(hero_data.get("name", hero_id))
	
	# 로그 출력 (BattleManager의 HUD로)
	_send_log("[%s] Lv.%d 도달!" % [hero_name, new_level])
	
	# 스탯 변화 로그
	var stat_names = {"max_hp": "HP", "attack": "공격력", "defense": "방어력", "speed": "속도", "luck": "행운"}
	for stat_key in stat_changes.keys():
		var change = stat_changes[stat_key]
		var display_name = stat_names.get(stat_key, stat_key)
		_send_log("  %s +%d (%d → %d)" % [display_name, change["increase"], change["old"], change["new"]])
	
	# 스킬 해금 로그
	for skill_id in new_skills:
		var skill_data = DataManager.get_skill(skill_id)
		var skill_name = str(skill_data.get("name", skill_id))
		_send_log("[%s] 스킬 해금: %s" % [hero_name, skill_name])
	
	# 필드 위 연출
	_show_floating_text(hero_id, "Lv UP!", Color.YELLOW, new_skills)


func _send_log(text: String) -> void:
	## BattleManager HUD로 로그 전송
	if battle_manager and battle_manager.hud:
		battle_manager.hud.add_log(text)
	else:
		print(text)


func _show_floating_text(hero_id: String, text: String, color: Color, new_skills: Array) -> void:
	## 캐릭터 머리 위에 떠오르는 텍스트
	if player_node == null:
		return
	
	var target_node: Node2D = null
	
	# FieldParty에서 유닛 찾기
	if player_node.has_method("get_unit_by_id"):
		target_node = player_node.get_unit_by_id(hero_id)
	
	if target_node == null:
		return
	
	# "Lv UP!" 텍스트 생성
	_create_floating_label(target_node, text, color, 0.0)
	
	# 스킬 해금 시 추가 텍스트
	if new_skills.size() > 0:
		_create_floating_label(target_node, "New Skill!", Color.CYAN, 0.5)


func _create_floating_label(target: Node2D, text: String, color: Color, delay: float) -> void:
	## 떠오르는 라벨 생성
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	
	# 위치 설정 (캐릭터 머리 위)
	label.position = Vector2(-20, -30)
	label.modulate.a = 0.0
	
	target.add_child(label)
	
	# 애니메이션
	var tween = target.create_tween()
	
	if delay > 0:
		tween.tween_interval(delay)
	
	# 나타나면서 위로 떠오름
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 15, 0.8).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	
	# 유지
	tween.tween_interval(0.3)
	
	# 페이드아웃
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(label.queue_free)


func get_hero_level(hero_id: String) -> int:
	return int(party_level.get(hero_id, 1))


func get_hero_exp(hero_id: String) -> int:
	return int(party_exp.get(hero_id, 0))


func get_hero_stat(hero_id: String, stat_name: String) -> int:
	if party_stats.has(hero_id):
		return int(party_stats[hero_id].get(stat_name, 0))
	return 0
#endregion
