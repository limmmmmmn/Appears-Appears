class_name RightUpgradePanel
extends PanelContainer

const PANEL_WIDTH: float = 160.0
const VISIBLE_ITEMS_AT_START: int = 2

const SECTION_DEFS: Array[Dictionary] = [
	{
		"id": &"party",
		"title": "PARTY",
		"node_ids": [&"party_hp", &"party_atk", &"party_agi", &"party_defense", &"hero_heavy_strike"],
	},
	{
		"id": &"enemy",
		"title": "ENEMY",
		"node_ids": [&"more_slimes", &"enemies_per_window", &"monster_chase", &"spawner", &"max_enemies"],
	},
	{
		"id": &"ally",
		"title": "ALLY",
		"node_ids": [&"magic", &"companion", &"companion_2", &"companion_3", &"combo_attack"],
	},
	{
		"id": &"window",
		"title": "WINDOW",
		"node_ids": [&"battle_movement", &"window_bash", &"window_push", &"window_blessing", &"window_echo"],
	},
]

var _gold_label: Label
var _field_label: Label
var _field_progress: ProgressBar
var _content: VBoxContainer
var _section_boxes: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(480.0, 0.0)
	size = Vector2(PANEL_WIDTH, 360.0)
	custom_minimum_size = Vector2(PANEL_WIDTH, 360.0)
	offset_left = 480.0
	offset_top = 0.0
	offset_right = 640.0
	offset_bottom = 360.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())
	_build_static_layout()
	_connect_events()
	_refresh()


func _connect_events() -> void:
	EventBus.gold_changed.connect(Callable(self, "_on_state_changed").unbind(1))
	EventBus.field_loop_started.connect(Callable(self, "_on_state_changed").unbind(1))
	EventBus.skill_node_purchase_succeeded.connect(Callable(self, "_on_state_changed").unbind(1))
	EventBus.skill_node_purchase_failed.connect(Callable(self, "_on_purchase_failed").unbind(1))
	EventBus.party_changed.connect(Callable(self, "_on_state_changed"))
	EventBus.enemy_defeated.connect(Callable(self, "_on_state_changed").unbind(3))


func _build_static_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	add_child(root)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	header.add_theme_constant_override("margin_left", 4)
	root.add_child(header)

	_gold_label = _make_label("Gold 0", 12, Color(1.0, 0.91, 0.48, 1.0))
	header.add_child(_gold_label)

	_field_label = _make_label("Field 1", 10, Color(0.88, 1.0, 0.78, 1.0))
	header.add_child(_field_label)

	_field_progress = ProgressBar.new()
	_field_progress.custom_minimum_size = Vector2(0.0, 8.0)
	_field_progress.show_percentage = false
	_field_progress.max_value = 1.0
	_field_progress.value = 0.0
	_field_progress.add_theme_stylebox_override("background", _progress_bg_style())
	_field_progress.add_theme_stylebox_override("fill", _progress_fill_style())
	header.add_child(_field_progress)

	var separator := HSeparator.new()
	root.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 7)
	scroll.add_child(_content)


func _refresh() -> void:
	_gold_label.text = "Gold: %d" % GameState.gold
	_field_label.text = "Field %d" % maxi(1, GameState.field_loop_count)
	_field_progress.value = _field_progress_ratio()
	for child in _content.get_children():
		child.queue_free()
	_section_boxes.clear()
	for section: Dictionary in SECTION_DEFS:
		if not _is_section_unlocked(section):
			continue
		_add_section(section)


func _add_section(section: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	_content.add_child(box)
	_section_boxes[section["id"]] = box

	var title := _make_label("-- %s --" % str(section["title"]), 10, Color(1.0, 1.0, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var node_ids: Array = section["node_ids"]
	for i in node_ids.size():
		var node_id: StringName = node_ids[i]
		if not _is_item_visible(node_ids, i):
			continue
		var node = SkillTreeDB.get_by_id(node_id)
		if node == null:
			continue
		box.add_child(_make_upgrade_item(node))


func _make_upgrade_item(node) -> Control:
	var level: int = GameState.skill_node_level(node.id)
	var max_level: int = int(node.max_level)
	var cost: int = GameState.skill_node_purchase_cost(node.id)
	var is_maxed: bool = level >= max_level
	var can_buy: bool = GameState.can_purchase_skill_node(node.id)

	var item := PanelContainer.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_theme_stylebox_override("panel", _item_style(can_buy, is_maxed))
	item.modulate = Color.WHITE if can_buy or is_maxed else Color(0.62, 0.62, 0.62, 1.0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_child(row)

	var icon := Label.new()
	icon.custom_minimum_size = Vector2(22.0, 30.0)
	icon.text = str(node.short_label).substr(0, 2).to_upper()
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 8)
	icon.add_theme_color_override("font_color", Color(0.1, 0.08, 0.03, 1.0))
	icon.add_theme_stylebox_override("normal", _icon_style())
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 1)
	row.add_child(text_col)

	var name := _make_label(str(node.display_name), 9, Color(1.0, 1.0, 0.96, 1.0))
	name.clip_text = true
	text_col.add_child(name)

	var level_label := _make_label("Lv %d/%d" % [level, max_level], 8, Color(0.72, 0.86, 1.0, 1.0))
	text_col.add_child(level_label)

	var desc := _make_label(_effect_line(node), 8, Color(0.86, 0.86, 0.8, 1.0))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc)

	var button := Button.new()
	button.custom_minimum_size = Vector2(42.0, 26.0)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &""
	button.add_theme_font_size_override("font_size", 8)
	button.add_theme_color_override("font_color", Color(0.08, 0.06, 0.03, 1.0))
	button.add_theme_color_override("font_disabled_color", Color(0.82, 0.82, 0.82, 0.65))
	button.add_theme_stylebox_override("normal", _button_style(can_buy))
	button.add_theme_stylebox_override("hover", _button_hover_style())
	button.add_theme_stylebox_override("pressed", _button_pressed_style())
	button.add_theme_stylebox_override("disabled", _button_disabled_style())
	button.text = "MAX" if is_maxed else "%dG" % cost
	button.disabled = is_maxed or not can_buy
	button.pressed.connect(_on_purchase_pressed.bind(node.id))
	row.add_child(button)

	return item


func _is_section_unlocked(section: Dictionary) -> bool:
	match section["id"]:
		&"party":
			return true
		&"enemy":
			return GameState.total_gold_earned >= 3 or GameState.field_loop_count >= 2
		&"ally":
			return GameState.total_gold_earned >= 18 or GameState.field_loop_count >= 2 or GameState.party_size() >= 2
		&"window":
			return GameState.total_gold_earned >= 35 or GameState.field_loop_count >= 3 or GameState.battle_movement_unlocked()
	return false


func _is_item_visible(node_ids: Array, index: int) -> bool:
	if index < VISIBLE_ITEMS_AT_START:
		return true
	var previous_id: StringName = node_ids[index - 1]
	return GameState.skill_node_level(previous_id) > 0 or GameState.skill_node_level(node_ids[index]) > 0


func _effect_line(node) -> String:
	if node.linked_modifier != null:
		return _effect_line_from_data(node.linked_modifier.effect_data)
	return _effect_line_from_data(node.effect_data)


func _effect_line_from_data(effect_data: Dictionary) -> String:
	if effect_data.has("hp_flat"):
		return "최대 HP 증가"
	if effect_data.has("atk_flat"):
		return "공격력 증가"
	if effect_data.has("agi_flat"):
		return "행동 속도 증가"
	if effect_data.has("def_flat"):
		return "방어력 증가"
	if effect_data.has("hero_damage_bonus_mult"):
		return "용사 공격 강화"
	if effect_data.has("field_enemy_count_bonus"):
		return "필드 적 증가"
	if effect_data.has("enemies_per_window_bonus"):
		return "전투창 적 증가"
	if effect_data.has("chaser_enemies_enabled"):
		return "추격 적 출현"
	if effect_data.has("field_spawn_interval_mult"):
		return "적 재생성 가속"
	if effect_data.has("battle_movement_enabled"):
		return "전투 중 이동"
	if effect_data.has("party_bump_damage_ratio"):
		return "창 밀치기 피해"
	if effect_data.has("window_collision_damage_ratio"):
		return "창 충돌 피해"
	if effect_data.has("window_collision_heal_flat"):
		return "충돌 시 회복"
	if effect_data.has("extra_windows_flat"):
		return "추가 창 생성"
	return "즉시 적용"


func _field_progress_ratio() -> float:
	var next_unlock: int = 3
	if GameState.total_gold_earned >= 3:
		next_unlock = 18
	if GameState.total_gold_earned >= 18:
		next_unlock = 35
	if GameState.total_gold_earned >= 35:
		return 1.0
	return clampf(float(GameState.total_gold_earned) / float(next_unlock), 0.0, 1.0)


func _on_purchase_pressed(node_id: StringName) -> void:
	GameState.purchase_skill_node(node_id)
	_refresh()


func _on_state_changed() -> void:
	_refresh()


func _on_purchase_failed() -> void:
	_refresh()


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", load("res://assets/fonts/field_ui_font.tres"))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.038, 0.045, 1.0)
	style.border_width_left = 1
	style.border_color = Color(0.78, 0.86, 0.72, 1.0)
	style.content_margin_left = 5
	style.content_margin_top = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 5
	return style


func _item_style(can_buy: bool, is_maxed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.18, 0.16, 0.94) if can_buy else Color(0.09, 0.095, 0.105, 0.92)
	if is_maxed:
		style.bg_color = Color(0.13, 0.2, 0.17, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.52, 0.66, 0.42, 1.0) if can_buy else Color(0.26, 0.28, 0.28, 1.0)
	style.content_margin_left = 3
	style.content_margin_top = 3
	style.content_margin_right = 3
	style.content_margin_bottom = 3
	return style


func _icon_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.77, 0.28, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.12, 0.08, 0.02, 1.0)
	return style


func _button_style(can_buy: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.77, 0.28, 1.0) if can_buy else Color(0.18, 0.18, 0.18, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 0.96, 0.72, 1.0)
	return style


func _button_hover_style() -> StyleBoxFlat:
	var style := _button_style(true)
	style.bg_color = Color(1.0, 0.88, 0.42, 1.0)
	return style


func _button_pressed_style() -> StyleBoxFlat:
	var style := _button_style(true)
	style.bg_color = Color(0.66, 0.48, 0.14, 1.0)
	return style


func _button_disabled_style() -> StyleBoxFlat:
	var style := _button_style(false)
	style.border_color = Color(0.34, 0.34, 0.34, 1.0)
	return style


func _progress_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.06, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.28, 0.32, 0.28, 1.0)
	return style


func _progress_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.68, 0.9, 0.42, 1.0)
	return style
