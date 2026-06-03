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

	# Compact title chip (the window "name"), then the narration text.
	var title := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = ACCENT
	ts.set_corner_radius_all(OSWindow.CORNER)
	ts.content_margin_left = 4
	ts.content_margin_right = 4
	ts.content_margin_top = 1
	ts.content_margin_bottom = 1
	title.add_theme_stylebox_override("panel", ts)
	title.add_child(_label("이야기", 8, Color(0.95, 0.96, 0.98, 1.0)))
	row.add_child(title)
	_text_label = _label("…", 9, DIM)
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.clip_text = true
	row.add_child(_text_label)


func _on_narration(text: String) -> void:
	if _text_label != null:
		_text_label.text = text
		_text_label.add_theme_color_override("font_color", TEXT)


func _window_style() -> StyleBoxFlat:
	var s := OSWindow.body_style(WINDOW_BG)  # unified white border + small corners
	s.content_margin_left = 6
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 2
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
