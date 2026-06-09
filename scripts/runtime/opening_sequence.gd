class_name OpeningSequence
extends CanvasLayer

@onready var _label: Label = %LineLabel


func play_lines(lines: PackedStringArray) -> void:
	for line in lines:
		_label.text = line
		_label.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_label, "modulate:a", 1.0, 0.35)
		tween.tween_interval(1.05)
		tween.tween_property(_label, "modulate:a", 0.0, 0.25)
		await tween.finished
	await get_tree().create_timer(0.25).timeout
	queue_free()
