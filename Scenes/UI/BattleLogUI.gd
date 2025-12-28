# res://Scenes/UI/BattleLogUI.gd
extends Control

@onready var rich_label = $Panel/RichTextLabel

func _ready():
	rich_label.text = "[color=yellow]=== 모험이 시작됩니다 ===[/color]\n"

# 외부에서 이 함수를 호출해서 글씨를 씁니다.
func add_log(text: String):
	# BBCode를 사용하여 줄바꿈(\n)과 함께 텍스트 추가
	rich_label.append_text("\n" + text)
