extends Control
## 새 게임 시작 시 트링켓 1개 선택

const ACT_NODE_SELECT_SCENE := "res://scenes/main/ActNodeSelect.tscn"

const BG_COLOR := Color(0.07, 0.08, 0.12, 1.0)
const PANEL_COLOR := Color(0.12, 0.14, 0.2, 0.96)
const PANEL_BORDER := Color(0.36, 0.44, 0.66, 0.95)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 420)
	panel.add_theme_stylebox_override("panel", _make_style(PANEL_COLOR, PANEL_BORDER, 12, 2))
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_top = 20
	root.offset_right = -24
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.text = "시작 트링켓 선택"
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.modulate = Color(0.9, 0.93, 1.0, 0.95)
	subtitle.text = "세 가지 중 하나를 선택하면 Act 1 노드 선택으로 이동합니다."
	root.add_child(subtitle)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 14)
	root.add_child(cards)

	var ids: Array[String] = []
	if DataManager != null and DataManager.has_method("get_all_trinket_ids"):
		ids = DataManager.get_all_trinket_ids()

	for trinket_id in ids:
		var data: Dictionary = DataManager.get_trinket(trinket_id)
		cards.add_child(_build_trinket_card(trinket_id, data))

	if ids.is_empty():
		var fallback := Label.new()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.add_theme_font_size_override("font_size", 15)
		fallback.text = "트링켓 데이터가 없어 기본 진행으로 이동합니다."
		root.add_child(fallback)
		call_deferred("_go_to_node_select")


func _build_trinket_card(trinket_id: String, data: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(228, 260)
	card.add_theme_stylebox_override("panel", _make_style(Color(0.14, 0.16, 0.24, 0.98), Color(0.46, 0.56, 0.82, 0.95), 10, 2))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 12
	vbox.offset_right = -12
	vbox.offset_bottom = -12
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var emoji_label := Label.new()
	emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji_label.add_theme_font_size_override("font_size", 44)
	emoji_label.text = str(data.get("emoji", "🧿"))
	vbox.add_child(emoji_label)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.text = str(data.get("name", trinket_id))
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.modulate = Color(0.9, 0.93, 0.98, 0.96)
	desc_label.text = str(data.get("description", ""))
	vbox.add_child(desc_label)

	var pick_btn := Button.new()
	pick_btn.text = "선택"
	pick_btn.custom_minimum_size = Vector2(0, 36)
	pick_btn.add_theme_font_size_override("font_size", 14)
	pick_btn.pressed.connect(_on_pick_trinket_pressed.bind(trinket_id))
	vbox.add_child(pick_btn)

	return card


func _on_pick_trinket_pressed(trinket_id: String) -> void:
	if GameManager == null or not GameManager.has_method("choose_starting_trinket"):
		_go_to_node_select()
		return
	var ok: bool = bool(GameManager.call("choose_starting_trinket", trinket_id))
	if not ok:
		return
	_go_to_node_select()


func _go_to_node_select() -> void:
	get_tree().change_scene_to_file(ACT_NODE_SELECT_SCENE)


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
