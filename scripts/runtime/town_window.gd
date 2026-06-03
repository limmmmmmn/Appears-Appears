class_name TownWindow
extends Control

## 마을 — a big tabbed MODAL you open anytime with the 마을 button. Unlike the
## right panel (small always-on cards = fast in-flow upgrades), this is a separate
## SPACE: the field dims behind a large macOS-style window where you stop and
## outfit. Tabs: 무기 / 방어구 / 도구 / 부활 / 상태.
##   v1: 무기(구매 사다리 + 판매) + 상태(스탯 대시보드) are live; the rest are stubs.
## Opened/closed via the group "town_window" (the 마을 button looks us up).

const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

# ── Resurrect 64 palette ───────────────────────────────────────────────
const WINDOW_BG: Color = Color(0.18, 0.133, 0.184, 1.0)    ## #2e222f dark interior
const PANEL_BG: Color = Color(0.235, 0.176, 0.235, 1.0)    ## #3c2d3c card fill
const LOCKED_GREY: Color = Color(0.384, 0.333, 0.396, 1.0) ## #625565 locked
const ACCENT: Color = Color(0.055, 0.686, 0.608, 1.0)      ## #0eaf9b teal titlebar
const GOLD: Color = Color(1.0, 0.91, 0.48, 1.0)            ## price / affordable
const POOR: Color = Color(0.7, 0.55, 0.4, 1.0)            ## can't afford
const OWNED: Color = Color(0.5, 0.78, 0.55, 1.0)          ## already owned (dim green)
const TEXT: Color = Color(0.92, 0.93, 0.95, 1.0)
const DIM: Color = Color(0.66, 0.68, 0.72, 1.0)

const TABS: Array[Dictionary] = [
	{"id": &"weapon", "name": "무기"},
	{"id": &"armor", "name": "방어구"},
	{"id": &"tool", "name": "도구"},
	{"id": &"revive", "name": "부활"},
	{"id": &"status", "name": "상태"},
]
const WINDOW_SIZE: Vector2 = Vector2(470.0, 300.0)

var _backdrop: ColorRect
var _content: VBoxContainer        ## the swappable per-tab body
var _tab_buttons: Dictionary = {}  ## id → Button
var _gold_label: Label
var _active_tab: StringName = &"weapon"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("town_window")
	_build()
	# Buying / selling / earning re-reads the open tab so prices + lists stay live.
	EventBus.gold_changed.connect(_on_state_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_state_changed.unbind(1))
	EventBus.inventory_changed.connect(_on_state_changed)
	EventBus.party_equipment_changed.connect(_on_state_changed.unbind(1))


# ─── Open / close ──────────────────────────────────────────────────────
func open() -> void:
	visible = true
	_show_tab(_active_tab)


func close() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _on_state_changed() -> void:
	if visible:
		_show_tab(_active_tab)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ─── Build the shell ───────────────────────────────────────────────────
func _build() -> void:
	# Dim backdrop — clicking it (outside the window) closes the town.
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.0, 0.0, 0.0, 0.5)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	# Centered window.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let the backdrop catch outside clicks
	add_child(center)

	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", _window_style())
	window.custom_minimum_size = WINDOW_SIZE
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.clip_contents = true
	center.add_child(window)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	window.add_child(vb)

	vb.add_child(_build_titlebar())
	vb.add_child(_build_tab_row())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 5)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 7)
	pad.add_child(_content)
	scroll.add_child(pad)


func _build_titlebar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _titlebar_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	var title := _label("마을", 11, Color(1, 1, 1, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_gold_label = _label("", 9, Color(1.0, 0.96, 0.78, 1.0))
	row.add_child(_gold_label)
	var close_btn := _make_close_button()
	close_btn.pressed.connect(close)
	row.add_child(close_btn)
	return bar


func _build_tab_row() -> PanelContainer:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", _flat_style(Color(0.13, 0.097, 0.135, 1.0)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	wrap.add_child(row)
	_tab_buttons.clear()
	for tab: Dictionary in TABS:
		var id: StringName = tab["id"]
		var b := Button.new()
		b.text = str(tab["name"])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", PANEL_FONT)
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(_on_tab_pressed.bind(id))
		row.add_child(b)
		_tab_buttons[id] = b
	return wrap


# ─── Tab switching ─────────────────────────────────────────────────────
func _on_tab_pressed(id: StringName) -> void:
	_active_tab = id
	_show_tab(id)


func _show_tab(id: StringName) -> void:
	if _content == null:
		return
	for child in _content.get_children():
		child.queue_free()
	_style_tabs()
	_update_gold_label()
	match id:
		&"weapon": _build_weapon_tab()
		&"status": _build_status_tab()
		&"armor": _build_stub("방어구 상점은 곧 열립니다.")
		&"tool": _build_stub("도구 상점은 곧 열립니다.")
		&"revive": _build_stub("부활 제단은 준비 중입니다.")
		_: _build_stub("준비 중.")


func _style_tabs() -> void:
	for id in _tab_buttons:
		var b: Button = _tab_buttons[id]
		var active: bool = id == _active_tab
		var bg: Color = ACCENT if active else Color(0.27, 0.21, 0.27, 1.0)
		var fg: Color = Color(1, 1, 1, 1) if active else DIM
		b.add_theme_stylebox_override("normal", _tab_style(bg))
		b.add_theme_stylebox_override("hover", _tab_style(bg.lightened(0.1)))
		b.add_theme_stylebox_override("pressed", _tab_style(bg))
		b.add_theme_color_override("font_color", fg)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))


func _update_gold_label() -> void:
	if _gold_label != null:
		_gold_label.text = "보유 %dG" % GameState.gold


# ─── 무기 tab — 구매 사다리 + 판매 ──────────────────────────────────────
func _build_weapon_tab() -> void:
	_content.add_child(_section("구매 — 무기 (직업별 사다리)"))
	for type_id: StringName in GameState.owned_weapon_types():
		_content.add_child(_weapon_ladder_card(type_id))
	_content.add_child(_section("판매 — 안 쓰는 무기"))
	var any_weapon: bool = false
	var items: Array = GameState.inventory_items()
	for i in items.size():
		var item: ItemData = GameState.item_entry_data(items[i])
		if item != null and item.slot == ItemData.Slot.WEAPON:
			_content.add_child(_sell_row(i, items[i]))
			any_weapon = true
	if not any_weapon:
		_content.add_child(_hint("팔 무기가 없습니다. (전투에서 무기를 주우면 여기서 판매)"))


func _weapon_ladder_card(type_id: StringName) -> PanelContainer:
	var card := _card()
	var vb: VBoxContainer = card.get_child(0)
	var type_name: String = str(Balance.weapon_type_by_id(type_id).get("name", "무기"))
	vb.add_child(_label("◆ %s" % type_name, 10, ACCENT.lightened(0.25)))
	var lvl: int = GameState.weapon_level(type_id)
	var names: Array = Balance.WEAPON_NAMES_BY_TYPE.get(type_id, [])
	var top: int = maxi(names.size(), lvl + 1)
	for t in range(1, top + 1):
		var wname: String = Balance.weapon_name_for(type_id, t)
		if t == lvl + 1:
			# The single buyable tier → a buy button (cost from the current level).
			var cost: int = GameState.weapon_upgrade_cost(type_id)
			var afford: bool = GameState.gold >= cost
			var b := _buy_button("%s  —  %dG 구매" % [wname, cost], afford)
			b.pressed.connect(_buy_weapon.bind(type_id))
			vb.add_child(b)
		else:
			var state: String = ""
			var col: Color = TEXT
			if t < lvl:
				state = "보유"
				col = OWNED
			elif t == lvl:
				state = "장착 중"
				col = Color(1, 1, 1, 1)
			else:
				state = "잠김"
				col = LOCKED_GREY
			vb.add_child(_tier_row(wname, state, col))
	return card


func _buy_weapon(type_id: StringName) -> void:
	GameState.upgrade_weapon(type_id)


func _sell_row(inv_index: int, entry) -> Button:
	var item: ItemData = GameState.item_entry_data(entry)
	var lvl: int = GameState.item_entry_level(entry)
	var val: int = GameState.inventory_sell_value(entry)
	var b := _buy_button("%s Lv%d  —  %dG 판매" % [item.display_name, lvl, val], true)
	b.pressed.connect(_sell_item.bind(inv_index))
	return b


func _sell_item(inv_index: int) -> void:
	GameState.sell_inventory_entry_at(inv_index)


# ─── 상태 tab — per-member dashboard ───────────────────────────────────
func _build_status_tab() -> void:
	_content.add_child(_section("상태 — 파티 스탯"))
	for i in GameState.party.size():
		var card := _card()
		var vb: VBoxContainer = card.get_child(0)
		var lbl := _label(GameState.party_member_stat_tooltip(i), 8, TEXT)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		vb.add_child(lbl)
		_content.add_child(card)


func _build_stub(text: String) -> void:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(0, 120)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_label(text, 9, DIM))
	_content.add_child(box)


# ─── Small building blocks ─────────────────────────────────────────────
func _section(text: String) -> Label:
	var l := _label(text, 8, Color(0.78, 0.82, 0.74, 0.7))
	return l


func _hint(text: String) -> Label:
	return _label(text, 8, DIM)


func _tier_row(name_text: String, state: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var n := _label(name_text, 9, color)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	row.add_child(_label(state, 8, color))
	return row


func _card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	card.add_child(vb)
	return card


func _buy_button(text: String, affordable: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not affordable
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", PANEL_FONT)
	b.add_theme_font_size_override("font_size", 8)
	var bg: Color = GOLD if affordable else LOCKED_GREY
	b.add_theme_stylebox_override("normal", _btn_style(bg))
	b.add_theme_stylebox_override("hover", _btn_style(bg.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _btn_style(bg.darkened(0.1)))
	b.add_theme_stylebox_override("disabled", _btn_style(LOCKED_GREY))
	b.add_theme_color_override("font_color", Color(0.12, 0.1, 0.06, 1.0) if affordable else Color(0.78, 0.8, 0.84, 0.8))
	b.add_theme_color_override("font_disabled_color", Color(0.78, 0.8, 0.84, 0.7))
	return b


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


# ─── Styles ────────────────────────────────────────────────────────────
func _window_style() -> StyleBoxFlat:
	var s := OSWindow.body_style(WINDOW_BG)  # unified white border + small corners
	s.shadow_size = 10
	s.set_content_margin_all(0)
	return s


func _titlebar_style() -> StyleBoxFlat:
	var s := OSWindow.titlebar_style(ACCENT)
	s.content_margin_left = 7
	s.content_margin_right = 5
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _tab_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = 3
	s.corner_radius_top_right = 3
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	s.content_margin_left = 2
	s.content_margin_right = 2
	return s


func _card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL_BG
	s.set_corner_radius_all(4)
	s.set_border_width_all(1)
	s.border_color = Color(1, 1, 1, 0.08)
	s.set_content_margin_all(5)
	return s


func _btn_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(3)
	s.content_margin_left = 5
	s.content_margin_right = 5
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


func _flat_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.content_margin_left = 3
	s.content_margin_right = 3
	s.content_margin_top = 3
	s.content_margin_bottom = 0
	return s


func _make_close_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(12, 12)
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.96, 0.96, 0.97, 1.0)
	base.set_corner_radius_all(6)
	base.set_border_width_all(1)
	base.border_color = Color(0.1, 0.1, 0.12, 0.6)
	var hov := base.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.969, 0.306, 0.275, 1.0)  # #f74e46
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	return b


func _label(text: String, pt: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PANEL_FONT)
	l.add_theme_font_size_override("font_size", pt)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
