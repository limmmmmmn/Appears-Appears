class_name DamageNumber
extends Node2D

## Floating damage popup. Spawned by Enemy on take_damage.
## Rises and fades over `duration` then frees itself.

@export var rise_pixels: float = 14.0
@export var duration: float = 0.6

@onready var _label: Label = $Label

## When > 0, the popup punches in from this scale (jackpot juice).
var _spawn_scale_pop: float = 0.0


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


## Kill reward reveal, sized to luck. low = 작고 시무룩("피용"), normal = 보통,
## jackpot = 화려하게("팡팡팡!", 큰 숫자 + scale 펀치).
func setup_gold_roll(amount: int, tier: StringName) -> void:
	_label.offset_left = -48.0
	_label.offset_top = -12.0
	_label.offset_right = 48.0
	_label.offset_bottom = 8.0
	var ls: LabelSettings = _label.label_settings.duplicate()
	match tier:
		&"jackpot":
			_label.text = "팡팡팡! +%d G" % amount
			ls.font_color = Color(1.0, 0.86, 0.2, 1.0)
			ls.font_size = 14
			ls.outline_size = 4
			ls.outline_color = Color(0.5, 0.18, 0.0, 1.0)
			rise_pixels = 26.0
			duration = 1.05
			_spawn_scale_pop = 0.45
		&"low":
			_label.text = "피용.. +%d G" % amount
			ls.font_color = Color(0.74, 0.7, 0.55, 1.0)  # muted, 시무룩
			ls.font_size = 6
			ls.outline_size = 2
			rise_pixels = 7.0
			duration = 0.5
		_:
			_label.text = "+%d G" % amount
			ls.font_color = Color(1.0, 0.82, 0.24, 1.0)
			ls.font_size = 9
			ls.outline_size = 3
			rise_pixels = 16.0
			duration = 0.72
	_label.label_settings = ls


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
	# Jackpot punch: snap in from small with a BACK overshoot that settles to 1.
	if _spawn_scale_pop > 0.0:
		scale = Vector2.ONE * _spawn_scale_pop
		tween.tween_property(self, "scale", Vector2.ONE, duration * 0.35)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(queue_free)
