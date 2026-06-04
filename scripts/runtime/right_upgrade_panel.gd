class_name RightUpgradePanel
extends PanelContainer

## Right zone — DOS-style tabbed window. Two tabs:
##   [강화]  every spend-gold upgrade as a uniform row: [icon] name  price / desc
##   [장비]  weapon + armor shop (buy) AND inventory (equip / sell) in one place
##
## LOOK = scenes/ui/right_upgrade_panel.tscn (card position/size, tabs, scroll, the
## panel background via the theme) + the row templates dos_upgrade_row.tscn /
## dos_row.tscn / dos_inventory_row.tscn — all editable in the editor. This script
## is LOGIC ONLY: which rows exist, what they cost, and what clicking does.

const ICON_WEAPON: Texture2D = preload("res://assets/sprites/icons/hero_sword.png")
const ICON_ARMOR: Texture2D = preload("res://assets/sprites/icons/shield.png")
const ICON_GOLD: Texture2D = preload("res://assets/sprites/icons/gold.png")

const UPGRADE_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_upgrade_row.tscn")
const SHOP_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_row.tscn")
const INVENTORY_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_inventory_row.tscn")

const TAB_UPGRADE: StringName = &"upgrade"
const TAB_GEAR: StringName = &"gear"

@onready var _content: VBoxContainer = %Content

var _tab_buttons: Dictionary = {}
var _active_tab: StringName = TAB_UPGRADE
var _rows: Array[Dictionary] = []   ## {button, cost} — for live affordability re-tint


func _ready() -> void:
	add_to_group("upgrade_window")
	_tab_buttons = {TAB_UPGRADE: %TabUpgrade, TAB_GEAR: %TabGear}
	(%TabUpgrade as Button).pressed.connect(_on_tab.bind(TAB_UPGRADE))
	(%TabGear as Button).pressed.connect(_on_tab.bind(TAB_GEAR))
	_show_tab(_active_tab)
	# Gold ticks only re-tint affordability (no rebuild → no flicker). Structural
	# changes (purchases, inventory, equips) rebuild the active tab.
	EventBus.gold_changed.connect(_refresh_afford.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))
	EventBus.inventory_changed.connect(_on_changed)
	EventBus.party_equipment_changed.connect(_on_changed.unbind(1))
	EventBus.weapon_equipped.connect(_on_changed.unbind(1))
	EventBus.armor_equipped.connect(_on_changed.unbind(1))


# ─── Window open/close (menu bar 강화 toggle) ───────────────────────────
func open() -> void:
	visible = true
	_show_tab(_active_tab)


func close() -> void:
	visible = false


func toggle() -> void:
	visible = not visible


func _on_changed() -> void:
	if visible:
		_show_tab(_active_tab)


## Gold tick → re-tint affordability of the existing rows (no rebuild).
func _refresh_afford() -> void:
	if not visible:
		return
	for r: Dictionary in _rows:
		var b: Button = r["button"]
		if not is_instance_valid(b):
			continue
		var cost: int = r["cost"]
		var afford: bool = GameState.gold >= cost
		b.modulate = Color(1, 1, 1, 1) if afford else Color(0.62, 0.64, 0.68, 1.0)
		if cost > 0:
			b.disabled = not afford


# ─── Tabs ──────────────────────────────────────────────────────────────
func _on_tab(id: StringName) -> void:
	_active_tab = id
	_show_tab(id)


func _show_tab(id: StringName) -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	_rows.clear()
	for tid: StringName in _tab_buttons:
		var tb: Button = _tab_buttons[tid]
		tb.add_theme_color_override("font_color", DOS.TEXT if tid == id else DOS.DIM)
		tb.modulate = Color(1, 1, 1, 1) if tid == id else Color(0.8, 0.82, 0.85, 1.0)
	match id:
		TAB_UPGRADE: _build_upgrade_tab()
		TAB_GEAR: _build_gear_tab()


# ─── 강화 tab ──────────────────────────────────────────────────────────
func _build_upgrade_tab() -> void:
	for u: Dictionary in _upgrade_items():
		_add_upgrade_row(u)


## Each upgrade kind as a uniform data row.
func _upgrade_items() -> Array[Dictionary]:
	return [
		{"icon": ICON_WEAPON, "name": "무기 루팅", "desc": "Lv%d 장비 드롭" % GameState.weapon_loot_level,
			"price": GameState.weapon_loot_cost(), "afford": GameState.can_upgrade_weapon_loot(), "maxed": false, "kind": &"weapon_loot"},
		{"icon": ICON_ARMOR, "name": "방어구 루팅", "desc": "Lv%d 장비 드롭" % GameState.armor_loot_level,
			"price": GameState.armor_loot_cost(), "afford": GameState.can_upgrade_armor_loot(), "maxed": false, "kind": &"armor_loot"},
		{"icon": ICON_GOLD, "name": "운", "desc": "대박 %.0f%%" % (GameState.luck_jackpot_chance() * 100.0),
			"price": GameState.luck_upgrade_cost(), "afford": GameState.can_upgrade_luck(), "maxed": GameState.luck_is_maxed(), "kind": &"luck"},
		{"icon": ICON_GOLD, "name": "멀티 전투창", "desc": "현재 %d개" % GameState.scale_window_count(),
			"price": GameState.scale_upgrade_cost(), "afford": GameState.can_upgrade_scale(), "maxed": false, "kind": &"scale"},
		{"icon": ICON_GOLD, "name": "보상 개봉", "desc": "%.2fs" % GameState.chest_hover_duration(),
			"price": GameState.open_speed_upgrade_cost(), "afford": GameState.can_upgrade_open_speed(), "maxed": GameState.open_speed_is_maxed(), "kind": &"open_speed"},
		{"icon": ICON_GOLD, "name": "자동 줍기", "desc": ("자동" if GameState.auto_pickup_unlocked else "수동(호버)"),
			"price": GameState.auto_pickup_cost(), "afford": GameState.can_unlock_auto_pickup(), "maxed": GameState.auto_pickup_unlocked, "kind": &"auto_pickup"},
	]


func _add_upgrade_row(u: Dictionary) -> void:
	var maxed: bool = u["maxed"]
	var afford: bool = u["afford"]
	var price_text: String = "MAX" if maxed else "%dG" % int(u["price"])
	var row: Button = UPGRADE_ROW_SCENE.instantiate()
	row.disabled = maxed or not afford
	(row.get_node("VBox/Top/Icon") as TextureRect).texture = u["icon"]
	(row.get_node("VBox/Top/Name") as Label).text = str(u["name"])
	var price_lbl := row.get_node("VBox/Top/Price") as Label
	price_lbl.text = price_text
	price_lbl.add_theme_color_override("font_color", DOS.TEXT if (afford or maxed) else DOS.DIM)
	(row.get_node("VBox/Desc") as Label).text = str(u["desc"])
	row.modulate = Color(1, 1, 1, 1) if (afford or maxed) else Color(0.62, 0.64, 0.68, 1.0)
	row.pressed.connect(_on_upgrade.bind(u["kind"]))
	_content.add_child(row)
	_rows.append({"button": row, "cost": 99999999 if maxed else int(u["price"])})


func _on_upgrade(kind: StringName) -> void:
	match kind:
		&"weapon_loot": GameState.upgrade_weapon_loot()
		&"armor_loot": GameState.upgrade_armor_loot()
		&"luck": GameState.upgrade_luck()
		&"scale": GameState.upgrade_scale()
		&"open_speed": GameState.upgrade_open_speed()
		&"auto_pickup": GameState.unlock_auto_pickup()


# ─── 장비 tab (buy / equip / sell) ─────────────────────────────────────
func _build_gear_tab() -> void:
	_content.add_child(DOS.section("구매"))
	for type_id: StringName in GameState.owned_weapon_types():
		var lvl: int = GameState.weapon_level(type_id)
		var next_name: String = Balance.weapon_name_for(type_id, lvl + 1)
		var cost: int = GameState.weapon_upgrade_cost(type_id)
		_add_shop_row(ICON_WEAPON, next_name, cost, GameState.gold >= cost, _on_buy_weapon.bind(type_id))
	var a_cost: int = GameState.armor_upgrade_cost()
	_add_shop_row(ICON_ARMOR, GameState.next_armor_name(), a_cost, GameState.gold >= a_cost, _on_buy_armor)

	_content.add_child(DOS.section("보유 장비"))
	var items: Array = GameState.inventory_items()
	var any: bool = false
	for i in items.size():
		var item: ItemData = GameState.item_entry_data(items[i])
		if item == null:
			continue
		any = true
		_add_inventory_row(i, items[i], item)
	if not any:
		_content.add_child(DOS.label("(없음)", DOS.DIM))


func _add_shop_row(icon: Texture2D, name_text: String, cost: int, afford: bool, action: Callable) -> void:
	var row: Button = SHOP_ROW_SCENE.instantiate()
	row.disabled = not afford
	(row.get_node("HBox/Icon") as TextureRect).texture = icon
	(row.get_node("HBox/Name") as Label).text = name_text
	var tag := row.get_node("HBox/Tag") as Label
	tag.text = "%dG" % cost
	tag.add_theme_color_override("font_color", DOS.TEXT if afford else DOS.DIM)
	row.modulate = Color(1, 1, 1, 1) if afford else Color(0.62, 0.64, 0.68, 1.0)
	row.pressed.connect(action)
	_content.add_child(row)
	_rows.append({"button": row, "cost": cost})


## Inventory row: [icon] name Lv  → click equips; [N] button sells.
func _add_inventory_row(inv_index: int, entry, item: ItemData) -> void:
	var lvl: int = GameState.item_entry_level(entry)
	var val: int = GameState.inventory_sell_value(entry)
	var row: HBoxContainer = INVENTORY_ROW_SCENE.instantiate()
	var equip_btn := row.get_node("Equip") as Button
	(row.get_node("Equip/Inner/Icon") as TextureRect).texture = item.icon
	(row.get_node("Equip/Inner/Name") as Label).text = "%s Lv%d" % [item.display_name, lvl]
	equip_btn.pressed.connect(_on_equip_inventory.bind(inv_index))
	var sell_btn := row.get_node("Sell") as Button
	sell_btn.text = "%dG" % val
	sell_btn.pressed.connect(_on_sell_inventory.bind(inv_index))
	_content.add_child(row)
	_rows.append({"button": equip_btn, "cost": 0})  # equip/sell always available
	_rows.append({"button": sell_btn, "cost": 0})


func _on_buy_weapon(type_id: StringName) -> void:
	GameState.upgrade_weapon(type_id)


func _on_buy_armor() -> void:
	GameState.upgrade_armor()


func _on_sell_inventory(inv_index: int) -> void:
	GameState.sell_inventory_entry_at(inv_index)


func _on_equip_inventory(inv_index: int) -> void:
	var items: Array = GameState.inventory_items()
	if inv_index < 0 or inv_index >= items.size():
		return
	var item: ItemData = GameState.item_entry_data(items[inv_index])
	if item == null:
		return
	var member: int = _member_for(item)
	if member < 0:
		return
	var slot: int = GameState.slot_index_for_item(item)
	if slot < 0:
		return
	GameState.equip_inventory_item_to(inv_index, member, slot)


func _member_for(item: ItemData) -> int:
	if item.allowed_character_id == &"":
		return 0
	for i in GameState.party.size():
		if GameState.party[i].id == item.allowed_character_id:
			return i
	return -1
