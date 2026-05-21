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


func setup_window_damage(amount: int, label_prefix: String = "CRASH") -> void:
	_label.text = "%s -%d" % [label_prefix, amount]
	_label.offset_left = -36.0
	_label.offset_top = -12.0
	_label.offset_right = 36.0
	_label.offset_bottom = 8.0
	var ls: LabelSettings = _label.label_settings.duplicate()
	ls.font_color = Color(1.0, 0.48, 0.12, 1.0)
	ls.font_size = 8
	ls.outline_size = 3
	_label.label_settings = ls
	rise_pixels = 8.0
	duration = 0.5


func setup_window_heal(amount: int, label_prefix: String = "HEAL") -> void:
	_label.text = "%s +%d" % [label_prefix, amount]
	_label.offset_left = -36.0
	_label.offset_top = -12.0
	_label.offset_right = 36.0
	_label.offset_bottom = 8.0
	var ls: LabelSettings = _label.label_settings.duplicate()
	ls.font_color = Color(0.45, 1.0, 0.56, 1.0)
	ls.font_size = 8
	ls.outline_size = 3
	_label.label_settings = ls
	rise_pixels = 8.0
	duration = 0.5


func setup_heal(amount: int) -> void:
	_label.text = "+%d" % amount
	var ls: LabelSettings = _label.label_settings.duplicate()
	ls.font_color = Color(0.45, 1.0, 0.56, 1.0)
	ls.font_size = 8
	ls.outline_size = 3
	_label.label_settings = ls
	rise_pixels = 12.0
	duration = 0.55


func setup_gold(amount: int) -> void:
	_label.text = "+%d G" % amount
	_label.offset_left = -34.0
	_label.offset_top = -12.0
	_label.offset_right = 34.0
	_label.offset_bottom = 8.0
	var ls: LabelSettings = _label.label_settings.duplicate()
	ls.font_color = Color(1.0, 0.82, 0.24, 1.0)
	ls.font_size = 8
	ls.outline_size = 3
	_label.label_settings = ls
	rise_pixels = 16.0
	duration = 0.75


func setup_text(text: String, text_color: Color = Color.WHITE) -> void:
	_label.text = text
	_label.offset_left = -42.0
	_label.offset_top = -12.0
	_label.offset_right = 42.0
	_label.offset_bottom = 8.0
	var ls: LabelSettings = _label.label_settings.duplicate()
	ls.font_color = text_color
	ls.font_size = 6
	ls.outline_size = 3
	_label.label_settings = ls
	rise_pixels = 14.0
	duration = 0.75


func _ready() -> void:
	call_deferred("_start_float")


func _start_float() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise_pixels, duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration * 0.6)\
		.set_delay(duration * 0.4)
	tween.chain().tween_callback(queue_free)
