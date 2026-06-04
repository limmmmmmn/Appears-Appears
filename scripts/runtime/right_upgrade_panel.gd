class_name RightUpgradePanel
extends PanelContainer

## Right zone — the 강화 (spend-gold upgrades) list only. The 장비 shop moved to the
## village's on-field panel (everything-happens-on-the-field redesign); this panel
## will go away too eventually. LOGIC ONLY; look = scene + master theme.

const ICON_WEAPON: Texture2D = preload("res://assets/sprites/icons/hero_sword.png")
const ICON_ARMOR: Texture2D = preload("res://assets/sprites/icons/shield.png")
const ICON_GOLD: Texture2D = preload("res://assets/sprites/icons/gold.png")
const UPGRADE_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_upgrade_row.tscn")

@onready var _content: VBoxContainer = %Content

var _rows: Array[Dictionary] = []   ## {button, cost} — for live affordability re-tint


func _ready() -> void:
	add_to_group("upgrade_window")
	_rebuild()
	# Gold ticks only re-tint affordability (no rebuild → no flicker); a purchase
	# (combat_upgrade_changed) rebuilds so prices/levels refresh.
	EventBus.gold_changed.connect(_refresh_afford.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))


# ─── Window open/close (menu bar 강화 toggle) ───────────────────────────
func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func toggle() -> void:
	visible = not visible


func _on_changed() -> void:
	if visible:
		_rebuild()


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


# ─── 강화 list ─────────────────────────────────────────────────────────
func _rebuild() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	_rows.clear()
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
