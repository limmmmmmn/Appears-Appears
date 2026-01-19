extends PanelContainer
class_name InventoryPanel
## 인벤토리 패널 - 소지 장비 목록, 드래그로 장착

@onready var item_grid: GridContainer = $VBox/ItemGrid

var item_slots: Array[InventorySlot] = []


func _ready() -> void:
	_setup_style()
	_cache_slots()


func _setup_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	add_theme_stylebox_override("panel", style)


func _cache_slots() -> void:
	for child in item_grid.get_children():
		if child is InventorySlot:
			item_slots.append(child)


func update_items(items: Array) -> void:
	for i in range(item_slots.size()):
		if i < items.size():
			item_slots[i].set_item(str(items[i]))
		else:
			item_slots[i].set_item("")
