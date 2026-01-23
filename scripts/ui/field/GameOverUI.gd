extends CanvasLayer
class_name GameOverUI
## 게임오버 화면 UI

signal restart_pressed
signal quit_pressed

var panel: PanelContainer
var title_label: Label
var message_label: Label
var restart_button: Button
var quit_button: Button


func _ready() -> void:
	layer = 100  # 최상위 레이어
	# 일시정지 중에도 UI가 작동하도록 설정
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()


func _build_ui() -> void:
	# 어두운 배경
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# 중앙 패널
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(300, 200)
	panel.position = Vector2(-150, -100)
	add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	# 마진용 컨테이너
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(inner_vbox)
	
	# 타이틀
	title_label = Label.new()
	title_label.text = "GAME OVER"
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", Color.RED)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(title_label)
	
	# 메시지
	message_label = Label.new()
	message_label.text = "파티가 전멸했습니다..."
	message_label.add_theme_font_size_override("font_size", 14)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner_vbox.add_child(message_label)
	
	# 스페이서
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	inner_vbox.add_child(spacer)
	
	# 버튼 컨테이너
	var button_container := HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 20)
	inner_vbox.add_child(button_container)
	
	# 타이틀로 버튼
	restart_button = Button.new()
	restart_button.text = "타이틀로"
	restart_button.custom_minimum_size = Vector2(100, 40)
	restart_button.pressed.connect(_on_restart_pressed)
	button_container.add_child(restart_button)
	
	# 종료 버튼
	quit_button = Button.new()
	quit_button.text = "종료"
	quit_button.custom_minimum_size = Vector2(100, 40)
	quit_button.pressed.connect(_on_quit_pressed)
	button_container.add_child(quit_button)


func show_game_over(message: String = "파티가 전멸했습니다...") -> void:
	message_label.text = message
	show()
	
	# 게임 일시정지
	get_tree().paused = true


func _on_restart_pressed() -> void:
	get_tree().paused = false
	restart_pressed.emit()
	hide()


func _on_quit_pressed() -> void:
	get_tree().paused = false
	quit_pressed.emit()
	hide()
