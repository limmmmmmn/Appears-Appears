class_name NarrationWindow
extends Control

## The always-on narration window — the bottom "text terminal" of the OS desktop.
## A persistent macOS-style strip that shows the latest story / system line. Field
## messages are mirrored here via EventBus.narration. (Story content comes later;
## for now it surfaces whatever narration the game emits.)

const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const WINDOW_BG: Color = Color(0.18, 0.133, 0.184, 0.96)   ## #2e222f
const ACCENT: Color = Color(0.337, 0.247, 0.337, 1.0)      ## muted plum titlebar
const TEXT: Color = Color(0.9, 0.91, 0.94, 1.0)
const DIM: Color = Color(0.66, 0.68, 0.72, 1.0)

var _text_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 52.0
	offset_right = -52.0
	offset_top = -30.0
	offset_bottom = -4.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.narration.connect(_on_narration)


func _build() -> void:
	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", _window_style())
	window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.clip_contents = true
	add_child(window)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	window.add_child(row)

	var tag := _label("▸", 9, ACCENT.lightened(0.4))
	row.add_child(tag)
	_text_label = _label("…", 9, DIM)
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.clip_text = true
	row.add_child(_text_label)


func _on_narration(text: String) -> void:
	if _text_label != null:
		_text_label.text = text
		_text_label.add_theme_color_override("font_color", TEXT)


func _window_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = WINDOW_BG
	s.set_corner_radius_all(6)
	s.set_border_width_all(1)
	s.border_color = Color(1, 1, 1, 0.12)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	s.shadow_color = Color(0, 0, 0, 0.4)
	s.shadow_size = 4
	return s


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
