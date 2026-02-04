extends Node
## 원념 선택 팝업 입력 처리

var hud: FieldHUD = null
var go_btn: Button = null
var stop_btn: Button = null
var go_style: StyleBoxFlat = null
var stop_style: StyleBoxFlat = null
var go_style_selected: StyleBoxFlat = null
var stop_style_selected: StyleBoxFlat = null

var selection: int = 0  # 0 = 고, 1 = 스톱


func _ready() -> void:
	_update_selection_visual()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				if selection != 0:
					selection = 0
					_update_selection_visual()
				get_viewport().set_input_as_handled()
			KEY_RIGHT:
				if selection != 1:
					selection = 1
					_update_selection_visual()
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				_confirm_selection()
				get_viewport().set_input_as_handled()


func _update_selection_visual() -> void:
	if not go_btn or not stop_btn:
		return

	if selection == 0:
		go_btn.text = "▶ 고 (계속) ◀"
		go_btn.add_theme_stylebox_override("normal", go_style_selected if go_style_selected else go_style)
		go_btn.add_theme_stylebox_override("hover", go_style_selected if go_style_selected else go_style)
		go_btn.add_theme_color_override("font_color", Color.WHITE)

		stop_btn.text = "스톱 (보상)"
		stop_btn.add_theme_stylebox_override("normal", stop_style)
		stop_btn.add_theme_stylebox_override("hover", stop_style)
		stop_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	else:
		go_btn.text = "고 (계속)"
		go_btn.add_theme_stylebox_override("normal", go_style)
		go_btn.add_theme_stylebox_override("hover", go_style)
		go_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

		stop_btn.text = "▶ 스톱 (보상) ◀"
		stop_btn.add_theme_stylebox_override("normal", stop_style_selected)
		stop_btn.add_theme_stylebox_override("hover", stop_style_selected)
		stop_btn.add_theme_color_override("font_color", Color.WHITE)


func _confirm_selection() -> void:
	if not hud:
		return

	if selection == 0:
		hud._on_grudge_go_selected()
	else:
		hud._on_grudge_stop_selected()
