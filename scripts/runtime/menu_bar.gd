class_name TopMenuBar
extends Control

## Top menu bar — the "OS" of the desktop metaphor. A thin macOS-style strip across
## the top: a logo + app menus on the left, status (gold / hero level) on the right
## like the macOS clock. Cute + colorful (Resurrect 64), rounded bottom corners.
##   Stage 1: chrome + live status. Menu items are mostly identity for now; a couple
##   double as shortcuts (마을 / 강화) that toggle their desktop windows.
## Designed so a later "retro game skin" can be laid over this OS layer.

const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const BAR_BG: Color = Color(0.18, 0.133, 0.184, 0.96)   ## #2e222f dark, like windows
const TEXT: Color = Color(0.93, 0.94, 0.96, 1.0)
const GOLD: Color = Color(1.0, 0.91, 0.48, 1.0)
const ACCENT: Color = Color(0.055, 0.686, 0.608, 1.0)   ## teal logo
const BAR_HEIGHT: float = 15.0
const VIEWPORT_W: float = 640.0

## (label, target window group). Empty group = inert identity menu (Stage 1).
const MENUS: Array = [
	{"text": "필드", "group": &""},
	{"text": "강화", "group": &"upgrade_window"},
	{"text": "마을", "group": &"town_window"},
	{"text": "도움말", "group": &""},
]

var _gold_label: Label
var _level_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = BAR_HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.gold_changed.connect(_on_gold_changed.unbind(1))
	EventBus.party_member_xp_changed.connect(_on_any_change.unbind(4))
	EventBus.party_changed.connect(_on_any_change)
	_refresh_status()


func _build() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _bar_style())
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)

	# Logo dot + OS name.
	var logo := _label("◆", 10, ACCENT.lightened(0.2))
	row.add_child(logo)
	var name_lbl := _label("HyperOS", 9, TEXT)
	row.add_child(name_lbl)
	row.add_child(_spacer(6))

	# App menus.
	for menu: Dictionary in MENUS:
		row.add_child(_menu_item(str(menu["text"]), StringName(menu["group"])))

	# Right-aligned status (gold + hero level), macOS-clock style.
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(push)
	_level_label = _label("Lv 1", 9, TEXT)
	row.add_child(_level_label)
	row.add_child(_label("│", 9, Color(1, 1, 1, 0.25)))
	_gold_label = _label("◆ 0", 9, GOLD)
	row.add_child(_gold_label)
	row.add_child(_spacer(4))


func _menu_item(text: String, group: StringName) -> Control:
	if group == &"":
		var l := _label(text, 9, Color(0.78, 0.8, 0.84, 0.85))
		return l
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_font_override("font", PANEL_FONT)
	b.add_theme_font_size_override("font_size", 9)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", ACCENT.lightened(0.3))
	b.add_theme_stylebox_override("normal", _empty_style())
	b.add_theme_stylebox_override("hover", _hover_style())
	b.add_theme_stylebox_override("pressed", _hover_style())
	b.pressed.connect(_toggle_group.bind(group))
	return b


func _toggle_group(group: StringName) -> void:
	var w: Node = get_tree().get_first_node_in_group(String(group))
	if w == null:
		return
	if w.has_method("toggle"):
		w.call("toggle")
	elif w.has_method("open"):
		w.call("open")


func _on_gold_changed() -> void:
	if _gold_label != null:
		_gold_label.text = "◆ %d" % GameState.gold


func _on_any_change() -> void:
	_refresh_status()


func _refresh_status() -> void:
	if _gold_label != null:
		_gold_label.text = "◆ %d" % GameState.gold
	if _level_label != null and GameState.party_size() > 0:
		_level_label.text = "Lv %d" % GameState.party_level(0)


# ─── Styles ────────────────────────────────────────────────────────────
func _bar_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BAR_BG
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 3
	return s


func _empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _hover_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 1, 1, 0.12)
	s.set_corner_radius_all(3)
	s.content_margin_left = 3
	s.content_margin_right = 3
	return s


func _spacer(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _label(text: String, pt: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", PANEL_FONT)
	l.add_theme_font_size_override("font_size", pt)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
