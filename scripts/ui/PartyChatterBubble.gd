extends PanelContainer
class_name PartyChatterBubble

@export var min_width: float = 132.0
@export var font_size: int = 11
@export var corner_radius: int = 4
@export var border_width: int = 1
@export var padding_h: int = 6
@export var padding_v: int = 3
@export var base_bg_color: Color = Color(1.0, 1.0, 1.0, 0.96)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var text_color: Color = Color(0.0, 0.0, 0.0, 1.0)
@export var bg_tint_strength: float = 0.18

@onready var text_label: Label = $TextLabel
var _pending_text: String = ""
var _pending_tint: Color = Color(0.95, 0.95, 1.0, 1.0)


func _ready() -> void:
	var mixed_bg: Color = base_bg_color.lerp(_pending_tint, clampf(bg_tint_strength, 0.0, 1.0))
	mixed_bg.a = base_bg_color.a
	_apply_style(mixed_bg)
	custom_minimum_size = Vector2(min_width + float(padding_h * 2), 0.0)
	var label: Label = _get_text_label()
	if label == null:
		return
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_constant_override("line_spacing", 0)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)
	label.custom_minimum_size = Vector2(min_width, 0.0)
	label.text = _pending_text


func configure(text: String, tint_color: Color = Color(0.95, 0.95, 1.0, 1.0)) -> void:
	_pending_text = text
	_pending_tint = tint_color
	var label: Label = _get_text_label()
	if label != null:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(min_width, 0.0)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", text_color)
		label.text = text
	custom_minimum_size = Vector2(min_width + float(padding_h * 2), 0.0)
	var mixed_bg: Color = base_bg_color.lerp(tint_color, clampf(bg_tint_strength, 0.0, 1.0))
	mixed_bg.a = base_bg_color.a
	_apply_style(mixed_bg)


func _get_text_label() -> Label:
	if text_label != null:
		return text_label
	return get_node_or_null("TextLabel") as Label


func _apply_style(bg_color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border_color
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.content_margin_left = padding_h
	style.content_margin_right = padding_h
	style.content_margin_top = padding_v
	style.content_margin_bottom = padding_v
	add_theme_stylebox_override("panel", style)
