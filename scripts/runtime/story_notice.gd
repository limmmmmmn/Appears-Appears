class_name StoryNotice
extends CanvasLayer

@onready var _panel: Panel = %Panel
@onready var _label: Label = %Label


func show_notice(text: String) -> void:
	_label.text = text
	_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, 0.12)
	tween.tween_interval(3.0)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)
