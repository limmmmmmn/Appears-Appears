class_name DesktopIcons
extends Control

## Right-edge desktop icons. In the OS metaphor the upgrade/town/inventory surfaces
## are collapsed to little rounded app icons; clicking one OPENS its window (toggle).
## Cute + colorful (Resurrect 64). This is Stage 1 (iconify) + Stage 2 (open window).

const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const ICON: float = 30.0
const SLOT_H: float = 42.0       ## icon + label
const TOP_MARGIN: float = 20.0   ## clear the menu bar

## id → window group to toggle, glyph, label, accent (Resurrect 64).
const APPS: Array = [
	{"group": &"upgrade_window", "glyph": "강", "label": "강화", "color": Color(0.910, 0.231, 0.231, 1.0)},
	{"group": &"town_window",    "glyph": "마", "label": "마을", "color": Color(0.412, 0.792, 0.353, 1.0)},
	{"group": &"inventory_window","glyph": "인", "label": "인벤", "color": Color(0.055, 0.686, 0.608, 1.0)},
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -40.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 360.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var y: float = TOP_MARGIN
	for app: Dictionary in APPS:
		_add_icon(app, y)
		y += SLOT_H


func _add_icon(app: Dictionary, y: float) -> void:
	var slot := Control.new()
	slot.position = Vector2(4.0, y)
	slot.size = Vector2(ICON, SLOT_H)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size = Vector2(ICON, ICON)
	btn.text = str(app["glyph"])
	btn.add_theme_font_override("font", PANEL_FONT)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	var accent: Color = app["color"]
	btn.add_theme_stylebox_override("normal", _icon_style(accent))
	btn.add_theme_stylebox_override("hover", _icon_style(accent.lightened(0.16)))
	btn.add_theme_stylebox_override("pressed", _icon_style(accent.darkened(0.12)))
	btn.pressed.connect(_toggle.bind(StringName(app["group"])))
	slot.add_child(btn)

	var label := Label.new()
	label.text = str(app["label"])
	label.add_theme_font_override("font", PANEL_FONT)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.94, 0.95, 0.97, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(ICON, 9.0)
	label.position = Vector2(0.0, ICON + 1.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)


func _toggle(group: StringName) -> void:
	var w: Node = get_tree().get_first_node_in_group(String(group))
	if w == null:
		return
	if w.has_method("toggle"):
		w.call("toggle")
	elif w.has_method("open"):
		w.call("open")


func _icon_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = accent
	s.set_corner_radius_all(7)  # rounded "app icon" squircle-ish
	s.set_border_width_all(1)
	s.border_color = Color(1, 1, 1, 0.35)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 2
	return s
