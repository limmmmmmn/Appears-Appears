# scripts/ui/InventoryUI.gd
# I 키로 열기, 아이템 장착/해제
extends Panel

signal closed

# UI 참조
@onready var inventory_list = $HSplitContainer/InventoryPanel/InventoryList
@onready var equipment_list = $HSplitContainer/EquipmentPanel/EquipmentList
@onready var item_info = $HSplitContainer/EquipmentPanel/ItemInfo
@onready var close_button = $CloseButton

# 선택된 아이템
var selected_item: Dictionary = {}
var selected_hero_index: int = 0

func _ready():
	print("[InventoryUI] Created")
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	refresh_ui()

func _input(event):
	if event.is_action_pressed("ui_cancel"):  # ESC
		close_ui()

func refresh_ui():
	refresh_inventory()
	refresh_equipment()

# ========================================
# 인벤토리 표시
# ========================================

func refresh_inventory():
	# 기존 제거
	for child in inventory_list.get_children():
		child.queue_free()
	
	# 인벤토리 아이템 표시
	for item in GameManager.inventory:
		var button = create_item_button(item, false)
		inventory_list.add_child(button)
	
	# 빈 슬롯 표시
	var empty_slots = 20 - GameManager.inventory.size()
	for i in range(empty_slots):
		var empty_label = Label.new()
		empty_label.text = "[ Empty ]"
		empty_label.add_theme_color_override("font_color", Color.GRAY)
		inventory_list.add_child(empty_label)

func refresh_equipment():
	# 기존 제거
	for child in equipment_list.get_children():
		child.queue_free()
	
	# 파티원별 장비 표시
	for i in range(GameManager.party.size()):
		var hero = GameManager.party[i]
		
		# 영웅 이름
		var hero_label = Label.new()
		hero_label.text = "=== %s ===" % hero.name
		hero_label.add_theme_color_override("font_color", Color.YELLOW)
		equipment_list.add_child(hero_label)
		
		# 장비 슬롯
		var slots = ["weapon", "armor", "accessory"]
		for slot in slots:
			var slot_button = Button.new()
			
			var equipped_item = get_equipped_item(hero, slot)
			if equipped_item.is_empty():
				slot_button.text = "[%s] - Empty" % slot.capitalize()
				slot_button.add_theme_color_override("font_color", Color.GRAY)
			else:
				slot_button.text = "[%s] %s" % [slot.capitalize(), equipped_item.name]
				slot_button.add_theme_color_override("font_color", get_rarity_color(equipped_item.rarity))
			
			slot_button.pressed.connect(_on_equipment_slot_pressed.bind(i, slot))
			equipment_list.add_child(slot_button)
		
		# 구분선
		var separator = HSeparator.new()
		equipment_list.add_child(separator)

func create_item_button(item: Dictionary, is_equipped: bool) -> Button:
	var button = Button.new()
	
	var prefix = "[E] " if is_equipped else ""
	button.text = "%s%s (%s)" % [prefix, item.name, item.rarity]
	button.add_theme_color_override("font_color", get_rarity_color(item.rarity))
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
	
	var info_text = "[%s] %s\n\n" % [item.rarity.to_upper(), item.name]
	info_text += "Type: %s\n" % item.get("type", "Unknown")
	info_text += "Slot: %s\n\n" % item.get("slot", "None")
	
	if item.has("stats"):
		info_text += "Stats:\n"
		var stats = item.stats
		if stats.has("attack"):
			info_text += "  ATK +%d\n" % stats.attack
		if stats.has("defense"):
			info_text += "  DEF +%d\n" % stats.defense
		if stats.has("hp"):
			info_text += "  HP +%d\n" % stats.hp
		if stats.has("luck"):
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
		print("Item has no slot!")
		return
	
	# 기존 장비 해제
	var old_item = get_equipped_item(hero, slot)
	if not old_item.is_empty():
		unequip_item(hero_index, slot)
	
	# 새 장비 장착
	if not hero.has("equipped"):
		hero["equipped"] = {}
	
	hero.equipped[slot] = item.id
	
	# 인벤토리에서 제거
	GameManager.inventory.erase(item)
	
	# 스탯 적용
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
	
	# 스탯 제거
	apply_item_stats(hero, item, false)
	
	# 인벤토리로 복귀
	GameManager.inventory.append(item)
	
	# 장비 슬롯 비우기
	hero.equipped.erase(slot)
	
	print("[Inventory] %s unequipped %s" % [hero.name, item.name])
	refresh_ui()

func apply_item_stats(hero: Dictionary, item: Dictionary, is_equip: bool):
	if not item.has("stats"):
		return
	
	var stats = item.stats
	var multiplier = 1 if is_equip else -1
	
	if stats.has("attack"):
		hero.base_stats.attack += stats.attack * multiplier
	if stats.has("defense"):
		hero.base_stats.defense += stats.defense * multiplier
	if stats.has("hp"):
		hero.base_stats.hp += stats.hp * multiplier
		hero.current_hp = min(hero.current_hp, hero.base_stats.hp)
	if stats.has("luck"):
		hero.base_stats.luck += stats.luck * multiplier
	if stats.has("attack_speed"):
		hero.base_stats.attack_speed += stats.attack_speed * multiplier

func get_equipped_item(hero: Dictionary, slot: String) -> Dictionary:
	if not hero.has("equipped") or not hero.equipped.has(slot):
		return {}
	
	return DataManager.get_item(hero.equipped[slot])

# ========================================
# 이벤트 핸들러
# ========================================

func _on_item_pressed(item: Dictionary):
	show_item_info(item)
	selected_item = item

func _on_equipment_slot_pressed(hero_index: int, slot: String):
	selected_hero_index = hero_index
	
	# 장비 해제 또는 새 장비 장착
	var hero = GameManager.party[hero_index]
	var equipped = get_equipped_item(hero, slot)
	
	if not equipped.is_empty():
		# 이미 장착 중 → 해제
		unequip_item(hero_index, slot)
	elif not selected_item.is_empty() and selected_item.get("slot") == slot:
		# 선택된 아이템이 있고 슬롯 맞으면 장착
		equip_item(hero_index, selected_item)

func _on_close_pressed():
	close_ui()

func close_ui():
	closed.emit()
	queue_free()

# ========================================
# 유틸리티
# ========================================

func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color.WHITE
		"magic":
			return Color.CYAN
		"unique":
			return Color.GOLD
		"legendary":
			return Color.ORANGE
		_:
			return Color.WHITE
