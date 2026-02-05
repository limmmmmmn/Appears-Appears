extends Control
class_name BottomPartyCards
## 하단 파티 카드 UI - 파티원당 개별 카드
## 평소에는 상단만 보이고, 마우스 hover시 위로 튀어나옴

const SLOT_ICONS := {"main_hand": "⚔", "off_hand": "🛡", "head": "👒", "body": "👕", "acc1": "💍", "acc2": "💍"}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

# 카드 크기
const CARD_WIDTH := 105
const CARD_HEIGHT := 170
const CARD_VISIBLE_HEIGHT := 58  # 평소 보이는 높이 (이름 + HP + 공격바)
const CARD_SPACING := 6
const HOVER_OFFSET := 115  # 마우스 hover시 올라가는 높이

# 색상
const HP_COLOR_HIGH := Color(0.2, 0.75, 0.2)
const HP_COLOR_MID := Color(0.9, 0.7, 0.2)
const HP_COLOR_LOW := Color(0.9, 0.2, 0.2)

# 시그널
signal equipment_dropped(hero_index: int, item_id: String)

# 카드 데이터
class HeroCard:
	var wrapper: Control  # 래퍼 (HBoxContainer 자식, 클리핑용)
	var panel: PanelContainer  # 실제 카드 패널 (wrapper 자식, 애니메이션 대상)
	var drop_target: Control  # 드롭 영역
	var name_label: Label
	var hp_bar: ProgressBar
	var hp_label: Label
	var atb_section: VBoxContainer
	var basic_atb_bar: ProgressBar
	var skill_rows: Dictionary = {}  # skill_id -> {row, bar, label}
	var equip_section: VBoxContainer
	var equip_rows: Dictionary = {}
	var hero_index: int = -1
	var hero_id: String = ""
	var is_hovered: bool = false

var hero_cards: Array[HeroCard] = []
var cards_container: HBoxContainer


func _ready() -> void:
	_build_ui()
	_connect_signals()
	update_display()


func _build_ui() -> void:
	# 전체 컨테이너 (하단 전체 폭, 중앙 정렬)
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	# 카드 래퍼가 화면 하단에 위치하도록 (래퍼 전체 높이만큼)
	offset_top = -CARD_HEIGHT
	offset_bottom = 0

	# HBoxContainer로 카드들을 가로로 배치 (중앙 정렬)
	cards_container = HBoxContainer.new()
	cards_container.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	cards_container.add_theme_constant_override("separation", CARD_SPACING)
	add_child(cards_container)


func _connect_signals() -> void:
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(_on_party_changed):
			PartyManager.party_changed.connect(_on_party_changed)

	if BattleManager:
		if BattleManager.has_signal("party_hp_changed"):
			if not BattleManager.party_hp_changed.is_connected(update_display):
				BattleManager.party_hp_changed.connect(update_display)

	if ATBManager and ATBManager.has_signal("atb_updated"):
		if not ATBManager.atb_updated.is_connected(_on_atb_updated):
			ATBManager.atb_updated.connect(_on_atb_updated)


func _on_party_changed() -> void:
	_rebuild_cards()
	update_display()


func _rebuild_cards() -> void:
	## 파티원 수에 맞게 카드 재구성
	# 기존 카드 데이터 초기화
	hero_cards.clear()

	# cards_container의 모든 자식 즉시 제거 (free 사용으로 즉시 삭제)
	if cards_container:
		for child in cards_container.get_children():
			cards_container.remove_child(child)
			child.free()  # queue_free 대신 free로 즉시 삭제

	var party: Array = PartyManager.get_party() if PartyManager else []

	# 새 카드 생성
	for i in range(party.size()):
		if party[i] == null:
			continue
		var card := _create_hero_card(i)
		hero_cards.append(card)
		cards_container.add_child(card.wrapper)


func _create_hero_card(index: int) -> HeroCard:
	var card := HeroCard.new()
	card.hero_index = index

	# 래퍼 컨트롤 (HBoxContainer의 자식으로 들어감, 클리핑 담당)
	card.wrapper = Control.new()
	card.wrapper.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.wrapper.clip_contents = true  # 패널이 래퍼 밖으로 나가면 잘림

	# 메인 패널 (래퍼 안에서 움직임)
	card.panel = PanelContainer.new()
	card.panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.panel.position.y = HOVER_OFFSET  # 초기 위치: 아래로 내려가 있음
	_style_card_panel(card.panel)
	card.wrapper.add_child(card.panel)

	# 드롭 타겟 (전체 카드 영역) + hover 처리
	card.drop_target = _EquipDropTarget.new()
	card.drop_target.hero_index = index
	card.drop_target.cards_ref = self
	card.drop_target.card_ref = card
	card.drop_target.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.panel.add_child(card.drop_target)

	# 내부 VBox
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 5
	vbox.offset_right = -5
	vbox.offset_top = 5
	vbox.offset_bottom = -5
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.drop_target.add_child(vbox)

	# === 이름 ===
	card.name_label = Label.new()
	card.name_label.text = "영웅"
	card.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.name_label.add_theme_font_size_override("font_size", 10)
	card.name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	card.name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(card.name_label)

	# === HP바 ===
	var hp_container := Control.new()
	hp_container.custom_minimum_size = Vector2(0, 12)
	hp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hp_container)

	card.hp_bar = ProgressBar.new()
	card.hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.hp_bar.max_value = 100.0
	card.hp_bar.value = 100.0
	card.hp_bar.show_percentage = false
	card.hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_hp_bar(card.hp_bar)
	hp_container.add_child(card.hp_bar)

	card.hp_label = Label.new()
	card.hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.hp_label.add_theme_font_size_override("font_size", 8)
	card.hp_label.add_theme_color_override("font_color", Color.WHITE)
	card.hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	card.hp_label.add_theme_constant_override("outline_size", 2)
	card.hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_container.add_child(card.hp_label)

	# === ATB 섹션 ===
	card.atb_section = VBoxContainer.new()
	card.atb_section.add_theme_constant_override("separation", 1)
	card.atb_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(card.atb_section)

	# 기본 공격 ATB
	var basic_row := _create_atb_row("공격")
	card.basic_atb_bar = basic_row.get_node("Bar")
	card.atb_section.add_child(basic_row)

	# === 구분선 ===
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# === 장비 섹션 ===
	card.equip_section = VBoxContainer.new()
	card.equip_section.add_theme_constant_override("separation", 0)
	card.equip_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(card.equip_section)

	for slot_name in SLOT_ORDER:
		var row := _create_equip_row(slot_name)
		card.equip_section.add_child(row)
		card.equip_rows[slot_name] = row

	return card


func _style_card_panel(panel: PanelContainer) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.4, 0.55, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)


func _create_atb_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	label.custom_minimum_size.x = 24
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(60, 5)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_atb_bar(bar, false)
	row.add_child(bar)

	return row


func _create_equip_row(slot_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_lbl := Label.new()
	icon_lbl.name = "Icon"
	icon_lbl.text = SLOT_ICONS.get(slot_name, "?")
	icon_lbl.add_theme_font_size_override("font_size", 8)
	icon_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	icon_lbl.custom_minimum_size.x = 12
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = "-"
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	return row


func _style_hp_bar(bar: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.1, 0.1)
	bg.corner_radius_top_left = 3
	bg.corner_radius_top_right = 3
	bg.corner_radius_bottom_left = 3
	bg.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = HP_COLOR_HIGH
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	bar.add_theme_stylebox_override("fill", fill)


func _style_atb_bar(bar: ProgressBar, is_ready: bool) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.2)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.8, 0.2) if is_ready else Color(0.3, 0.7, 1.0)
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)


func _style_cooldown_bar(bar: ProgressBar, is_ready: bool) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.2)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.8, 0.3) if is_ready else Color(0.4, 0.4, 0.5)
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)


#region Hover 애니메이션
func _on_card_mouse_entered(card: HeroCard) -> void:
	if card.is_hovered:
		return
	card.is_hovered = true

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	# 래퍼 안에서 패널을 위로 올림 (HOVER_OFFSET -> 0)
	tween.tween_property(card.panel, "position:y", 0.0, 0.2)


func _on_card_mouse_exited(card: HeroCard) -> void:
	if not card.is_hovered:
		return
	card.is_hovered = false

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	# 래퍼 안에서 패널을 아래로 내림 (0 -> HOVER_OFFSET)
	tween.tween_property(card.panel, "position:y", float(HOVER_OFFSET), 0.15)
#endregion


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	# 카드 수와 파티원 수가 다르면 재구성
	if hero_cards.size() != party.size():
		_rebuild_cards()
		return

	for i in range(hero_cards.size()):
		if i >= party.size() or party[i] == null:
			continue

		var card := hero_cards[i]
		var hero: Hero = party[i]
		card.hero_id = hero.id

		# 이름 업데이트
		card.name_label.text = hero.hero_name

		# HP 업데이트
		var max_hp := hero.get_max_hp()
		var hp_percent: float = float(hero.current_hp) / float(max_hp) if max_hp > 0 else 1.0
		card.hp_bar.value = hp_percent * 100.0
		card.hp_label.text = "%d/%d" % [hero.current_hp, max_hp]
		_update_hp_bar_color(card, hp_percent)

		# 장비 목록 업데이트
		_update_equip_list(card, hero)

		# 스킬 ATB 바들 업데이트
		_update_skill_atb_bars(card, hero)


func _update_hp_bar_color(card: HeroCard, hp_percent: float) -> void:
	var fill := StyleBoxFlat.new()
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3

	if hp_percent <= 0.25:
		fill.bg_color = HP_COLOR_LOW
	elif hp_percent <= 0.5:
		fill.bg_color = HP_COLOR_MID
	else:
		fill.bg_color = HP_COLOR_HIGH

	card.hp_bar.add_theme_stylebox_override("fill", fill)


func _update_equip_list(card: HeroCard, hero: Hero) -> void:
	for slot_name in SLOT_ORDER:
		var row: HBoxContainer = card.equip_rows.get(slot_name)
		if not row:
			continue

		var icon_lbl: Label = row.get_node_or_null("Icon")
		var name_lbl: Label = row.get_node_or_null("Name")
		if not icon_lbl or not name_lbl:
			continue

		var equip_id: String = hero.equipment.get(slot_name, "")
		if equip_id.is_empty():
			icon_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			name_lbl.text = "-"
			name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			var rarity: String = equip_data.get("rarity", "common")
			var rarity_color: Color = _get_rarity_color(rarity)

			icon_lbl.add_theme_color_override("font_color", rarity_color)
			name_lbl.text = equip_data.get("name", equip_id)
			name_lbl.add_theme_color_override("font_color", rarity_color)


func _update_skill_atb_bars(card: HeroCard, hero: Hero) -> void:
	## 스킬 쿨다운 바 생성/업데이트
	var skills: Array = hero.get_available_skills()

	# 기존에 없는 스킬 행 추가
	for skill_id in skills:
		if skill_id == "basic_attack":
			continue

		if not card.skill_rows.has(skill_id):
			var skill_data: Dictionary = DataManager.get_skill(skill_id)
			var skill_name: String = skill_data.get("name", skill_id)

			var row := _create_cooldown_row(skill_name)
			card.atb_section.add_child(row)
			card.skill_rows[skill_id] = {
				"row": row,
				"bar": row.get_node("Bar"),
				"label": row.get_node("Label")
			}

	# 더 이상 없는 스킬 행 제거
	var to_remove: Array = []
	for skill_id in card.skill_rows.keys():
		if skill_id not in skills:
			to_remove.append(skill_id)

	for skill_id in to_remove:
		var row_data: Dictionary = card.skill_rows[skill_id]
		row_data["row"].queue_free()
		card.skill_rows.erase(skill_id)


func _create_cooldown_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	label.custom_minimum_size.x = 24
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(60, 5)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_cooldown_bar(bar, true)
	row.add_child(bar)

	return row


func _on_atb_updated() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(hero_cards.size()):
		if i >= party.size() or party[i] == null:
			continue

		var card := hero_cards[i]
		var hero: Hero = party[i]

		# 기본 공격 ATB 업데이트
		var atb_percent: float = ATBManager.get_hero_atb_percent(hero.id) if ATBManager else 0.0
		card.basic_atb_bar.value = atb_percent * 100.0
		_style_atb_bar(card.basic_atb_bar, atb_percent >= 1.0)

		# 스킬 쿨다운 업데이트
		for skill_id in card.skill_rows.keys():
			var row_data: Dictionary = card.skill_rows[skill_id]
			var bar: ProgressBar = row_data["bar"]

			var cooldown_percent: float = CooldownManager.get_cooldown_percent(hero.id, skill_id) if CooldownManager else 0.0
			var is_ready: bool = cooldown_percent <= 0.0

			bar.value = 100.0 if is_ready else (1.0 - cooldown_percent) * 100.0
			_style_cooldown_bar(bar, is_ready)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.7, 0.7, 0.7)
		"uncommon": return Color(0.4, 0.8, 0.4)
		"magic": return Color(0.4, 0.6, 1.0)
		"rare": return Color(0.8, 0.6, 1.0)
		"epic": return Color(1.0, 0.5, 0.2)
		"legendary": return Color(1.0, 0.8, 0.2)
	return Color.WHITE


#region 장비 드래그 앤 드롭
func _on_equipment_dropped(hero_index: int, item_id: String) -> void:
	## 장비가 드롭되었을 때 호출
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < 0 or hero_index >= party.size():
		return

	var hero: Hero = party[hero_index]
	if hero == null:
		return

	# 장비 가능 여부 확인
	if not hero.can_equip(item_id):
		_show_equip_fail_feedback(hero_index)
		return

	# 장비 장착 시도
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	var item_slot: String = item_data.get("slot", "")

	# 악세사리 슬롯 처리
	var target_slot: String = item_slot
	if item_slot in ["accessory", "acc", "acc1", "acc2"]:
		if hero.equipment.get("acc1", "").is_empty():
			target_slot = "acc1"
		elif hero.equipment.get("acc2", "").is_empty():
			target_slot = "acc2"
		else:
			target_slot = "acc1"

	if InventoryManager.equip_item(hero, item_id, target_slot):
		_show_equip_success_feedback(hero_index)
		update_display()
		equipment_dropped.emit(hero_index, item_id)
	else:
		_show_equip_fail_feedback(hero_index)


func _show_equip_success_feedback(hero_index: int) -> void:
	if hero_index < 0 or hero_index >= hero_cards.size():
		return
	var card := hero_cards[hero_index]
	if not card.name_label:
		return

	var tween := create_tween()
	tween.tween_property(card.name_label, "modulate", Color(0.5, 1.0, 0.5), 0.1)
	tween.tween_property(card.name_label, "modulate", Color.WHITE, 0.15)


func _show_equip_fail_feedback(hero_index: int) -> void:
	if hero_index < 0 or hero_index >= hero_cards.size():
		return
	var card := hero_cards[hero_index]
	if not card.name_label:
		return

	var tween := create_tween()
	tween.tween_property(card.name_label, "modulate", Color(1.0, 0.3, 0.3), 0.1)
	tween.tween_property(card.name_label, "modulate", Color.WHITE, 0.15)


## 드롭 타겟 컨트롤 + hover 처리
class _EquipDropTarget extends Control:
	var hero_index: int = -1
	var cards_ref: BottomPartyCards = null
	var card_ref: HeroCard = null
	var highlight: ColorRect = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

		highlight = ColorRect.new()
		highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
		highlight.color = Color(0.3, 0.8, 0.3, 0.3)
		highlight.visible = false
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(highlight)

	func _on_mouse_entered() -> void:
		if cards_ref and card_ref:
			cards_ref._on_card_mouse_entered(card_ref)

	func _on_mouse_exited() -> void:
		if cards_ref and card_ref:
			cards_ref._on_card_mouse_exited(card_ref)

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		if data.get("type") != "equipment":
			return false

		var party: Array = PartyManager.get_party() if PartyManager else []
		if hero_index < 0 or hero_index >= party.size():
			return false

		var hero: Hero = party[hero_index]
		if hero == null:
			return false

		var item_id: String = data.get("item_id", "")
		var can_equip: bool = hero.can_equip(item_id)

		if highlight:
			highlight.visible = true
			highlight.color = Color(0.3, 0.8, 0.3, 0.3) if can_equip else Color(0.8, 0.3, 0.3, 0.3)

		return can_equip

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if highlight:
			highlight.visible = false

		if not data is Dictionary:
			return

		var item_id: String = data.get("item_id", "")
		if item_id.is_empty():
			return

		if cards_ref:
			cards_ref._on_equipment_dropped(hero_index, item_id)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			if highlight:
				highlight.visible = false
#endregion
