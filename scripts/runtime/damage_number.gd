class_name DamageNumber
extends Node2D

## Floating damage popup. Spawned by Enemy on take_damage.
## Rises and fades over `duration` then frees itself.

@export var rise_pixels: float = 14.0
@export var duration: float = 0.6

@onready var _label: Label = $Label


func setup(amount: int, is_crit: bool = false) -> void:
	_label.text = str(amount)
	if is_crit:
		_label.text += "!"
		# Duplicate the label settings so we don't mutate the shared resource.
		var ls: LabelSettings = _label.label_settings.duplicate()
		ls.font_color = Color(1, 0.85, 0.2, 1)
		ls.font_size += 2
		_label.label_settings = ls


func _ready() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise_pixels, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.6)\
		.set_delay(duration * 0.4)
	tween.chain().tween_callback(queue_free)
