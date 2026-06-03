class_name RightUpgradePanel
extends PanelContainer

## Right zone — DOS-style tabbed window. Two tabs:
##   [업그레이드] every spend-gold upgrade as a uniform row: [icon] name  price / desc
##   [장비]       weapon + armor shop (buy) AND inventory (equip / sell) in one place
## Flat single-tone boxes, one font, one border — only item sprites keep their color.

const ICON_WEAPON: Texture2D = preload("res://assets/sprites/icons/hero_sword.png")
const ICON_ARMOR: Texture2D = preload("res://assets/sprites/icons/shield.png")
const ICON_GOLD: Texture2D = preload("res://assets/sprites/icons/gold.png")

const TAB_UPGRADE: StringName = &"upgrade"
const TAB_GEAR: StringName = &"gear"

var _tab_buttons: Dictionary = {}
var _content: VBoxContainer
var _active_tab: StringName = TAB_UPGRADE
var _rows: Array[Dictionary] = []   ## {button, cost} — for live affordability re-tint


func _ready() -> void:
	var x: float = UITheme.right_panel_left()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = x
	offset_top = 17.0  # clear the menu bar
	offset_right = 640.0
	offset_bottom = 360.0
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_theme_stylebox_override("panel", DOS.box_style())
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("upgrade_window")
	_build()
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


# ─── Shell ─────────────────────────────────────────────────────────────
func _build() -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	add_child(col)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	col.add_child(tabs)
	_tab_buttons.clear()
	_tab_buttons[TAB_UPGRADE] = _add_tab(tabs, "강화", TAB_UPGRADE)
	_tab_buttons[TAB_GEAR] = _add_tab(tabs, "장비", TAB_GEAR)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0.0, 200.0)
	col.add_child(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 2)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_show_tab(_active_tab)


func _add_tab(parent: HBoxContainer, text: String, id: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_override("font", DOS.FONT)
	b.add_theme_font_size_override("font_size", DOS.FONT_SIZE)
	DOS.style_button(b)
	b.pressed.connect(_on_tab.bind(id))
	parent.add_child(b)
	return b


func _on_tab(id: StringName) -> void:
	_active_tab = id
	_show_tab(id)


func _show_tab(id: StringName) -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	_rows.clear()
	for tid in _tab_buttons:
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
		{"icon": ICON_ARMOR, "name": "방어 루팅", "desc": "Lv%d 장비 드롭" % GameState.armor_loot_level,
			"price": GameState.armor_loot_cost(), "afford": GameState.can_upgrade_armor_loot(), "maxed": false, "kind": &"armor_loot"},
		{"icon": ICON_GOLD, "name": "운", "desc": "대박 %.0f%%" % (GameState.luck_jackpot_chance() * 100.0),
			"price": GameState.luck_upgrade_cost(), "afford": GameState.can_upgrade_luck(), "maxed": GameState.luck_is_maxed(), "kind": &"luck"},
		{"icon": ICON_GOLD, "name": "멀티 전투창", "desc": ("무제한" if GameState.scale_is_maxed() else "1개"),
			"price": GameState.scale_upgrade_cost(), "afford": GameState.can_upgrade_scale(), "maxed": GameState.scale_is_maxed(), "kind": &"scale"},
		{"icon": ICON_GOLD, "name": "보상 개봉", "desc": "%.2fs" % GameState.chest_hover_duration(),
			"price": GameState.open_speed_upgrade_cost(), "afford": GameState.can_upgrade_open_speed(), "maxed": GameState.open_speed_is_maxed(), "kind": &"open_speed"},
		{"icon": ICON_GOLD, "name": "자동 줍기", "desc": ("자동" if GameState.auto_pickup_unlocked else "수동(호버)"),
			"price": GameState.auto_pickup_cost(), "afford": GameState.can_unlock_auto_pickup(), "maxed": GameState.auto_pickup_unlocked, "kind": &"auto_pickup"},
	]


func _add_upgrade_row(u: Dictionary) -> void:
	var maxed: bool = u["maxed"]
	var afford: bool = u["afford"]
	var price_text: String = "MAX" if maxed else "%dG" % int(u["price"])
	var b := Button.new()
	DOS.style_button(b)
	b.disabled = maxed or not afford
	b.pressed.connect(_on_upgrade.bind(u["kind"]))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	top.add_child(DOS.icon(u["icon"]))
	var name_lbl := DOS.label(str(u["name"]))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true
	top.add_child(name_lbl)
	top.add_child(DOS.label(price_text, DOS.TEXT if (afford or maxed) else DOS.DIM))
	vb.add_child(DOS.label(str(u["desc"]), DOS.DIM))
	b.modulate = Color(1, 1, 1, 1) if (afford or maxed) else Color(0.62, 0.64, 0.68, 1.0)
	b.custom_minimum_size = Vector2(0.0, DOS.ROW_H + 9.0)
	_content.add_child(b)
	_rows.append({"button": b, "cost": 99999999 if maxed else int(u["price"])})


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
	var b := Button.new()
	DOS.style_button(b)
	b.disabled = not afford
	b.pressed.connect(action)
	b.custom_minimum_size = Vector2(0.0, DOS.ROW_H)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(DOS.icon(icon))
	var n := DOS.label(name_text)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	row.add_child(n)
	row.add_child(DOS.label("%dG" % cost, DOS.TEXT if afford else DOS.DIM))
	b.modulate = Color(1, 1, 1, 1) if afford else Color(0.62, 0.64, 0.68, 1.0)
	_content.add_child(b)
	_rows.append({"button": b, "cost": cost})


## Inventory row: [icon] name Lv  → click equips; [N] button sells.
func _add_inventory_row(inv_index: int, entry, item: ItemData) -> void:
	var lvl: int = GameState.item_entry_level(entry)
	var val: int = GameState.inventory_sell_value(entry)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_content.add_child(row)

	var equip_btn := Button.new()
	DOS.style_button(equip_btn)
	equip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_btn.custom_minimum_size = Vector2(0.0, DOS.ROW_H)
	equip_btn.tooltip_text = "클릭: 장착"
	equip_btn.pressed.connect(_on_equip_inventory.bind(inv_index))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 3)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equip_btn.add_child(inner)
	inner.add_child(DOS.icon(item.icon))
	var n := DOS.label("%s Lv%d" % [item.display_name, lvl])
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	inner.add_child(n)
	row.add_child(equip_btn)

	var sell_btn := Button.new()
	sell_btn.text = "%dG" % val
	sell_btn.add_theme_font_override("font", DOS.FONT)
	sell_btn.add_theme_font_size_override("font_size", DOS.FONT_SIZE)
	sell_btn.add_theme_color_override("font_color", DOS.TEXT)
	DOS.style_button(sell_btn)
	sell_btn.custom_minimum_size = Vector2(22.0, DOS.ROW_H)
	sell_btn.tooltip_text = "팔기"
	sell_btn.pressed.connect(_on_sell_inventory.bind(inv_index))
	row.add_child(sell_btn)
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
