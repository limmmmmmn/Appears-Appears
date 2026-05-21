extends Control

signal purchase_requested(node_id: StringName)

const GRID_STEP: Vector2 = Vector2(56, 35)
const NODE_SIZE: Vector2 = Vector2(34, 34)
const TREE_CENTER: Vector2 = Vector2(330, 220)
const TOOLTIP_SIZE: Vector2 = Vector2(190, 58)
const TOOLTIP_GAP: float = 7.0
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 1.75
const ZOOM_STEP: float = 1.12
const KEYBOARD_PAN_SPEED: float = 280.0
const COLOR_LINE_OWNED: Color = Color(0.95, 0.62, 0.16, 1.0)
const COLOR_LINE_AVAILABLE: Color = Color(0.26, 0.55, 0.7, 1.0)
const COLOR_LINE_LOCKED: Color = Color(0.22, 0.28, 0.32, 0.45)
const TOWN_UI_FONT: Font = preload("res://assets/fonts/town_ui_font.tres")

var _buttons_by_id: Dictionary = {}
var _can_purchase_by_id: Dictionary = {}
var _hover_tweens_by_button: Dictionary = {}
var _tree_layer: Control
var _tree_zoom: float = 0.86
var _tree_offset: Vector2 = Vector2(0.0, 34.0)
var _tooltip_panel: Panel
var _tooltip_label: Label
var _hovered_button: Button
var _hovered_node
var _is_drag_panning: bool = false
var _drag_pan_button: int = 0
var _keyboard_pan_armed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_process(true)
	set_process_input(true)
	_build_tree_layer()
	_build_buttons()
	_build_tooltip()
	refresh()


func _draw() -> void:
	for node in SkillTreeDB.get_all():
		var node_center: Vector2 = _tree_to_view(_node_center(node))
		for prereq_id: StringName in node.prerequisite_ids:
			var prereq = SkillTreeDB.get_by_id(prereq_id)
			if prereq == null:
				continue
			var color: Color = COLOR_LINE_LOCKED
			if GameState.has_skill_node(node.id):
				color = COLOR_LINE_OWNED
			elif GameState.can_unlock_skill_node(node.id):
				color = COLOR_LINE_AVAILABLE
			_draw_connection(_tree_to_view(_node_center(prereq)), node_center, color)


func _gui_input(event: InputEvent) -> void:
	_handle_zoom_input(event)
	_handle_left_drag_pan_input(event)


func _input(event: InputEvent) -> void:
	_handle_drag_pan_input(event)


func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)


func refresh() -> void:
	for node in SkillTreeDB.get_all():
		var button := _buttons_by_id.get(node.id, null) as Button
		if button == null:
			continue
		var owned: bool = GameState.has_skill_node(node.id)
		var available: bool = GameState.can_unlock_skill_node(node.id)
		var can_buy: bool = GameState.can_purchase_skill_node(node.id)
		_can_purchase_by_id[node.id] = can_buy
		button.text = _button_text(node)
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL if can_buy else Control.FOCUS_NONE
		button.tooltip_text = ""
		_apply_button_style(button, owned, available, can_buy)
	queue_redraw()


func _build_tree_layer() -> void:
	_tree_layer = Control.new()
	_tree_layer.name = "SkillTreeLayer"
	_tree_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_tree_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tree_layer)
	_apply_tree_transform()


func _build_tooltip() -> void:
	_tooltip_panel = Panel.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 100
	_tooltip_panel.custom_minimum_size = TOOLTIP_SIZE
	_tooltip_panel.size = TOOLTIP_SIZE
	_tooltip_panel.add_theme_stylebox_override("panel", _tooltip_style())
	_tooltip_label = Label.new()
	_tooltip_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tooltip_label.offset_left = 8.0
	_tooltip_label.offset_top = 6.0
	_tooltip_label.offset_right = -8.0
	_tooltip_label.offset_bottom = -6.0
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.add_theme_font_override("font", TOWN_UI_FONT)
	_tooltip_label.add_theme_font_size_override("font_size", 10)
	_tooltip_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
	_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_label.clip_text = true
	_tooltip_panel.add_child(_tooltip_label)
	add_child(_tooltip_panel)


func _build_buttons() -> void:
	for node in SkillTreeDB.get_all():
		var button := Button.new()
		button.custom_minimum_size = NODE_SIZE
		button.size = NODE_SIZE
		button.position = _node_center(node) - NODE_SIZE * 0.5
		button.pivot_offset = NODE_SIZE * 0.5
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.focus_mode = Control.FOCUS_ALL
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_font_override("font", TOWN_UI_FONT)
		button.add_theme_font_size_override("font_size", 10)
		button.gui_input.connect(_handle_zoom_input)
		button.mouse_entered.connect(_on_button_mouse_entered.bind(button, node))
		button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
		button.pressed.connect(_on_button_pressed.bind(node.id))
		_tree_layer.add_child(button)
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
	var border: Color = Color.WHITE
	var bg: Color = Color(0.12, 0.16, 0.17, 1.0)
	var hover_bg: Color = Color(0.2, 0.25, 0.26, 1.0)
	var pressed_bg: Color = Color(0.08, 0.11, 0.12, 1.0)
	var focus_bg: Color = Color(0.24, 0.3, 0.31, 1.0)
	var text: Color = Color(0.62, 0.66, 0.66, 1.0)
	if owned:
		bg = Color(0.95, 0.63, 0.18, 1.0)
		hover_bg = Color(1.0, 0.74, 0.28, 1.0)
		pressed_bg = Color(0.72, 0.43, 0.09, 1.0)
		focus_bg = Color(1.0, 0.78, 0.32, 1.0)
		text = Color(0.08, 0.05, 0.02, 1.0)
	elif can_buy:
		bg = Color(0.28, 0.68, 0.72, 1.0)
		hover_bg = Color(0.38, 0.82, 0.86, 1.0)
		pressed_bg = Color(0.17, 0.46, 0.5, 1.0)
		focus_bg = Color(0.44, 0.9, 0.94, 1.0)
		text = Color(0.02, 0.07, 0.08, 1.0)
	elif available:
		bg = Color(0.4, 0.45, 0.44, 1.0)
		hover_bg = Color(0.52, 0.58, 0.56, 1.0)
		pressed_bg = Color(0.28, 0.32, 0.31, 1.0)
		focus_bg = Color(0.58, 0.64, 0.62, 1.0)
		text = Color(1.0, 0.78, 0.22, 1.0)
	var normal := _style(bg, border, 2)
	var hover := _style(hover_bg, border, 2)
	var focus := _style(focus_bg, border, 3)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", _style(pressed_bg, border, 2))
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
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _draw_connection(from: Vector2, to: Vector2, color: Color) -> void:
	var shadow_width: float = maxf(2.0, 6.0 * _tree_zoom)
	var line_width: float = maxf(1.0, 3.0 * _tree_zoom)
	draw_line(from, to, Color(0.03, 0.08, 0.1, 0.78), shadow_width)
	draw_line(from, to, color, line_width)


func _tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.05, 1.0)
	style.border_color = Color(1.0, 0.82, 0.28, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	return style


func _on_button_mouse_entered(button: Button, node) -> void:
	_hovered_button = button
	_hovered_node = node
	_show_node_tooltip(button, node)
	_play_hover_pop(button)


func _on_button_mouse_exited(button: Button) -> void:
	if _hovered_button == button:
		_hovered_button = null
		_hovered_node = null
	_hide_node_tooltip()
	_stop_hover_pop(button)


func _show_node_tooltip(button: Button, node) -> void:
	_tooltip_label.text = _tooltip_text(node)
	_tooltip_panel.size = TOOLTIP_SIZE
	var button_top_left: Vector2 = _tree_to_view(button.position)
	var button_center: Vector2 = _tree_to_view(button.position + button.size * 0.5)
	var scaled_button_height: float = button.size.y * _tree_zoom
	var bounds: Vector2 = get_viewport_rect().size
	var prefer_below: bool = button_top_left.y - TOOLTIP_SIZE.y - TOOLTIP_GAP < 8.0
	var target := Vector2(
		button_center.x - TOOLTIP_SIZE.x * 0.5,
		button_top_left.y + scaled_button_height + TOOLTIP_GAP if prefer_below else button_top_left.y - TOOLTIP_SIZE.y - TOOLTIP_GAP
	)
	target.x = clampf(target.x, 8.0, maxf(8.0, bounds.x - TOOLTIP_SIZE.x - 8.0))
	target.y = clampf(target.y, 8.0, maxf(8.0, bounds.y - TOOLTIP_SIZE.y - 8.0))
	_tooltip_panel.position = target
	_tooltip_panel.visible = true
	_tooltip_panel.modulate = Color.WHITE


func _hide_node_tooltip() -> void:
	_tooltip_panel.visible = false


func _play_hover_pop(button: Button) -> void:
	_stop_hover_tween(button)
	button.z_index = 20
	button.scale = Vector2.ONE
	button.rotation = 0.0
	var tween := create_tween()
	_hover_tweens_by_button[button] = tween
	tween.tween_property(button, "scale", Vector2(1.20, 1.20), 0.07)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(button, "rotation", deg_to_rad(-7.0), 0.07)
	tween.tween_property(button, "rotation", deg_to_rad(4.0), 0.05)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(button, "scale", Vector2(1.12, 1.12), 0.05)
	tween.tween_property(button, "rotation", 0.0, 0.07)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(button, "scale", Vector2(1.10, 1.10), 0.07)


func _stop_hover_pop(button: Button) -> void:
	_stop_hover_tween(button)
	button.z_index = 0
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.09)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(button, "rotation", 0.0, 0.09)


func _stop_hover_tween(button: Button) -> void:
	var tween := _hover_tweens_by_button.get(button, null) as Tween
	if tween and tween.is_valid():
		tween.kill()
	_hover_tweens_by_button.erase(button)


func _handle_zoom_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	var pivot: Vector2 = get_local_mouse_position()
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_tree_at(ZOOM_STEP, pivot)
		accept_event()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_tree_at(1.0 / ZOOM_STEP, pivot)
		accept_event()


func _handle_drag_pan_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE or mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			if mouse_button.pressed:
				_is_drag_panning = true
				_drag_pan_button = mouse_button.button_index
			elif _is_drag_panning and mouse_button.button_index == _drag_pan_button:
				_is_drag_panning = false
				_drag_pan_button = 0
			accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _is_drag_panning:
		_pan_tree_by(motion.relative)
		accept_event()


func _handle_left_drag_pan_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if mouse_button.pressed:
			_is_drag_panning = true
			_drag_pan_button = MOUSE_BUTTON_LEFT
		elif _is_drag_panning and _drag_pan_button == MOUSE_BUTTON_LEFT:
			_is_drag_panning = false
			_drag_pan_button = 0
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _is_drag_panning and _drag_pan_button == MOUSE_BUTTON_LEFT:
		_pan_tree_by(motion.relative)
		accept_event()


func _handle_keyboard_pan(delta: float) -> void:
	if not _keyboard_pan_armed:
		if not _is_any_pan_action_pressed():
			_keyboard_pan_armed = true
		return
	var pan := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		pan.x += 1.0
	if Input.is_action_pressed("move_right"):
		pan.x -= 1.0
	if Input.is_action_pressed("move_up"):
		pan.y += 1.0
	if Input.is_action_pressed("move_down"):
		pan.y -= 1.0
	if pan == Vector2.ZERO:
		return
	_pan_tree_by(pan.normalized() * KEYBOARD_PAN_SPEED * delta)


func _is_any_pan_action_pressed() -> bool:
	return Input.is_action_pressed("move_left")\
		or Input.is_action_pressed("move_right")\
		or Input.is_action_pressed("move_up")\
		or Input.is_action_pressed("move_down")


func _zoom_tree_at(factor: float, pivot: Vector2) -> void:
	var old_zoom: float = _tree_zoom
	var next_zoom: float = clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old_zoom, next_zoom):
		return
	var tree_point_under_cursor: Vector2 = (pivot - _tree_offset) / old_zoom
	_tree_zoom = next_zoom
	_tree_offset = pivot - tree_point_under_cursor * next_zoom
	_apply_tree_transform()
	if _hovered_button != null and _hovered_node != null:
		_show_node_tooltip(_hovered_button, _hovered_node)


func _pan_tree_by(delta: Vector2) -> void:
	_tree_offset += delta
	_apply_tree_transform()
	if _hovered_button != null and _hovered_node != null:
		_show_node_tooltip(_hovered_button, _hovered_node)


func _apply_tree_transform() -> void:
	if _tree_layer == null:
		return
	_tree_layer.position = _tree_offset
	_tree_layer.scale = Vector2(_tree_zoom, _tree_zoom)
	queue_redraw()


func _tree_to_view(point: Vector2) -> Vector2:
	return _tree_offset + point * _tree_zoom


func _on_button_pressed(node_id: StringName) -> void:
	if not bool(_can_purchase_by_id.get(node_id, false)):
		return
	purchase_requested.emit(node_id)
