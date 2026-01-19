extends PanelContainer
class_name LogPanel
## 로그 패널 - 전투/시스템 메시지 스크롤 표시

const MAX_LOGS := 50

var logs: Array[String] = []

@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var log_label: RichTextLabel = $VBox/ScrollContainer/LogText


func _ready() -> void:
	_setup_style()


func _setup_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1)
	style.border_width_top = 1
	style.border_color = Color(0.25, 0.25, 0.3)
	add_theme_stylebox_override("panel", style)


func add_log(text: String) -> void:
	logs.append(text)
	
	while logs.size() > MAX_LOGS:
		logs.pop_front()
	
	_update_display()
	
	# 스크롤 맨 아래로
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)


func _update_display() -> void:
	var display_text = ""
	
	for log in logs:
		var colored_log = _colorize_log(log)
		display_text += colored_log + "\n"
	
	log_label.text = display_text


func _colorize_log(text: String) -> String:
	# 승리/레벨업 - 노란색
	if text.contains("승리") or text.contains("Lv.") or text.contains("레벨"):
		return "[color=#ffdd44]%s[/color]" % text
	
	# 피해/격파 - 빨간색
	if text.contains("격파") or text.contains("DEAD"):
		return "[color=#ff6666]%s[/color]" % text
	
	# 스킬 해금 - 시안
	if text.contains("스킬 해금"):
		return "[color=#66ffff]%s[/color]" % text
	
	# 장착/해제 - 초록
	if text.contains("장착") or text.contains("해제"):
		return "[color=#66ff66]%s[/color]" % text
	
	# 힐 - 연두
	if text.contains("힐"):
		return "[color=#88ff88]%s[/color]" % text
	
	# 출현 - 주황
	if text.contains("출현"):
		return "[color=#ffaa44]%s[/color]" % text
	
	# EXP/Gold - 보라
	if text.contains("EXP") or text.contains("Gold"):
		return "[color=#aa88ff]%s[/color]" % text
	
	return text


func clear_logs() -> void:
	logs.clear()
	log_label.text = ""
