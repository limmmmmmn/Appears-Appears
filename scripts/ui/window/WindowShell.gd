extends Control
class_name WindowShell

signal shell_opened
signal shell_closed(reason: String)

enum PausePolicy {
	NONE,
	TREE_PAUSE,
}

@export var title_text: String = "윈도우쉘"
@export var window_size: Vector2 = Vector2(280, 200)
@export var random_spawn: bool = true
@export var draggable: bool = true
@export var pause_policy: PausePolicy = PausePolicy.NONE
@export var window_margin: float = 20.0
@export var hud_top_height: float = 32.0
@export var hud_bottom_height: float = 60.0
@export var center_safe_size: float = 100.0

@onready var shell_panel: PanelContainer = get_node_or_null("%ShellPanel") as PanelContainer
@onready var title_label: Label = get_node_or_null("%TitleLabel") as Label
@onready var close_button: Button = get_node_or_null("%CloseButton") as Button
@onready var content_root: MarginContainer = get_node_or_null("%ContentRoot") as MarginContainer

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _opened_with_tree_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if shell_panel == null:
		push_warning("WindowShell: %ShellPanel 노드를 찾을 수 없습니다.")
		return
	if title_label:
		title_label.text = title_text
	if shell_panel:
		shell_panel.custom_minimum_size = window_size
		shell_panel.size = window_size
		if not shell_panel.gui_input.is_connected(_on_shell_gui_input):
			shell_panel.gui_input.connect(_on_shell_gui_input)
	if close_button and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)


func set_title(text: String) -> void:
	title_text = text
	if title_label:
		title_label.text = title_text


func set_window_size(size_value: Vector2) -> void:
	if size_value.x <= 0.0 or size_value.y <= 0.0:
		return
	window_size = size_value
	if shell_panel:
		shell_panel.custom_minimum_size = window_size
		shell_panel.size = window_size
		_clamp_to_viewport()


func set_content(control: Control) -> void:
	if content_root == null or control == null:
		return
	for child in content_root.get_children():
		child.queue_free()
	content_root.add_child(control)


func open_shell() -> void:
	if shell_panel:
		shell_panel.custom_minimum_size = window_size
		shell_panel.size = window_size
		set_title(title_text)
		if random_spawn:
			shell_panel.position = _calculate_spawn_position()
		else:
			_center_panel()
		_clamp_to_viewport()

	if pause_policy == PausePolicy.TREE_PAUSE:
		_opened_with_tree_paused = not get_tree().paused
		get_tree().paused = true
	else:
		_opened_with_tree_paused = false

	visible = true
	modulate.a = 0.0
	shell_panel.scale = Vector2(0.86, 0.86)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, 0.16)
	tween.tween_property(shell_panel, "scale", Vector2.ONE, 0.2)
	shell_opened.emit()


func close_shell(reason: String = "closed") -> void:
	if pause_policy == PausePolicy.TREE_PAUSE and _opened_with_tree_paused and get_tree().paused:
		get_tree().paused = false
	_opened_with_tree_paused = false
	shell_closed.emit(reason)
	if not visible:
		queue_free()
		return

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	if shell_panel:
		tween.tween_property(shell_panel, "scale", Vector2(0.9, 0.9), 0.14)
	tween.finished.connect(queue_free)


func close_shell_immediate(reason: String = "closed") -> void:
	if pause_policy == PausePolicy.TREE_PAUSE and _opened_with_tree_paused and get_tree().paused:
		get_tree().paused = false
	_opened_with_tree_paused = false
	shell_closed.emit(reason)
	queue_free()


func _on_close_pressed() -> void:
	close_shell("close_button")


func _on_shell_gui_input(event: InputEvent) -> void:
	if not draggable or shell_panel == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				begin_shell_drag(mb.global_position)
				shell_panel.accept_event()
			else:
				end_shell_drag()
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		drag_shell_to(mm.global_position)
		shell_panel.accept_event()


func begin_shell_drag(global_mouse_pos: Vector2) -> void:
	if not draggable or shell_panel == null:
		return
	_is_dragging = true
	_drag_offset = global_mouse_pos - shell_panel.global_position
	_bring_shell_to_front()


func drag_shell_to(global_mouse_pos: Vector2) -> void:
	if not draggable or shell_panel == null or not _is_dragging:
		return
	shell_panel.global_position = global_mouse_pos - _drag_offset
	_clamp_to_viewport()


func end_shell_drag() -> void:
	_is_dragging = false


func _bring_shell_to_front() -> void:
	var parent_node := get_parent()
	if parent_node:
		parent_node.move_child(self, parent_node.get_child_count() - 1)


func _center_panel() -> void:
	if shell_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	shell_panel.global_position = viewport_size * 0.5 - window_size * 0.5


func _clamp_to_viewport() -> void:
	if shell_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	shell_panel.global_position.x = clampf(shell_panel.global_position.x, -window_size.x + 40.0, vp.x - 40.0)
	shell_panel.global_position.y = clampf(shell_panel.global_position.y, 0.0, vp.y - 30.0)


func _calculate_spawn_position() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var existing_rects: Array[Rect2] = []
	var parent_node := get_parent()
	if parent_node:
		for child in parent_node.get_children():
			if child == self:
				continue
			if not (child is Control):
				continue
			var child_control: Control = child as Control
			if child_control == null or not child_control.visible:
				continue
			var child_shell_panel: Control = child_control.get_node_or_null("%ShellPanel") as Control
			if child_shell_panel:
				existing_rects.append(Rect2(child_shell_panel.global_position, child_shell_panel.size))
	return calculate_spawn_position(
		window_size,
		viewport_size,
		existing_rects,
		window_margin,
		hud_top_height,
		hud_bottom_height,
		center_safe_size
	)


static func calculate_spawn_position(
		window_size: Vector2,
		viewport_size: Vector2,
		existing_rects: Array = [],
		margin: float = 20.0,
		top_hud: float = 32.0,
		bottom_hud: float = 60.0,
		center_safe: float = 100.0
	) -> Vector2:
	var safe_left: float = maxf(0.0, margin)
	var safe_top: float = maxf(0.0, top_hud)
	var safe_right: float = maxf(safe_left, viewport_size.x - window_size.x - margin)
	var safe_bottom: float = maxf(safe_top, viewport_size.y - window_size.y - bottom_hud)

	var center := viewport_size * 0.5
	var center_avoid := Rect2(
		center.x - center_safe * 0.5,
		center.y - center_safe * 0.5,
		center_safe,
		center_safe
	)

	var best_pos := Vector2(randf_range(safe_left, safe_right), randf_range(safe_top, safe_bottom))
	var best_score: float = -1.0
	for _i in range(40):
		var x := randf_range(safe_left, safe_right)
		var y := randf_range(safe_top, safe_bottom)
		var candidate := Rect2(x, y, window_size.x, window_size.y)
		if candidate.intersects(center_avoid):
			continue

		var overlap_score: float = 0.0
		for existing_raw in existing_rects:
			if not (existing_raw is Rect2):
				continue
			var existing: Rect2 = existing_raw as Rect2
			overlap_score += candidate.intersection(existing).get_area()

		if best_score < 0.0 or overlap_score < best_score:
			best_score = overlap_score
			best_pos = Vector2(x, y)
			if overlap_score == 0.0:
				break

	return best_pos


static func clamp_to_viewport(pos: Vector2, window_size: Vector2, viewport_size: Vector2) -> Vector2:
	var out: Vector2 = pos
	out.x = clampf(out.x, -window_size.x + 40.0, viewport_size.x - 40.0)
	out.y = clampf(out.y, 0.0, viewport_size.y - 30.0)
	return out
