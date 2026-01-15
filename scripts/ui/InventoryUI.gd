# scripts/ui/InventoryUI.gd
extends Panel

signal closed

# UI 참조 - find_child로 찾기
var inventory_list: VBoxContainer
var equipment_list: VBoxContainer
var item_info: Label
var close_button: Button

var selected_item: Dictionary = {}
var selected_hero_index: int = 0

func _ready():
	print("[InventoryUI] Created")
	
	# ⭐ 노드 이름으로 검색
	inventory_list = find_child("InventoryList", true, false)
	equipment_list = find_child("EquipmentList", true, false)
	item_info = find_child("ItemInfo", true, false)
	close_button = find_child("CloseButton", true, false)
	
	# 디버그
	print("  inventory_list: ", inventory_list)
	print("  equipment_list: ", equipment_list)
	print("  item_info: ", item_info)
	print("  close_button: ", close_button)
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	refresh_ui()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		close_ui()

func refresh_ui():
	refresh_inventory()
	refresh_equipment()

# ========================================
# 인벤토리 표시
# ========================================

func refresh_inventory():
	if not inventory_list:
		print("[InventoryUI] ERROR: inventory_list is null!")
		return
	
	for child in inventory_list.get_children():
		child.queue_free()
	
	for item in GameManager.inventory:
		var button = create_item_button(item, false)
		inventory_list.add_child(button)
	
	var empty_slots = 20 - GameManager.inventory.size()
	for i in range(empty_slots):
		var empty_label = Label.new()
		empty_label.text = "[ Empty ]"
		empty_label.add_theme_color_override("font_color", Color.GRAY)
		inventory_list.add_child(empty_label)

func refresh_equipment():
	if not equipment_list:
		print("[InventoryUI] ERROR: equipment_list is null!")
		return
	
	for child in equipment_list.get_children():
		child.queue_free()
	
	for i in range(GameManager.party.size()):
		var hero = GameManager.party[i]
		
		var hero_label = Label.new()
		hero_label.text = "=== %s ===" % hero.name
		hero_label.add_theme_color_override("font_color", Color.YELLOW)
		equipment_list.add_child(hero_label)
		
		var slots = ["weapon", "armor", "accessory"]
		for slot in slots:
			var slot_button = Button.new()
			var equipped_item = get_equipped_item(hero, slot)
			
			if equipped_item.is_empty():
				slot_button.text = "[%s] - Empty" % slot.capitalize()
				slot_button.add_theme_color_override("font_color", Color.GRAY)
			else:
				slot_button.text = "[%s] %s" % [slot.capitalize(), equipped_item.name]
				slot_button.add_theme_color_override("font_color", get_rarity_color(equipped_item.get("rarity", "common")))
			
			slot_button.pressed.connect(_on_equipment_slot_pressed.bind(i, slot))
			equipment_list.add_child(slot_button)
		
		var separator = HSeparator.new()
		equipment_list.add_child(separator)

func create_item_button(item: Dictionary, is_equipped: bool) -> Button:
	var button = Button.new()
	var prefix = "[E] " if is_equipped else ""
	button.text = "%s%s (%s)" % [prefix, item.name, item.get("rarity", "common")]
	button.add_theme_color_override("font_color", get_rarity_color(item.get("rarity", "common")))
	button.custom_minimum_size = Vector2(200, 30)
	button.pressed.connect(_on_item_pressed.bind(item))
	return button

# ========================================
# 아이템 정보 표시
# ========================================

func show_item_info(item: Dictionary):
	selected_item = item
	
	if not item_info:
		return
	
	var info_text = "[%s] %s\n\n" % [item.get("rarity", "?").to_upper(), item.name]
	info_text += "Type: %s\n" % item.get("type", "Unknown")
	info_text += "Slot: %s\n\n" % item.get("slot", "None")
	
	if item.has("stats"):
		info_text += "Stats:\n"
		var stats = item.stats
		if stats.has("attack") and stats.attack > 0:
			info_text += "  ATK +%d\n" % stats.attack
		if stats.has("defense") and stats.defense > 0:
			info_text += "  DEF +%d\n" % stats.defense
		if stats.has("hp") and stats.hp > 0:
			info_text += "  HP +%d\n" % stats.hp
		if stats.has("luck") and stats.luck > 0:
			info_text += "  LUCK +%d\n" % stats.luck
	
	info_text += "\n%s" % item.get("description", "")
	item_info.text = info_text

# ========================================
# 장비 장착/해제
# ========================================

func equip_item(hero_index: int, item: Dictionary):
	if hero_index >= GameManager.party.size():
		return
	
	var hero = GameManager.party[hero_index]
	var slot = item.get("slot", "")
	
	if slot.is_empty():
		return
	
	var old_item = get_equipped_item(hero, slot)
	if not old_item.is_empty():
		unequip_item(hero_index, slot)
	
	if not hero.has("equipped"):
		hero["equipped"] = {}
	
	hero.equipped[slot] = item.id
	GameManager.inventory.erase(item)
	apply_item_stats(hero, item, true)
	
	print("[Inventory] %s equipped %s" % [hero.name, item.name])
	refresh_ui()

func unequip_item(hero_index: int, slot: String):
	if hero_index >= GameManager.party.size():
		return
	
	var hero = GameManager.party[hero_index]
	
	if not hero.has("equipped") or not hero.equipped.has(slot):
		return
	
	var item_id = hero.equipped[slot]
	var item = DataManager.get_item(item_id)
	
	if item.is_empty():
		return
	
	apply_item_stats(hero, item, false)
	GameManager.inventory.append(item)
	hero.equipped.erase(slot)
	
	print("[Inventory] %s unequipped %s" % [hero.name, item.name])
	refresh_ui()

func apply_item_stats(hero: Dictionary, item: Dictionary, is_equip: bool):
	if not item.has("stats"):
		return
	
	var stats = item.stats
	var mult = 1 if is_equip else -1
	
	if stats.has("attack"):
		hero.base_stats.attack += stats.attack * mult
	if stats.has("defense"):
		hero.base_stats.defense += stats.defense * mult
	if stats.has("hp"):
		hero.base_stats.hp += stats.hp * mult
		hero.current_hp = min(hero.current_hp, hero.base_stats.hp)

func get_equipped_item(hero: Dictionary, slot: String) -> Dictionary:
	if not hero.has("equipped") or not hero.equipped.has(slot):
		return {}
	return DataManager.get_item(hero.equipped[slot])

# ========================================
# 이벤트
# ========================================

func _on_item_pressed(item: Dictionary):
	show_item_info(item)
	selected_item = item

func _on_equipment_slot_pressed(hero_index: int, slot: String):
	selected_hero_index = hero_index
	var hero = GameManager.party[hero_index]
	var equipped = get_equipped_item(hero, slot)
	
	if not equipped.is_empty():
		unequip_item(hero_index, slot)
	elif not selected_item.is_empty() and selected_item.get("slot") == slot:
		equip_item(hero_index, selected_item)

func _on_close_pressed():
	close_ui()

func close_ui():
	closed.emit()
	queue_free()

func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color.WHITE
		"magic": return Color.CYAN
		"unique": return Color.GOLD
		"legendary": return Color.ORANGE
		_: return Color.WHITE
