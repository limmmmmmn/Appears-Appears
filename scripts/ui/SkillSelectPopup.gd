extends PanelContainer
class_name SkillSelectPopup
## 레벨업 시 스킬 3지선다 팝업

signal skill_selected(hero_id: String, skill_id: String)

var _hero_id: String = ""
var _hero_name: String = ""
var _choices: Array = []  # Array of skill_id strings
var _buttons: Array = []


func open(hero_id: String, hero_name: String, choices: Array) -> void:
	_hero_id = hero_id
	_hero_name = hero_name
	_choices = choices
	_build_ui()
	visible = true


func _build_ui() -> void:
	# 기존 자식 제거
	for child in get_children():
		child.queue_free()

	# 메인 마진
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# 타이틀
	var title := Label.new()
	title.text = "%s - 스킬 선택" % _hero_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	vbox.add_child(title)

	# 구분선
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 스킬 버튼 3개
	_buttons.clear()
	for skill_id in _choices:
		var skill_data: Dictionary = DataManager.get_skill(skill_id)
		var btn := Button.new()
		var skill_name: String = skill_data.get("name", skill_id)
		var skill_desc: String = skill_data.get("description", "")
		var skill_type: String = skill_data.get("type", "")
		var cooldown: float = float(skill_data.get("cooldown", 0.0))

		var type_label: String = ""
		match skill_type:
			"physical": type_label = "[물리]"
			"magic": type_label = "[마법]"
			"heal": type_label = "[회복]"
			_: type_label = "[%s]" % skill_type

		btn.text = "%s %s  CD:%.0fs\n%s" % [type_label, skill_name, cooldown, skill_desc]
		btn.custom_minimum_size = Vector2(220, 40)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 10)

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.12, 0.12, 0.2, 0.95)
		btn_style.border_color = Color(0.5, 0.5, 0.7)
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(4)
		btn_style.content_margin_left = 8
		btn_style.content_margin_right = 8
		btn_style.content_margin_top = 4
		btn_style.content_margin_bottom = 4
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := btn_style.duplicate()
		hover_style.border_color = Color(0.8, 0.8, 1.0)
		hover_style.bg_color = Color(0.2, 0.2, 0.35, 0.95)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style := btn_style.duplicate()
		pressed_style.bg_color = Color(0.25, 0.25, 0.4, 0.95)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.pressed.connect(_on_skill_chosen.bind(skill_id))
		vbox.add_child(btn)
		_buttons.append(btn)


func _center_on_screen() -> void:
	## 화면 중앙에 배치
	var screen_size: Vector2 = get_viewport_rect().size
	global_position = (screen_size - size) * 0.5


func _on_skill_chosen(skill_id: String) -> void:
	visible = false
	skill_selected.emit(_hero_id, skill_id)
