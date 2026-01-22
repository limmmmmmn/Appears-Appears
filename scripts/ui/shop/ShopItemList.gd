extends PanelContainer
class_name ShopItemList
## 상점 아이템 목록 UI

signal item_focused(item_id: String)
signal item_buy_pressed(item_id: String, price: int)
signal item_sell_pressed(item_id: String, price: int)

var scroll: ScrollContainer
var container: VBoxContainer
var item_buttons: Array[Button] = []


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	
	container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 3)
	scroll.add_child(container)


func build_buy_list(shop_id: String) -> void:
	_clear()
	
	var item_list: Array = DataManager.get_shop_items(shop_id)
	
	for item_id in item_list:
		var item_data: Dictionary = DataManager.get_item(item_id)
		if item_data.is_empty():
			continue
		
		var price: int = _get_buy_price(item_data)
		var hbox := _create_buy_item_row(item_id, item_data, price)
		container.add_child(hbox)
	
	_focus_first()


func build_sell_list() -> void:
	_clear()
	
	var items: Array = InventoryManager.get_all_items() if InventoryManager else []
	
	if items.is_empty():
		var empty := Label.new()
		empty.text = "판매할 아이템이 없습니다."
		container.add_child(empty)
		return
	
	for item_info in items:
		var item_id: String = str(item_info.get("id", ""))
		var count: int = int(item_info.get("quantity", 1))
		var item_data: Dictionary = item_info.get("data", {})
		
		if item_data.is_empty():
			item_data = DataManager.get_item(item_id)
		if item_data.is_empty():
			continue
		
		var sell_price: int = _get_sell_price(item_data)
		var hbox := _create_sell_item_row(item_id, item_data, count, sell_price)
		container.add_child(hbox)
	
	_focus_first()


func _create_buy_item_row(item_id: String, item_data: Dictionary, price: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	
	var item_btn := Button.new()
	item_btn.text = item_data.get("name", "???")
	item_btn.custom_minimum_size.x = 120
	item_btn.focus_entered.connect(func(): item_focused.emit(item_id))
	item_btn.mouse_entered.connect(func(): item_focused.emit(item_id))
	item_btn.pressed.connect(func(): item_buy_pressed.emit(item_id, price))
	hbox.add_child(item_btn)
	item_buttons.append(item_btn)
	
	var price_lbl := Label.new()
	price_lbl.text = "%d G" % price
	price_lbl.custom_minimum_size.x = 60
	if GameManager.gold < price:
		price_lbl.add_theme_color_override("font_color", Color.RED)
	hbox.add_child(price_lbl)
	
	# 장비 슬롯 표시
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	if not equip_data.is_empty():
		var slot_lbl := Label.new()
		var slot: String = equip_data.get("slot", "")
		slot_lbl.text = "[%s]" % StatCompareUtil.get_slot_display_name(slot)
		slot_lbl.add_theme_color_override("font_color", Color.GRAY)
		hbox.add_child(slot_lbl)
	
	return hbox


func _create_sell_item_row(item_id: String, item_data: Dictionary, count: int, price: int) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	
	var item_btn := Button.new()
	item_btn.text = "%s x%d" % [item_data.get("name", "???"), count]
	item_btn.custom_minimum_size.x = 150
	item_btn.focus_entered.connect(func(): item_focused.emit(item_id))
	item_btn.mouse_entered.connect(func(): item_focused.emit(item_id))
	item_btn.pressed.connect(func(): item_sell_pressed.emit(item_id, price))
	hbox.add_child(item_btn)
	item_buttons.append(item_btn)
	
	var price_lbl := Label.new()
	price_lbl.text = "+%d G" % price
	price_lbl.custom_minimum_size.x = 60
	price_lbl.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(price_lbl)
	
	return hbox


func _get_buy_price(item_data: Dictionary) -> int:
	var price: int = int(item_data.get("buy_price", 0))
	if price == 0:
		price = int(item_data.get("gear_score", 10)) * 10
	return price


func _get_sell_price(item_data: Dictionary) -> int:
	var price: int = int(item_data.get("sell_price", 0))
	if price == 0:
		price = int(item_data.get("gear_score", 5)) * 5
	return price


func _clear() -> void:
	for child in container.get_children():
		child.queue_free()
	item_buttons.clear()


func _focus_first() -> void:
	await get_tree().process_frame
	if item_buttons.size() > 0:
		item_buttons[0].grab_focus()
