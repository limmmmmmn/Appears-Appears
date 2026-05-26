class_name StoryEventWindow
extends CanvasLayer

signal finished

const WINDOW_SIZE: Vector2 = Vector2(128.0, 96.0)
const FIELD_GREEN: Color = Color(0.3529412, 0.70980394, 0.32156864, 1.0)
const BONFIRE_TEXTURE: Texture2D = preload("res://assets/sprites/objects/bonfire.png")
const MAGE_DATA: CharacterData = preload("res://data/characters/mage.tres")
const FIELD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

var _window: Panel
var _mage_visual: CharacterVisual


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	layer = 16
	_build_window()
	await _play_mage_event()
	finished.emit()


func _build_window() -> void:
	_window = Panel.new()
	_window.name = "MageEventWindow"
	_window.size = WINDOW_SIZE
	_window.position = (get_viewport().get_visible_rect().size - WINDOW_SIZE) * 0.5
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_theme_stylebox_override("panel", _window_style())
	add_child(_window)

	var bonfire := Sprite2D.new()
	bonfire.name = "Bonfire"
	bonfire.texture = BONFIRE_TEXTURE
	bonfire.centered = true
	bonfire.position = Vector2(64.0, 58.0)
	bonfire.scale = Vector2(0.9, 0.9)
	bonfire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_window.add_child(bonfire)

	_add_party_visuals()
	_add_mage_visual()


func _add_party_visuals() -> void:
	var base_foot := Vector2(42.0, 60.0)
	var spacing := Vector2(-10.0, 6.0)
	for i in GameState.party_size():
		var member: CharacterData = GameState.party[i]
		if member == null or member.id == &"mage":
			continue
		var visual := CharacterVisual.new()
		visual.name = "%sEventVisual" % member.display_name
		visual.setup(member)
		visual.position = base_foot + spacing * float(i)
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.z_index = i
		_window.add_child(visual)
		visual.set_velocity(Vector2.RIGHT)


func _add_mage_visual() -> void:
	_mage_visual = CharacterVisual.new()
	_mage_visual.name = "MageEventVisual"
	_mage_visual.setup(MAGE_DATA)
	_mage_visual.position = Vector2(111.0, 60.0)
	_mage_visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mage_visual.z_index = 8
	_window.add_child(_mage_visual)
	_mage_visual.set_velocity(Vector2.LEFT)


func _play_mage_event() -> void:
	await get_tree().create_timer(0.12).timeout
	var tween := create_tween()
	tween.tween_property(_mage_visual, "position", Vector2(87.0, 60.0), 0.75)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)
	await tween.finished
	_mage_visual.set_velocity(Vector2.ZERO)

	await _show_speech(_mage_visual, "난 불이 좋아", Vector2(87.0, 34.0))
	await _show_speech(null, "더 태워볼래?", Vector2(35.0, 34.0))
	await _show_speech(_mage_visual, "좋아!", Vector2(87.0, 34.0))
	GameState.story_recruit_mage_companion()
	await get_tree().create_timer(0.25).timeout


func _show_speech(_speaker: Node, text: String, center: Vector2) -> void:
	var bubble := Panel.new()
	bubble.name = "EventSpeechBubble"
	bubble.size = _speech_size(text)
	bubble.position = center - bubble.size * 0.5
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 30
	bubble.add_theme_stylebox_override("panel", _speech_style())
	_window.add_child(bubble)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 5.0
	label.offset_right = -5.0
	label.add_theme_font_override("font", FIELD_FONT)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)

	await _pop_in(bubble)
	await _type_label(label, text)
	await get_tree().create_timer(0.5).timeout
	await _fade_out_and_free(bubble)


func _speech_size(text: String) -> Vector2:
	var width: float = maxf(46.0, FIELD_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 7).x + 14.0)
	return Vector2(minf(width, 82.0), 20.0)


func _type_label(label: Label, text: String) -> void:
	label.text = ""
	for i in text.length():
		label.text = text.substr(0, i + 1)
		await get_tree().create_timer(0.035).timeout


func _pop_in(control: Control) -> void:
	control.modulate.a = 0.0
	control.scale = Vector2(0.82, 0.82)
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	tween.tween_property(control, "modulate:a", 1.0, 0.06)
	tween.parallel().tween_property(control, "scale", Vector2.ONE, 0.1)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	await tween.finished


func _fade_out_and_free(control: Control) -> void:
	var tween := create_tween()
	tween.tween_property(control, "modulate:a", 0.0, 0.12)
	tween.tween_callback(Callable(control, "queue_free"))
	await tween.finished


func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FIELD_GREEN
	style.border_color = Color(0.08, 0.16, 0.07, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.anti_aliasing = false
	return style


func _speech_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.96, 0.82, 1.0)
	style.border_color = Color(0.12, 0.09, 0.05, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style
