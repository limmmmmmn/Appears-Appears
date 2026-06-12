class_name NamePrompt
extends Control

## Opening "이름을 입력하세요" overlay, split out of the HUD into its own scene. The root
## is an invisible full-rect Control that does NOT eat input; only when a name is still
## needed does it build the dimming backdrop + dialog (which DO block). Built in code, so
## the scene is just this root + the script.

const HUD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

var _line_edit: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # idle root never blocks
	# 이름 입력 오프닝 스킵 — 그냥 "용사"로 바로 시작 ㅋㅋ (start_world도 여기서 발동)
	if not GameState.name_entered:
		GameState.set_player_name("용사")


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.45)  # dim, but the lone hero still shows through
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.13, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.35, 0.9)
	style.set_corner_radius_all(7)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)

	var title := Label.new()
	title.text = "이름을 입력하세요"
	title.add_theme_font_override("font", HUD_FONT)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_line_edit = LineEdit.new()
	_line_edit.custom_minimum_size = Vector2(160.0, 22.0)
	_line_edit.placeholder_text = "용사"
	_line_edit.max_length = 10
	_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line_edit.add_theme_font_override("font", HUD_FONT)
	_line_edit.add_theme_font_size_override("font_size", 12)
	_line_edit.text_submitted.connect(_on_submitted)
	col.add_child(_line_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	row.add_child(_make_button("확인", Color(1.0, 0.85, 0.35, 1.0), _on_confirm))
	row.add_child(_make_button("랜덤", Color(0.6, 0.78, 0.95, 1.0), _on_random))

	_line_edit.call_deferred("grab_focus")


func _make_button(text: String, accent: Color, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56.0, 22.0)
	b.add_theme_font_override("font", HUD_FONT)
	b.add_theme_font_size_override("font_size", 11)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, Color(0.08, 0.07, 0.05, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent
	normal.set_corner_radius_all(3)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.lightened(0.18)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(handler)
	return b


func _on_submitted(_text: String) -> void:
	_on_confirm()


func _on_confirm() -> void:
	GameState.set_player_name(_line_edit.text if _line_edit != null else "")
	_dismiss()


func _on_random() -> void:
	if _line_edit != null:
		_line_edit.text = GameState.random_hero_name()  # fill so the player sees it


func _dismiss() -> void:
	for c in get_children():
		c.queue_free()
