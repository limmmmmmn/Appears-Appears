extends Control

signal purchase_requested(node_id: StringName)

const GRID_STEP: Vector2 = Vector2(54, 40)
const ROOT_NODE_SIZE: Vector2 = Vector2(36, 36)
## Per-tier node face metrics. 0 = minor pip, 1 = normal, 2 = major feature.
const NODE_SIZE_BY_TIER: Dictionary = {
	0: Vector2(26, 20),
	1: Vector2(32, 27),
	2: Vector2(38, 31),
}
const NODE_FONT_BY_TIER: Dictionary = {0: 8, 1: 9, 2: 9}
const NODE_BORDER_BY_TIER: Dictionary = {0: 1, 1: 2, 2: 2}
const NODE_CORNER_BY_TIER: Dictionary = {0: 1, 1: 2, 2: 3}
const TREE_CENTER: Vector2 = Vector2(330, 220)
const TOOLTIP_WIDTH: float = 168.0
const TOOLTIP_PAD: Vector2 = Vector2(9.0, 7.0)
const TOOLTIP_GAP: float = 7.0
const ZOOM_MIN: float = 0.5
const ZOOM_MAX: float = 1.75
const ZOOM_STEP: float = 1.12
const KEYBOARD_PAN_SPEED: float = 280.0
const CAMP_ACTOR_WANDER_RADIUS: Vector2 = Vector2(13.0, 7.0)
const CAMP_ACTOR_WANDER_SPEED: float = 13.0
const CAMP_SPEECH_MIN_WAIT: float = 3.8
const CAMP_SPEECH_MAX_WAIT: float = 7.2
const CAMP_SPEECH_DURATION: float = 2.1
const CAMP_SPEECH_FONT_SIZE: int = 9
const CAMP_SPEECH_PADDING: Vector2 = Vector2(8.0, 5.0)
const CAMP_SPEECH_MIN_SIZE: Vector2 = Vector2(64.0, 22.0)
const COLOR_LINE_OWNED: Color = Color(0.95, 0.62, 0.16, 1.0)
const COLOR_LINE_AVAILABLE: Color = Color(0.26, 0.55, 0.7, 1.0)
const COLOR_LINE_LOCKED: Color = Color(0.22, 0.28, 0.32, 0.45)
const TOWN_UI_FONT: Font = preload("res://assets/fonts/town_ui_font.tres")
const BONFIRE_ICON: Texture2D = preload("res://assets/sprites/objects/bonfire.png")
const FOREST_ICON: Texture2D = preload("res://assets/sprites/objects/forest 2.png")
const ROOT_NODE_ID: StringName = &"root"
const FOREST_NODE_ID: StringName = &"forest_region"
const BONFIRE_COMPANION_OFFSET: Dictionary = {
	&"elf": Vector2(24.0, 18.0),
	&"mage": Vector2(-24.0, 18.0),
	&"knight": Vector2(0.0, 34.0),
}
const BONFIRE_COMPANION_REQUIRED_NODE: Dictionary = {
	&"elf": &"companion",
	&"mage": &"companion_2",
	&"knight": &"companion_3",
}
const BONFIRE_COMPANION_LINES: Dictionary = {
	&"elf": [
		"길은 내가 볼게.",
		"숲 냄새가 나.",
		"조용히 가자.",
	],
	&"mage": [
		"불씨는 준비됐어.",
		"창 안쪽까지 태워볼까?",
		"마력이 잘 돌아.",
	],
	&"knight": [
		"내가 앞을 맡지.",
		"대열을 지키겠다.",
		"방패를 올려.",
	],
}

var _buttons_by_id: Dictionary = {}
var _can_purchase_by_id: Dictionary = {}
var _hover_tweens_by_button: Dictionary = {}
var _tree_layer: Control
var _tree_zoom: float = 0.86
var _tree_offset: Vector2 = Vector2(0.0, 34.0)
var _tooltip_panel: Panel
var _tooltip_title: Label
var _tooltip_rule: ColorRect
var _tooltip_status: Label
var _tooltip_desc: Label
var _hovered_button: Button
var _hovered_node
var _is_drag_panning: bool = false
var _drag_pan_button: int = 0
var _keyboard_pan_armed: bool = false
var _camp_actors_by_id: Dictionary = {}


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
	_update_camp_actors(delta)


func refresh() -> void:
	for node in SkillTreeDB.get_all():
		var button := _buttons_by_id.get(node.id, null) as Button
		if button == null:
			continue
		var owned: bool = GameState.has_skill_node(node.id)
		var available: bool = GameState.can_unlock_skill_node(node.id)
		var can_buy: bool = GameState.can_purchase_skill_node(node.id)
		_can_purchase_by_id[node.id] = can_buy
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL if can_buy else Control.FOCUS_NONE
		button.tooltip_text = ""
		if node.id == ROOT_NODE_ID:
			_apply_icon_node(button)
		elif node.id == FOREST_NODE_ID:
			_apply_forest_node(button, node, owned, available, can_buy)
		else:
			button.icon = null
			button.text = _button_text(node)
			_apply_button_style(button, node, owned, available, can_buy)
		_apply_button_visibility(button, node)
	_refresh_camp_actors()
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
	_tooltip_panel.add_theme_stylebox_override("panel", _tooltip_style())

	_tooltip_title = Label.new()
	_tooltip_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_title.add_theme_font_override("font", TOWN_UI_FONT)
	_tooltip_title.add_theme_font_size_override("font_size", 11)
	_tooltip_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4, 1.0))
	_tooltip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_tooltip_panel.add_child(_tooltip_title)

	_tooltip_status = Label.new()
	_tooltip_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_status.add_theme_font_override("font", TOWN_UI_FONT)
	_tooltip_status.add_theme_font_size_override("font_size", 8)
	_tooltip_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_status.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_tooltip_panel.add_child(_tooltip_status)

	_tooltip_rule = ColorRect.new()
	_tooltip_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_rule.color = Color(1.0, 0.82, 0.28, 0.45)
	_tooltip_panel.add_child(_tooltip_rule)

	_tooltip_desc = Label.new()
	_tooltip_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_desc.add_theme_font_override("font", TOWN_UI_FONT)
	_tooltip_desc.add_theme_font_size_override("font_size", 9)
	_tooltip_desc.add_theme_color_override("font_color", Color(0.86, 0.89, 0.82, 1.0))
	_tooltip_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tooltip_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_panel.add_child(_tooltip_desc)

	add_child(_tooltip_panel)


func _build_buttons() -> void:
	for node in SkillTreeDB.get_all():
		var button := Button.new()
		var node_size: Vector2 = _node_size(node)
		button.custom_minimum_size = node_size
		button.size = node_size
		button.position = _node_center(node) - node_size * 0.5
		button.pivot_offset = node_size * 0.5
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.focus_mode = Control.FOCUS_ALL
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.expand_icon = false
		button.clip_text = true
		button.add_theme_font_override("font", TOWN_UI_FONT)
		button.add_theme_font_size_override("font_size", _node_font_size(node))
		button.add_theme_constant_override("h_separation", 0)
		button.gui_input.connect(_handle_zoom_input)
		button.mouse_entered.connect(_on_button_mouse_entered.bind(button, node))
		button.mouse_exited.connect(_on_button_mouse_exited.bind(button))
		button.pressed.connect(_on_button_pressed.bind(node.id))
		_tree_layer.add_child(button)
		_buttons_by_id[node.id] = button


func _node_center(node) -> Vector2:
	return TREE_CENTER + Vector2(node.grid_position) * GRID_STEP


func _node_size(node) -> Vector2:
	if node.id == ROOT_NODE_ID:
		return ROOT_NODE_SIZE
	return NODE_SIZE_BY_TIER.get(node.tier, NODE_SIZE_BY_TIER[1])


func _node_font_size(node) -> int:
	return int(NODE_FONT_BY_TIER.get(node.tier, 9))


func _button_text(node) -> String:
	var level: int = GameState.skill_node_level(node.id)
	var max_level: int = int(node.max_level)
	if max_level > 1 and level > 0:
		return "%s\n%d/%d" % [node.short_label, level, max_level]
	# Minor pips show only their name; bigger nodes carry the price tag too.
	if node.tier <= 0:
		return node.short_label
	if level > 0:
		return "%s\nON" % node.short_label
	if node.cost <= 0:
		return "%s\n무료" % node.short_label
	return "%s\n%dG" % [node.short_label, GameState.skill_node_purchase_cost(node.id)]


func _tooltip_status_parts(node) -> Array:
	var level: int = GameState.skill_node_level(node.id)
	var max_level: int = int(node.max_level)
	if level >= max_level:
		if max_level > 1:
			return ["최대 레벨 · Lv %d/%d" % [level, max_level], Color(1.0, 0.84, 0.4, 1.0)]
		return ["습득 완료", Color(1.0, 0.84, 0.4, 1.0)]
	var cost: int = GameState.skill_node_purchase_cost(node.id)
	var cost_text: String = "무료" if cost <= 0 else "%dG" % cost
	if GameState.can_purchase_skill_node(node.id):
		if level > 0 and max_level > 1:
			return ["강화 가능 · Lv %d/%d · %s" % [level + 1, max_level, cost_text], Color(0.5, 0.9, 0.95, 1.0)]
		return ["구매 가능 · %s" % cost_text, Color(0.5, 0.9, 0.95, 1.0)]
	if GameState.can_unlock_skill_node(node.id):
		if level > 0 and max_level > 1:
			return ["골드 부족 · Lv %d/%d · %s" % [level + 1, max_level, cost_text], Color(0.93, 0.56, 0.42, 1.0)]
		return ["골드 부족 · %s" % cost_text, Color(0.93, 0.56, 0.42, 1.0)]
	return ["잠김 · %s" % cost_text, Color(0.62, 0.65, 0.65, 1.0)]


## Fills the tooltip window for a node and sizes it to its content. Returns the
## final panel size so callers can place it without clipping the viewport.
func _layout_tooltip(node) -> Vector2:
	var inner_w: float = TOOLTIP_WIDTH - TOOLTIP_PAD.x * 2.0
	var status_parts: Array = _tooltip_status_parts(node)
	_tooltip_title.text = node.display_name
	_tooltip_status.text = str(status_parts[0])
	_tooltip_status.add_theme_color_override("font_color", status_parts[1])
	_tooltip_desc.text = node.description

	var title_h: float = ceilf(TOWN_UI_FONT.get_multiline_string_size(
		_tooltip_title.text, HORIZONTAL_ALIGNMENT_CENTER, inner_w, 11).y)
	var status_h: float = ceilf(TOWN_UI_FONT.get_multiline_string_size(
		_tooltip_status.text, HORIZONTAL_ALIGNMENT_CENTER, inner_w, 8).y)
	var desc_h: float = ceilf(TOWN_UI_FONT.get_multiline_string_size(
		_tooltip_desc.text, HORIZONTAL_ALIGNMENT_LEFT, inner_w, 9).y)

	var y: float = TOOLTIP_PAD.y
	_tooltip_title.position = Vector2(TOOLTIP_PAD.x, y)
	_tooltip_title.size = Vector2(inner_w, title_h)
	y += title_h + 3.0
	_tooltip_status.position = Vector2(TOOLTIP_PAD.x, y)
	_tooltip_status.size = Vector2(inner_w, status_h)
	y += status_h + 4.0
	_tooltip_rule.position = Vector2(TOOLTIP_PAD.x, y)
	_tooltip_rule.size = Vector2(inner_w, 1.0)
	y += 1.0 + 5.0
	_tooltip_desc.position = Vector2(TOOLTIP_PAD.x, y)
	_tooltip_desc.size = Vector2(inner_w, desc_h)
	y += desc_h + TOOLTIP_PAD.y

	var panel_size := Vector2(TOOLTIP_WIDTH, y)
	_tooltip_panel.size = panel_size
	return panel_size


func _apply_button_style(button: Button, node, owned: bool, available: bool, can_buy: bool) -> void:
	var bw: int = int(NODE_BORDER_BY_TIER.get(node.tier, 2))
	var corner: int = int(NODE_CORNER_BY_TIER.get(node.tier, 2))
	var is_major: bool = node.tier >= 2
	var border: Color = Color(0.32, 0.38, 0.4, 1.0)
	var bg: Color = Color(0.12, 0.16, 0.17, 1.0)
	var hover_bg: Color = Color(0.2, 0.25, 0.26, 1.0)
	var pressed_bg: Color = Color(0.08, 0.11, 0.12, 1.0)
	var focus_bg: Color = Color(0.24, 0.3, 0.31, 1.0)
	var text: Color = Color(0.62, 0.66, 0.66, 1.0)
	if owned:
		border = Color(1.0, 0.92, 0.62, 1.0)
		bg = Color(0.95, 0.63, 0.18, 1.0)
		hover_bg = Color(1.0, 0.74, 0.28, 1.0)
		pressed_bg = Color(0.72, 0.43, 0.09, 1.0)
		focus_bg = Color(1.0, 0.78, 0.32, 1.0)
		text = Color(0.08, 0.05, 0.02, 1.0)
	elif can_buy:
		border = Color(0.72, 0.96, 1.0, 1.0)
		bg = Color(0.28, 0.68, 0.72, 1.0)
		hover_bg = Color(0.38, 0.82, 0.86, 1.0)
		pressed_bg = Color(0.17, 0.46, 0.5, 1.0)
		focus_bg = Color(0.44, 0.9, 0.94, 1.0)
		text = Color(0.02, 0.07, 0.08, 1.0)
	elif available:
		border = Color(0.82, 0.86, 0.84, 1.0)
		bg = Color(0.4, 0.45, 0.44, 1.0)
		hover_bg = Color(0.52, 0.58, 0.56, 1.0)
		pressed_bg = Color(0.28, 0.32, 0.31, 1.0)
		focus_bg = Color(0.58, 0.64, 0.62, 1.0)
		text = Color(1.0, 0.78, 0.22, 1.0)
	elif is_major:
		# Locked major nodes still glint gold so milestones read as important.
		border = Color(0.55, 0.45, 0.24, 1.0)
	var normal := _style(bg, border, bw, corner)
	var hover := _style(hover_bg, border, bw, corner)
	var focus := _style(focus_bg, border, bw + 1, corner)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", _style(pressed_bg, border, bw, corner))
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_color_override("font_color", text)
	button.add_theme_color_override("font_hover_color", text)
	button.add_theme_color_override("font_focus_color", text)
	button.add_theme_color_override("font_disabled_color", text.darkened(0.2) if not owned else text)


func _apply_button_visibility(button: Button, node) -> void:
	button.modulate.a = 1.0
	button.mouse_filter = Control.MOUSE_FILTER_PASS


func _apply_icon_node(button: Button) -> void:
	button.text = ""
	button.icon = BONFIRE_ICON
	button.add_theme_stylebox_override("normal", _icon_style())
	button.add_theme_stylebox_override("hover", _icon_style())
	button.add_theme_stylebox_override("pressed", _icon_style())
	button.add_theme_stylebox_override("focus", _icon_focus_style())
	button.add_theme_stylebox_override("disabled", _icon_style())
	button.add_theme_color_override("icon_normal_color", Color.WHITE)
	button.add_theme_color_override("icon_hover_color", Color.WHITE)
	button.add_theme_color_override("icon_pressed_color", Color.WHITE)
	button.add_theme_color_override("icon_focus_color", Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color.WHITE)


func _apply_forest_node(button: Button, node, owned: bool, available: bool, can_buy: bool) -> void:
	button.text = ""
	button.icon = FOREST_ICON
	button.expand_icon = false
	_apply_button_style(button, node, owned, available, can_buy)
	button.add_theme_color_override("icon_normal_color", Color.WHITE)
	button.add_theme_color_override("icon_hover_color", Color.WHITE)
	button.add_theme_color_override("icon_pressed_color", Color.WHITE)
	button.add_theme_color_override("icon_focus_color", Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color.WHITE)


func _refresh_camp_actors() -> void:
	var wanted: Dictionary = {}
	for i in range(1, GameState.party_size()):
		var member: CharacterData = GameState.party[i]
		if member == null:
			continue
		var required_node: StringName = BONFIRE_COMPANION_REQUIRED_NODE.get(member.id, &"")
		if BONFIRE_COMPANION_OFFSET.has(member.id) and (required_node == &"" or GameState.has_skill_node(required_node)):
			wanted[member.id] = member
			if not _camp_actors_by_id.has(member.id):
				_create_camp_actor(member)
	for id in _camp_actors_by_id.keys():
		if wanted.has(id):
			continue
		var actor_data: Dictionary = _camp_actors_by_id[id]
		var actor := actor_data.get("root", null) as Control
		if actor:
			actor.queue_free()
		_camp_actors_by_id.erase(id)


func _create_camp_actor(member: CharacterData) -> void:
	var root := Control.new()
	root.name = "%sCampActor" % member.display_name
	var actor_size := Vector2(
		maxf(24.0, member.frame_size.x + 8.0),
		maxf(34.0, member.frame_size.y + 10.0)
	)
	var foot_position := Vector2(actor_size.x * 0.5, actor_size.y - 4.0)
	var speech_anchor := foot_position + member.speech_anchor_local()
	root.custom_minimum_size = actor_size
	root.size = actor_size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.z_index = 18
	var sprite := CharacterVisual.new()
	sprite.name = "Sprite"
	sprite.setup(member)
	sprite.position = foot_position
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(sprite)
	var bubble := Panel.new()
	bubble.name = "SpeechBubble"
	bubble.visible = false
	bubble.size = Vector2(112.0, 22.0)
	bubble.position = Vector2(-44.0, -15.0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 20
	bubble.add_theme_stylebox_override("panel", _speech_bubble_style())
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 6.0
	label.offset_top = 2.0
	label.offset_right = -6.0
	label.offset_bottom = -2.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", TOWN_UI_FONT)
	label.add_theme_font_size_override("font_size", CAMP_SPEECH_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = false
	bubble.add_child(label)
	root.add_child(bubble)
	_tree_layer.add_child(root)
	var lines: Array = BONFIRE_COMPANION_LINES.get(member.id, ["..."])
	var root_node = SkillTreeDB.get_by_id(ROOT_NODE_ID)
	var base_position := TREE_CENTER
	if root_node != null:
		base_position = _node_center(root_node)
	_camp_actors_by_id[member.id] = {
		"root": root,
		"sprite": sprite,
		"bubble": bubble,
		"label": label,
		"foot_position": foot_position,
		"speech_anchor": speech_anchor,
		"base": base_position + BONFIRE_COMPANION_OFFSET.get(member.id, Vector2.ZERO),
		"offset": Vector2.ZERO,
		"target_offset": _random_camp_actor_offset(),
		"wait_timer": randf_range(0.2, 1.1),
		"line_index": 0,
		"speech_wait_timer": randf_range(0.8, 2.4),
		"speech_visible_timer": 0.0,
		"lines": lines,
	}


func _update_camp_actors(delta: float) -> void:
	for id in _camp_actors_by_id.keys():
		var actor_data: Dictionary = _camp_actors_by_id[id]
		var root := actor_data.get("root", null) as Control
		var sprite := actor_data.get("sprite", null) as CharacterVisual
		var bubble := actor_data.get("bubble", null) as Panel
		var label := actor_data.get("label", null) as Label
		if root == null or sprite == null or bubble == null or label == null:
			continue
		var base: Vector2 = actor_data.get("base", Vector2.ZERO)
		var foot_position: Vector2 = actor_data.get("foot_position", root.size * 0.5)
		var offset: Vector2 = actor_data.get("offset", Vector2.ZERO)
		var target_offset: Vector2 = actor_data.get("target_offset", Vector2.ZERO)
		var wait_timer: float = float(actor_data.get("wait_timer", 0.0)) - delta
		var velocity := Vector2.ZERO
		if wait_timer <= 0.0:
			var to_target: Vector2 = target_offset - offset
			if to_target.length() <= 0.45:
				offset = target_offset
				target_offset = _random_camp_actor_offset()
				wait_timer = randf_range(0.45, 1.25)
			else:
				velocity = to_target.normalized() * CAMP_ACTOR_WANDER_SPEED
				offset += velocity * delta
		sprite.set_velocity(velocity)
		actor_data["offset"] = offset
		actor_data["target_offset"] = target_offset
		actor_data["wait_timer"] = wait_timer
		root.position = base + offset - foot_position
		var speech_visible_timer: float = float(actor_data.get("speech_visible_timer", 0.0)) - delta
		if speech_visible_timer > 0.0:
			bubble.visible = true
			actor_data["speech_visible_timer"] = speech_visible_timer
			continue
		bubble.visible = false
		var speech_wait_timer: float = float(actor_data.get("speech_wait_timer", 0.0)) - delta
		if speech_wait_timer <= 0.0:
			var lines: Array = actor_data.get("lines", [])
			var line_index: int = int(actor_data.get("line_index", 0))
			if not lines.is_empty():
				var speech_anchor: Vector2 = actor_data.get("speech_anchor", Vector2.ZERO)
				_apply_speech_text(bubble, label, str(lines[line_index % lines.size()]), speech_anchor)
				actor_data["line_index"] = line_index + 1
				bubble.visible = true
				actor_data["speech_visible_timer"] = CAMP_SPEECH_DURATION
			speech_wait_timer = randf_range(CAMP_SPEECH_MIN_WAIT, CAMP_SPEECH_MAX_WAIT)
		actor_data["speech_wait_timer"] = speech_wait_timer


func _random_camp_actor_offset() -> Vector2:
	return Vector2(
		randf_range(-CAMP_ACTOR_WANDER_RADIUS.x, CAMP_ACTOR_WANDER_RADIUS.x),
		randf_range(-CAMP_ACTOR_WANDER_RADIUS.y, CAMP_ACTOR_WANDER_RADIUS.y)
	)


func _apply_speech_text(bubble: Panel, label: Label, raw_text: String, anchor: Vector2) -> void:
	var text: String = _single_speech_sentence(raw_text)
	label.text = text
	var text_size: Vector2 = TOWN_UI_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, CAMP_SPEECH_FONT_SIZE)
	var bubble_size := Vector2(
		maxf(CAMP_SPEECH_MIN_SIZE.x, ceilf(text_size.x + CAMP_SPEECH_PADDING.x * 2.0)),
		maxf(CAMP_SPEECH_MIN_SIZE.y, ceilf(text_size.y + CAMP_SPEECH_PADDING.y * 2.0))
	)
	bubble.size = bubble_size
	bubble.position = anchor + Vector2(-bubble_size.x * 0.5, -bubble_size.y - 4.0)


func _single_speech_sentence(raw_text: String) -> String:
	var text: String = raw_text.replace("\n", " ").strip_edges()
	for i in range(text.length()):
		var ch: String = text.substr(i, 1)
		if ch == "." or ch == "!" or ch == "?" or ch == "。" or ch == "！" or ch == "？":
			return text.substr(0, i + 1).strip_edges()
	return text


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


func _style(bg: Color, border: Color, border_width: int, corner: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	return style


func _icon_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0, 0, 0, 0)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style


func _icon_focus_style() -> StyleBoxFlat:
	var style := _icon_style()
	style.border_color = Color(1.0, 0.78, 0.22, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	return style


func _draw_connection(from: Vector2, to: Vector2, color: Color) -> void:
	var line_width: float = maxf(1.0, 3.0 * _tree_zoom)
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
	var tip_size: Vector2 = _layout_tooltip(node)
	var button_top_left: Vector2 = _tree_to_view(button.position)
	var button_center: Vector2 = _tree_to_view(button.position + button.size * 0.5)
	var scaled_button_height: float = button.size.y * _tree_zoom
	var bounds: Vector2 = get_viewport_rect().size
	var prefer_below: bool = button_top_left.y - tip_size.y - TOOLTIP_GAP < 8.0
	var target := Vector2(
		button_center.x - tip_size.x * 0.5,
		button_top_left.y + scaled_button_height + TOOLTIP_GAP if prefer_below else button_top_left.y - tip_size.y - TOOLTIP_GAP
	)
	target.x = clampf(target.x, 8.0, maxf(8.0, bounds.x - tip_size.x - 8.0))
	target.y = clampf(target.y, 8.0, maxf(8.0, bounds.y - tip_size.y - 8.0))
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
