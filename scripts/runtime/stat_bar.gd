class_name StatBar
extends Panel

## Reusable horizontal bar: a background panel with a colored fill that
## stretches from the left edge by `ratio`, plus a text label overlay.
##
## Drives HP and EXP rows in HUD (and is generic enough to drop into any
## other "labeled progress" spot). Fill color + label alignment are @export
## so the same scene serves both flavors without code branches.

@export var fill_color: Color = Color(0.84, 0.22, 0.22, 1)
@export_enum("Center", "Right", "Left") var label_alignment: int = 0

@onready var _fill: ColorRect = %Fill
@onready var _label: Label = %BarLabel


func _ready() -> void:
	_fill.color = fill_color
	_label.horizontal_alignment = _alignment_to_godot(label_alignment)


## Width of the colored fill as a 0..1 fraction of the bar's available width.
func set_ratio(ratio: float) -> void:
	_fill.anchor_right = clampf(ratio, 0.0, 1.0)
	_fill.offset_right = 0.0


## Overlay text (e.g. "12/40", "LV 3").
func set_label(text: String) -> void:
	_label.text = text


func _alignment_to_godot(value: int) -> int:
	match value:
		1: return HORIZONTAL_ALIGNMENT_RIGHT
		2: return HORIZONTAL_ALIGNMENT_LEFT
		_: return HORIZONTAL_ALIGNMENT_CENTER
