extends Control
## Act 시작 시 노드 선택 화면 (임시)

const BG_COLOR := Color(0.06, 0.08, 0.12, 1.0)
const PANEL_COLOR := Color(0.12, 0.15, 0.22, 0.96)
const PANEL_BORDER := Color(0.35, 0.46, 0.72, 0.95)
const FIELD_NODE_COLOR := Color(0.2, 0.33, 0.24, 0.98)
const TOWN_NODE_COLOR := Color(0.24, 0.22, 0.34, 0.98)
const NODE_DISABLED_COLOR := Color(0.18, 0.18, 0.2, 0.9)

var act_id: String = "act_1"
var field_area_id: String = ""
var town_area_id: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_resolve_act_and_nodes()
	_build_ui()


func _resolve_act_and_nodes() -> void:
	FieldManager.ensure_runtime_acts()
	if not GameManager.current_act_id.is_empty():
		act_id = GameManager.current_act_id

	if not FieldManager.set_current_act(act_id):
		var acts: Array[Dictionary] = FieldManager.get_runtime_acts()
		if not acts.is_empty():
			act_id = str((acts[0] as Dictionary).get("id", "act_1"))
			FieldManager.set_current_act(act_id)

	field_area_id = FieldManager.get_first_area_id(act_id)
	if field_area_id.is_empty():
		return

	var next_ids: Array[String] = FieldManager.get_next_runtime_area_ids(act_id, field_area_id)
	for next_id in next_ids:
		var area: Dictionary = FieldManager.get_runtime_area(act_id, next_id)
		if str(area.get("type", "")) == "town":
			town_area_id = next_id
			break

	if town_area_id.is_empty():
		var act_data: Dictionary = FieldManager.get_runtime_act(act_id)
		var areas: Array = act_data.get("areas", []) as Array
		for area_any in areas:
			var area: Dictionary = area_any as Dictionary
			if str(area.get("type", "")) == "town":
				town_area_id = str(area.get("id", ""))
				break


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 360)
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_COLOR, PANEL_BORDER, 12, 2))
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 16)
	root.offset_left = 24
	root.offset_top = 20
	root.offset_right = -24
	root.offset_bottom = -20
	panel.add_child(root)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.text = "%s 노드 선택" % _get_act_name()
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.modulate = Color(0.85, 0.9, 1.0, 0.95)
	subtitle.text = "현재는 필드 -> 마을 순서로만 진행됩니다."
	root.add_child(subtitle)

	var flow := Control.new()
	flow.custom_minimum_size = Vector2(620, 180)
	flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(flow)

	var link := ColorRect.new()
	link.color = Color(0.6, 0.68, 0.92, 0.92)
	link.size = Vector2(200, 4)
	link.position = Vector2(210, 88)
	flow.add_child(link)

	var field_btn := Button.new()
	field_btn.custom_minimum_size = Vector2(180, 96)
	field_btn.position = Vector2(40, 40)
	field_btn.text = "필드\n%s" % _get_area_name(field_area_id, "시작 필드")
	field_btn.add_theme_font_size_override("font_size", 16)
	field_btn.add_theme_stylebox_override("normal", _make_style(FIELD_NODE_COLOR, Color(0.5, 0.78, 0.58, 0.95), 10, 2))
	field_btn.pressed.connect(_on_field_pressed)
	field_btn.disabled = field_area_id.is_empty()
	flow.add_child(field_btn)

	var town_btn := Button.new()
	town_btn.custom_minimum_size = Vector2(180, 96)
	town_btn.position = Vector2(420, 40)
	town_btn.text = "마을\n%s\n(잠금)" % _get_area_name(town_area_id, "다음 노드")
	town_btn.add_theme_font_size_override("font_size", 16)
	town_btn.add_theme_stylebox_override("normal", _make_style(TOWN_NODE_COLOR, Color(0.55, 0.62, 0.9, 0.95), 10, 2))
	town_btn.add_theme_stylebox_override("disabled", _make_style(NODE_DISABLED_COLOR, Color(0.4, 0.4, 0.44, 0.9), 10, 1))
	town_btn.disabled = true
	flow.add_child(town_btn)

	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.9, 0.95, 1.0, 0.95)
	hint.text = "필드 클리어 후 다음 노드(마을)로 자동 이동합니다."
	root.add_child(hint)


func _on_field_pressed() -> void:
	if field_area_id.is_empty():
		return
	GameManager.go_to_area(act_id, field_area_id)


func _get_act_name() -> String:
	var name: String = FieldManager.get_current_act_name()
	if name.is_empty():
		return "Act 1"
	return name


func _get_area_name(area_id: String, fallback: String) -> String:
	if area_id.is_empty():
		return fallback
	var data: Dictionary = FieldManager.get_runtime_area(act_id, area_id)
	var name: String = str(data.get("name", ""))
	if name.is_empty():
		return fallback
	return name


func _make_style(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
