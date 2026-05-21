class_name EquipSlot
extends ColorRect

## A single equipment slot. Shows an ItemData icon when equipped.

const EMPTY_COLOR: Color = Color(0.66, 0.66, 0.68, 0.85)
const FILLED_COLOR: Color = Color(0.08, 0.1, 0.08, 0.92)
const EQUIP_FLASH_COLOR: Color = Color(0.75, 1.0, 0.45, 1.0)
const MERGE_FLASH_COLOR: Color = Color(1.0, 0.78, 0.25, 1.0)

@onready var _icon: TextureRect = $Icon
@onready var _level_label: Label = $LevelLabel

var _empty_label: String = "Empty"
var _last_item_id: StringName = &""
var _last_level: int = 0
var _has_item_state: bool = false
var _burst_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_update_pivot)
	_update_pivot()
	clear()


func set_empty_label(label: String) -> void:
	_empty_label = label
	if _icon == null or _icon.texture == null:
		tooltip_text = _empty_tooltip()


## Drop the slot back to the empty state. Convenience for "unequip" /
## "rebuild on party change" paths.
func clear() -> void:
	color = EMPTY_COLOR
	_icon.texture = null
	_icon.hide()
	_level_label.text = ""
	_level_label.hide()
	tooltip_text = _empty_tooltip()
	_remember_item_state(&"", 0)


func set_paint(c: Color) -> void:
	color = c


func set_item(entry) -> void:
	var item: ItemData = GameState.item_entry_data(entry)
	if item == null:
		clear()
		return
	var level: int = GameState.item_entry_level(entry)
	var burst_text: String = _burst_text_for(item.id, level)
	color = FILLED_COLOR
	_icon.texture = item.icon
	_icon.visible = item.icon != null
	_level_label.text = str(level)
	_level_label.show()
	tooltip_text = GameState.item_entry_tooltip(entry)
	_remember_item_state(item.id, level)
	if not burst_text.is_empty():
		_play_burst(burst_text, burst_text.begins_with("MERGE"))


func _empty_tooltip() -> String:
	return "%s\nNo item" % _empty_label


func _update_pivot() -> void:
	pivot_offset = size * 0.5


func _remember_item_state(item_id: StringName, level: int) -> void:
	_last_item_id = item_id
	_last_level = level
	_has_item_state = true


func _burst_text_for(item_id: StringName, level: int) -> String:
	if not _has_item_state:
		return ""
	if _last_item_id == &"":
		return "EQUIP!"
	if _last_item_id != item_id:
		return "EQUIP!"
	if level > _last_level:
		return "MERGE Lv %d!" % level
	return ""


func _play_burst(text: String, is_merge: bool) -> void:
	_update_pivot()
	if _burst_tween and _burst_tween.is_valid():
		_burst_tween.kill()
	scale = Vector2.ONE
	modulate = Color.WHITE
	var flash: Color = MERGE_FLASH_COLOR if is_merge else EQUIP_FLASH_COLOR
	_burst_tween = create_tween()
	_burst_tween.set_parallel(true)
	_burst_tween.tween_property(self, "scale", Vector2(1.72, 1.72), 0.10)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(self, "modulate", flash, 0.08)
	_burst_tween.chain().tween_property(self, "scale", Vector2(0.9, 0.9), 0.08)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_IN_OUT)
	_burst_tween.chain().set_parallel(true)
	_burst_tween.tween_property(self, "scale", Vector2.ONE, 0.14)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(self, "modulate", Color.WHITE, 0.14)
	_spawn_burst_label(text, flash)


func _spawn_burst_label(text: String, flash: Color) -> void:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 80
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(96, 12)
	label.position = Vector2(size.x * 0.5 - label.size.x * 0.5, -14.0)
	label.modulate = flash
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 16.0, 0.42)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.24).set_delay(0.18)
	tween.chain().tween_callback(label.queue_free)
