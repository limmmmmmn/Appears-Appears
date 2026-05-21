class_name EquipSlot
extends ColorRect

## A single equipment slot. Shows an ItemData icon when equipped.

const EMPTY_COLOR: Color = Color(0.66, 0.66, 0.68, 0.85)
const FILLED_COLOR: Color = Color(0.08, 0.1, 0.08, 0.92)

@onready var _icon: TextureRect = $Icon


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clear()


## Drop the slot back to the empty state. Convenience for "unequip" /
## "rebuild on party change" paths.
func clear() -> void:
	color = EMPTY_COLOR
	_icon.texture = null
	_icon.hide()


func set_paint(c: Color) -> void:
	color = c


func set_item(item: ItemData) -> void:
	if item == null:
		clear()
		return
	color = FILLED_COLOR
	_icon.texture = item.icon
	_icon.visible = item.icon != null
