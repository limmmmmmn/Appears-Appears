extends Control
## Town: 회복/상점/정비/출발

signal depart_requested

const DQThemeScript := preload("res://scripts/ui/dq_theme.gd")

@onready var town_name: Label = $TownName
@onready var rest_button: Button = $Panel/VBox/RestButton
@onready var shop_button: Button = $Panel/VBox/ShopButton
@onready var party_button: Button = $Panel/VBox/PartyButton
@onready var depart_button: Button = $Panel/VBox/DepartButton
@onready var message: Label = $Message
@onready var shop_panel: PanelContainer = $ShopPanel
@onready var shop_list: VBoxContainer = $ShopPanel/ShopVBox/ItemList
@onready var shop_close_button: Button = $ShopPanel/ShopVBox/CloseButton
@onready var shop_gold_label: Label = $ShopPanel/ShopVBox/Header/GoldLabel

var _node_data: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	DQThemeScript.apply_full(self)
	rest_button.pressed.connect(_on_rest)
	shop_button.pressed.connect(_on_shop_open)
	party_button.pressed.connect(_on_party)
	depart_button.pressed.connect(_on_depart)
	shop_close_button.pressed.connect(_on_shop_close)
	shop_panel.visible = false
	GameManager.gold_changed.connect(_refresh_shop_gold)
	rest_button.grab_focus()

func setup(node_data: Dictionary) -> void:
	_node_data = node_data
	town_name.text = String(node_data.get("name", "마을"))

func _on_rest() -> void:
	GameManager.heal_full()
	message.text = "푹 쉬었다. HP/MP 완전 회복."

func _on_shop_open() -> void:
	for c in shop_list.get_children():
		c.queue_free()
	var items := DataLoader.load_all_equipment()
	items.sort_custom(func(a, b) -> bool: return int(a.get("buy_price", 0)) < int(b.get("buy_price", 0)))
	for item in items:
		_add_shop_row(item)
	_refresh_shop_gold()
	shop_panel.visible = true

func _refresh_shop_gold(_amount: int = 0) -> void:
	if shop_gold_label:
		shop_gold_label.text = "소지금: %dG" % GameManager.gold

func _add_shop_row(item: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = String(item.get("name", ""))
	name_label.custom_minimum_size = Vector2(160, 0)
	row.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = "+%s" % _stat_summary(item)
	desc_label.custom_minimum_size = Vector2(160, 0)
	row.add_child(desc_label)
	var price_label := Label.new()
	price_label.text = "%dG" % int(item.get("buy_price", 0))
	price_label.custom_minimum_size = Vector2(90, 0)
	row.add_child(price_label)
	var buy := Button.new()
	buy.text = "구매"
	buy.pressed.connect(func() -> void: _try_buy(item))
	row.add_child(buy)
	shop_list.add_child(row)
	DQThemeScript.apply_label_color(row)

func _stat_summary(item: Dictionary) -> String:
	var parts: Array[String] = []
	var str_b := int(item.get("str_bonus", 0))
	var vit_b := int(item.get("vit_bonus", 0))
	var agi_b := int(item.get("agi_bonus", 0))
	var int_b := int(item.get("int_bonus", 0))
	if str_b != 0: parts.append("STR%+d" % str_b)
	if vit_b != 0: parts.append("VIT%+d" % vit_b)
	if agi_b != 0: parts.append("AGI%+d" % agi_b)
	if int_b != 0: parts.append("INT%+d" % int_b)
	return " ".join(parts) if parts.size() > 0 else "-"

func _try_buy(item: Dictionary) -> void:
	var price := int(item.get("buy_price", 0))
	if GameManager.spend_gold(price):
		var first: Dictionary = GameManager.party_members[0] if GameManager.party_members.size() > 0 else {}
		if not first.is_empty():
			first["base_str"] = int(first.get("base_str", 0)) + int(item.get("str_bonus", 0))
			first["base_vit"] = int(first.get("base_vit", 0)) + int(item.get("vit_bonus", 0))
			first["base_agi"] = int(first.get("base_agi", 0)) + int(item.get("agi_bonus", 0))
			first["base_int"] = int(first.get("base_int", 0)) + int(item.get("int_bonus", 0))
		message.text = "%s 구매 완료!" % item.get("name", "")
	else:
		message.text = "골드가 부족하다."

func _on_shop_close() -> void:
	shop_panel.visible = false

func _on_party() -> void:
	var names: Array[String] = []
	for m in GameManager.party_members:
		names.append(String(m.get("name", "?")))
	message.text = "파티: " + ", ".join(names)

func _on_depart() -> void:
	depart_requested.emit()
