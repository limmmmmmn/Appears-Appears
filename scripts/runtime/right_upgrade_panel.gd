class_name RightUpgradePanel
extends PanelContainer

## Right zone of the ㄷ-shaped layout: the upgrade shop.
## Three axes only — SPEED (red) / GREED (gold) / SCALE (blue). Each card shows
## current level + next effect + price on a single buy-button. The weapon shop
## is SPEED's UI skin (buying SPEED = unlocking + equipping the next weapon).
## Armor / region unlocks are stubbed here as "coming soon" rows.
##
## CORE PRINCIPLE: every purchase causes a visible change (weapon name swaps,
## window count rises, gold-per-kill jumps) — never a silent number bump.

const PANEL_WIDTH: float = 160.0
const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

const SPEED_COLOR: Color = Color(0.95, 0.42, 0.38, 1.0)   # red
const GREED_COLOR: Color = Color(0.98, 0.82, 0.34, 1.0)   # gold
const SCALE_COLOR: Color = Color(0.46, 0.68, 1.0, 1.0)    # blue
const ARMOR_COLOR: Color = Color(0.62, 0.82, 0.86, 1.0)   # steel/cyan (survival)
const STUB_COLOR: Color = Color(0.5, 0.52, 0.56, 1.0)     # gray (coming soon)

var _gold_label: Label
var _content: VBoxContainer
## axis key → {"effect": Label, "button": Button, "sub": Label}
var _cards: Dictionary = {}
## building id → {"button": Button, "card": PanelContainer}
var _building_cards: Dictionary = {}
## companion id → {"button": Button, "card": PanelContainer}
var _companion_cards: Dictionary = {}
## weapon type id → {"button","card","sub","effect"}
var _weapon_cards: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(480.0, 0.0)
	custom_minimum_size = Vector2(PANEL_WIDTH, 360.0)
	offset_left = 480.0
	offset_top = 0.0
	offset_right = 640.0
	offset_bottom = 360.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())
	_build()
	_connect_events()
	_refresh()


func _connect_events() -> void:
	EventBus.gold_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_failed.connect(_on_failed)
	EventBus.building_built.connect(_on_changed.unbind(1))
	EventBus.companion_appeared.connect(_on_changed.unbind(1))
	EventBus.companion_recruited.connect(_on_changed.unbind(1))


func _on_changed() -> void:
	_refresh()


func _on_failed(axis: StringName) -> void:
	_flash_card(axis)


# ─── Layout ────────────────────────────────────────────────────────────
func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_gold_label = _make_label("Gold 0", 13, Color(1.0, 0.91, 0.48, 1.0))
	root.add_child(_gold_label)

	var title := _make_label("강화 상점", 10, Color(0.86, 0.9, 0.82, 1.0))
	root.add_child(title)
	root.add_child(_hsep())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	_content.add_child(_make_label("무기", 10, SPEED_COLOR))
	for i in Balance.weapon_type_count():
		_add_weapon_card(Balance.weapon_type_at(i))
	_content.add_child(_hsep())
	_add_axis_card(&"greed", "GREED", GREED_COLOR)
	_add_axis_card(&"scale", "SCALE", SCALE_COLOR)
	_add_axis_card(&"armor", "방어구", ARMOR_COLOR)
	_content.add_child(_hsep())
	_content.add_child(_make_label("건물", 10, Color(0.86, 0.9, 0.82, 1.0)))
	for i in Balance.building_count():
		_add_building_card(Balance.building_at(i))
	_content.add_child(_hsep())
	_content.add_child(_make_label("동료", 10, Color(0.86, 0.9, 0.82, 1.0)))
	for i in Balance.companion_count():
		_add_companion_card(Balance.companion_at(i))
	_content.add_child(_hsep())
	_add_stub_card("지역 해금", "준비 중")


func _add_axis_card(axis: StringName, title: String, accent: Color) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	box.add_child(header)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3.0, 12.0)
	header.add_child(bar)
	header.add_child(_make_label(title, 11, accent))

	var sub := _make_label("", 8, Color(0.78, 0.8, 0.74, 1.0))
	box.add_child(sub)

	var effect := _make_label("", 9, Color(0.92, 0.94, 0.86, 1.0))
	box.add_child(effect)

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 22.0)
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(_on_card_pressed.bind(axis))
	box.add_child(button)

	_cards[axis] = {"effect": effect, "button": button, "sub": sub, "accent": accent, "card": card}

	# GREED hosts a sub-upgrade: chest open speed (hover-gauge time).
	if axis == &"greed":
		box.add_child(HSeparator.new())
		var open_effect := _make_label("", 8, Color(0.9, 0.92, 0.84, 1.0))
		box.add_child(open_effect)
		var open_button := Button.new()
		open_button.focus_mode = Control.FOCUS_NONE
		open_button.custom_minimum_size = Vector2(0.0, 20.0)
		open_button.add_theme_font_override("font", PANEL_FONT)
		open_button.add_theme_font_size_override("font_size", 8)
		open_button.pressed.connect(_on_open_speed_pressed)
		box.add_child(open_button)
		_cards[axis]["open_effect"] = open_effect
		_cards[axis]["open_button"] = open_button


func _add_stub_card(title: String, note: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(STUB_COLOR))
	card.modulate = Color(1, 1, 1, 0.6)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	card.add_child(box)
	box.add_child(_make_label(title, 10, STUB_COLOR))
	box.add_child(_make_label(note, 8, Color(0.6, 0.62, 0.66, 1.0)))


func _add_building_card(building: Dictionary) -> void:
	var id: StringName = building["id"]
	var accent: Color = building.get("color", Color(0.7, 0.85, 1.0, 1.0))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	box.add_child(header)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3.0, 12.0)
	header.add_child(bar)
	header.add_child(_make_label(str(building.get("name", "?")), 11, accent))

	var desc := _make_label(str(building.get("desc", "")), 8, Color(0.82, 0.84, 0.78, 1.0))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(PANEL_WIDTH - 24.0, 0.0)
	box.add_child(desc)

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 22.0)
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(_on_building_pressed.bind(id))
	box.add_child(button)

	_building_cards[id] = {"button": button, "card": card}


func _refresh_buildings() -> void:
	for i in Balance.building_count():
		var building: Dictionary = Balance.building_at(i)
		var id: StringName = building["id"]
		if not _building_cards.has(id):
			continue
		var button: Button = _building_cards[id]["button"]
		if GameState.is_building_built(id):
			_set_buy_button(button, "설치됨", false)
		else:
			_set_buy_button(button, "설치  %dG" % GameState.building_cost(id), GameState.can_purchase_building(id))


func _on_building_pressed(id: StringName) -> void:
	GameState.purchase_building(id)


func _add_companion_card(comp: Dictionary) -> void:
	var id: StringName = comp["id"]
	var accent := Color(0.92, 0.82, 0.55, 1.0)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	box.add_child(header)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(3.0, 12.0)
	header.add_child(bar)
	header.add_child(_make_label(str(comp.get("name", "?")), 11, accent))

	var role_desc: Dictionary = {&"mage": "광역 공격", &"priest": "힐 / 부활 가속", &"thief": "골드 획득 ↑"}
	box.add_child(_make_label(str(role_desc.get(StringName(comp.get("role", &"")), "")), 8, Color(0.82, 0.84, 0.78, 1.0)))

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 22.0)
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(_on_companion_pressed.bind(id))
	box.add_child(button)

	_companion_cards[id] = {"button": button, "card": card}


func _refresh_companions() -> void:
	for i in Balance.companion_count():
		var comp: Dictionary = Balance.companion_at(i)
		var id: StringName = comp["id"]
		if not _companion_cards.has(id):
			continue
		var refs: Dictionary = _companion_cards[id]
		var card: PanelContainer = refs["card"]
		var button: Button = refs["button"]
		if GameState.is_companion_recruited(id):
			card.visible = true
			_set_buy_button(button, "영입됨", false)
		elif GameState.is_companion_appeared(id):
			card.visible = true
			_set_buy_button(button, "영입  %dG" % GameState.companion_recruit_cost(id), GameState.can_recruit_companion(id))
		else:
			# Not yet 등장 — hidden until its appearance condition is met.
			card.visible = false


func _on_companion_pressed(id: StringName) -> void:
	GameState.recruit_companion(id)


# ─── Refresh ───────────────────────────────────────────────────────────
func _refresh() -> void:
	_gold_label.text = "Gold %d" % GameState.gold
	_refresh_weapons()
	_refresh_greed()
	_refresh_scale()
	_refresh_armor()
	_refresh_buildings()
	_refresh_companions()


func _add_weapon_card(wtype: Dictionary) -> void:
	var id: StringName = wtype["id"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(SPEED_COLOR))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	box.add_child(header)
	var bar := ColorRect.new()
	bar.color = SPEED_COLOR
	bar.custom_minimum_size = Vector2(3.0, 12.0)
	header.add_child(bar)
	header.add_child(_make_label(str(wtype.get("name", "무기")), 11, SPEED_COLOR))

	var sub := _make_label("", 8, Color(0.78, 0.8, 0.74, 1.0))
	box.add_child(sub)
	var effect := _make_label("", 9, Color(0.92, 0.94, 0.86, 1.0))
	box.add_child(effect)

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 22.0)
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", 9)
	button.pressed.connect(_on_weapon_pressed.bind(id))
	box.add_child(button)

	_weapon_cards[id] = {"button": button, "card": card, "sub": sub, "effect": effect}


func _refresh_weapons() -> void:
	var owned: Array[StringName] = GameState.owned_weapon_types()
	for i in Balance.weapon_type_count():
		var wtype: Dictionary = Balance.weapon_type_at(i)
		var id: StringName = wtype["id"]
		if not _weapon_cards.has(id):
			continue
		var refs: Dictionary = _weapon_cards[id]
		# Only show categories a current party member actually wields.
		if not owned.has(id):
			refs["card"].visible = false
			continue
		refs["card"].visible = true
		refs["sub"].text = GameState.current_weapon_name(id)
		refs["effect"].text = "Lv %d · 공격 ×%s" % [GameState.weapon_level(id), _fmt_mult(GameState.weapon_attack_multiplier(id))]
		var next_mult: float = Balance.effect_multiplier(GameState.weapon_level(id) + 1)
		_set_buy_button(refs["button"], "%s ×%s  %dG" % [GameState.next_weapon_name(id), _fmt_mult(next_mult), GameState.weapon_upgrade_cost(id)], GameState.can_upgrade_weapon(id))


func _on_weapon_pressed(id: StringName) -> void:
	GameState.upgrade_weapon(id)


func _refresh_greed() -> void:
	var card: Dictionary = _cards[&"greed"]
	card["sub"].text = "골드 획득 배수"
	card["effect"].text = "Lv %d · 골드 ×%s" % [GameState.greed_level, _fmt_mult(GameState.greed_gold_multiplier())]
	var cost: int = GameState.greed_upgrade_cost()
	var next_mult: float = Balance.effect_multiplier(GameState.greed_level + 1)
	_set_buy_button(card["button"], "다음 ×%s  %dG" % [_fmt_mult(next_mult), cost], GameState.can_upgrade_greed())
	# Chest open-speed sub-upgrade.
	if card.has("open_button"):
		card["open_effect"].text = "개봉 %.2fs" % GameState.chest_hover_duration()
		if GameState.open_speed_is_maxed():
			_set_buy_button(card["open_button"], "개봉 최속", false)
		else:
			var next_dur: float = Balance.chest_open_duration(GameState.open_speed_level + 1)
			_set_buy_button(card["open_button"], "개봉↑ %.2fs  %dG" % [next_dur, GameState.open_speed_upgrade_cost()], GameState.can_upgrade_open_speed())


func _refresh_scale() -> void:
	var card: Dictionary = _cards[&"scale"]
	var count: int = GameState.scale_window_count()
	card["sub"].text = "동시 전투창"
	card["effect"].text = "전투창 %d개" % count
	if GameState.scale_is_maxed():
		_set_buy_button(card["button"], "최대 (%d개)" % count, false)
		return
	var cost: int = GameState.scale_upgrade_cost()
	var next_count: int = Balance.scale_window_count(GameState.scale_purchases + 1)
	_set_buy_button(card["button"], "+창 → %d개  %dG" % [next_count, cost], GameState.can_upgrade_scale())


func _refresh_armor() -> void:
	var card: Dictionary = _cards[&"armor"]
	card["sub"].text = "방어구: %s" % GameState.current_armor_name()
	card["effect"].text = "Lv %d · 방어 +%d" % [GameState.armor_level, GameState.armor_defense_bonus()]
	var cost: int = GameState.armor_upgrade_cost()
	var next_def: int = Balance.armor_defense_for_level(GameState.armor_level + 1)
	_set_buy_button(card["button"], "%s 방어+%d  %dG" % [GameState.next_armor_name(), next_def, cost], GameState.can_upgrade_armor())


func _set_buy_button(button: Button, text: String, affordable: bool) -> void:
	button.text = text
	button.disabled = not affordable
	button.modulate = Color(1, 1, 1, 1) if affordable else Color(0.62, 0.62, 0.66, 1.0)


# ─── Purchase ──────────────────────────────────────────────────────────
func _on_card_pressed(axis: StringName) -> void:
	match axis:
		&"greed":
			GameState.upgrade_greed()
		&"scale":
			GameState.upgrade_scale()
		&"armor":
			GameState.upgrade_armor()
	# Combat_upgrade_changed / gold_changed drive the refresh; no manual call.


func _on_open_speed_pressed() -> void:
	GameState.upgrade_open_speed()


func _flash_card(axis: StringName) -> void:
	if not _cards.has(axis):
		return
	var card_node: Control = _cards[axis]["card"]
	var tween := create_tween()
	tween.tween_property(card_node, "modulate", Color(1.0, 0.4, 0.4, 1.0), 0.06)
	tween.tween_property(card_node, "modulate", Color(1, 1, 1, 1), 0.22)


# ─── Helpers / styles ──────────────────────────────────────────────────
func _fmt_mult(v: float) -> String:
	return "%.2f" % v


func _make_label(text: String, pt: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", PANEL_FONT)
	label.add_theme_font_size_override("font_size", pt)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _hsep() -> HSeparator:
	return HSeparator.new()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.038, 0.045, 1.0)
	style.border_width_left = 1
	style.border_color = Color(0.78, 0.86, 0.72, 1.0)
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style


func _card_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.13, 1.0)
	style.border_width_left = 2
	style.border_color = accent
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 5
	style.content_margin_top = 4
	style.content_margin_right = 5
	style.content_margin_bottom = 4
	return style
