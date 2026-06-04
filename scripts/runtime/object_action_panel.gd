class_name ObjectActionPanel
extends Node2D

## A speech-bubble action panel that floats ABOVE a clicked field object, with a
## little pointer aimed down at it (Downwell-style). It lives in WORLD space so it
## zooms/pans with the camera. Each object type shows its own buttons — campfire =
## [쉰다] (rest) + [닫기] (close). Look comes from the master theme (retro window).

const THEME: Theme = preload("res://assets/themes/ui_theme.tres")
const POINTER_TIP_GAP: float = 14.0   ## pointer tip sits this far above the object
const POINTER_H: float = 6.0          ## pointer height (panel-bottom → tip)
const POINTER_HALF_W: float = 5.0

var _panel: PanelContainer
var _title: Label
var _row: HBoxContainer
var _pointer_fill: Polygon2D
var _pointer_edge: Line2D


func _ready() -> void:
	z_index = 60  # above the world battle windows
	visible = false
	_build()
	EventBus.structure_clicked.connect(_on_structure_clicked)


func _build() -> void:
	# Pointer first (drawn UNDER the panel so the panel hides its base seam).
	_pointer_fill = Polygon2D.new()
	add_child(_pointer_fill)
	_pointer_edge = Line2D.new()
	_pointer_edge.width = 1.0
	_pointer_edge.joint_mode = Line2D.LINE_JOINT_SHARP
	add_child(_pointer_edge)

	_panel = PanelContainer.new()
	_panel.theme = THEME  # root is a Node2D (no theme) → give the Control its own
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_panel.add_child(col)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 5)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_row)


func _on_structure_clicked(building_id: StringName, world_position: Vector2) -> void:
	open(building_id, world_position)


func open(building_id: StringName, world_position: Vector2) -> void:
	position = world_position  # anchor on the object (world space → zooms)
	for c in _row.get_children():
		c.queue_free()
	match building_id:
		&"campfire":
			_title.text = "모닥불"
			_add_button("쉰다", _on_rest)
			_add_button("닫기", close)
		_:
			var bname: String = str(Balance.building_by_id(building_id).get("name", ""))
			if bname.is_empty():
				bname = str(Balance.tile_by_id(building_id).get("name", building_id))
			_title.text = bname
			_add_button("닫기", close)
	visible = true
	await get_tree().process_frame  # let the panel size to its content first
	_layout()


## Place the box above the anchor and aim the pointer down at it.
func _layout() -> void:
	if _panel == null:
		return
	var w: Vector2 = _panel.size
	var base_y: float = -(POINTER_TIP_GAP + POINTER_H)  # panel bottom edge
	var tip_y: float = -POINTER_TIP_GAP                 # pointer tip (near object)
	_panel.position = Vector2(-w.x * 0.5, base_y - w.y)
	var box := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	var fill_color: Color = box.bg_color if box != null else Color(0.26, 0.53, 0.72, 1)
	var edge_color: Color = box.border_color if box != null else Color(0, 0, 0, 1)
	_pointer_fill.color = fill_color
	_pointer_fill.polygon = PackedVector2Array([
		Vector2(-POINTER_HALF_W, base_y), Vector2(POINTER_HALF_W, base_y), Vector2(0.0, tip_y),
	])
	_pointer_edge.default_color = edge_color
	_pointer_edge.points = PackedVector2Array([
		Vector2(-POINTER_HALF_W, base_y), Vector2(0.0, tip_y), Vector2(POINTER_HALF_W, base_y),
	])


func _add_button(text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40.0, 14.0)
	b.pressed.connect(handler)
	_row.add_child(b)


func _on_rest() -> void:
	EventBus.rest_requested.emit()
	close()


func close() -> void:
	visible = false
