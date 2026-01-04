extends CanvasLayer

@onready var log_text: RichTextLabel = $Control/PanelContainer/LogText

func _ready() -> void:
	# [설계도 167] 로그 메시지 수신
	SignalBus.on_log_message.connect(_add_log)

func _add_log(text: String, color: Color) -> void:
	# BBCode로 색상 적용
	var color_hex = color.to_html()
	log_text.append_text("[color=#%s]%s[/color]\n" % [color_hex, text])
	# 스크롤 자동 내리기
	# (Godot 버전에 따라 scroll_to_line 사용)
