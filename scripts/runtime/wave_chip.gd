class_name WaveChip
extends PanelContainer

## Top-strip cycle readout: ☀ "W3 · 7s" by day, 🌙 "밤! · 9s" by night. A drawn
## circle stands in for the sun/moon art (placeholder until sprites exist).
## Ticks every frame; blushes red when time runs short / night falls.

const TEXT_COLOR: Color = Color(0.12941177, 0.11764706, 0.101960786, 1.0)
const URGENT_COLOR: Color = Color(0.85, 0.22, 0.18, 1.0)
const NIGHT_COLOR: Color = Color(0.36, 0.32, 0.62, 1.0)
const SUN_COLOR: Color = Color(0.98, 0.78, 0.2, 1.0)
const SUN_RIM: Color = Color(0.7, 0.5, 0.08, 1.0)
const MOON_COLOR: Color = Color(0.82, 0.86, 1.0, 1.0)
const MOON_RIM: Color = Color(0.45, 0.5, 0.78, 1.0)

@onready var _label: Label = %WaveLabel

var _dial: Control  ## the sun/moon circle (placeholder for future art)
var _town_btn: Button  ## "마을로" — settle the wave early, on YOUR clock


func _ready() -> void:
	# 해/달 placeholder: a small drawn circle to the LEFT of the text.
	_dial = Control.new()
	_dial.custom_minimum_size = Vector2(14.0, 0.0)
	_dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dial.draw.connect(_draw_dial)
	# Put the dial + label in a row (label already lives under the panel).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if _label != null and _label.get_parent() != null:
		_label.get_parent().remove_child(_label)
	add_child(row)
	row.add_child(_dial)
	row.add_child(_label)
	# 마을로 버튼: 시간이 남아도 내 타이밍에 정산하러 간다 (유기적 마을행).
	_town_btn = Button.new()
	_town_btn.text = "마을로"
	_town_btn.tooltip_text = "지금 바로 정산하고 마을로 간다"
	_town_btn.focus_mode = Control.FOCUS_NONE
	_town_btn.add_theme_font_size_override("font_size", 8)
	_town_btn.pressed.connect(func() -> void:
		if GameState.wave_active and not GameState.wave_winding_down:
			GameState.end_cycle())
	row.add_child(_town_btn)


func _draw_dial() -> void:
	var c := Vector2(_dial.size.x * 0.5, _dial.size.y * 0.5)
	if GameState.is_night:
		_dial.draw_circle(c, 5.0, MOON_RIM)
		_dial.draw_circle(c, 4.0, MOON_COLOR)
	else:
		_dial.draw_circle(c, 5.0, SUN_RIM)
		_dial.draw_circle(c, 4.0, SUN_COLOR)


func _process(_delta: float) -> void:
	if _label == null:
		return
	if GameState.wave_number <= 0:
		visible = false
		return
	visible = true
	if _dial != null:
		_dial.queue_redraw()
	if _town_btn != null:
		_town_btn.visible = GameState.wave_active and not GameState.wave_winding_down
	if GameState.wave_active:
		if GameState.is_night:
			_label.text = "밤! · %ds" % int(ceil(GameState.night_time_left))
			_label.add_theme_color_override("font_color", NIGHT_COLOR)
		else:
			_label.text = "W%d · %ds" % [GameState.wave_number, int(ceil(GameState.wave_time_left))]
			_label.add_theme_color_override("font_color",
				URGENT_COLOR if GameState.wave_time_left <= 3.0 else TEXT_COLOR)
	else:
		_label.text = "W%d · 마을" % GameState.wave_number
		_label.add_theme_color_override("font_color", URGENT_COLOR)
