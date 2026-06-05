class_name ObjectActionPanel
extends Node2D

## A speech-bubble action panel that floats ABOVE a clicked field object, pointer
## aimed down at it. WORLD space → zooms/pans with the camera. EVERY object's
## actions happen here (the long-term plan: no side panel / top menu, the field is
## the whole UI). Per-object buttons:
##   • 모닥불 : [쉰다] [닫기]
##   • 마을   : [여관] [상점] [닫기]  — 상점 expands the GEAR SHOP inline.
## Look = master theme (retro window).

const THEME: Theme = preload("res://assets/themes/ui_theme.tres")
const SHOP_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_row.tscn")
const INVENTORY_ROW_SCENE: PackedScene = preload("res://scenes/ui/dos_inventory_row.tscn")
const ICON_WEAPON: Texture2D = preload("res://assets/sprites/icons/hero_sword.png")
const ICON_ARMOR: Texture2D = preload("res://assets/sprites/icons/shield.png")
const POINTER_TIP_GAP: float = 14.0
const POINTER_H: float = 6.0
const POINTER_HALF_W: float = 5.0

var _panel: PanelContainer
var _title: Label
var _row: HBoxContainer
var _shop: VBoxContainer
var _pointer_fill: Polygon2D
var _pointer_edge: Line2D
var _current_building: StringName = &""
var _shop_open: bool = false


func _ready() -> void:
	z_index = 60
	visible = false
	_build()
	EventBus.structure_clicked.connect(_on_structure_clicked)
	# Keep an open shop fresh after a buy / equip / sell (not every gold tick).
	EventBus.combat_upgrade_changed.connect(_on_shop_dirty.unbind(1))
	EventBus.inventory_changed.connect(_on_shop_dirty)
	EventBus.party_equipment_changed.connect(_on_shop_dirty.unbind(1))
	EventBus.weapon_equipped.connect(_on_shop_dirty.unbind(1))
	EventBus.armor_equipped.connect(_on_shop_dirty.unbind(1))


func _build() -> void:
	_pointer_fill = Polygon2D.new()
	add_child(_pointer_fill)
	_pointer_edge = Line2D.new()
	_pointer_edge.width = 1.0
	_pointer_edge.joint_mode = Line2D.LINE_JOINT_SHARP
	add_child(_pointer_edge)

	_panel = PanelContainer.new()
	_panel.theme = THEME
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_panel.add_child(col)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 5)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_row)
	_shop = VBoxContainer.new()
	_shop.add_theme_constant_override("separation", 2)
	_shop.visible = false
	col.add_child(_shop)


func _on_structure_clicked(building_id: StringName, world_position: Vector2) -> void:
	open(building_id, world_position)


func open(building_id: StringName, world_position: Vector2) -> void:
	_current_building = building_id
	position = world_position
	_shop_open = false
	_shop.visible = false
	for c in _shop.get_children():
		c.queue_free()
	for c in _row.get_children():
		c.queue_free()
	match building_id:
		&"campfire":
			_title.text = "모닥불"
			_add_button("쉰다", _on_rest)
			_add_button("닫기", close)
		&"village":
			_title.text = "마을"
			_add_button("여관", _on_inn)
			_add_button("상점", _on_shop)
			_add_button("닫기", close)
		_:
			var bname: String = str(Balance.building_by_id(building_id).get("name", ""))
			if bname.is_empty():
				bname = str(Balance.tile_by_id(building_id).get("name", building_id))
			_title.text = bname
			_add_button("닫기", close)
	visible = true
	await get_tree().process_frame
	_layout()


func _add_button(text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40.0, 14.0)
	b.pressed.connect(handler)
	_row.add_child(b)


# ─── Per-object actions ────────────────────────────────────────────────
func _on_rest() -> void:
	EventBus.rest_requested.emit()
	close()


func _on_inn() -> void:
	GameState.restore_party_full()  # 여관: wake up topped off (revive + full HP)
	close()


func _on_shop() -> void:
	_shop_open = not _shop_open
	if _shop_open:
		_build_shop()
	else:
		for c in _shop.get_children():
			c.queue_free()
	_shop.visible = _shop_open
	await get_tree().process_frame
	_layout()


func _on_shop_dirty() -> void:
	if not visible or not _shop_open:
		return
	_build_shop()
	await get_tree().process_frame
	_layout()


# ─── Gear shop (moved here from the right panel) ───────────────────────
func _build_shop() -> void:
	for c in _shop.get_children():
		c.queue_free()
	_shop.add_child(DOS.section("구매"))
	for type_id: StringName in GameState.owned_weapon_types():
		var lvl: int = GameState.weapon_level(type_id)
		var next_name: String = Balance.weapon_name_for(type_id, lvl + 1)
		var cost: int = GameState.weapon_upgrade_cost(type_id)
		_add_shop_row(ICON_WEAPON, next_name, cost, _on_buy_weapon.bind(type_id))
	var a_cost: int = GameState.armor_upgrade_cost()
	_add_shop_row(ICON_ARMOR, GameState.next_armor_name(), a_cost, _on_buy_armor)

	_shop.add_child(DOS.section("보유 장비"))
	var items: Array = GameState.inventory_items()
	var any: bool = false
	for i in items.size():
		var item: ItemData = GameState.item_entry_data(items[i])
		if item == null:
			continue
		any = true
		_add_inventory_row(i, items[i], item)
	if not any:
		_shop.add_child(DOS.label("(없음)", DOS.DIM))


func _add_shop_row(icon: Texture2D, name_text: String, cost: int, action: Callable) -> void:
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
	_shop.add_child(row)


func _add_inventory_row(inv_index: int, entry, item: ItemData) -> void:
	var lvl: int = GameState.item_entry_level(entry)
	var val: int = GameState.inventory_sell_value(entry)
	var row: HBoxContainer = INVENTORY_ROW_SCENE.instantiate()
	(row.get_node("Equip/Inner/Icon") as TextureRect).texture = item.icon
	(row.get_node("Equip/Inner/Name") as Label).text = "%s Lv%d" % [item.display_name, lvl]
	(row.get_node("Equip") as Button).pressed.connect(_on_equip_inventory.bind(inv_index))
	var sell := row.get_node("Sell") as Button
	sell.text = "%dG" % val
	sell.pressed.connect(_on_sell_inventory.bind(inv_index))
	_shop.add_child(row)


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


# ─── Layout (box above the object, pointer down at it) ─────────────────
func _layout() -> void:
	if _panel == null:
		return
	# Shrink/grow the panel to fit the CURRENT content every time. Without this a
	# Control keeps the largest size it has ever had (e.g. after the shop expanded
	# it), so a later buttons-only open would stay needlessly huge.
	_panel.reset_size()
	var w: Vector2 = _panel.size
	var base_y: float = -(POINTER_TIP_GAP + POINTER_H)
	var tip_y: float = -POINTER_TIP_GAP
	_panel.position = Vector2(-w.x * 0.5, base_y - w.y)
	var box := _panel.get_theme_stylebox("panel") as StyleBoxFlat
	var fill_color: Color = box.bg_color if box != null else Color(0.26, 0.53, 0.72, 1)
	var edge_color: Color = box.border_color if box != null else Color(0, 0, 0, 1)
	_pointer_fill.color = fill_color
	_pointer_fill.polygon = PackedVector2Array([
		Vector2(-POINTER_HALF_W, base_y), Vector2(POINTER_HALF_W, base_y), Vector2(0.0, tip_y),
	])
	_pointer_edge.default_color = edge_color
	_pointer_edge.points = PackedVector2Array([
		Vector2(-POINTER_HALF_W, base_y), Vector2(0.0, tip_y), Vector2(POINTER_HALF_W, base_y),
	])


func close() -> void:
	visible = false
	_shop_open = false
