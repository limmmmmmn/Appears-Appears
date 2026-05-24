class_name FieldTownTile
extends Area2D

## Field tile that offers a return to the home base after it is revealed.

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _prompt_panel: Panel = $PromptPanel
@onready var _yes_button: Button = %YesButton
@onready var _no_button: Button = %NoButton

var _triggered: bool = false
var _revealed: bool = true
var _player_inside: bool = false
var _reveal_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_yes_button.pressed.connect(_enter_town)
	_no_button.pressed.connect(_hide_prompt)
	_hide_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _triggered or not _prompt_panel.visible:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_yes_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_no_button.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused == _no_button:
			_hide_prompt()
		else:
			_enter_town()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_hide_prompt()
		get_viewport().set_input_as_handled()


func reset() -> void:
	_triggered = false
	_player_inside = false
	hide_until_revealed()


func hide_until_revealed() -> void:
	_revealed = false
	visible = false
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	_hide_prompt()
	if _reveal_tween:
		_reveal_tween.kill()
	scale = Vector2.ONE
	modulate = Color.WHITE


func reveal_with_impact() -> void:
	if _revealed:
		return
	_revealed = true
	visible = true
	monitoring = false
	monitorable = false
	_collision_shape.disabled = true
	scale = Vector2(2.2, 0.35)
	modulate = Color(1.0, 0.92, 0.55, 0.0)
	if _reveal_tween:
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	_reveal_tween.parallel().tween_property(self, "scale", Vector2(0.86, 1.18), 0.18)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(self, "scale", Vector2(1.08, 0.94), 0.12)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN_OUT)
	_reveal_tween.tween_property(self, "scale", Vector2.ONE, 0.10)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_callback(_enable_entry)


func _enable_entry() -> void:
	monitoring = true
	monitorable = true
	_collision_shape.disabled = false


func _on_body_entered(body: Node) -> void:
	if _triggered or not _revealed or not body.is_in_group("player"):
		return
	_player_inside = true
	_show_prompt()


func _on_body_exited(body: Node) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_player_inside = false
	_hide_prompt()


func _show_prompt() -> void:
	_prompt_panel.visible = true
	_yes_button.call_deferred("grab_focus")


func _hide_prompt() -> void:
	if _prompt_panel:
		_prompt_panel.visible = false
	if _yes_button:
		_yes_button.release_focus()
	if _no_button:
		_no_button.release_focus()


func _enter_town() -> void:
	if _triggered:
		return
	_triggered = true
	_hide_prompt()
	EventBus.town_entered.emit(self)
