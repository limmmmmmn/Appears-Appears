extends Control
class_name InventoryCard
## 인벤토리 카드 (우측 끝 독립 배치)
## InventoryCard.tscn과 1:1 대응
## 아이템 목록 표시, 클릭 자동장착, 드래그 장착, 장비해제 드롭 타겟

var hero_cards_container: Node = null

const ITEM_TYPE_ICONS := {
	"sword": "⚔", "dagger": "🗡", "staff": "🪄", "bow": "🏹", "axe": "🪓",
	"shield": "🛡", "helmet": "⛑", "heavy_armor": "🥋", "medium_armor": "🥋",
	"light_armor": "🥋", "robe": "👘", "ring": "💍", "amulet": "💍",
	"shoes": "💍", "necklace": "💍", "acc": "💍",
}
const MAX_DISPLAY_ITEMS := 12

@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %TitleLabel
@onready var item_scroll: ScrollContainer = %ItemScroll
@onready var item_list: VBoxContainer = %ItemList

var _panel_normal_style: StyleBoxFlat
var _panel_highlight_style: StyleBoxFlat
var _stat_popup: PanelContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_panel_normal_style = panel.get_theme_stylebox("panel").duplicate()
	_panel_highlight_style = _panel_normal_style.duplicate()
	_panel_highlight_style.border_color = Color(1.0, 0.95, 0.3, 1.0)
	panel.mouse_entered.connect(_on_panel_mouse_entered)
	panel.mouse_exited.connect(_on_panel_mouse_exited)
	if InventoryManager:
		if not InventoryManager.inventory_changed.is_connected(refresh):
			InventoryManager.inventory_changed.connect(refresh)
	call_deferred("refresh")


#region 패널 호버 → 히어로 장비칸 펼치기/접기
func _on_panel_mouse_entered() -> void:
	_set_hero_equips_expanded(true)


func _on_panel_mouse_exited() -> void:
	_set_hero_equips_expanded(false)


func _set_hero_equips_expanded(expanded: bool) -> void:
	var container = hero_cards_container
	if not container:
		container = get_parent()
	if not container:
		return
	for child in container.get_children():
		if child is HeroCard:
			if expanded:
				child.expand_equips()
			else:
				child.collapse_equips()
#endregion


#region 아이템 리스트 갱신
func refresh() -> void:
	if not item_list or not is_inside_tree():
		return

	for child in item_list.get_children():
		child.queue_free()

	var items: Array = InventoryManager.get_all_items() if InventoryManager else []
	var count: int = 0
	for item in items:
		if count >= MAX_DISPLAY_ITEMS:
			break
		var row := _create_item_row(item)
		item_list.add_child(row)
		count += 1

	title_label.text = "[ 인벤토리 %d ]" % items.size() if items.size() > 0 else "[ 인벤토리 ]"
#endregion


#region 아이템 행 생성
func _create_item_row(item: Dictionary) -> Button:
	var row := _DraggableItemButton.new()
	row.inv_card = self
	row.item_id = item.id
	row.item_data = item.data

	var rarity: String = item.data.get("rarity", "common")
	var rarity_color: Color = InventoryManager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
	row.rarity_color = rarity_color

	var item_type: String = item.data.get("type", "?")
	var icon: String = ITEM_TYPE_ICONS.get(item_type, "?")
	var item_name: String = item.data.get("name", item.id)
	if item.quantity > 1:
		row.text = "%s%s x%d" % [icon, item_name, item.quantity]
	else:
		row.text = "%s%s" % [icon, item_name]

	row.custom_minimum_size = Vector2(0, 16)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT

	row.add_theme_font_size_override("font_size", 8)
	row.add_theme_color_override("font_color", rarity_color)

	var normal_style := FieldHUD._make_flat_style(
		Color(0.06, 0.06, 0.08, 0.0), Color.TRANSPARENT, 2
	)
	normal_style.content_margin_left = 3
	normal_style.content_margin_right = 3
	normal_style.content_margin_top = 0
	normal_style.content_margin_bottom = 0

	var hover_style := FieldHUD._make_flat_style(
		FieldHUD.STYLE.bg_btn_hover, Color(1.0, 0.95, 0.3, 1.0), 2, 2
	)
	hover_style.content_margin_left = 3
	hover_style.content_margin_right = 3
	hover_style.content_margin_top = 0
	hover_style.content_margin_bottom = 0

	row._normal_style = normal_style
	row._hover_style = hover_style
	row.add_theme_stylebox_override("normal", normal_style)
	row.add_theme_stylebox_override("hover", hover_style)
	row.add_theme_stylebox_override("pressed", hover_style)

	# 툴팁
	var stats: Dictionary = item.data.get("stats", {})
	var tip: String = item_name + " [" + rarity + "]\n"
	for stat_key in stats:
		tip += "%s: %+d\n" % [stat_key.to_upper(), stats[stat_key]]
	tip += "[클릭: 자동장착] [드래그: 영웅에게]"
	row.tooltip_text = tip

	return row
#endregion


#region 클릭 자동장착
func _on_item_clicked(item_id: String) -> void:
	if not InventoryManager:
		return
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		return
	InventoryManager.try_auto_equip(item_id)
#endregion


#region 아이템 정보 팝업
func show_item_info(item_id: String) -> void:
	hide_item_info()
	if item_id.is_empty():
		return
	var edata: Dictionary = DataManager.get_equipment(item_id)
	if edata.is_empty():
		return

	_stat_popup = PanelContainer.new()
	var style := FieldHUD._make_flat_style(
		Color(0.05, 0.05, 0.08, 0.95), Color(0.4, 0.6, 0.9, 0.8), 4, 1
	)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_stat_popup.add_theme_stylebox_override("panel", style)
	_stat_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_popup.add_child(vbox)

	var rarity: String = edata.get("rarity", "common")
	var rcolor: Color = InventoryManager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))
	var name_lbl := Label.new()
	name_lbl.text = edata.get("name", item_id)
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", rcolor)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var stats: Dictionary = edata.get("stats", {})
	for sk in stats:
		var lbl := Label.new()
		lbl.text = "%s +%d" % [sk.to_upper(), int(stats[sk])]
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl)

	add_child(_stat_popup)
	_stat_popup.reset_size()
	var popup_h: float = _stat_popup.get_combined_minimum_size().y
	_stat_popup.position = Vector2(0, -popup_h - 2)


func hide_item_info() -> void:
	if _stat_popup and is_instance_valid(_stat_popup):
		_stat_popup.queue_free()
		_stat_popup = null
#endregion


#region 장비 해제 드롭 (카드 전체가 드롭 타겟)
func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var valid: bool = data.get("type", "") == "equipment" and data.get("source", "") == "equipment"
	if valid and panel and _panel_highlight_style:
		panel.add_theme_stylebox_override("panel", _panel_highlight_style)
	return valid


func _drop_data(_pos: Vector2, data: Variant) -> void:
	_restore_panel_style()
	if not data is Dictionary:
		return
	var hero_index: int = data.get("hero_index", -1)
	var source_slot: String = data.get("source_slot", "")
	if hero_index < 0 or source_slot.is_empty():
		return
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size() or party[hero_index] == null:
		return
	var hero: Hero = party[hero_index]
	if InventoryManager:
		InventoryManager.unequip_item(hero, source_slot)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_restore_panel_style()


func _restore_panel_style() -> void:
	if panel and _panel_normal_style:
		panel.add_theme_stylebox_override("panel", _panel_normal_style)
#endregion


#region 드래그 가능 아이템 버튼
class _DraggableItemButton extends Button:
	var inv_card: InventoryCard = null
	var item_id: String = ""
	var item_data: Dictionary = {}
	var rarity_color: Color = Color.WHITE
	var _normal_style: StyleBoxFlat
	var _hover_style: StyleBoxFlat

	func _ready() -> void:
		pressed.connect(_on_pressed)
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)

	func _on_mouse_entered() -> void:
		if _hover_style:
			add_theme_stylebox_override("normal", _hover_style)
		if inv_card:
			inv_card.show_item_info(item_id)
		_highlight_compatible_slots(true)

	func _on_mouse_exited() -> void:
		if _normal_style:
			add_theme_stylebox_override("normal", _normal_style)
		if inv_card:
			inv_card.hide_item_info()
		_highlight_compatible_slots(false)

	func _highlight_compatible_slots(on: bool) -> void:
		if not inv_card:
			return
		var equip_data: Dictionary = DataManager.get_equipment(item_id) if DataManager else {}
		var eslot: String = equip_data.get("slot", item_data.get("slot", ""))
		if eslot.is_empty():
			return
		var target_slots: Array = HeroCard.get_target_slots(eslot)
		var container = inv_card.hero_cards_container
		if not container:
			container = inv_card.get_parent()
		if not container:
			return
		for child in container.get_children():
			if child is HeroCard:
				if on:
					for ts in target_slots:
						child.highlight_slot(ts, item_id)
					child.show_stat_compare(item_id)
				else:
					child.clear_slot_highlights()
					child.hide_stat_compare()

	func _on_pressed() -> void:
		if inv_card:
			inv_card._on_item_clicked(item_id)

	func _get_drag_data(_pos: Vector2) -> Variant:
		# DataManager에서 장비 데이터 조회 (인벤토리 데이터에 slot이 없을 수 있음)
		var equip_data: Dictionary = DataManager.get_equipment(item_id) if DataManager else {}
		var slot: String = equip_data.get("slot", item_data.get("slot", ""))
		if slot.is_empty():
			return null
		var preview := Label.new()
		preview.text = self.text
		preview.add_theme_font_size_override("font_size", 9)
		preview.add_theme_color_override("font_color", rarity_color)
		preview.add_theme_color_override("font_outline_color", Color.BLACK)
		preview.add_theme_constant_override("outline_size", 2)
		preview.modulate.a = 0.9
		set_drag_preview(preview)
		var drag_data := equip_data if not equip_data.is_empty() else item_data
		return {"type": "equipment", "item_id": item_id, "item_data": drag_data, "source": "inventory"}
#endregion
