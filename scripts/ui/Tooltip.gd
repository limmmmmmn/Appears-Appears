extends PanelContainer
class_name Tooltip

@export var max_width: float = 156.0
@export var row_spacing: int = 2

@onready var row_box: HBoxContainer = $Margin/Row
@onready var icon_rect: TextureRect = $Margin/Row/Icon
@onready var content_vbox: VBoxContainer = $Margin/Row/ContentVBox

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_apply_default_style()
	if content_vbox != null:
		content_vbox.add_theme_constant_override("separation", row_spacing)


func set_rows(rows: Array, icon_texture: Texture2D = null) -> void:
	if content_vbox == null:
		return
	for child in content_vbox.get_children():
		child.queue_free()

	if icon_rect != null:
		icon_rect.visible = icon_texture != null
		icon_rect.texture = icon_texture

	for row_any in rows:
		if not (row_any is Dictionary):
			continue
		var row: Dictionary = row_any as Dictionary
		var text: String = str(row.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		var label := Label.new()
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(row.get("size", 9)))
		label.add_theme_color_override("font_color", row.get("color", Color(0.9, 0.9, 0.95, 1.0)) as Color)
		content_vbox.add_child(label)

	await get_tree().process_frame
	if row_box != null:
		custom_minimum_size = Vector2.ZERO
		size = row_box.size + Vector2(12.0, 8.0)


func place_near(anchor_global: Vector2, clamp_rect: Rect2, prefer_above: bool = true, gap: float = 4.0) -> void:
	await get_tree().process_frame
	var x: float = anchor_global.x - size.x * 0.5
	var y: float = anchor_global.y - size.y - gap if prefer_above else anchor_global.y + gap
	if prefer_above and y < clamp_rect.position.y:
		y = anchor_global.y + gap
	elif not prefer_above and y + size.y > clamp_rect.end.y:
		y = anchor_global.y - size.y - gap
	x = clampf(x, clamp_rect.position.x, clamp_rect.end.x - size.x)
	y = clampf(y, clamp_rect.position.y, clamp_rect.end.y - size.y)
	global_position = Vector2(x, y)


func _apply_default_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.5, 0.6, 0.82)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	add_theme_stylebox_override("panel", style)
