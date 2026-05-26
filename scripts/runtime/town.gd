class_name Town
extends CanvasLayer

## Home-base hub between field loops. The current screen is the incremental
## skill-tree screen plus a small persistent bottom bar.

signal closed(region_id: StringName)

const SKILL_TREE_VIEW_SCENE_SCRIPT: Script = preload("res://scripts/runtime/skill_tree_view.gd")
const BONFIRE_TEXTURE: Texture2D = preload("res://assets/sprites/objects/bonfire.png")
const CHARACTER_VISUAL_SCRIPT: Script = preload("res://scripts/runtime/character_visual.gd")
const STORY_HERO_POSITION: Vector2 = Vector2(320.0, 150.0)

@onready var _title_label: Label = %TitleLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _background: Panel = $Background
@onready var _horizon_strip: Panel = $HorizonStrip

var _title_override: String = ""
var _tree_view: Control
var _grass_button: Button
var _forest_button: Button
var _choosing_region: bool = false
var _story_skill_unlock_node
var _story_sequence_running: bool = false
var _story_skill_button: Button
var _story_skill_prompt_bubble: Control


func setup(title_override: String = "") -> void:
	_title_override = title_override


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_title_label.text = _title_override if not _title_override.is_empty() else GameState.field_region_summary()
	_heal_party_to_full()
	_refresh_gold_label()
	if GameState.STORY_MODE_ENABLED:
		_install_story_camp()
	else:
		_install_skill_tree()
		_install_region_buttons()
	_update_continue_button()
	_continue_button.pressed.connect(_on_continue_pressed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.skill_node_purchase_succeeded.connect(_on_skill_node_purchase_succeeded)
	EventBus.skill_node_purchase_failed.connect(_on_skill_node_purchase_failed)
	_continue_button.grab_focus()


func _install_story_camp() -> void:
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.015, 0.018, 0.02, 1.0)
	_background.add_theme_stylebox_override("panel", bg_style)
	_horizon_strip.hide()
	_title_label.text = "모닥불"

	var glow := ColorRect.new()
	glow.name = "Firelight"
	glow.size = Vector2(214.0, 112.0)
	glow.position = Vector2(213.0, 118.0)
	glow.color = Color(1.0, 0.58, 0.18, 0.12)
	add_child(glow)
	move_child(glow, 2)

	var camp := Node2D.new()
	camp.name = "StoryCamp"
	add_child(camp)
	move_child(camp, 3)

	var bonfire := Sprite2D.new()
	bonfire.texture = BONFIRE_TEXTURE
	bonfire.centered = true
	bonfire.position = Vector2(320.0, 178.0)
	bonfire.scale = Vector2(1.35, 1.35)
	bonfire.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	camp.add_child(bonfire)

	if GameState.party_size() > 0:
		_add_camp_member(camp, GameState.party[0], STORY_HERO_POSITION)
	if GameState.party_size() > 1:
		_add_camp_member(camp, GameState.party[1], Vector2(292.0, 184.0))
	if GameState.story_is_first_camp():
		_story_sequence_running = true
		_continue_button.disabled = true
		_play_first_camp_sequence()

	var line := Label.new()
	line.name = "CampLine"
	line.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	line.offset_left = 36.0
	line.offset_top = 246.0
	line.offset_right = -36.0
	line.offset_bottom = 284.0
	line.add_theme_font_override("font", load("res://assets/fonts/field_ui_font.tres"))
	line.add_theme_font_size_override("font_size", 10)
	line.add_theme_color_override("font_color", Color(0.92, 0.9, 0.78, 1.0))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.text = _story_camp_line()
	line.visible = not GameState.story_is_first_camp()
	add_child(line)


func _add_camp_member(root: Node2D, data: CharacterData, pos: Vector2) -> void:
	if data == null:
		return
	var visual := Sprite2D.new()
	visual.set_script(CHARACTER_VISUAL_SCRIPT)
	root.add_child(visual)
	visual.position = pos
	visual.scale = Vector2(1.35, 1.35)
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if visual.has_method("setup"):
		visual.setup(data)


func _story_camp_line() -> String:
	return GameState.story_camp_line()


func _play_first_camp_sequence() -> void:
	for speech_line in GameState.story_first_camp_hero_lines():
		await _show_typed_first_camp_hero_bubble(speech_line)
	_story_skill_unlock_node = GameState.story_first_camp_skill_node()
	if _story_skill_unlock_node != null:
		_story_skill_button = _add_story_skill_unlock_node(_story_skill_unlock_node)
		_story_skill_prompt_bubble = _add_click_skill_prompt_bubble()
		_pulse(_story_skill_button)
		return
	_finish_first_camp_sequence()


func _show_typed_first_camp_hero_bubble(text: String) -> void:
	var bubble := Panel.new()
	bubble.name = "HeroSpeechBubble"
	bubble.size = Vector2(246.0, 34.0)
	bubble.position = Vector2(STORY_HERO_POSITION.x - bubble.size.x * 0.5, STORY_HERO_POSITION.y - 66.0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 20
	bubble.add_theme_stylebox_override("panel", _speech_bubble_style())
	add_child(bubble)

	var tail := ColorRect.new()
	tail.name = "Tail"
	tail.size = Vector2(8.0, 8.0)
	tail.position = Vector2(bubble.size.x * 0.5 - 4.0, bubble.size.y - 3.0)
	tail.rotation = deg_to_rad(45.0)
	tail.color = Color(1.0, 0.96, 0.82, 1.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(tail)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 8.0
	label.offset_right = -8.0
	label.add_theme_font_override("font", load("res://assets/fonts/field_ui_font.tres"))
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)
	await _pop_in(bubble, 0.04)
	await _type_label(label, text, 0.035)
	await get_tree().create_timer(0.38).timeout
	await _fade_out_and_free(bubble, 0.12)


func _add_story_skill_unlock_node(node) -> Button:
	var button := Button.new()
	button.name = "StorySkillNode"
	button.size = Vector2(42.0, 36.0)
	button.position = Vector2(299.0, 206.0)
	button.z_index = 18
	button.text = str(node.short_label)
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.clip_text = true
	button.add_theme_font_override("font", load("res://assets/fonts/town_ui_font.tres"))
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_constant_override("h_separation", 0)
	_apply_story_skill_button_style(button, false)
	button.pressed.connect(_on_story_skill_node_pressed)
	add_child(button)
	_pop_in(button, 0.04)
	button.grab_focus()
	return button


func _add_click_skill_prompt_bubble() -> Control:
	var bubble := Panel.new()
	bubble.name = "SkillPromptBubble"
	bubble.size = Vector2(228.0, 34.0)
	bubble.position = Vector2(206.0, 160.0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 21
	bubble.add_theme_stylebox_override("panel", _speech_bubble_style())
	add_child(bubble)

	var tail := ColorRect.new()
	tail.name = "Tail"
	tail.size = Vector2(8.0, 8.0)
	tail.position = Vector2(bubble.size.x * 0.5 - 4.0, bubble.size.y - 3.0)
	tail.rotation = deg_to_rad(45.0)
	tail.color = Color(1.0, 0.96, 0.82, 1.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(tail)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 8.0
	label.offset_right = -8.0
	label.add_theme_font_override("font", load("res://assets/fonts/field_ui_font.tres"))
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	label.text = "네모난 노드를 클릭하여 스킬을 습득하자."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)
	_pop_in(bubble, 0.12)
	return bubble


func _on_story_skill_node_pressed() -> void:
	if _story_skill_button == null or not is_instance_valid(_story_skill_button):
		return
	_story_skill_button.disabled = true
	_apply_story_skill_button_style(_story_skill_button, true)
	_story_skill_unlock_node = GameState.story_claim_first_camp_skill_node()
	if _story_skill_prompt_bubble != null and is_instance_valid(_story_skill_prompt_bubble):
		_story_skill_prompt_bubble.queue_free()
	_story_skill_prompt_bubble = _add_story_skill_learned_bubble()
	_pulse(_story_skill_button)
	await get_tree().create_timer(0.75).timeout
	_finish_first_camp_sequence()


func _add_story_skill_learned_bubble() -> Control:
	var bubble := Panel.new()
	bubble.name = "SkillLearnedBubble"
	bubble.size = Vector2(238.0, 42.0)
	bubble.position = Vector2(201.0, 154.0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 21
	bubble.add_theme_stylebox_override("panel", _speech_bubble_style())
	add_child(bubble)

	var tail := ColorRect.new()
	tail.name = "Tail"
	tail.size = Vector2(8.0, 8.0)
	tail.position = Vector2(bubble.size.x * 0.5 - 4.0, bubble.size.y - 3.0)
	tail.rotation = deg_to_rad(45.0)
	tail.color = Color(1.0, 0.96, 0.82, 1.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(tail)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 8.0
	label.offset_right = -8.0
	label.add_theme_font_override("font", load("res://assets/fonts/field_ui_font.tres"))
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	label.text = "멀티 전투창 터득!\n전투창 중에도 움직일 수 있다."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)
	_pop_in(bubble, 0.02)
	return bubble


func _finish_first_camp_sequence() -> void:
	_story_sequence_running = false
	_continue_button.disabled = false
	_continue_button.grab_focus()


func _speech_bubble_style() -> StyleBoxFlat:
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


func _skill_unlock_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.042, 0.96)
	style.border_color = Color(1.0, 0.82, 0.28, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _skill_node_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.63, 0.18, 1.0)
	style.border_color = Color(1.0, 0.92, 0.62, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


func _apply_story_skill_button_style(button: Button, learned: bool) -> void:
	var bg: Color = Color(0.28, 0.68, 0.72, 1.0)
	var border: Color = Color(0.72, 0.96, 1.0, 1.0)
	var hover_bg: Color = Color(0.38, 0.82, 0.86, 1.0)
	var pressed_bg: Color = Color(0.17, 0.46, 0.5, 1.0)
	if learned:
		bg = Color(0.95, 0.63, 0.18, 1.0)
		border = Color(1.0, 0.92, 0.62, 1.0)
		hover_bg = Color(1.0, 0.74, 0.28, 1.0)
		pressed_bg = Color(0.72, 0.43, 0.09, 1.0)
	button.add_theme_stylebox_override("normal", _button_box(bg, border))
	button.add_theme_stylebox_override("hover", _button_box(hover_bg, border))
	button.add_theme_stylebox_override("pressed", _button_box(pressed_bg, border))
	button.add_theme_stylebox_override("focus", _button_box(hover_bg, border, 3))
	button.add_theme_stylebox_override("disabled", _button_box(bg, border))
	button.add_theme_color_override("font_color", Color(0.08, 0.05, 0.02, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.02, 1.0))
	button.add_theme_color_override("font_focus_color", Color(0.08, 0.05, 0.02, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.08, 0.05, 0.02, 1.0))


func _button_box(bg: Color, border: Color, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


func _pop_in(control: Control, delay: float = 0.0) -> void:
	control.modulate.a = 0.0
	control.scale = Vector2(0.78, 0.78)
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(control, "modulate:a", 1.0, 0.06)
	tween.parallel().tween_property(control, "scale", Vector2(1.08, 1.08), 0.1)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.06)
	await tween.finished


func _fade_out_and_free(control: Control, duration: float) -> void:
	if control == null or not is_instance_valid(control):
		return
	var tween := create_tween()
	tween.tween_property(control, "modulate:a", 0.0, duration)
	tween.parallel().tween_property(control, "scale", Vector2(0.86, 0.86), duration)
	tween.tween_callback(Callable(control, "queue_free"))
	await tween.finished


func _type_label(label: Label, text: String, seconds_per_character: float) -> void:
	label.text = ""
	for i in text.length():
		label.text = text.substr(0, i + 1)
		await get_tree().create_timer(seconds_per_character).timeout


func _pulse(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2(1.06, 1.06), 0.08)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, 0.08)


func _install_skill_tree() -> void:
	_tree_view = SKILL_TREE_VIEW_SCENE_SCRIPT.new() as Control
	_tree_view.name = "SkillTreeView"
	_tree_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_tree_view)
	move_child(_tree_view, 2)
	_tree_view.purchase_requested.connect(_on_skill_node_purchase_requested)


func _install_region_buttons() -> void:
	var bottom_bar := _continue_button.get_parent()
	_grass_button = _make_region_button("초원")
	_forest_button = _make_region_button("숲")
	bottom_bar.add_child(_grass_button)
	bottom_bar.add_child(_forest_button)
	_grass_button.hide()
	_forest_button.hide()
	_grass_button.pressed.connect(_close_with_region.bind(GameState.FIELD_REGION_GRASS))
	_forest_button.pressed.connect(_close_with_region.bind(GameState.FIELD_REGION_FOREST))


func _make_region_button(label: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(70.0, 22.0)
	button.focus_mode = Control.FOCUS_ALL
	button.text = label
	button.add_theme_stylebox_override("normal", _continue_button.get_theme_stylebox("normal"))
	button.add_theme_stylebox_override("hover", _continue_button.get_theme_stylebox("hover"))
	button.add_theme_stylebox_override("pressed", _continue_button.get_theme_stylebox("pressed"))
	button.add_theme_stylebox_override("focus", _continue_button.get_theme_stylebox("focus"))
	button.add_theme_color_override("font_color", Color(0.1, 0.07, 0.03, 1))
	button.add_theme_color_override("font_hover_color", Color(0.1, 0.07, 0.03, 1))
	button.add_theme_color_override("font_focus_color", Color(0.1, 0.07, 0.03, 1))
	button.add_theme_font_override("font", _continue_button.get_theme_font("font"))
	button.add_theme_font_size_override("font_size", 11)
	return button


func _heal_party_to_full() -> void:
	for i in GameState.party_size():
		var max_hp: int = GameState.effective_max_hp(i)
		if GameState.party_hp[i] < max_hp:
			GameState.heal_party_member(i, max_hp - GameState.party_hp[i])


func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold_label()
	if _tree_view:
		_tree_view.refresh()


func _refresh_gold_label() -> void:
	_gold_label.text = "%d G" % GameState.gold


func _on_skill_node_purchase_requested(node_id: StringName) -> void:
	GameState.purchase_skill_node(node_id)
	if _tree_view:
		_tree_view.refresh()


func _on_skill_node_purchase_succeeded(_node) -> void:
	_refresh_gold_label()
	_update_continue_button()
	if _tree_view:
		_tree_view.refresh()


func _on_skill_node_purchase_failed(_node) -> void:
	if _tree_view:
		_tree_view.refresh()


func _on_continue_pressed() -> void:
	if _story_sequence_running:
		return
	if GameState.STORY_MODE_ENABLED:
		_close_with_region(GameState.FIELD_REGION_GRASS)
		return
	if GameState.forest_region_unlocked():
		_show_region_choices()
		return
	_close_with_region(GameState.FIELD_REGION_GRASS)


func _show_region_choices() -> void:
	if _choosing_region:
		return
	_choosing_region = true
	_continue_button.hide()
	_grass_button.show()
	_forest_button.show()
	_grass_button.grab_focus()


func _update_continue_button() -> void:
	if GameState.STORY_MODE_ENABLED:
		_continue_button.text = "다음 필드로"
		return
	_continue_button.text = "필드로 나가기" if GameState.forest_region_unlocked() else "초원으로 나가기"


func _close_with_region(region_id: StringName) -> void:
	closed.emit(region_id)
	queue_free()
