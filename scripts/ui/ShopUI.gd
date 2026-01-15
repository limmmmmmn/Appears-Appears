# scripts/ui/ShopUI.gd
# 상점: 아이템 구매/판매
extends Panel

signal closed

@onready var shop_list = $HSplitContainer/ShopPanel/ShopList
@onready var inventory_list = $HSplitContainer/InventoryPanel/InventoryList
@onready var gold_label = $GoldLabel
@onready var close_button = $CloseButton

# 상점 재고
var shop_items: Array = []

func _ready():
	print("[ShopUI] Created")
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	generate_shop_items()
	refresh_ui()

func generate_shop_items():
	# 상점 아이템 생성 (랜덤 or 고정)
	shop_items.clear()
	
	if DataManager.items.has("items"):
		var all_items = []
		for item_id in DataManager.items.items:
			var item = DataManager.items.items[item_id]
			if item.get("enabled", true) and item.get("type") != "consumable":
				all_items.append(item)
		
		all_items.shuffle()
		
		# 6개 아이템만
		for i in range(min(6, all_items.size())):
			shop_items.append(all_items[i])
	
	print("[ShopUI] Generated %d items" % shop_items.size())

func refresh_ui():
	refresh_shop()
	refresh_inventory()
	update_gold_display()

func update_gold_display():
	if gold_label:
		gold_label.text = "💰 %d Gold" % GameManager.gold

# ========================================
# 상점 목록
# ========================================

func refresh_shop():
	for child in shop_list.get_children():
		child.queue_free()
	
	var title = Label.new()
	title.text = "=== 구매 ==="
	title.add_theme_color_override("font_color", Color.YELLOW)
	shop_list.add_child(title)
	
	for item in shop_items:
		var button = Button.new()
		var price = item.get("shop_price", 100)
		
		button.text = "%s\n💰 %d" % [item.name, price]
		button.custom_minimum_size = Vector2(150, 50)
		button.add_theme_color_override("font_color", get_rarity_color(item.rarity))
		
		if GameManager.gold < price:
			button.disabled = true
		
		button.pressed.connect(_on_buy_pressed.bind(item))
		shop_list.add_child(button)

# ========================================
# 인벤토리 (판매용)
# ========================================

func refresh_inventory():
	for child in inventory_list.get_children():
		child.queue_free()
	
	var title = Label.new()
	title.text = "=== 판매 ==="
	title.add_theme_color_override("font_color", Color.YELLOW)
	inventory_list.add_child(title)
	
	for item in GameManager.inventory:
		var button = Button.new()
		var sell_price = item.get("sell_price", 10)
		
		button.text = "%s\n💰 %d" % [item.name, sell_price]
		button.custom_minimum_size = Vector2(150, 50)
		button.add_theme_color_override("font_color", get_rarity_color(item.rarity))
		
		button.pressed.connect(_on_sell_pressed.bind(item))
		inventory_list.add_child(button)

# ========================================
# 구매/판매
# ========================================

func _on_buy_pressed(item: Dictionary):
	var price = item.get("shop_price", 100)
	
	if GameManager.gold < price:
		print("[Shop] Not enough gold!")
		return
	
	if GameManager.inventory.size() >= 20:
		print("[Shop] Inventory full!")
		return
	
	GameManager.spend_gold(price)
	GameManager.add_item(item.id)
	
	# 상점에서 제거
	shop_items.erase(item)
	
	print("[Shop] Bought %s for %d gold" % [item.name, price])
	refresh_ui()

func _on_sell_pressed(item: Dictionary):
	var sell_price = item.get("sell_price", 10)
	
	GameManager.add_gold(sell_price)
	GameManager.inventory.erase(item)
	
	print("[Shop] Sold %s for %d gold" % [item.name, sell_price])
	refresh_ui()

func _on_close_pressed():
	closed.emit()
	queue_free()

func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color.WHITE
		"magic":
			return Color.CYAN
		"unique":
			return Color.GOLD
		_:
			return Color.WHITE
