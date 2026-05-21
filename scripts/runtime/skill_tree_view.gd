extends Control

signal purchase_requested(node_id: StringName)

const GRID_STEP: Vector2 = Vector2(60, 26)
const NODE_SIZE: Vector2 = Vector2(58, 22)
const TREE_CENTER: Vector2 = Vector2(330, 214)
const COLOR_LINE_OWNED: Color = Color(0.95, 0.62, 0.16, 1.0)
const COLOR_LINE_AVAILABLE: Color = Color(0.26, 0.55, 0.7, 1.0)
const COLOR_LINE_LOCKED: Color = Color(0.22, 0.28, 0.32, 0.45)

var _buttons_by_id: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_buttons()
	refresh()


func _draw() -> void:
	for node in SkillTreeDB.get_all():
		var node_center: Vector2 = _node_center(node)
		for prereq_id: StringName in node.prerequisite_ids:
			var prereq = SkillTreeDB.get_by_id(prereq_id)
			if prereq == null:
				continue
			var color: Color = COLOR_LINE_LOCKED
			if GameState.has_skill_node(node.id):
				color = COLOR_LINE_OWNED
			elif GameState.can_unlock_skill_node(node.id):
				color = COLOR_LINE_AVAILABLE
			draw_line(_node_center(prereq), node_center, color, 3.0)


func refresh() -> void:
	for node in SkillTreeDB.get_all():
		var button := _buttons_by_id.get(node.id, null) as Button
		if button == null:
			continue
		var owned: bool = GameState.has_skill_node(node.id)
		var available: bool = GameState.can_unlock_skill_node(node.id)
		var can_buy: bool = GameState.can_purchase_skill_node(node.id)
		button.text = _button_text(node)
		button.disabled = owned or not available
		button.tooltip_text = _tooltip_text(node)
		_apply_button_style(button, owned, available, can_buy)
	queue_redraw()


func _build_buttons() -> void:
	for node in SkillTreeDB.get_all():
		var button := Button.new()
		button.custom_minimum_size = NODE_SIZE
		button.size = NODE_SIZE
		button.position = _node_center(node) - NODE_SIZE * 0.5
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 7)
		button.pressed.connect(_on_button_pressed.bind(node.id))
		add_child(button)
		_buttons_by_id[node.id] = button


func _node_center(node) -> Vector2:
	return TREE_CENTER + Vector2(node.grid_position) * GRID_STEP


func _button_text(node) -> String:
	if GameState.has_skill_node(node.id):
		return "%s\nON" % node.short_label
	if node.cost <= 0:
		return "%s\nFREE" % node.short_label
	return "%s\n%dG" % [node.short_label, node.cost]


func _tooltip_text(node) -> String:
	var state: String = "Owned" if GameState.has_skill_node(node.id) else "Locked"
	if not GameState.has_skill_node(node.id) and GameState.can_unlock_skill_node(node.id):
		state = "Available"
	return "%s\n%s\nCost: %dG\n%s" % [node.display_name, state, node.cost, node.description]


func _apply_button_style(button: Button, owned: bool, available: bool, can_buy: bool) -> void:
	var bg: Color = Color(0.18, 0.22, 0.24, 1.0)
	var border: Color = Color(0.07, 0.08, 0.09, 1.0)
	var text: Color = Color(0.64, 0.68, 0.68, 1.0)
	if owned:
		bg = Color(0.95, 0.63, 0.18, 1.0)
		border = Color(0.18, 0.1, 0.04, 1.0)
		text = Color(0.09, 0.06, 0.03, 1.0)
	elif can_buy:
		bg = Color(0.28, 0.68, 0.72, 1.0)
		border = Color(0.05, 0.22, 0.26, 1.0)
		text = Color(0.05, 0.09, 0.1, 1.0)
	elif available:
		bg = Color(0.38, 0.42, 0.44, 1.0)
		border = Color(0.12, 0.14, 0.15, 1.0)
		text = Color(0.95, 0.88, 0.68, 1.0)
	var normal := _style(bg, border, 2)
	var hover := _style(bg.lightened(0.08), border, 2)
	var focus := _style(bg.lightened(0.14), Color(1.0, 0.9, 0.32, 1.0), 3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", _style(bg.darkened(0.08), border, 2))
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_color_override("font_color", text)
	button.add_theme_color_override("font_hover_color", text)
	button.add_theme_color_override("font_focus_color", text)
	button.add_theme_color_override("font_disabled_color", text.darkened(0.2) if not owned else text)


func _style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _on_button_pressed(node_id: StringName) -> void:
	purchase_requested.emit(node_id)
