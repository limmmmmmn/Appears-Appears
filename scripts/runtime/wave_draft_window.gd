class_name WaveDraftWindow
extends Control

## 드래프트 창 — the dopamine valve. A wave's timer runs out → the field freezes
## → THREE cards (적/아군/보상/필살기 axes, color-coded) → pick one → next wave
## starts instantly. No 닫기: the only way forward is a choice, and every choice
## is an upgrade — the player can never pick wrong.

const CARD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const AXIS_COLORS: Dictionary = {
	&"enemy": Color(0.92, 0.33, 0.23, 1.0),  # danger = red
	&"ally": Color(0.27, 0.5, 0.85, 1.0),    # power = blue
	&"loot": Color(0.9, 0.71, 0.24, 1.0),    # greed = gold
	&"hook": Color(0.54, 0.44, 0.82, 1.0),   # spectacle = purple
}
const AXIS_NAMES: Dictionary = {
	&"enemy": "적", &"ally": "아군", &"loot": "보상", &"hook": "필살기",
}

@onready var _dim: ColorRect = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %TitleLabel
@onready var _cards: VBoxContainer = %Cards


func _ready() -> void:
	visible = false
	EventBus.wave_ended.connect(_on_wave_ended)


func _on_wave_ended(wave: int) -> void:
	if visible:
		return
	GameState.open_event_window()  # full freeze — the world holds its breath
	visible = true
	_title.text = "웨이브 %d 클리어!" % wave
	_render_cards()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.88, 0.88)
	_dim.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_dim, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _render_cards() -> void:
	for c in _cards.get_children():
		c.queue_free()
	for card: Dictionary in GameState.draft_options():
		_cards.add_child(_make_card(card))


func _make_card(card: Dictionary) -> Button:
	var axis: StringName = StringName(card.get("axis", &"ally"))
	var accent: Color = AXIS_COLORS.get(axis, Color.WHITE)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 38.0)
	b.pressed.connect(_on_card_picked.bind(StringName(card.get("id", &""))))

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6.0
	col.offset_right = -6.0
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var axis_tag := Label.new()
	axis_tag.text = "[%s]" % str(AXIS_NAMES.get(axis, "?"))
	axis_tag.add_theme_font_override("font", CARD_FONT)
	axis_tag.add_theme_font_size_override("font_size", 8)
	axis_tag.add_theme_color_override("font_color", accent)
	axis_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(axis_tag)
	var name_label := Label.new()
	name_label.text = str(card.get("name", ""))
	name_label.add_theme_font_override("font", CARD_FONT)
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name_label)

	var desc := Label.new()
	desc.text = str(card.get("desc", ""))
	desc.add_theme_font_override("font", CARD_FONT)
	desc.add_theme_font_size_override("font_size", 7)
	desc.add_theme_color_override("font_color", Color(0.478, 0.427, 0.36, 1.0))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(desc)
	return b


func _on_card_picked(card_id: StringName) -> void:
	GameState.apply_draft_card(card_id)
	visible = false
	GameState.close_event_window()
	GameState.start_next_wave()  # straight back into the action — no dead air
