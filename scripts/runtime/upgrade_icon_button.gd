class_name UpgradeIconButton
extends Button

## Compact icon-only button used by RightUpgradePanel. Holds a skill-node id and
## renders a rich tooltip on hover (name / description / level / cost / status).
## The panel layers an icon and optional cost-strip / level-badge children on top.

const TOOLTIP_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

signal purchase_requested(node_id: StringName)

var node_id: StringName = &""


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	pressed.connect(_on_pressed)
	# tooltip_text must be non-empty for the engine to even consider calling
	# _make_custom_tooltip. We use a single space so no native tooltip ever
	# leaks through if our override fails.
	tooltip_text = " "


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _on_pressed() -> void:
	pulse()
	purchase_requested.emit(node_id)


## Quick scale bump on click. The panel keeps refresh suppressed for ~180ms so
## this animation has time to play before the button is freed and rebuilt.
func pulse() -> void:
	scale = Vector2.ONE
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.22, 1.22), 0.06) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.10) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)


# ─── Rich tooltip ─────────────────────────────────────────────────────
func _make_custom_tooltip(_for_text: String) -> Object:
	if node_id == &"":
		return null
	var node = SkillTreeDB.get_by_id(node_id)
	if node == null:
		return null
	return _build_tooltip(node)


func _build_tooltip(node) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _tooltip_style())
	panel.custom_minimum_size = Vector2(180.0, 0.0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	var level: int = GameState.skill_node_level(node.id)
	var max_level: int = int(node.max_level)
	var is_maxed: bool = level >= max_level
	var has_prereqs: bool = _all_prereqs_met(node)
	var can_purchase: bool = GameState.can_purchase_skill_node(node.id)
	var cost: int = GameState.skill_node_purchase_cost(node.id)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	vbox.add_child(title_row)

	var name_label := _label(str(node.display_name), 11, Color(1.0, 1.0, 0.94, 1.0))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_label)
	if max_level > 1 or level > 0:
		var lv := _label("Lv %d/%d" % [level, max_level], 9, Color(0.72, 0.88, 1.0, 1.0))
		title_row.add_child(lv)

	if not String(node.description).is_empty():
		var desc := _label(str(node.description), 9, Color(0.86, 0.86, 0.78, 1.0))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(168.0, 0.0)
		vbox.add_child(desc)

	var status_text: String
	var status_color: Color
	if is_maxed:
		status_text = "최대 레벨"
		status_color = Color(0.7, 0.95, 0.62, 1.0)
	elif not has_prereqs:
		status_text = "선행 노드 필요"
		status_color = Color(0.95, 0.5, 0.42, 1.0)
	elif can_purchase:
		status_text = "비용 %d G" % cost
		status_color = Color(1.0, 0.88, 0.38, 1.0)
	else:
		status_text = "비용 %d G  (골드 부족)" % cost
		status_color = Color(0.82, 0.66, 0.34, 1.0)
	vbox.add_child(_label(status_text, 9, status_color))

	return panel


func _all_prereqs_met(node) -> bool:
	for prereq_id: StringName in node.prerequisite_ids:
		if not GameState.has_skill_node(prereq_id):
			return false
	return true


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", TOOLTIP_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label


func _tooltip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.055, 0.98)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.82, 0.88, 0.72, 1.0)
	style.content_margin_left = 7
	style.content_margin_top = 6
	style.content_margin_right = 7
	style.content_margin_bottom = 6
	return style
