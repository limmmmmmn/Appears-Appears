extends VBoxContainer
class_name StatusInventoryList
## 파티 상태창용 인벤토리 목록

signal equipment_pressed(item_id: String)
signal equipment_hovered(item_id: String)
signal equipment_unhovered()
signal seed_used(item_id: String)

var scroll: ScrollContainer
var container: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	_build_ui()


func _build_ui() -> void:
	var title := Label.new()
	title.text = "--- 인벤토리 (클릭 = 장착) ---"
	add_child(title)
	
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	
	container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 2)
	scroll.add_child(container)


func refresh() -> void:
	_clear()
	
	await get_tree().process_frame
	
	var inventory := PartyManager.get_all_items()
	
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "(비어있음)"
		container.add_child(empty)
		return
	
	var equipments: Array = []
	var seeds: Array = []
	var others: Array = []
	
	# 아이템 분류
	for item_id in inventory:
		var count: int = inventory[item_id]
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		
		if not equip_data.is_empty():
			equipments.append({"id": item_id, "count": count, "data": equip_data})
		else:
			var item_data: Dictionary = DataManager.get_item(item_id)
			if not item_data.is_empty():
				if item_data.get("category", "") == "seed":
					seeds.append({"id": item_id, "count": count, "data": item_data})
				else:
					others.append({"id": item_id, "count": count, "data": item_data})
	
	# 장비 섹션
	if not equipments.is_empty():
		_add_section_title("[장비]")
		for item in equipments:
			_add_equipment_button(item)
	
	# 씨앗 섹션
	if not seeds.is_empty():
		_add_section_title("[씨앗] (클릭 = 사용)")
		for item in seeds:
			_add_seed_button(item)
	
	# 기타 아이템
	if not others.is_empty():
		_add_section_title("[아이템]")
		for item in others:
			_add_item_label(item)


func _add_section_title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	container.add_child(lbl)


func _add_equipment_button(item: Dictionary) -> void:
	var btn := Button.new()
	btn.text = "%s x%d" % [item["data"].get("name", "???"), item["count"]]
	btn.custom_minimum_size.x = 160
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	var item_id: String = item["id"]
	btn.pressed.connect(func(): equipment_pressed.emit(item_id))
	btn.mouse_entered.connect(func(): equipment_hovered.emit(item_id))
	btn.focus_entered.connect(func(): equipment_hovered.emit(item_id))
	btn.mouse_exited.connect(func(): equipment_unhovered.emit())
	btn.focus_exited.connect(func(): equipment_unhovered.emit())
	
	container.add_child(btn)


func _add_seed_button(item: Dictionary) -> void:
	var btn := Button.new()
	btn.text = "%s x%d" % [item["data"].get("name", "???"), item["count"]]
	btn.custom_minimum_size.x = 160
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	
	var item_id: String = item["id"]
	btn.pressed.connect(func(): seed_used.emit(item_id))
	
	container.add_child(btn)


func _add_item_label(item: Dictionary) -> void:
	var lbl := Label.new()
	lbl.text = "%s x%d" % [item["data"].get("name", "???"), item["count"]]
	container.add_child(lbl)


func _clear() -> void:
	for child in container.get_children():
		child.queue_free()
