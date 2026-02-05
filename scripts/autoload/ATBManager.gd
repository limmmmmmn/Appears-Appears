extends Node
## ATBManager: 중앙 ATB 관리 시스템
## - 모든 영웅의 ATB를 중앙에서 관리
## - 적 ATB는 각 전투창에서 관리
## - 영웅 ATB가 차면 스킬/타겟 선택 UI 표시

signal hero_atb_ready(hero: Hero)  # 영웅 ATB 충전 완료
signal hero_action_completed(hero: Hero)  # 영웅 행동 완료
signal target_selection_requested(hero: Hero, skill_id: String)  # 타겟 선택 요청
signal action_executed  # 액션 실행됨

# ATB 설정
const ATB_MAX: float = 100.0
const ATB_FILL_RATE: float = 30.0  # 기본 충전 속도
const ALLY_SPEED_MULT: float = 2.0  # 아군 속도 배율 (2배)

# 영웅 ATB 상태
var hero_atb: Dictionary = {}  # hero_id -> {hero: Hero, atb: float, speed: int}
var is_paused: bool = false  # 타겟 선택 중 일시정지
var is_processing_action: bool = false  # 액션 처리 중

# 현재 행동 중인 영웅
var current_hero: Hero = null
var current_skill_id: String = ""

# UI 참조
var action_ui: Control = null


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
	current_hero = null
	current_skill_id = ""

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
	current_hero = null
	current_skill_id = ""
	if action_ui and is_instance_valid(action_ui):
		action_ui.queue_free()
		action_ui = null


func get_hero_atb(hero_id: String) -> float:
	## 특정 영웅의 ATB 값 반환
	if hero_atb.has(hero_id):
		return hero_atb[hero_id]["atb"]
	return 0.0


func get_all_hero_atb() -> Dictionary:
	## 모든 영웅 ATB 반환
	return hero_atb


func set_paused(paused: bool) -> void:
	## ATB 일시정지/재개
	is_paused = paused


func _update_hero_atb(delta: float) -> void:
	## 영웅 ATB 업데이트
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

	# 준비된 영웅이 있으면 행동 시작
	if ready_hero != null:
		_start_hero_action(ready_hero)


func _start_hero_action(hero: Hero) -> void:
	## 영웅 행동 시작 - 스킬 선택 UI 표시
	is_paused = true
	is_processing_action = true
	current_hero = hero

	# 모든 전투창 일시정지
	_pause_all_battle_windows(true)

	# 스킬 선택 UI 표시
	_show_skill_selection_ui(hero)


func _show_skill_selection_ui(hero: Hero) -> void:
	## 스킬 선택 UI 표시
	if action_ui and is_instance_valid(action_ui):
		action_ui.queue_free()

	action_ui = _create_skill_selection_ui(hero)

	# CanvasLayer에 추가하여 최상위에 표시
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.name = "ATBActionUI"
	get_tree().root.add_child(canvas)
	canvas.add_child(action_ui)


func _create_skill_selection_ui(hero: Hero) -> Control:
	## 스킬 선택 UI 생성
	# CenterContainer로 중앙 정렬
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 200)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.4, 0.6, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(inner_vbox)

	# 제목
	var title := Label.new()
	title.text = "⚔️ %s의 턴" % hero.hero_name
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(title)

	# 구분선
	var sep := HSeparator.new()
	inner_vbox.add_child(sep)

	# 스킬 버튼들
	var skills := hero.get_available_skills()
	for skill_id in skills:
		var skill_data: Dictionary = DataManager.get_skill(skill_id)
		if skill_data.is_empty():
			continue

		var btn := Button.new()
		var skill_name: String = skill_data.get("name", skill_id)
		var cooldown: float = CooldownManager.get_remaining_cooldown(hero.id, skill_id)

		if cooldown > 0:
			btn.text = "%s (%.1f초)" % [skill_name, cooldown]
			btn.disabled = true
		else:
			btn.text = skill_name
			btn.pressed.connect(_on_skill_selected.bind(skill_id))

		btn.custom_minimum_size.y = 35
		inner_vbox.add_child(btn)

	center.add_child(panel)
	return center


func _on_skill_selected(skill_id: String) -> void:
	## 스킬 선택됨
	current_skill_id = skill_id
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var target_type: String = skill_data.get("target", "single_enemy")

	# UI 제거
	if action_ui and is_instance_valid(action_ui):
		var canvas = action_ui.get_parent()
		action_ui.queue_free()
		if canvas:
			canvas.queue_free()
		action_ui = null

	# 타겟 타입에 따른 처리
	match target_type:
		"single_ally":
			_show_ally_selection_ui()
		"all_allies":
			_execute_ally_skill_all()
		"all_enemies":
			_execute_aoe_skill()
		_:  # single_enemy
			_show_enemy_selection_ui()


func _show_enemy_selection_ui() -> void:
	## 적 선택 UI 표시 (모든 전투창의 적 표시)
	action_ui = _create_enemy_selection_ui()

	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.name = "ATBTargetUI"
	get_tree().root.add_child(canvas)
	canvas.add_child(action_ui)


func _create_enemy_selection_ui() -> Control:
	## 적 선택 UI 생성
	# CenterContainer로 중앙 정렬
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(350, 300)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.08, 0.08, 0.95)
	style.border_color = Color(0.9, 0.4, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 280)
	panel.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	# 제목
	var title := Label.new()
	title.text = "🎯 공격 대상 선택"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 모든 전투창의 적 목록
	var enemies_found := false
	for battle_id in BattleManager.active_battles:
		var battle_data: Dictionary = BattleManager.active_battles[battle_id]
		var window: BattleWindow = battle_data.get("window")
		if window == null or not is_instance_valid(window):
			continue

		var enemies: Array = window.get_alive_enemies()
		if enemies.is_empty():
			continue

		enemies_found = true

		# 전투창 라벨
		var window_label := Label.new()
		window_label.text = "━ 전투창 %d ━" % (battle_id + 1)
		window_label.add_theme_font_size_override("font_size", 11)
		window_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		window_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(window_label)

		# 적 버튼들 - battle_id와 enemy의 battle_uid를 저장 (window 참조 대신)
		for enemy in enemies:
			var btn := Button.new()
			var hp_percent: int = int((float(enemy.current_hp) / enemy.max_hp) * 100)
			btn.text = "%s (HP: %d%%)" % [enemy.enemy_name, hp_percent]
			btn.custom_minimum_size.y = 32
			btn.pressed.connect(_on_enemy_selected.bind(battle_id, enemy.battle_uid))
			vbox.add_child(btn)

	if not enemies_found:
		var no_enemy := Label.new()
		no_enemy.text = "공격할 적이 없습니다"
		no_enemy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(no_enemy)

	# 취소 버튼
	var cancel_sep := HSeparator.new()
	vbox.add_child(cancel_sep)

	var cancel_btn := Button.new()
	cancel_btn.text = "취소"
	cancel_btn.custom_minimum_size.y = 30
	cancel_btn.pressed.connect(_on_target_selection_cancelled)
	vbox.add_child(cancel_btn)

	center.add_child(panel)
	return center


func _on_enemy_selected(battle_id: int, enemy_uid: int) -> void:
	## 적 선택됨 - 공격 실행
	_cleanup_ui()

	# battle_id로 window 가져오기
	if not BattleManager.active_battles.has(battle_id):
		_finish_action()
		return

	var battle_data: Dictionary = BattleManager.active_battles[battle_id]
	var window: BattleWindow = battle_data.get("window")
	if window == null or not is_instance_valid(window):
		_finish_action()
		return

	# enemy_uid로 적 찾기
	var target_enemy: BattleEnemy = null
	for enemy in window.get_alive_enemies():
		if enemy.battle_uid == enemy_uid:
			target_enemy = enemy
			break

	if target_enemy == null:
		_finish_action()
		return

	# 해당 전투창에서 공격 실행
	await window.execute_hero_attack(current_hero, current_skill_id, target_enemy)

	# 쿨타임 시작
	CooldownManager.start_cooldown(current_hero.id, current_skill_id)

	# ATB 리셋
	if hero_atb.has(current_hero.id):
		hero_atb[current_hero.id]["atb"] = 0.0

	_finish_action()


func _on_target_selection_cancelled() -> void:
	## 타겟 선택 취소 - 스킬 선택으로 돌아가기
	_cleanup_ui()
	_show_skill_selection_ui(current_hero)


func _show_ally_selection_ui() -> void:
	## 아군 선택 UI 표시
	action_ui = _create_ally_selection_ui()

	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.name = "ATBAllyUI"
	get_tree().root.add_child(canvas)
	canvas.add_child(action_ui)


func _create_ally_selection_ui() -> Control:
	## 아군 선택 UI 생성
	# CenterContainer로 중앙 정렬
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 250)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.08, 0.95)
	style.border_color = Color(0.4, 0.9, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "💚 대상 선택"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 아군 버튼들 - hero.id 저장
	var heroes := PartyManager.get_alive_heroes()
	for hero in heroes:
		var btn := Button.new()
		var hp_percent: int = int((float(hero.current_hp) / hero.get_max_hp()) * 100)
		btn.text = "%s (HP: %d%%)" % [hero.hero_name, hp_percent]
		btn.custom_minimum_size.y = 32
		btn.pressed.connect(_on_ally_selected.bind(hero.id))
		vbox.add_child(btn)

	# 취소 버튼
	var cancel_sep := HSeparator.new()
	vbox.add_child(cancel_sep)

	var cancel_btn := Button.new()
	cancel_btn.text = "취소"
	cancel_btn.custom_minimum_size.y = 30
	cancel_btn.pressed.connect(_on_target_selection_cancelled)
	vbox.add_child(cancel_btn)

	center.add_child(panel)
	return center


func _on_ally_selected(hero_id: String) -> void:
	## 아군 선택됨 - 스킬 실행
	_cleanup_ui()

	# hero_id로 영웅 찾기
	var target_hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if target_hero == null:
		_finish_action()
		return

	var skill_data: Dictionary = DataManager.get_skill(current_skill_id)
	_execute_ally_skill(current_hero, target_hero, skill_data)

	# 쿨타임 시작
	CooldownManager.start_cooldown(current_hero.id, current_skill_id)

	# ATB 리셋
	if hero_atb.has(current_hero.id):
		hero_atb[current_hero.id]["atb"] = 0.0

	_finish_action()


func _execute_ally_skill(caster: Hero, target: Hero, skill_data: Dictionary) -> void:
	## 아군 대상 스킬 실행
	var skill_type: String = skill_data.get("type", "heal")
	var base_value: int = int(skill_data.get("base_damage", 20))
	var scaling: float = skill_data.get("scaling", 1.0)

	if skill_type == "heal":
		var int_stat: int = caster.get_int()
		var heal_amount: int = int(base_value + int_stat * scaling)
		target.heal(heal_amount)

		# 로그 전송
		BattleManager.battle_log_received.emit(
			"💚 %s → %s 회복! (+%d HP)" % [caster.hero_name, target.hero_name, heal_amount],
			Color.LIGHT_GREEN
		)


func _execute_ally_skill_all() -> void:
	## 전체 아군 스킬 실행
	_cleanup_ui()

	var skill_data: Dictionary = DataManager.get_skill(current_skill_id)
	var heroes := PartyManager.get_alive_heroes()

	for hero in heroes:
		_execute_ally_skill(current_hero, hero, skill_data)

	# 쿨타임 시작
	CooldownManager.start_cooldown(current_hero.id, current_skill_id)

	# ATB 리셋
	if hero_atb.has(current_hero.id):
		hero_atb[current_hero.id]["atb"] = 0.0

	_finish_action()


func _execute_aoe_skill() -> void:
	## 전체 공격 스킬 실행 (모든 전투창의 적에게)
	_cleanup_ui()

	var skill_data: Dictionary = DataManager.get_skill(current_skill_id)
	var total_damage: int = 0
	var enemies_hit: int = 0

	# 모든 전투창의 적 공격
	for battle_id in BattleManager.active_battles:
		var battle_data: Dictionary = BattleManager.active_battles[battle_id]
		var window: BattleWindow = battle_data.get("window")
		if window == null or not is_instance_valid(window):
			continue

		var enemies: Array = window.get_alive_enemies()
		for enemy in enemies:
			var damage: int = _calculate_damage(current_hero, enemy, skill_data)
			enemy.take_damage(damage)
			total_damage += damage
			enemies_hit += 1

			# 적 사망 처리
			if not enemy.is_alive():
				window.on_enemy_defeated(enemy)

	# 로그 전송
	if enemies_hit > 0:
		BattleManager.battle_log_received.emit(
			"🔥 %s의 %s! %d명에게 총 %d 피해" % [
				current_hero.hero_name,
				skill_data.get("name", "공격"),
				enemies_hit,
				total_damage
			],
			Color.ORANGE
		)

	# 쿨타임 시작
	CooldownManager.start_cooldown(current_hero.id, current_skill_id)

	# ATB 리셋
	if hero_atb.has(current_hero.id):
		hero_atb[current_hero.id]["atb"] = 0.0

	_finish_action()


func _calculate_damage(attacker: Hero, target: BattleEnemy, skill_data: Dictionary) -> int:
	## 데미지 계산
	var damage_type: String = skill_data.get("damage_type", "physical")
	var base_damage: int = int(skill_data.get("base_damage", 10))
	var scaling: float = skill_data.get("scaling", 1.0)

	var atk_stat: int = 0
	var def_stat: int = target.get_def()

	if damage_type == "magic":
		atk_stat = attacker.get_int()
	else:
		atk_stat = attacker.get_str()

	var raw_damage: int = int(base_damage + atk_stat * scaling)
	var final_damage: int = maxi(1, raw_damage - def_stat / 2)

	# 크리티컬 체크
	var crit_chance: float = attacker.get_luk() / 100.0
	if randf() < crit_chance:
		final_damage = int(final_damage * 1.5)

	return final_damage


func _cleanup_ui() -> void:
	## UI 정리
	if action_ui and is_instance_valid(action_ui):
		var canvas = action_ui.get_parent()
		action_ui.queue_free()
		if canvas and is_instance_valid(canvas):
			canvas.queue_free()
		action_ui = null


func _finish_action() -> void:
	## 행동 완료 처리
	current_hero = null
	current_skill_id = ""
	is_processing_action = false
	is_paused = false

	# 모든 전투창 재개
	_pause_all_battle_windows(false)

	action_executed.emit()


func _pause_all_battle_windows(paused: bool) -> void:
	## 모든 전투창 일시정지/재개
	for battle_id in BattleManager.active_battles:
		var battle_data: Dictionary = BattleManager.active_battles[battle_id]
		var window: BattleWindow = battle_data.get("window")
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
