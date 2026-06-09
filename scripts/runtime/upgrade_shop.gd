class_name UpgradeShop
extends RefCounted

const ICON_WEAPON: Texture2D = preload("res://assets/sprites/icons/hero_sword.png")
const ICON_ARMOR: Texture2D = preload("res://assets/sprites/icons/shield.png")
const ICON_GOLD: Texture2D = preload("res://assets/sprites/icons/gold.png")
const UPGRADE_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_upgrade_row.tscn")


static func build(parent: VBoxContainer) -> void:
	if parent == null:
		return
	var title := DOS.section("강화")
	parent.add_child(title)
	for item: Dictionary in upgrade_items():
		parent.add_child(make_upgrade_row(item))


static func upgrade_items() -> Array[Dictionary]:
	return [
		{"icon": ICON_WEAPON, "name": "무기 루팅", "desc": "Lv%d 장비 드롭" % GameState.weapon_loot_level,
			"price": GameState.weapon_loot_cost(), "afford": GameState.can_upgrade_weapon_loot(), "maxed": false, "kind": &"weapon_loot"},
		{"icon": ICON_ARMOR, "name": "방어구 루팅", "desc": "Lv%d 장비 드롭" % GameState.armor_loot_level,
			"price": GameState.armor_loot_cost(), "afford": GameState.can_upgrade_armor_loot(), "maxed": false, "kind": &"armor_loot"},
		{"icon": ICON_GOLD, "name": "운", "desc": "대박 %.0f%%" % (GameState.luck_jackpot_chance() * 100.0),
			"price": GameState.luck_upgrade_cost(), "afford": GameState.can_upgrade_luck(), "maxed": GameState.luck_is_maxed(), "kind": &"luck"},
		{"icon": ICON_GOLD, "name": "멀티 전투창", "desc": "현재 %d개" % GameState.scale_window_count(),
			"price": GameState.scale_upgrade_cost(), "afford": GameState.can_upgrade_scale(), "maxed": GameState.scale_is_maxed(), "kind": &"scale"},
		{"icon": ICON_GOLD, "name": "보상 개봉", "desc": "%.2fs" % GameState.chest_hover_duration(),
			"price": GameState.open_speed_upgrade_cost(), "afford": GameState.can_upgrade_open_speed(), "maxed": GameState.open_speed_is_maxed(), "kind": &"open_speed"},
		{"icon": ICON_GOLD, "name": "자동 줍기", "desc": ("자동" if GameState.auto_pickup_unlocked else "수동(호버)"),
			"price": GameState.auto_pickup_cost(), "afford": GameState.can_unlock_auto_pickup(), "maxed": GameState.auto_pickup_unlocked, "kind": &"auto_pickup"},
	]


static func make_upgrade_row(item: Dictionary) -> Button:
	var maxed: bool = bool(item.get("maxed", false))
	var afford: bool = bool(item.get("afford", false))
	var row: Button = UPGRADE_ROW_SCENE.instantiate()
	row.disabled = maxed or not afford
	(row.get_node("VBox/Top/Icon") as TextureRect).texture = item.get("icon", null)
	(row.get_node("VBox/Top/Name") as Label).text = str(item.get("name", "강화"))
	var price_lbl := row.get_node("VBox/Top/Price") as Label
	price_lbl.text = "MAX" if maxed else "%dG" % int(item.get("price", 0))
	price_lbl.add_theme_color_override("font_color", DOS.TEXT if (afford or maxed) else DOS.DIM)
	(row.get_node("VBox/Desc") as Label).text = str(item.get("desc", ""))
	row.modulate = Color(1, 1, 1, 1) if (afford or maxed) else Color(0.62, 0.64, 0.68, 1.0)
	if not maxed:
		row.pressed.connect(purchase.bind(StringName(item.get("kind", &""))))
	return row


static func purchase(kind: StringName) -> void:
	match kind:
		&"weapon_loot": GameState.upgrade_weapon_loot()
		&"armor_loot": GameState.upgrade_armor_loot()
		&"luck": GameState.upgrade_luck()
		&"scale": GameState.upgrade_scale()
		&"open_speed": GameState.upgrade_open_speed()
		&"auto_pickup": GameState.unlock_auto_pickup()
		&"auto_battle": GameState.unlock_auto_battle()
		&"auto_move": GameState.unlock_auto_move()
