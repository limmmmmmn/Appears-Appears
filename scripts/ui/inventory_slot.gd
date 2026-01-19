extends Panel
class_name InventorySlot
## 인벤토리 슬롯 - 드래그해서 장비 슬롯에 드롭

var item_id: String = ""

@onready var icon: TextureRect = $Icon


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_setup_style()


func _setup_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.25, 0.25, 0.3)
	add_theme_stylebox_override("panel", style)


func set_item(new_item_id: String) -> void:
	item_id = new_item_id
	
	if item_id.is_empty():
		icon.texture = null
		tooltip_text = ""
	else:
		var item_data = DataManager.get_equipment(item_id)
		var icon_path = str(item_data.get("icon", ""))
		
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		else:
			icon.texture = _create_placeholder_texture(item_data)
		
		tooltip_text = _get_item_tooltip(item_data)


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
		"from_inventory": true
	}
