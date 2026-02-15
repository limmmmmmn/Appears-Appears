extends PanelContainer
class_name EventWindow

signal event_finished(result: Dictionary)
signal choice_selected(choice_id: String, line_index: int)

const DEFAULT_WINDOW_SIZE := Vector2(280, 190)
const DEFAULT_LINE_INTERVAL: float = 1.55

@onready var title_label: Label = %TitleLabel
@onready var left_face: TextureRect = %LeftFace
@onready var right_face: TextureRect = %RightFace
@onready var left_face_panel: PanelContainer = %LeftFacePanel
@onready var right_face_panel: PanelContainer = %RightFacePanel
@onready var speaker_label: Label = %SpeakerLabel
@onready var dialog_label: RichTextLabel = %DialogLabel
@onready var choice_panel: VBoxContainer = %ChoicePanel
@onready var close_button: Button = %CloseButton

var _lines: Array[Dictionary] = []
var _line_index: int = -1
var _line_timer: float = 0.0
var _line_interval: float = DEFAULT_LINE_INTERVAL
var _waiting_choice: bool = false
var _running: bool = false
var _last_choice_id: String = ""
var _context: Dictionary = {}

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS

	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	gui_input.connect(_on_gui_input)


func setup_dialog(
		window_title: String,
		left_hero_id: String,
		right_hero_id: String,
		lines: Array[Dictionary],
		context: Dictionary = {}
	) -> void:
	_context = context.duplicate(true)
	_lines = lines.duplicate(true)
	_line_index = -1
	_last_choice_id = ""
	_waiting_choice = false
	_running = true
	_line_interval = float(_context.get("line_interval", DEFAULT_LINE_INTERVAL))

	custom_minimum_size = DEFAULT_WINDOW_SIZE
	size = DEFAULT_WINDOW_SIZE
	_center_in_viewport()

	if title_label:
		title_label.text = window_title

	if SpriteManager:
		if left_face:
			left_face.texture = SpriteManager.get_hero_face_sprite(left_hero_id)
		if right_face:
			right_face.texture = SpriteManager.get_hero_face_sprite(right_hero_id)

	visible = true
	set_process(true)
	modulate.a = 0.0
	scale = Vector2(0.8, 0.8)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)
	tween.tween_property(self, "scale", Vector2.ONE, 0.25)

	_advance_line()


func _process(delta: float) -> void:
	if not _running or _waiting_choice:
		return
	_line_timer -= delta
	if _line_timer <= 0.0:
		_advance_line()


func _advance_line() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_finish_dialog({"choice_id": _last_choice_id})
		return

	var line: Dictionary = _lines[_line_index]
	var speaker: String = str(line.get("speaker", "left"))
	var speaker_name: String = str(line.get("name", ""))
	var text: String = str(line.get("text", ""))

	if speaker_label:
		speaker_label.text = speaker_name
	if dialog_label:
		dialog_label.text = text
	_set_speaker_highlight(speaker)

	var choices: Array = line.get("choices", []) as Array
	if not choices.is_empty():
		_show_choices(choices)
		_waiting_choice = true
		return

	_waiting_choice = false
	_hide_choices()
	_line_timer = float(line.get("duration", _line_interval))


func _show_choices(choices: Array) -> void:
	_hide_choices()
	if choice_panel == null:
		return

	choice_panel.visible = true
	for raw_choice in choices:
		var choice: Dictionary = raw_choice as Dictionary
		var button := Button.new()
		button.text = str(choice.get("text", "선택"))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_choice_pressed.bind(choice))
		choice_panel.add_child(button)


func _hide_choices() -> void:
	if choice_panel == null:
		return
	for child in choice_panel.get_children():
		child.queue_free()
	choice_panel.visible = false


func _on_choice_pressed(choice: Dictionary) -> void:
	var choice_id: String = str(choice.get("id", ""))
	_last_choice_id = choice_id
	choice_selected.emit(choice_id, _line_index)

	var line: Dictionary = {}
	if _line_index >= 0 and _line_index < _lines.size():
		line = _lines[_line_index]
	var branch_map: Dictionary = line.get("next_index_by_choice", {}) as Dictionary
	if not branch_map.is_empty() and branch_map.has(choice_id):
		_line_index = int(branch_map.get(choice_id, _line_index + 1)) - 1

	_waiting_choice = false
	_hide_choices()
	_line_timer = 0.05


func _set_speaker_highlight(speaker: String) -> void:
	var left_active: bool = speaker != "right"
	if left_face_panel:
		left_face_panel.modulate = Color(1, 1, 1, 1.0 if left_active else 0.45)
	if right_face_panel:
		right_face_panel.modulate = Color(1, 1, 1, 1.0 if not left_active else 0.45)


func _finish_dialog(result: Dictionary) -> void:
	if not _running:
		return
	_running = false
	set_process(false)
	event_finished.emit(result)
	_play_close_effect()


func _play_close_effect() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.12)
	tween.tween_property(self, "scale", Vector2(0.85, 0.85), 0.14)
	tween.finished.connect(queue_free)


func close_window_immediate() -> void:
	_running = false
	set_process(false)
	queue_free()


func _on_close_pressed() -> void:
	_finish_dialog({"choice_id": _last_choice_id, "closed": true})


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_drag_offset = mb.global_position - global_position
				move_to_front()
				accept_event()
			else:
				_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		global_position = mm.global_position - _drag_offset
		_clamp_to_viewport()
		accept_event()


func _center_in_viewport() -> void:
	var viewport_size: Vector2 = Vector2(960, 540)
	if get_tree():
		viewport_size = get_tree().root.get_visible_rect().size
	position = viewport_size * 0.5 - size * 0.5


func _clamp_to_viewport() -> void:
	if not get_tree():
		return
	var vp_size: Vector2 = get_tree().root.get_visible_rect().size
	global_position.x = clampf(global_position.x, -size.x + 40.0, vp_size.x - 40.0)
	global_position.y = clampf(global_position.y, 0.0, vp_size.y - 30.0)
