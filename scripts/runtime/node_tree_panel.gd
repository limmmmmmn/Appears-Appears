class_name NodeTreePanel
extends Node2D

## Step 2 of the field-end settlement: the skill node tree screen.
## Shown only when the player picks [업그레이드] on ResultsPanel.
## The single [계속] button funnels back to the field.
##
## Node-row layout is intentionally a flat list for now; once the catalog
## passes ~8 nodes we'll switch to a real grid by NodeData.grid_position.

signal continue_pressed

const PANEL_MARGIN: Vector2 = Vector2(8.0, 8.0)
const BG_OVERLAY: Color = Color(0.05, 0.04, 0.03, 0.86)
const PANEL_BG: Color = Color(0.12, 0.10, 0.08, 0.96)
const PANEL_BORDER: Color = Color(0.32, 0.24, 0.14, 1.0)
const HEADER_COLOR: Color = Color(1.0, 0.92, 0.42)
const NODE_LOCKED_COLOR: Color = Color(0.55, 0.5, 0.45)
const NODE_UNLOCKED_COLOR: Color = Color(0.6, 0.95, 0.55)

const NODE_ROW_HEIGHT: float = 44.0
const NODE_ROW_GAP: float = 6.0
const COLUMN_WIDTH: float = 200.0
const MAX_PANEL_HEIGHT: float = 220.0

var _viewport_size: Vector2
var _gold_label: Label
var _node_rows: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport_size = get_viewport_rect().size
	_build_camera()
	_build_overlay()
	_build_header()
	_build_node_grid()
	_build_footer()
	EventBus.gold_changed.connect(_on_gold_changed)
	SkillTreeDB.node_unlocked.connect(_on_node_unlocked)
	_refresh_all()


func _build_camera() -> void:
	var cam := Camera2D.new()
	cam.position = _viewport_size * 0.5
	cam.zoom = Vector2.ONE
	add_child(cam)
	cam.make_current()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 22
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = BG_OVERLAY
	dim.position = Vector2.ZERO
	dim.size = _viewport_size
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var panel_origin: Vector2 = PANEL_MARGIN
	var panel_size: Vector2 = _viewport_size - PANEL_MARGIN * 2.0
	var border := ColorRect.new()
	border.color = PANEL_BORDER
	border.position = panel_origin - Vector2(2.0, 2.0)
	border.size = panel_size + Vector2(4.0, 4.0)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(border)

	var bg := ColorRect.new()
	bg.color = PANEL_BG
	bg.position = panel_origin
	bg.size = panel_size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)


func _build_header() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 23
	add_child(layer)

	var origin: Vector2 = PANEL_MARGIN + Vector2(10.0, 6.0)
	var title := Label.new()
	title.text = "스킬 노드"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", HEADER_COLOR)
	title.position = origin
	layer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "골드를 써서 시스템을 풀어내세요."
	subtitle.add_theme_font_size_override("font_size", 9)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	subtitle.position = origin + Vector2(0.0, 18.0)
	layer.add_child(subtitle)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 11)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	_gold_label.position = Vector2(_viewport_size.x - PANEL_MARGIN.x - 90.0, origin.y + 4.0)
	layer.add_child(_gold_label)


func _build_node_grid() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 23
	add_child(layer)

	var origin: Vector2 = Vector2(PANEL_MARGIN.x + 14.0, PANEL_MARGIN.y + 44.0)
	var y: float = 0.0
	var column: float = 0.0
	for node: NodeData in SkillTreeDB.get_all():
		_build_node_row(layer, node, origin + Vector2(column, y))
		y += NODE_ROW_HEIGHT + NODE_ROW_GAP
		if y > MAX_PANEL_HEIGHT:
			y = 0.0
			column += COLUMN_WIDTH


func _build_node_row(parent: CanvasLayer, node: NodeData, origin: Vector2) -> void:
	var name_label := Label.new()
	name_label.text = node.display_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.position = origin
	parent.add_child(name_label)

	var status_label := Label.new()
	status_label.add_theme_font_size_override("font_size", 8)
	status_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78))
	status_label.position = origin + Vector2(0.0, 14.0)
	status_label.size = Vector2(COLUMN_WIDTH - 16.0, 14.0)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(status_label)

	var button := Button.new()
	button.add_theme_font_size_override("font_size", 9)
	button.position = origin + Vector2(0.0, 28.0)
	button.size = Vector2(COLUMN_WIDTH - 16.0, 14.0)
	button.pressed.connect(_on_node_buy_pressed.bind(node))
	parent.add_child(button)

	_node_rows.append({
		"node": node,
		"name_label": name_label,
		"status_label": status_label,
		"button": button,
	})


func _build_footer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 23
	add_child(layer)

	var button_width: float = 140.0
	var button_height: float = 24.0
	var cont := Button.new()
	cont.text = "계속  ▶"
	cont.add_theme_font_size_override("font_size", 12)
	cont.size = Vector2(button_width, button_height)
	cont.position = Vector2(
		(_viewport_size.x - button_width) * 0.5,
		_viewport_size.y - PANEL_MARGIN.y - 14.0 - button_height,
	)
	cont.pressed.connect(_on_continue_pressed)
	layer.add_child(cont)
	cont.grab_focus()


# ─── Refresh ──────────────────────────────────────────────────────────
func _refresh_all() -> void:
	_refresh_header()
	_refresh_node_grid()


func _refresh_header() -> void:
	if _gold_label != null and is_instance_valid(_gold_label):
		_gold_label.text = "골드  %d" % GameState.gold


func _refresh_node_grid() -> void:
	for row: Dictionary in _node_rows:
		var node: NodeData = row.node
		var button: Button = row.button
		var name_label: Label = row.name_label
		var status_label: Label = row.status_label
		var unlocked: bool = SkillTreeDB.is_unlocked(node.id)
		var prereq_ok: bool = SkillTreeDB.prereqs_satisfied(node)
		var affordable: bool = GameState.gold >= node.cost
		if unlocked:
			name_label.add_theme_color_override("font_color", NODE_UNLOCKED_COLOR)
			button.text = "보유 중"
			button.disabled = true
			status_label.text = node.description
		elif not prereq_ok:
			name_label.add_theme_color_override("font_color", NODE_LOCKED_COLOR)
			button.text = "🔒 잠김"
			button.disabled = true
			status_label.text = "선행: %s" % _prereq_summary(node)
		else:
			name_label.add_theme_color_override("font_color", Color.WHITE)
			button.text = "구매 (%d g)" % node.cost
			button.disabled = not affordable
			status_label.text = node.description


func _prereq_summary(node: NodeData) -> String:
	if node.prereq_ids.is_empty():
		return "-"
	var names: Array[String] = []
	for prereq_id: StringName in node.prereq_ids:
		var prereq: NodeData = SkillTreeDB.get_by_id(prereq_id)
		names.append(prereq.display_name if prereq != null else String(prereq_id))
	return ", ".join(names)


# ─── Signal handlers ──────────────────────────────────────────────────
func _on_gold_changed(_new_gold: int) -> void:
	_refresh_header()
	_refresh_node_grid()


func _on_node_unlocked(_node: NodeData) -> void:
	_refresh_node_grid()


func _on_node_buy_pressed(node: NodeData) -> void:
	SkillTreeDB.try_purchase(node)


func _on_continue_pressed() -> void:
	continue_pressed.emit()
