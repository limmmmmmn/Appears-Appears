class_name ObjectActionPanel
extends Node2D

## A speech-bubble that floats ABOVE a clicked field object, pointer aimed down
## at it. WORLD space → zooms/pans with the camera. Two buttons, RPG-style:
##   [간다]  — the hero walks over; the 방문 창 opens on arrival
##   [닫기]  — dismiss
## All object interaction (rest / upgrades / shop) happens in the 방문 창
## (ObjectWindow), not here — this bubble only answers "갈까?".
## Look = master theme.

const THEME: Theme = preload("res://assets/themes/ui_theme.tres")
const POINTER_TIP_GAP: float = 14.0
const POINTER_H: float = 6.0
const POINTER_HALF_W: float = 5.0

var _panel: PanelContainer
var _title: Label
var _row: HBoxContainer
var _pointer_fill: Polygon2D
var _pointer_edge: Line2D
var _structure: Node = null


func _ready() -> void:
	z_index = 60
	visible = false
	_build()
	EventBus.structure_clicked.connect(_on_structure_clicked)
	# The hero is already on his way / arrived — the bubble's question is answered.
	EventBus.structure_visit_requested.connect(close.unbind(1))
	EventBus.object_window_requested.connect(close.unbind(1))


func _build() -> void:
	_pointer_fill = Polygon2D.new()
	add_child(_pointer_fill)
	_pointer_edge = Line2D.new()
	_pointer_edge.width = 1.0
	_pointer_edge.joint_mode = Line2D.LINE_JOINT_SHARP
	add_child(_pointer_edge)

	_panel = PanelContainer.new()
	_panel.theme = THEME
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


func _on_structure_clicked(structure: Node) -> void:
	open(structure)


func open(structure: Node) -> void:
	if structure == null or not (structure is Node2D):
		return
	_structure = structure
	position = (structure as Node2D).global_position
	for c in _row.get_children():
		c.queue_free()
	var building_id: StringName = structure.building_id if "building_id" in structure else &""
	var bname: String = str(Balance.building_by_id(building_id).get("name", ""))
	if bname.is_empty():
		bname = str(Balance.tile_by_id(building_id).get("name", building_id))
	_title.text = bname
	_add_button("간다", _on_visit)
	_add_button("닫기", close)
	visible = true
	await get_tree().process_frame
	_layout()


func _add_button(text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40.0, 14.0)
	b.pressed.connect(handler)
	_row.add_child(b)


# ─── Per-object actions ────────────────────────────────────────────────
func _on_visit() -> void:
	if is_instance_valid(_structure):
		EventBus.structure_visit_requested.emit(_structure)
	close()


# ─── Layout (box above the object, pointer down at it) ─────────────────
func _layout() -> void:
	if _panel == null:
		return
	# Shrink/grow the panel to fit the CURRENT content every time. Without this a
	# Control keeps the largest size it has ever had, so a later buttons-only open
	# would stay needlessly huge.
	_panel.reset_size()
	var w: Vector2 = _panel.size
	var base_y: float = -(POINTER_TIP_GAP + POINTER_H)
	var tip_y: float = -POINTER_TIP_GAP
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


func close() -> void:
	visible = false
