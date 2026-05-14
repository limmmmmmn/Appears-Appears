class_name FieldShadow
extends Polygon2D

@export var shadow_size: Vector2 = Vector2(14.0, 5.0)
@export_range(0.0, 1.0, 0.01) var shadow_alpha: float = 0.34
@export_range(8, 32, 1) var segment_count: int = 18


func _ready() -> void:
	_rebuild()


func setup_shadow(size: Vector2, alpha: float = shadow_alpha) -> void:
	shadow_size = size
	shadow_alpha = alpha
	_rebuild()


func _rebuild() -> void:
	var points := PackedVector2Array()
	var count: int = maxi(8, segment_count)
	for i in count:
		var angle: float = TAU * float(i) / float(count)
		points.append(Vector2(cos(angle) * shadow_size.x * 0.5, sin(angle) * shadow_size.y * 0.5))
	polygon = points
	color = Color(0.02, 0.015, 0.01, shadow_alpha)
