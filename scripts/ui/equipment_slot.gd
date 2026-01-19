extends Panel
class_name EquipmentSlot
## 장비 슬롯 - 드래그앤드롭으로 장착/해제

signal item_dropped_on_slot(item_id: String)

@export var slot_type: String = ""
@export var slot_label: String = ""

var item_id: String = ""
var hero_id: String = ""

@onready var label: Label = $Label
@onready var icon: TextureRect = $Icon
@onready var highlight: ColorRect = $Highlight


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	label.text = slot_label
	_setup_style()


func _setup_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	add_theme_stylebox_override("panel", style)


func set_item(new_item_id: String) -> void:
	item_id = new_item_id
	
	if item_id.is_empty():
		icon.texture = null
		label.visible = true
		tooltip_text = _get_slot_name()
	else:
		var item_data = DataManager.get_equipment(item_id)
		var icon_path = str(item_data.get("icon", ""))
		
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		else:
			icon.texture = _create_placeholder_texture(item_data)
		
		label.visible = false
		tooltip_text = _get_item_tooltip(item_data)


func _get_slot_name() -> String:
	var names = {
		"weapon_left": "왼손",
		"weapon_right": "오른손",
		"helmet": "머리",
		"armor": "갑옷",
		"accessory1": "악세1",
		"accessory2": "악세2"
	}
	return names.get(slot_type, slot_type)


func _get_item_tooltip(item_data: Dictionary) -> String:
	var item_name = str(item_data.get("name", "???"))
	var desc = str(item_data.get("description", ""))
	var stats = item_data.get("stats", {})
	
	var stat_text = ""
	var stat_names = {"max_hp": "HP", "atk": "ATK", "def": "DEF", "dex": "DEX", "int": "INT", "luk": "LUK"}
	for stat in stats:
		var value = int(stats[stat])
		var sign = "+" if value >= 0 else ""
		stat_text += "%s%s%d " % [stat_names.get(stat, stat), sign, value]
	
	return "%s\n%s\n%s" % [item_name, desc, stat_text]


func _create_placeholder_texture(item_data: Dictionary) -> ImageTexture:
	var rarity = str(item_data.get("rarity", "common"))
	var color = DataManager.get_rarity_color(rarity)
	
	var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)
	
	return ImageTexture.create_from_image(img)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	
	if not data.has("item_id"):
		return false
	
	var dragged_item_id = str(data["item_id"])
	var item_data = DataManager.get_equipment(dragged_item_id)
	
	if item_data.is_empty():
		return false
	
	var item_slot = str(item_data.get("slot", ""))
	
	# 슬롯 호환성 체크
	var compatible = false
	if item_slot == slot_type:
		compatible = true
	elif item_slot in ["accessory1", "accessory2"] and slot_type in ["accessory1", "accessory2"]:
		compatible = true
	
	if not compatible:
		return false
	
	# 영웅 장착 가능 체크
	if not hero_id.is_empty():
		if not DataManager.can_hero_equip(hero_id, dragged_item_id):
			return false
	
	highlight.visible = true
	return true


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	highlight.visible = false
	
	if data is Dictionary and data.has("item_id"):
		item_dropped_on_slot.emit(str(data["item_id"]))


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		highlight.visible = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty():
		return null
	
	var preview = TextureRect.new()
	preview.texture = icon.texture
	preview.custom_minimum_size = Vector2(24, 24)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	set_drag_preview(preview)
	
	return {
		"item_id": item_id,
		"from_slot": slot_type,
		"from_hero": hero_id
	}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not item_id.is_empty():
				item_dropped_on_slot.emit("")
