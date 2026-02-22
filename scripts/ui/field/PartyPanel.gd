extends Control
class_name PartyPanel
## 파티 초상화 패널 (하단 중앙, 가로 배치)
## HeroCard.tscn을 인스턴스하여 파티원별 초상화를 표시

const HeroCardScene := preload("res://scenes/ui/HeroCard.tscn")

signal equipment_dropped(hero_index: int, item_id: String)
signal hero_selected(hero_index: int)

@onready var cards_container: HBoxContainer = %CardsContainer

var cards: Array[HeroCard] = []
var selected_hero_index: int = -1
var selection_enabled: bool = true

# === 타겟팅 모드 ===
const ARROW_COLOR := Color(0.4, 0.85, 1.0, 0.9)
const ARROW_COLOR_VALID := Color(0.3, 1.0, 0.45, 0.95)
const ARROW_COLOR_ALLY := Color(0.35, 1.0, 0.7, 0.95)
const ARROW_WIDTH := 3.0
const ARROW_HEAD_SIZE := 10.0
const ARROW_STEPS := 24

var _targeting: bool = false
var _targeting_hero_id: String = ""
var _targeting_skill_id: String = ""
var _targeting_skill_data: Dictionary = {}
var _targeting_source_pos: Vector2 = Vector2.ZERO
var _targeting_is_ally_skill: bool = false
var _targeting_overlay: CanvasLayer = null
var _targeting_overlay_ctrl: Control = null
var _targeting_hovered_enemy: Node = null  # BattleEnemy
var _targeting_hovered_card: HeroCard = null


func _ready() -> void:
	_connect_signals()
	call_deferred("_initial_setup")
	set_process(true)


func _process(_delta: float) -> void:
	# Will/EXP 바를 매 프레임 갱신 (Will은 전투 밖에서도 항상 충전)
	_update_realtime_bars()
	# 타겟팅 오버레이 갱신
	if _targeting and _targeting_overlay_ctrl:
		_update_targeting_hover()
		_targeting_overlay_ctrl.queue_redraw()


func _initial_setup() -> void:
	if cards_container:
		update_display()


#region 시그널
func _connect_signals() -> void:
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(_on_party_changed):
			PartyManager.party_changed.connect(_on_party_changed)

	if BattleManager:
		if BattleManager.has_signal("party_hp_changed"):
			if not BattleManager.party_hp_changed.is_connected(update_display):
				BattleManager.party_hp_changed.connect(update_display)
		if BattleManager.has_signal("hero_attacked"):
			if not BattleManager.hero_attacked.is_connected(_on_hero_attacked):
				BattleManager.hero_attacked.connect(_on_hero_attacked)
		if BattleManager.has_signal("hero_damaged"):
			if not BattleManager.hero_damaged.is_connected(_on_hero_damaged):
				BattleManager.hero_damaged.connect(_on_hero_damaged)

#endregion


func _on_party_changed() -> void:
	update_display()


#region 카드 관리
func _rebuild_cards() -> void:
	cards.clear()
	if cards_container:
		for child in cards_container.get_children():
			cards_container.remove_child(child)
			child.queue_free()

	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		if party[i] == null:
			continue
		var card: HeroCard = HeroCardScene.instantiate()
		card.init(i)
		card.equipment_dropped.connect(_on_card_equip_dropped)
		card.field_heal_requested.connect(_on_field_heal_requested)
		card.card_selected.connect(_on_card_selected)
		card.active_skill_pressed.connect(_on_active_skill_pressed)
		cards_container.add_child(card)
		cards.append(card)
	_update_selection_visuals()


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	if cards.size() != party.size():
		_rebuild_cards()

	for i in range(cards.size()):
		if i >= party.size() or party[i] == null:
			continue
		cards[i].update_from_hero(party[i])
	_update_selection_visuals()
#endregion


#region 패널 레벨 API
func init_party(heroes: Array) -> void:
	## 파티 데이터로 초기화. 각 영웅의 max_hp에 따라 바 길이 자동 계산
	cards.clear()
	if cards_container:
		for child in cards_container.get_children():
			cards_container.remove_child(child)
			child.queue_free()
	for i in range(heroes.size()):
		if heroes[i] == null:
			continue
		var card: HeroCard = HeroCardScene.instantiate()
		card.init(i)
		card.equipment_dropped.connect(_on_card_equip_dropped)
		card.field_heal_requested.connect(_on_field_heal_requested)
		card.card_selected.connect(_on_card_selected)
		card.active_skill_pressed.connect(_on_active_skill_pressed)
		cards_container.add_child(card)
		cards.append(card)
		card.update_from_hero(heroes[i])
	_update_selection_visuals()


func update_hp(index: int, current: int, max_hp: int) -> void:
	if index >= 0 and index < cards.size():
		cards[index].update_hp(current, max_hp)




func set_dead(index: int, is_dead: bool) -> void:
	if index >= 0 and index < cards.size():
		cards[index].set_dead(is_dead)


func set_portrait(index: int, texture: Texture2D) -> void:
	if index >= 0 and index < cards.size():
		cards[index].set_portrait(texture)


func shake(index: int) -> void:
	if index >= 0 and index < cards.size():
		cards[index].shake()
#endregion


#region EXP 실시간 갱신
func _update_realtime_bars() -> void:
	## EXP 바만 경량 갱신
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(cards.size()):
		if i >= party.size():
			continue
		var hero: Hero = party[i]
		if hero == null:
			continue
		var card: HeroCard = cards[i]
		if not hero.is_dead:
			card.update_exp(hero.get_exp_ratio())
			card.update_level(hero.level)
		card.update_skill_atb_bars(hero)
		card.update_active_skill_cooldowns()
#endregion


#region 애니메이션 포워딩
func _find_card_by_hero_id(p_hero_id: String) -> HeroCard:
	for card in cards:
		if card.hero_id == p_hero_id:
			return card
	return null


func _on_hero_attacked(p_hero_id: String) -> void:
	var card := _find_card_by_hero_id(p_hero_id)
	if card:
		card.play_attack_anim()


func _on_hero_damaged(p_hero_id: String) -> void:
	var card := _find_card_by_hero_id(p_hero_id)
	if card:
		card.play_damage_anim()
#endregion


#region 이벤트 포워딩
func _on_card_equip_dropped(hero_index: int, item_id: String) -> void:
	equipment_dropped.emit(hero_index, item_id)


func _on_field_heal_requested(hero_index: int) -> void:
	_try_field_heal(hero_index)


func _on_active_skill_pressed(p_hero_id: String, skill_id: String) -> void:
	## 액티브 스킬 버튼 → 타겟팅 모드 진입
	if _targeting:
		_cancel_targeting()
	if BattleManager == null or BattleManager.get_active_battle_count() == 0:
		return
	if not CooldownManager.is_skill_ready(p_hero_id, skill_id):
		return
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	if skill_data.is_empty():
		return
	var target_type: String = str(skill_data.get("target", "single_enemy"))
	# AOE는 타겟팅 불필요 → 즉시 발동
	if target_type == "all_enemies" or target_type == "all_allies":
		_execute_skill_immediate(p_hero_id, skill_id)
		return
	_start_targeting(p_hero_id, skill_id, skill_data)


func _on_card_accordion_toggle(hero_index: int) -> void:
	pass


func _on_card_selected(hero_index: int) -> void:
	if _targeting:
		return  # 타겟팅 중에는 카드 선택 무시
	if not selection_enabled:
		return
	if hero_index < 0:
		return
	selected_hero_index = hero_index
	_update_selection_visuals()
	hero_selected.emit(hero_index)


func _on_item_equipped(hero_name: String, item_id: String, slot: String, _replaced_id: String) -> void:
	pass
#endregion


func get_hero_slot_global_center(hero_name: String, slot: String) -> Vector2:
	return Vector2.ZERO


func _update_selection_visuals() -> void:
	if cards.is_empty():
		return
	if selected_hero_index >= cards.size():
		selected_hero_index = cards.size() - 1
	if selected_hero_index < -1:
		selected_hero_index = -1
	for i in range(cards.size()):
		cards[i].set_selected(i == selected_hero_index)


func get_selected_hero_index() -> int:
	return selected_hero_index


func set_selection_enabled(enabled: bool) -> void:
	selection_enabled = enabled
	if not enabled:
		selected_hero_index = -1
	_update_selection_visuals()


func set_selected_hero_index(index: int, emit_signal: bool = false) -> void:
	if cards.is_empty():
		selected_hero_index = -1
		return
	if index < 0:
		selected_hero_index = -1
	else:
		selected_hero_index = clampi(index, 0, cards.size() - 1)
	_update_selection_visuals()
	if emit_signal and selected_hero_index >= 0:
		hero_selected.emit(selected_hero_index)


#region 타겟팅 모드
func _start_targeting(hero_id: String, skill_id: String, skill_data: Dictionary) -> void:
	_targeting = true
	_targeting_hero_id = hero_id
	_targeting_skill_id = skill_id
	_targeting_skill_data = skill_data
	var target_type: String = str(skill_data.get("target", "single_enemy"))
	_targeting_is_ally_skill = target_type in ["single_ally", "all_allies"]

	# 소스 위치: 해당 히어로 카드 중앙
	for card in cards:
		if card.hero_id == hero_id:
			_targeting_source_pos = card.global_position + card.size * 0.5
			break

	_create_targeting_overlay()


func _create_targeting_overlay() -> void:
	_targeting_overlay = CanvasLayer.new()
	_targeting_overlay.layer = 200
	_targeting_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_targeting_overlay)

	_targeting_overlay_ctrl = Control.new()
	_targeting_overlay_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_targeting_overlay_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	_targeting_overlay_ctrl.draw.connect(_draw_targeting_arrow)
	_targeting_overlay_ctrl.gui_input.connect(_on_targeting_input)
	_targeting_overlay.add_child(_targeting_overlay_ctrl)


func _cancel_targeting() -> void:
	_clear_targeting_highlights()
	_targeting = false
	_targeting_hero_id = ""
	_targeting_skill_id = ""
	_targeting_skill_data = {}
	_targeting_hovered_enemy = null
	_targeting_hovered_card = null
	if _targeting_overlay:
		_targeting_overlay.queue_free()
		_targeting_overlay = null
		_targeting_overlay_ctrl = null


func _execute_skill_immediate(hero_id: String, skill_id: String) -> void:
	## AOE/전체 아군 스킬 → 타겟팅 없이 즉시 발동
	var battle_windows: Array = get_tree().get_nodes_in_group("battle_windows")
	for bw in battle_windows:
		if bw.has_method("execute_active_skill"):
			bw.execute_active_skill(hero_id, skill_id)
			return


func _update_targeting_hover() -> void:
	## 매 프레임: 마우스 아래 유효한 타겟 감지 + 하이라이트
	var mouse_pos: Vector2 = _targeting_overlay_ctrl.get_global_mouse_position()
	var prev_enemy: Node = _targeting_hovered_enemy
	var prev_card: HeroCard = _targeting_hovered_card
	_targeting_hovered_enemy = null
	_targeting_hovered_card = null

	if _targeting_is_ally_skill:
		# 아군 카드 호버 감지
		for card in cards:
			if card.hero_id.is_empty():
				continue
			var rect := Rect2(card.global_position, card.size)
			if rect.has_point(mouse_pos):
				_targeting_hovered_card = card
				break
	else:
		# 적 호버 감지
		var battle_windows: Array = get_tree().get_nodes_in_group("battle_windows")
		for bw in battle_windows:
			if not bw.has_method("get_enemy_at_position"):
				continue
			var enemy: Node = bw.get_enemy_at_position(mouse_pos)
			if enemy != null:
				_targeting_hovered_enemy = enemy
				break

	# 하이라이트 갱신
	if prev_enemy != _targeting_hovered_enemy:
		if prev_enemy != null and is_instance_valid(prev_enemy) and prev_enemy.has_method("set_hover_highlight"):
			prev_enemy.set_hover_highlight(false)
		if _targeting_hovered_enemy != null and _targeting_hovered_enemy.has_method("set_hover_highlight"):
			_targeting_hovered_enemy.set_hover_highlight(true)


func _clear_targeting_highlights() -> void:
	if _targeting_hovered_enemy != null and is_instance_valid(_targeting_hovered_enemy):
		if _targeting_hovered_enemy.has_method("set_hover_highlight"):
			_targeting_hovered_enemy.set_hover_highlight(false)
	_targeting_hovered_enemy = null
	_targeting_hovered_card = null


func _draw_targeting_arrow() -> void:
	## 오버레이 _draw 콜백: 베지어 화살표
	if not _targeting or _targeting_overlay_ctrl == null:
		return
	var mouse_pos: Vector2 = _targeting_overlay_ctrl.get_global_mouse_position()
	var from: Vector2 = _targeting_source_pos
	var to: Vector2 = mouse_pos

	# 유효 타겟 위에 있으면 색상 변경
	var has_valid_target: bool = (_targeting_hovered_enemy != null) or (_targeting_hovered_card != null)
	var color: Color
	if has_valid_target:
		color = ARROW_COLOR_ALLY if _targeting_is_ally_skill else ARROW_COLOR_VALID
	else:
		color = ARROW_COLOR

	# 베지어 커브 계산
	var dist: float = from.distance_to(to)
	var mid: Vector2 = (from + to) * 0.5
	var control: Vector2 = mid - Vector2(0, dist * 0.3)
	var points := PackedVector2Array()
	for i in range(ARROW_STEPS + 1):
		var t: float = float(i) / float(ARROW_STEPS)
		var a: Vector2 = from.lerp(control, t)
		var b: Vector2 = control.lerp(to, t)
		points.append(a.lerp(b, t))

	# 곡선 그리기
	if points.size() >= 2:
		_targeting_overlay_ctrl.draw_polyline(points, color, ARROW_WIDTH, true)

	# 화살촉
	if points.size() >= 2:
		var tip: Vector2 = points[-1]
		var dir: Vector2 = (points[-1] - points[-2]).normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var left: Vector2 = tip - dir * ARROW_HEAD_SIZE + perp * ARROW_HEAD_SIZE * 0.5
		var right: Vector2 = tip - dir * ARROW_HEAD_SIZE - perp * ARROW_HEAD_SIZE * 0.5
		_targeting_overlay_ctrl.draw_polygon(
			PackedVector2Array([tip, left, right]),
			PackedColorArray([color, color, color])
		)

	# 유효 타겟 위에 원형 표시
	if has_valid_target:
		var target_center: Vector2 = to
		if _targeting_hovered_enemy != null and is_instance_valid(_targeting_hovered_enemy):
			target_center = _targeting_hovered_enemy.global_position + _targeting_hovered_enemy.size * 0.5
		elif _targeting_hovered_card != null:
			target_center = _targeting_hovered_card.global_position + _targeting_hovered_card.size * 0.5
		_targeting_overlay_ctrl.draw_arc(target_center, 18.0, 0, TAU, 32, color, 2.0, true)


func _on_targeting_input(event: InputEvent) -> void:
	## 타겟팅 오버레이 입력 처리
	if not _targeting:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_targeting()
				_targeting_overlay_ctrl.accept_event()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				_try_confirm_target(mb.global_position)
				_targeting_overlay_ctrl.accept_event()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and key.keycode == KEY_ESCAPE:
			_cancel_targeting()


func _try_confirm_target(pos: Vector2) -> void:
	if _targeting_is_ally_skill:
		_try_confirm_ally_target(pos)
	else:
		_try_confirm_enemy_target(pos)


func _try_confirm_enemy_target(pos: Vector2) -> void:
	var battle_windows: Array = get_tree().get_nodes_in_group("battle_windows")
	for bw in battle_windows:
		if not bw.has_method("get_enemy_at_position"):
			continue
		var enemy = bw.get_enemy_at_position(pos)
		if enemy != null:
			var hero_id: String = _targeting_hero_id
			var skill_id: String = _targeting_skill_id
			_cancel_targeting()
			bw.execute_active_skill(hero_id, skill_id, enemy)
			return
	# 유효한 타겟 없으면 무시 (취소하지 않음)


func _try_confirm_ally_target(pos: Vector2) -> void:
	for card in cards:
		if card.hero_id.is_empty():
			continue
		var rect := Rect2(card.global_position, card.size)
		if rect.has_point(pos):
			var hero_id: String = _targeting_hero_id
			var skill_id: String = _targeting_skill_id
			var target_hero_id: String = card.hero_id
			_cancel_targeting()
			# 대상 아군에게 스킬 발동
			var battle_windows: Array = get_tree().get_nodes_in_group("battle_windows")
			for bw in battle_windows:
				if bw.has_method("execute_active_skill"):
					bw.execute_active_skill(hero_id, skill_id, null, target_hero_id)
					return
			return
#endregion


#region 필드 힐
func _try_field_heal(hero_index: int) -> void:
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		return

	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return

	var target: Hero = party[hero_index]
	if target == null or target.is_dead:
		return
	if target.current_hp >= target.get_max_hp():
		return

	var healer := _find_available_healer()
	if healer == null:
		return

	_execute_field_heal(healer, target)


func _find_available_healer() -> Hero:
	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		if hero == null or hero.is_dead:
			continue
		if hero.class_id != "cleric":
			continue
		if CooldownManager and not CooldownManager.is_skill_ready(hero.id, "heal"):
			continue
		return hero
	return null


func _execute_field_heal(healer: Hero, target: Hero) -> void:
	var skill_data: Dictionary = DataManager.get_skill("heal")

	var base_value: int = int(skill_data.get("base_damage", 25))
	var scaling: float = skill_data.get("scaling", 1.2)
	var int_stat: int = healer.get_int()
	var heal_amount: int = int(base_value + int_stat * scaling)

	var actual_heal := target.heal(heal_amount)

	if CooldownManager:
		CooldownManager.start_cooldown(healer.id, "heal")
	if SoundManager:
		SoundManager.play_heal()

	update_display()

	if BattleManager:
		BattleManager.battle_log_received.emit(
			"[필드] %s → %s HP +%d" % [healer.hero_name, target.hero_name, actual_heal],
			Color.LIGHT_GREEN
		)
#endregion
