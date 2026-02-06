extends Control
class_name BottomPartyCards
## 하단 파티 카드 UI

const SLOT_ICONS := {"main_hand": "⚔", "off_hand": "🛡", "head": "👒", "body": "👕", "acc1": "💍", "acc2": "💍"}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

# 카드 크기
const CARD_WIDTH := 105
const CARD_HEIGHT := 140

# 색상
const HP_COLOR_HIGH := Color(0.2, 0.75, 0.2)
const HP_COLOR_MID := Color(0.9, 0.7, 0.2)
const HP_COLOR_LOW := Color(0.9, 0.2, 0.2)

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
	var equip_rows: Dictionary = {}  # slot_name -> _EquipSlotRow
	var hero_index: int = -1
	var hero_id: String = ""

var hero_cards: Array[HeroCard] = []


class _EquipSlotRow extends PanelContainer:
	var card_ref: BottomPartyCards
	var hero_index: int = -1
	var slot_name: String = ""
	var item_id: String = ""
	var icon_label: Label
	var name_label: Label
	var _normal_style: StyleBoxFlat
	var _hover_style: StyleBoxFlat

	func setup(p_card_ref: BottomPartyCards, p_hero_index: int, p_slot_name: String) -> void:
		card_ref = p_card_ref
		hero_index = p_hero_index
		slot_name = p_slot_name
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 14)

		_normal_style = StyleBoxFlat.new()
		_normal_style.bg_color = Color(0.08, 0.08, 0.1, 0.0)
		_normal_style.border_width_left = 1
		_normal_style.border_width_top = 1
		_normal_style.border_width_right = 1
		_normal_style.border_width_bottom = 1
		_normal_style.border_color = Color(0.25, 0.25, 0.3, 0.6)
		_normal_style.corner_radius_top_left = 2
		_normal_style.corner_radius_top_right = 2
		_normal_style.corner_radius_bottom_left = 2
		_normal_style.corner_radius_bottom_right = 2
		_normal_style.content_margin_left = 2
		_normal_style.content_margin_right = 2
		add_theme_stylebox_override("panel", _normal_style)

		_hover_style = _normal_style.duplicate()
		_hover_style.bg_color = Color(0.25, 0.25, 0.15, 0.8)
		_hover_style.border_width_left = 2
		_hover_style.border_width_top = 2
		_hover_style.border_width_right = 2
		_hover_style.border_width_bottom = 2
		_hover_style.border_color = Color(1.0, 0.95, 0.3, 1.0)

		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

	func _on_mouse_entered() -> void:
		add_theme_stylebox_override("panel", _hover_style)

	func _on_mouse_exited() -> void:
		add_theme_stylebox_override("panel", _normal_style)

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		if data.get("type", "") != "equipment":
			return false

		var item_id_local: String = data.get("item_id", "")
		if item_id_local.is_empty():
			return false

		var party: Array = PartyManager.get_party() if PartyManager else []
		if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
			return false

		var hero: Hero = party[hero_index]
		if not hero.can_equip(item_id_local):
			return false

		var equip_data: Dictionary = DataManager.get_equipment(item_id_local)
		var equip_slot: String = equip_data.get("slot", "")
		if equip_slot.is_empty():
			return false

		if equip_slot in ["accessory", "acc", "acc1", "acc2"]:
			return slot_name in ["acc1", "acc2"]

		return equip_slot == slot_name

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if not data is Dictionary:
			return

		var item_id_local: String = data.get("item_id", "")
		if item_id_local.is_empty():
			return

		if card_ref:
			card_ref._handle_equipment_drop(hero_index, slot_name, item_id_local, data)

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item_id.is_empty():
			return null

		var preview := Label.new()
		preview.text = "%s %s" % [SLOT_ICONS.get(slot_name, "?"), name_label.text]
		preview.add_theme_font_size_override("font_size", 9)
		preview.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
		preview.add_theme_color_override("font_outline_color", Color.BLACK)
		preview.add_theme_constant_override("outline_size", 2)
		set_drag_preview(preview)

		return {
			"type": "equipment",
			"item_id": item_id,
			"source": "equipment",
			"hero_index": hero_index,
			"source_slot": slot_name
		}


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
		if BattleManager.has_signal("hero_attacked"):
			if not BattleManager.hero_attacked.is_connected(_on_hero_attacked):
				BattleManager.hero_attacked.connect(_on_hero_attacked)
		if BattleManager.has_signal("hero_damaged"):
			if not BattleManager.hero_damaged.is_connected(_on_hero_damaged):
				BattleManager.hero_damaged.connect(_on_hero_damaged)

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

	# 래퍼
	card.wrapper = Control.new()
	card.wrapper.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	# 메인 패널
	card.panel = PanelContainer.new()
	card.panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	card.panel.set_meta("card_index", index)
	_style_card_panel(card.panel)
	card.panel.gui_input.connect(_on_card_gui_input.bind(card))
	card.wrapper.add_child(card.panel)

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
		var row_data := _create_equip_row(slot_name, index)
		card.equip_section.add_child(row_data["row"])
		card.equip_rows[slot_name] = row_data

	return card


func _create_equip_row(slot_name: String, hero_index: int) -> Dictionary:
	var row := _EquipSlotRow.new()
	row.setup(self, hero_index, slot_name)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)

	var icon_lbl := Label.new()
	icon_lbl.name = "Icon"
	icon_lbl.text = SLOT_ICONS.get(slot_name, "?")
	icon_lbl.add_theme_font_size_override("font_size", 8)
	icon_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	icon_lbl.custom_minimum_size.x = 12
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = "-"
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)

	row.icon_label = icon_lbl
	row.name_label = name_lbl

	return {"row": row, "icon": icon_lbl, "name": name_lbl}


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

		var row: _EquipSlotRow = row_data.get("row")
		var icon_lbl: Label = row_data.get("icon")
		var name_lbl: Label = row_data.get("name")
		if not icon_lbl or not name_lbl:
			continue

		var equip_id: String = hero.equipment.get(slot_name, "")
		if row:
			row.item_id = equip_id
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


func _handle_equipment_drop(hero_index: int, target_slot: String, item_id: String, data: Dictionary) -> void:
	var source: String = data.get("source", "inventory")
	if source == "equipment":
		return

	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
		return

	var hero: Hero = party[hero_index]
	if not hero.can_equip(item_id):
		return

	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	var equip_slot: String = equip_data.get("slot", "")
	if equip_slot.is_empty():
		return

	if equip_slot in ["accessory", "acc", "acc1", "acc2"]:
		if target_slot not in ["acc1", "acc2"]:
			return
	elif equip_slot != target_slot:
		return

	if InventoryManager and InventoryManager.equip_item(hero, item_id, target_slot):
		update_display()
		equipment_dropped.emit(hero_index, item_id)


# === 카드 애니메이션 ===

func _find_card_by_hero_id(hero_id: String) -> HeroCard:
	for card in hero_cards:
		if card.hero_id == hero_id:
			return card
	return null


func _on_hero_attacked(hero_id: String) -> void:
	var card := _find_card_by_hero_id(hero_id)
	if card and is_instance_valid(card.panel):
		_play_attack_animation(card)


func _on_hero_damaged(hero_id: String) -> void:
	var card := _find_card_by_hero_id(hero_id)
	if card and is_instance_valid(card.panel):
		_play_damage_animation(card)


func _play_attack_animation(card: HeroCard) -> void:
	var panel := card.panel
	var original_y := panel.position.y

	var tween := create_tween()
	tween.tween_property(panel, "position:y", original_y - 15, 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position:y", original_y, 0.15).set_ease(Tween.EASE_IN)


func _play_damage_animation(card: HeroCard) -> void:
	var panel := card.panel
	var original_x := panel.position.x

	var tween := create_tween()
	tween.tween_property(panel, "position:x", original_x + 4, 0.03)
	tween.tween_property(panel, "position:x", original_x - 4, 0.03)
	tween.tween_property(panel, "position:x", original_x + 3, 0.03)
	tween.tween_property(panel, "position:x", original_x - 3, 0.03)
	tween.tween_property(panel, "position:x", original_x + 2, 0.03)
	tween.tween_property(panel, "position:x", original_x, 0.03)


# === 필드 힐 시스템 ===

func _on_card_gui_input(event: InputEvent, card: HeroCard) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_field_heal(card)


func _try_field_heal(card: HeroCard) -> void:
	## 필드에서 힐 시도 (전투 중이 아닐 때)
	# 전투 중이면 무시
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		return

	var party: Array = PartyManager.get_party() if PartyManager else []
	if card.hero_index >= party.size():
		return

	var target: Hero = party[card.hero_index]
	if target == null or target.is_dead:
		return

	# 이미 풀피면 무시
	if target.current_hp >= target.get_max_hp():
		return

	# 힐 가능한 영웅 찾기
	var healer := _find_available_healer()
	if healer == null:
		return

	# 힐 실행
	_execute_field_heal(healer, target)


func _find_available_healer() -> Hero:
	## 필드 힐 가능한 힐러 찾기
	var party: Array = PartyManager.get_party() if PartyManager else []

	for hero in party:
		if hero == null or hero.is_dead:
			continue

		# 힐러 클래스 확인
		if hero.class_id != "cleric":
			continue

		# 힐 스킬 쿨타임 확인
		if CooldownManager and not CooldownManager.is_skill_ready(hero.id, "heal"):
			continue

		return hero

	return null


func _execute_field_heal(healer: Hero, target: Hero) -> void:
	## 필드에서 힐 실행
	var skill_data: Dictionary = DataManager.get_skill("heal")
	var base_value: int = int(skill_data.get("base_damage", 25))
	var scaling: float = skill_data.get("scaling", 1.2)
	var int_stat: int = healer.get_int()
	var heal_amount: int = int(base_value + int_stat * scaling)

	var actual_heal := target.heal(heal_amount)

	# 쿨타임 시작
	if CooldownManager:
		CooldownManager.start_cooldown(healer.id, "heal")

	# 효과음
	if SoundManager:
		SoundManager.play_heal()

	# UI 업데이트
	update_display()

	# 로그 (배틀 로그 시그널 사용)
	if BattleManager:
		BattleManager.battle_log_received.emit(
			"[필드] %s → %s HP +%d" % [healer.hero_name, target.hero_name, actual_heal],
			Color.LIGHT_GREEN
		)
