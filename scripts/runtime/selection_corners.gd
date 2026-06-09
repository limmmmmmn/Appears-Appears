extends Node2D

## Pixel-style corner brackets for the currently selected field target.

const SELECT_COLOR: Color = Color(1.0, 0.82, 0.18, 1.0)
const SELECT_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.72)
const SELECT_CORNER_LEN: float = 7.0


func configure(rect: Rect2) -> void:
	for child in get_children():
		child.queue_free()
	z_index = 200
	visible = false
	var segments := _segments(rect)
	for points: PackedVector2Array in segments:
		_add_line(_offset_points(points, Vector2(1.0, 1.0)), SELECT_SHADOW, 3.0)
	for points: PackedVector2Array in segments:
		_add_line(points, SELECT_COLOR, 1.5)


func set_selected(selected: bool) -> void:
	visible = selected


func _segments(rect: Rect2) -> Array[PackedVector2Array]:
	var l := SELECT_CORNER_LEN
	var left := rect.position.x
	var top := rect.position.y
	var right := rect.position.x + rect.size.x
	var bottom := rect.position.y + rect.size.y
	return [
		PackedVector2Array([Vector2(left, top), Vector2(left + l, top)]),
		PackedVector2Array([Vector2(left, top), Vector2(left, top + l)]),
		PackedVector2Array([Vector2(right, top), Vector2(right - l, top)]),
		PackedVector2Array([Vector2(right, top), Vector2(right, top + l)]),
		PackedVector2Array([Vector2(left, bottom), Vector2(left + l, bottom)]),
		PackedVector2Array([Vector2(left, bottom), Vector2(left, bottom - l)]),
		PackedVector2Array([Vector2(right, bottom), Vector2(right - l, bottom)]),
		PackedVector2Array([Vector2(right, bottom), Vector2(right, bottom - l)]),
	]


func _add_line(points: PackedVector2Array, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_SHARP
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	line.points = points
	add_child(line)


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for p: Vector2 in points:
		shifted.append(p + offset)
	return shifted
