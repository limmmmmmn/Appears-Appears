class_name GearShop

## Shared 마을 상점 UI builder. Renders the 여관(휴식) action + the gear shop
## (구매 무기/방어구 사다리 한 칸 + 보유 장비 장착/판매) into any VBoxContainer.
##
## Pulled out of the floating ObjectActionPanel so the right property inspector can
## host the same shop under a selected 마을 (below the 강화 slot). Stateless: each
## call rebuilds rows from GameState, so the host re-invokes it on the relevant
## EventBus signals (gold / inventory / equipment) to keep prices + lists live.

const SHOP_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_row.tscn")
const INVENTORY_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_inventory_row.tscn")
const ICON_WEAPON: Texture2D = preload("res://assets/sprites/icons/hero_sword.png")
const ICON_ARMOR: Texture2D = preload("res://assets/sprites/icons/shield.png")


## Append 여관 + 상점 rows to `vbox`. Existing children are left untouched (the host
## clears + rebuilds the whole panel on each render).
static func build(vbox: VBoxContainer) -> void:
	_build_inn(vbox)
	_build_shop(vbox)


# ─── 여관: rest the party to full ──────────────────────────────────────
static func _build_inn(vbox: VBoxContainer) -> void:
	var b := Button.new()
	b.text = "여관 (휴식)"
	DOS.style_button(b)
	b.add_theme_font_size_override("font_size", UITheme.FONT_CARD_BUTTON)
	b.add_theme_color_override("font_color", DOS.TEXT)
	b.pressed.connect(_on_inn)
	vbox.add_child(b)


# ─── 상점: 구매 (무기/방어구) + 보유 장비 (장착/판매) ──────────────────
## Only gear within the 마을 레벨's tier ceiling is offered — the next 단계 stays
## HIDDEN until the village is upgraded (그때 비로소 "뜬다"). A hint takes its place so
## the player knows where the next gear comes from. Armor is a SINGLE 무기-style row:
## one click outfits the leftmost party member who can still take it (per-member, but
## auto-targeted — no name-by-name rows).
static func _build_shop(vbox: VBoxContainer) -> void:
	vbox.add_child(DOS.section("구매"))
	var locked: bool = false
	# 무기 — one row per owned weapon TYPE, only while its next tier is unlocked.
	for type_id: StringName in GameState.owned_weapon_types():
		var lvl: int = GameState.weapon_level(type_id)
		if not GameState.village_allows_gear_level(lvl + 1):
			locked = true
			continue
		var next_name: String = Balance.weapon_name_for(type_id, lvl + 1)
		var cost: int = GameState.weapon_upgrade_cost(type_id)
		_add_shop_row(vbox, ICON_WEAPON, next_name, cost, _on_buy_weapon.bind(type_id))
	# 방어구 — 무기처럼 한 줄. 클릭하면 아직 단계가 덜 오른 가장 왼쪽 파티원에게 끼워진다.
	var armor_target: int = GameState.next_armor_buyer()
	if armor_target >= 0:
		var alvl: int = GameState.member_armor_level(armor_target)
		var aname: String = Balance.armor_name_for_level(alvl + 1)
		var a_cost: int = GameState.member_armor_upgrade_cost(armor_target)
		_add_shop_row(vbox, ICON_ARMOR, aname, a_cost, _on_buy_armor)
	else:
		locked = true  # 모든 파티원이 현재 마을 단계 천장 → 마을 강화 필요
	if locked:
		# Must WRAP — a long one-line label would force the whole panel wider than the
		# screen (it sets the container's min width). Wrapping keeps it inside the fixed
		# panel width, like the header info line.
		var hint := DOS.label("마을을 강화하면 다음 단계 장비가 풀립니다.", DOS.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(hint)

	vbox.add_child(DOS.section("보유 장비"))
	var items: Array = GameState.inventory_items()
	var any: bool = false
	for i in items.size():
		var item: ItemData = GameState.item_entry_data(items[i])
		if item == null:
			continue
		any = true
		_add_inventory_row(vbox, i, items[i], item)
	if not any:
		vbox.add_child(DOS.label("(없음)", DOS.DIM))


static func _add_shop_row(vbox: VBoxContainer, icon: Texture2D, name_text: String, cost: int, action: Callable) -> void:
	var afford: bool = GameState.gold >= cost
	var row: Button = SHOP_ROW_SCENE.instantiate()
	row.disabled = not afford
	(row.get_node("HBox/Icon") as TextureRect).texture = icon
	(row.get_node("HBox/Name") as Label).text = name_text
	var tag := row.get_node("HBox/Tag") as Label
	tag.text = "%dG" % cost
	tag.add_theme_color_override("font_color", DOS.TEXT if afford else DOS.DIM)
	row.modulate = Color(1, 1, 1, 1) if afford else Color(0.62, 0.64, 0.68, 1.0)
	row.pressed.connect(action)
	vbox.add_child(row)


static func _add_inventory_row(vbox: VBoxContainer, inv_index: int, entry, item: ItemData) -> void:
	var lvl: int = GameState.item_entry_level(entry)
	var val: int = GameState.inventory_sell_value(entry)
	var row: HBoxContainer = INVENTORY_ROW_SCENE.instantiate()
	(row.get_node("Equip/Inner/Icon") as TextureRect).texture = item.icon
	(row.get_node("Equip/Inner/Name") as Label).text = "%s Lv%d" % [item.display_name, lvl]
	(row.get_node("Equip") as Button).pressed.connect(_on_equip_inventory.bind(inv_index))
	var sell := row.get_node("Sell") as Button
	sell.text = "%dG" % val
	sell.pressed.connect(_on_sell_inventory.bind(inv_index))
	vbox.add_child(row)


# ─── Actions (call into GameState; its signals drive the host's refresh) ──
static func _on_inn() -> void:
	GameState.restore_party_full()  # 여관: wake up topped off (revive + full HP)


static func _on_buy_weapon(type_id: StringName) -> void:
	GameState.upgrade_weapon(type_id)


static func _on_buy_armor() -> void:
	GameState.upgrade_next_member_armor()  # 가장 왼쪽의 장착 가능 파티원에게


static func _on_sell_inventory(inv_index: int) -> void:
	GameState.sell_inventory_entry_at(inv_index)


static func _on_equip_inventory(inv_index: int) -> void:
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


static func _member_for(item: ItemData) -> int:
	if item.allowed_character_id == &"":
		return 0
	for i in GameState.party.size():
		if GameState.party[i].id == item.allowed_character_id:
			return i
	return -1
