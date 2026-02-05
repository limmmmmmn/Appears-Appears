extends Control
class_name BottomPartyCards
## 하단 파티 카드 UI - 개별 카드 hover시 위로 슬라이드 + 장비 선택

const SLOT_ICONS := {"main_hand": "⚔", "off_hand": "🛡", "head": "👒", "body": "👕", "acc1": "💍", "acc2": "💍"}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

# 카드 크기
const CARD_WIDTH := 105
const CARD_HEIGHT := 140
const CARD_HIDDEN_OFFSET := 0  # 항상 보이게

# 색상
const HP_COLOR_HIGH := Color(0.2, 0.75, 0.2)
const HP_COLOR_MID := Color(0.9, 0.7, 0.2)
const HP_COLOR_LOW := Color(0.9, 0.2, 0.2)
const HIGHLIGHT_COLOR := Color(0.4, 0.7, 1.0, 0.8)

# 시그널
signal equipment_dropped(hero_index: int, item_id: String)

# 씬에서 가져오는 노드
@onready var cards_container: HBoxContainer = %CardsContainer

# 카드 데이터
class HeroCard:
	var wrapper: Control  # 클리핑용 래퍼
	var panel: PanelContainer
	var name_label: Label
	var hp_bar: ProgressBar
	var hp_label: Label
	var atb_section: VBoxContainer
	var basic_atb_bar: ProgressBar
	var skill_rows: Dictionary = {}
	var equip_section: VBoxContainer
	var equip_rows: Dictionary = {}  # slot_name -> {row, icon, name, highlight}
	var hero_index: int = -1
	var hero_id: String = ""
	var is_hovered: bool = false
	var card_highlight: ColorRect = null  # 카드 전체 하이라이트

var hero_cards: Array[HeroCard] = []
var _any_card_hovered: bool = false


func _ready() -> void:
	_connect_signals()
	call_deferred("_initial_setup")


func _initial_setup() -> void:
	if cards_container:
		update_display()
	else:
		push_error("[BottomPartyCards] CardsContainer not found!")


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
	hero_cards.clear()

	if cards_container:
		for child in cards_container.get_children():
			cards_container.remove_child(child)
			child.free()

	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(party.size()):
		if party[i] == null:
			continue
		var card := _create_hero_card(i)
		hero_cards.append(card)
		cards_container.add_child(card.wrapper)


func _create_hero_card(index: int) -> HeroCard:
	var card := HeroCard.new()
	card.hero_index = index

	# 클리핑 래퍼 (개별 카드용)
	card.wrapper = Control.new()
	card.wrapper.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.wrapper.clip_contents = true

	# 메인 패널 (래퍼 안에서 이동)
	card.panel = PanelContainer.new()
	card.panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.panel.position = Vector2(0, CARD_HIDDEN_OFFSET)  # 기본: 아래로 내려감
	card.panel.set_meta("card_index", index)
	_style_card_panel(card.panel)
	card.wrapper.add_child(card.panel)

	# 카드 전체 하이라이트 (숨김 상태로 시작)
	card.card_highlight = ColorRect.new()
	card.card_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.card_highlight.color = HIGHLIGHT_COLOR
	card.card_highlight.visible = false
	card.card_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.panel.add_child(card.card_highlight)

	# 마우스 이벤트 연결
	card.panel.mouse_entered.connect(_on_card_mouse_entered.bind(card))
	card.panel.mouse_exited.connect(_on_card_mouse_exited.bind(card))

	# 내부 VBox
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 5
	vbox.offset_right = -5
	vbox.offset_top = 4
	vbox.offset_bottom = -4
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.panel.add_child(vbox)

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

	var basic_row := _create_atb_row("공격")
	card.basic_atb_bar = basic_row.get_node("Bar")
	card.atb_section.add_child(basic_row)

	# === 구분선 ===
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	# === 장비 섹션 ===
	card.equip_section = VBoxContainer.new()
	card.equip_section.add_theme_constant_override("separation", 0)
	card.equip_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(card.equip_section)

	for slot_name in SLOT_ORDER:
		var row_data := _create_equip_row_with_highlight(slot_name, card)
		card.equip_section.add_child(row_data["row"])
		card.equip_rows[slot_name] = row_data

	return card


func _create_equip_row_with_highlight(slot_name: String, card: HeroCard) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_STOP  # 마우스 이벤트 받음

	# 하이라이트 배경
	var highlight := ColorRect.new()
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.color = HIGHLIGHT_COLOR
	highlight.visible = false
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(highlight)

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

	# 장비 슬롯 hover 이벤트
	row.mouse_entered.connect(_on_equip_slot_entered.bind(card, slot_name, highlight))
	row.mouse_exited.connect(_on_equip_slot_exited.bind(card, highlight))

	return {"row": row, "icon": icon_lbl, "name": name_lbl, "highlight": highlight}


func _on_card_mouse_entered(card: HeroCard) -> void:
	if card.is_hovered:
		return
	card.is_hovered = true
	_any_card_hovered = true

	# 카드 하이라이트 표시
	if card.card_highlight:
		card.card_highlight.visible = true


func _on_card_mouse_exited(card: HeroCard) -> void:
	if not card.is_hovered:
		return

	# 짧은 딜레이 후 확인
	await get_tree().create_timer(0.03).timeout

	if not is_instance_valid(card.panel):
		return

	# 마우스가 다시 카드 위에 있으면 무시
	var mouse_pos := card.panel.get_local_mouse_position()
	var panel_rect := Rect2(Vector2.ZERO, card.panel.size)
	if panel_rect.has_point(mouse_pos):
		return

	card.is_hovered = false

	# 카드 하이라이트 숨김
	if card.card_highlight:
		card.card_highlight.visible = false

	# 모든 장비 하이라이트 숨김
	for slot_name in card.equip_rows:
		var row_data: Dictionary = card.equip_rows[slot_name]
		if row_data.has("highlight"):
			row_data["highlight"].visible = false

	# 모든 카드가 닫혔는지 확인
	var any_hovered := false
	for c in hero_cards:
		if c.is_hovered:
			any_hovered = true
			break

	if not any_hovered:
		_any_card_hovered = false


func _on_equip_slot_entered(card: HeroCard, slot_name: String, highlight: ColorRect) -> void:
	# 카드 전체 하이라이트 숨기고 장비 슬롯 하이라이트 표시
	if card.card_highlight:
		card.card_highlight.visible = false
	highlight.visible = true


func _on_equip_slot_exited(card: HeroCard, highlight: ColorRect) -> void:
	highlight.visible = false
	# 카드 하이라이트 다시 표시 (카드가 여전히 hover 중이면)
	if card.is_hovered and card.card_highlight:
		card.card_highlight.visible = true


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


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	if hero_cards.size() != party.size():
		_rebuild_cards()
		return

	for i in range(hero_cards.size()):
		if i >= party.size() or party[i] == null:
			continue

		var card := hero_cards[i]
		var hero: Hero = party[i]
		card.hero_id = hero.id

		card.name_label.text = hero.hero_name

		var max_hp := hero.get_max_hp()
		var hp_percent: float = float(hero.current_hp) / float(max_hp) if max_hp > 0 else 1.0
		card.hp_bar.value = hp_percent * 100.0
		card.hp_label.text = "%d/%d" % [hero.current_hp, max_hp]
		_update_hp_bar_color(card, hp_percent)

		_update_equip_list(card, hero)
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
		var row_data: Dictionary = card.equip_rows.get(slot_name, {})
		if row_data.is_empty():
			continue

		var icon_lbl: Label = row_data.get("icon")
		var name_lbl: Label = row_data.get("name")
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
	var skills: Array = hero.get_available_skills()

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

		var atb_percent: float = ATBManager.get_hero_atb_percent(hero.id) if ATBManager else 0.0
		card.basic_atb_bar.value = atb_percent * 100.0
		_style_atb_bar(card.basic_atb_bar, atb_percent >= 1.0)

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
