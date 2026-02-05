extends CanvasLayer
class_name PauseMenu
## 일시정지 메뉴 UI
## - 통합 화면: 파티 상태 + 장비 + 룬 + 인벤토리

signal resume_pressed
signal title_pressed
signal quit_pressed

var is_showing: bool = false

# UI 참조
var main_control: Control = null
var hero_cards_container: HBoxContainer = null
var inventory_container: VBoxContainer = null
var rune_inventory_container: VBoxContainer = null

# 선택 상태
var selected_hero: Hero = null
var selected_slot: String = ""

# 드래그 프리뷰 레이어
var drag_preview: Control = null


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func show_menu() -> void:
	if is_showing:
		return

	is_showing = true
	visible = true
	get_tree().paused = true

	_create_ui()


func hide_menu() -> void:
	if not is_showing:
		return

	is_showing = false
	visible = false
	get_tree().paused = false

	if main_control:
		main_control.queue_free()
		main_control = null


func is_visible_menu() -> bool:
	return is_showing


func _create_ui() -> void:
	for child in get_children():
		child.queue_free()

	main_control = Control.new()
	main_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_control)

	# 어두운 배경
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.9)
	main_control.add_child(bg)

	# 메인 컨테이너 (세로)
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	main_control.add_child(main_vbox)

	# 상단: 타이틀
	_create_header(main_vbox)

	# 중앙: 콘텐츠 (가로 분할)
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(content_hbox)

	# 좌측: 파티원 카드들 (스탯+장비+룬)
	var left_panel := _create_left_panel()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 3.0
	content_hbox.add_child(left_panel)

	# 우측: 인벤토리 (장비 + 룬)
	var right_panel := _create_right_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(right_panel)

	# 하단: 버튼
	_create_footer(main_vbox)


func _create_header(parent: VBoxContainer) -> void:
	var header := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	header.add_theme_stylebox_override("panel", style)
	parent.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	header.add_child(hbox)

	var title := Label.new()
	title.text = "[ 상태창 ]"
	title.add_theme_font_size_override("font_size", 14)
	hbox.add_child(title)

	# 스페이서
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var hint := Label.new()
	hint.text = "[ESC] 닫기"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	hbox.add_child(hint)


func _create_left_panel() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	hero_cards_container = HBoxContainer.new()
	hero_cards_container.add_theme_constant_override("separation", 8)
	scroll.add_child(hero_cards_container)

	_refresh_hero_cards()

	return margin


func _refresh_hero_cards() -> void:
	if not hero_cards_container:
		return

	for child in hero_cards_container.get_children():
		child.queue_free()

	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		var card := _create_hero_full_card(hero)
		hero_cards_container.add_child(card)


func _create_hero_full_card(hero: Hero) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(140, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.98)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.25, 0.25, 0.3)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# === 헤더: 이름 + 레벨 ===
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	vbox.add_child(header)

	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(28, 28)
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if SpriteManager:
		face.texture = SpriteManager.get_hero_face_sprite(hero.id)
	header.add_child(face)

	var name_vbox := VBoxContainer.new()
	name_vbox.add_theme_constant_override("separation", 0)
	header.add_child(name_vbox)

	var name_label := Label.new()
	name_label.text = hero.hero_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_vbox.add_child(name_label)

	var class_label := Label.new()
	class_label.text = hero.hero_class_name
	class_label.add_theme_font_size_override("font_size", 8)
	class_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	name_vbox.add_child(class_label)

	vbox.add_child(_create_separator())

	# === HP 바 ===
	_add_stat_bar(vbox, "HP", hero.current_hp, hero.get_max_hp(), Color(0.2, 0.7, 0.2))

	vbox.add_child(_create_separator())

	# === 스탯 (2열) ===
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 8)
	stats_grid.add_theme_constant_override("v_separation", 1)
	vbox.add_child(stats_grid)

	_add_stat_label(stats_grid, "STR", hero.get_str())
	_add_stat_label(stats_grid, "DEF", hero.get_def())
	_add_stat_label(stats_grid, "INT", hero.get_int())
	_add_stat_label(stats_grid, "DEX", hero.get_dex())
	_add_stat_label(stats_grid, "LUK", hero.get_luk())
	_add_stat_label(stats_grid, "ATK", hero.get_atk(), Color(1.0, 0.7, 0.7))

	vbox.add_child(_create_separator())

	# === 장비 슬롯 (6개) - 드래그 앤 드롭 지원 ===
	var equip_label := Label.new()
	equip_label.text = "[ 장비 ] (드래그로 이동)"
	equip_label.add_theme_font_size_override("font_size", 9)
	equip_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(equip_label)

	var slots := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]
	var slot_icons := {"main_hand": "⚔", "off_hand": "🛡", "head": "👒", "body": "👕", "acc1": "💍", "acc2": "💍"}

	for slot in slots:
		var equip_id: String = hero.equipment.get(slot, "")
		var slot_icon: String = slot_icons.get(slot, "?")

		var draggable := DraggableSlot.new()
		draggable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		draggable.setup(self, hero, slot, equip_id, slot_icon, false)
		vbox.add_child(draggable)

	vbox.add_child(_create_separator())

	# === 룬 슬롯 - 드래그 앤 드롭 지원 ===
	var rune_label := Label.new()
	rune_label.text = "[ 룬 ]"
	rune_label.add_theme_font_size_override("font_size", 9)
	rune_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(rune_label)

	var rune_draggable := DraggableSlot.new()
	rune_draggable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rune_draggable.setup(self, hero, "rune", hero.equipped_rune_id, "🔮", true)
	vbox.add_child(rune_draggable)

	var trait_data: Dictionary = DataManager.get_rune_trait(hero.equipped_rune_id) if not hero.equipped_rune_id.is_empty() else {}

	# 특성 효과 표시
	if not trait_data.is_empty():
		var trait_label := Label.new()
		trait_label.text = "  %s %s" % [trait_data.get("icon", ""), trait_data.get("description", "")]
		trait_label.add_theme_font_size_override("font_size", 7)
		trait_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.4))
		vbox.add_child(trait_label)

	return card


func _create_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	return sep


func _add_stat_bar(parent: VBoxContainer, label_text: String, current: int, max_val: int, color: Color) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	parent.add_child(hbox)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 22
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color.lightened(0.3))
	hbox.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(40, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.max_value = max(max_val, 1)
	bar.value = current

	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 2
	fill.corner_radius_top_right = 2
	fill.corner_radius_bottom_left = 2
	fill.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg)
	hbox.add_child(bar)

	var value := Label.new()
	value.text = "%d" % current
	value.custom_minimum_size.x = 28
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_font_size_override("font_size", 8)
	hbox.add_child(value)


func _add_stat_label(parent: GridContainer, stat_name: String, stat_value: int, color: Color = Color.WHITE) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	parent.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = stat_name
	name_lbl.custom_minimum_size.x = 28
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hbox.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = str(stat_value)
	val_lbl.add_theme_font_size_override("font_size", 8)
	val_lbl.add_theme_color_override("font_color", color)
	hbox.add_child(val_lbl)


func _create_right_panel() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_width_left = 1
	style.border_color = Color(0.25, 0.25, 0.3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# === 장비 인벤토리 ===
	var equip_title := Label.new()
	equip_title.text = "[ 장비 인벤토리 ]"
	equip_title.add_theme_font_size_override("font_size", 10)
	equip_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(equip_title)

	var equip_scroll := ScrollContainer.new()
	equip_scroll.custom_minimum_size = Vector2(0, 120)
	equip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(equip_scroll)

	inventory_container = VBoxContainer.new()
	inventory_container.add_theme_constant_override("separation", 2)
	inventory_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_scroll.add_child(inventory_container)

	_refresh_equipment_inventory()

	vbox.add_child(_create_separator())

	# === 룬 인벤토리 ===
	var rune_title := Label.new()
	rune_title.text = "[ 룬 인벤토리 ]"
	rune_title.add_theme_font_size_override("font_size", 10)
	rune_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(rune_title)

	var rune_scroll := ScrollContainer.new()
	rune_scroll.custom_minimum_size = Vector2(0, 120)
	rune_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rune_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(rune_scroll)

	rune_inventory_container = VBoxContainer.new()
	rune_inventory_container.add_theme_constant_override("separation", 2)
	rune_inventory_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rune_scroll.add_child(rune_inventory_container)

	_refresh_rune_inventory()

	return panel


func _refresh_equipment_inventory() -> void:
	if not inventory_container:
		return

	for child in inventory_container.get_children():
		child.queue_free()

	var inventory: Dictionary = InventoryManager.items if InventoryManager else {}
	var has_equip := false

	for item_id in inventory:
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if equip_data.is_empty():
			continue

		has_equip = true
		var qty: int = inventory[item_id]
		var rarity: String = equip_data.get("rarity", "common")

		# 드래그 가능한 인벤토리 아이템
		var draggable := DraggableInventoryItem.new()
		draggable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		draggable.setup(self, item_id, qty, false)
		inventory_container.add_child(draggable)

		# 스탯 미리보기
		var stats: Dictionary = equip_data.get("stats", {})
		if not stats.is_empty():
			var stat_text := "  "
			for stat_name in stats:
				stat_text += "%s+%d " % [stat_name.to_upper(), stats[stat_name]]
			var stat_label := Label.new()
			stat_label.text = stat_text
			stat_label.add_theme_font_size_override("font_size", 7)
			stat_label.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
			inventory_container.add_child(stat_label)

	if not has_equip:
		var empty := Label.new()
		empty.text = "(비어있음)"
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		inventory_container.add_child(empty)


func _refresh_rune_inventory() -> void:
	if not rune_inventory_container:
		return

	for child in rune_inventory_container.get_children():
		child.queue_free()

	var inventory: Dictionary = InventoryManager.items if InventoryManager else {}
	var has_rune := false

	for item_id in inventory:
		var rune_data: Dictionary = DataManager.get_rune(item_id)
		if rune_data.is_empty():
			continue

		has_rune = true
		var qty: int = inventory[item_id]
		var trait_data: Dictionary = DataManager.get_rune_trait(item_id)

		# 드래그 가능한 룬 아이템
		var draggable := DraggableInventoryItem.new()
		draggable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		draggable.setup(self, item_id, qty, true)
		rune_inventory_container.add_child(draggable)

		if not trait_data.is_empty():
			var trait_label := Label.new()
			trait_label.text = "  %s %s" % [trait_data.get("icon", ""), trait_data.get("description", "")]
			trait_label.add_theme_font_size_override("font_size", 7)
			trait_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35))
			rune_inventory_container.add_child(trait_label)

	if not has_rune:
		var empty := Label.new()
		empty.text = "(비어있음)"
		empty.add_theme_font_size_override("font_size", 9)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		rune_inventory_container.add_child(empty)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.7, 0.7, 0.7)
		"uncommon": return Color(0.4, 0.8, 0.4)
		"magic": return Color(0.4, 0.6, 1.0)
		"rare": return Color(0.8, 0.6, 1.0)
		"epic": return Color(1.0, 0.5, 0.2)
		"legendary": return Color(1.0, 0.8, 0.2)
		_: return Color.WHITE


#region 장비 장착
func _on_equipment_slot_pressed(hero: Hero, slot: String) -> void:
	selected_hero = hero
	selected_slot = slot
	_show_equipment_popup(hero, slot)


func _show_equipment_popup(hero: Hero, slot: String) -> void:
	var existing := main_control.get_node_or_null("Popup")
	if existing:
		existing.queue_free()

	var popup := PanelContainer.new()
	popup.name = "Popup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(220, 280)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	popup.add_theme_stylebox_override("panel", style)
	main_control.add_child(popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	popup.add_child(vbox)

	var slot_names := {"main_hand": "주무기", "off_hand": "보조", "head": "머리", "body": "몸통", "acc1": "악세1", "acc2": "악세2"}
	var title := Label.new()
	title.text = "%s - %s" % [hero.hero_name, slot_names.get(slot, slot)]
	title.add_theme_font_size_override("font_size", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_create_separator())

	# 장착 해제
	var unequip := Button.new()
	unequip.text = "[ 해제 ]"
	unequip.add_theme_font_size_override("font_size", 9)
	unequip.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4))
	unequip.pressed.connect(_on_equip_selected.bind(hero, slot, ""))
	vbox.add_child(unequip)

	vbox.add_child(_create_separator())

	# 아이템 목록
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var items_vbox := VBoxContainer.new()
	items_vbox.add_theme_constant_override("separation", 3)
	items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(items_vbox)

	var inventory: Dictionary = InventoryManager.items if InventoryManager else {}
	var slot_type_map: Dictionary = {"main_hand": "weapon", "off_hand": "shield", "head": "head", "body": "body", "acc1": "accessory", "acc2": "accessory"}
	var slot_type: String = slot_type_map.get(slot, "")

	for item_id in inventory:
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if equip_data.is_empty():
			continue
		if equip_data.get("slot", "") != slot_type:
			continue
		if not hero.can_equip(item_id):
			continue

		var qty: int = inventory[item_id]
		var rarity: String = equip_data.get("rarity", "common")

		var btn := Button.new()
		btn.text = "%s x%d" % [equip_data.get("name", item_id), qty]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 9)
		btn.add_theme_color_override("font_color", _get_rarity_color(rarity))
		btn.pressed.connect(_on_equip_selected.bind(hero, slot, item_id))
		items_vbox.add_child(btn)

	# 닫기
	var close := Button.new()
	close.text = "닫기"
	close.add_theme_font_size_override("font_size", 9)
	close.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close)


func _on_equip_selected(hero: Hero, slot: String, item_id: String) -> void:
	var old_equip: String = hero.equipment.get(slot, "")
	if not old_equip.is_empty():
		InventoryManager.add_item(old_equip)

	if not item_id.is_empty():
		InventoryManager.remove_item(item_id)
		hero.equip_item(item_id, slot)
	else:
		hero.unequip_slot(slot)

	var popup := main_control.get_node_or_null("Popup")
	if popup:
		popup.queue_free()

	_refresh_hero_cards()
	_refresh_equipment_inventory()
#endregion


#region 룬 장착
func _on_rune_slot_pressed(hero: Hero) -> void:
	selected_hero = hero
	_show_rune_popup(hero)


func _show_rune_popup(hero: Hero) -> void:
	var existing := main_control.get_node_or_null("Popup")
	if existing:
		existing.queue_free()

	var popup := PanelContainer.new()
	popup.name = "Popup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(240, 280)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.4, 0.6)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	popup.add_theme_stylebox_override("panel", style)
	main_control.add_child(popup)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	popup.add_child(vbox)

	var title := Label.new()
	title.text = "%s - 룬 선택" % hero.hero_name
	title.add_theme_font_size_override("font_size", 11)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(_create_separator())

	# 룬 해제
	var unequip := Button.new()
	unequip.text = "[ 해제 ]"
	unequip.add_theme_font_size_override("font_size", 9)
	unequip.add_theme_color_override("font_color", Color(0.6, 0.4, 0.4))
	unequip.pressed.connect(_on_rune_selected.bind(hero, ""))
	vbox.add_child(unequip)

	vbox.add_child(_create_separator())

	# 룬 목록
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var items_vbox := VBoxContainer.new()
	items_vbox.add_theme_constant_override("separation", 4)
	items_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(items_vbox)

	var inventory: Dictionary = InventoryManager.items if InventoryManager else {}

	for item_id in inventory:
		var rune_data: Dictionary = DataManager.get_rune(item_id)
		if rune_data.is_empty():
			continue

		var qty: int = inventory[item_id]
		var rarity: String = rune_data.get("rarity", "common")
		var trait_data: Dictionary = DataManager.get_rune_trait(item_id)

		var container := VBoxContainer.new()
		container.add_theme_constant_override("separation", 1)
		items_vbox.add_child(container)

		var btn := Button.new()
		btn.text = "%s %s x%d" % [rune_data.get("icon", "🔮"), rune_data.get("name", item_id), qty]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 9)
		btn.add_theme_color_override("font_color", _get_rarity_color(rarity))
		btn.pressed.connect(_on_rune_selected.bind(hero, item_id))
		container.add_child(btn)

		if not trait_data.is_empty():
			var desc := Label.new()
			desc.text = "  %s %s" % [trait_data.get("icon", ""), trait_data.get("description", "")]
			desc.add_theme_font_size_override("font_size", 7)
			desc.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35))
			container.add_child(desc)

	# 닫기
	var close := Button.new()
	close.text = "닫기"
	close.add_theme_font_size_override("font_size", 9)
	close.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close)


func _on_rune_selected(hero: Hero, rune_id: String) -> void:
	var old_rune: String = hero.equipped_rune_id
	if not old_rune.is_empty():
		InventoryManager.add_item(old_rune)

	if not rune_id.is_empty():
		InventoryManager.remove_item(rune_id)
		hero.equip_rune(rune_id)
	else:
		hero.unequip_rune()

	# FieldHUD 갱신
	var field_hud = get_tree().get_first_node_in_group("field_hud")
	if field_hud and field_hud.has_method("refresh_traits"):
		field_hud.refresh_traits()

	var popup := main_control.get_node_or_null("Popup")
	if popup:
		popup.queue_free()

	_refresh_hero_cards()
	_refresh_rune_inventory()
#endregion


#region 하단 버튼
func _create_footer(parent: VBoxContainer) -> void:
	var footer := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_width_top = 1
	style.border_color = Color(0.3, 0.3, 0.35)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	footer.add_theme_stylebox_override("panel", style)
	parent.add_child(footer)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_child(hbox)

	# 감정 버튼 (미감정 아이템 있을 때만 활성화)
	var identify_count: int = InventoryManager.get_unidentified_count() if InventoryManager else 0
	var identify_btn := _create_btn("감정 (%d)" % identify_count, Color(0.4, 0.3, 0.5))
	if identify_count > 0:
		identify_btn.pressed.connect(_on_identify)
	else:
		identify_btn.disabled = true
		identify_btn.modulate.a = 0.5
	hbox.add_child(identify_btn)

	var resume := _create_btn("게임 계속", Color(0.2, 0.5, 0.3))
	resume.pressed.connect(_on_resume)
	hbox.add_child(resume)

	var title_btn := _create_btn("타이틀로", Color(0.4, 0.35, 0.2))
	title_btn.pressed.connect(_on_title)
	hbox.add_child(title_btn)

	var quit := _create_btn("게임 종료", Color(0.5, 0.2, 0.2))
	quit.pressed.connect(_on_quit)
	hbox.add_child(quit)


func _create_btn(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 28)
	btn.add_theme_font_size_override("font_size", 11)

	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)

	return btn


func _on_identify() -> void:
	## 미감정 아이템 모두 감정
	var count: int = InventoryManager.identify_all_items()
	if count > 0:
		# UI 갱신
		_create_ui()  # 전체 재생성


func _on_resume() -> void:
	hide_menu()
	resume_pressed.emit()


func _on_title() -> void:
	hide_menu()
	title_pressed.emit()


func _on_quit() -> void:
	hide_menu()
	quit_pressed.emit()
#endregion


# 하위 호환
func open(p_parent: Node) -> void:
	if not is_inside_tree():
		p_parent.add_child(self)
	show_menu()


func close() -> void:
	hide_menu()


func is_open() -> bool:
	return is_showing


#region 드래그 앤 드롭
class DraggableSlot extends Control:
	## 장비 슬롯 (드래그 앤 드롭 지원)
	var pause_menu: PauseMenu = null
	var hero: Hero = null
	var slot: String = ""
	var item_id: String = ""
	var slot_icon: String = ""
	var is_rune: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 24)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func setup(p_menu: PauseMenu, p_hero: Hero, p_slot: String, p_item_id: String, p_icon: String, p_rune: bool = false) -> void:
		pause_menu = p_menu
		hero = p_hero
		slot = p_slot
		item_id = p_item_id
		slot_icon = p_icon
		is_rune = p_rune
		queue_redraw()

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)

		# 배경
		var bg_color := Color(0.15, 0.15, 0.18, 0.9)
		if is_rune:
			bg_color = Color(0.18, 0.15, 0.2, 0.9)
		draw_rect(rect, bg_color, true)

		# 테두리
		var border_color := Color(0.3, 0.3, 0.35)
		if not item_id.is_empty():
			if is_rune:
				var rune_data: Dictionary = DataManager.get_rune(item_id)
				border_color = pause_menu._get_rarity_color(rune_data.get("rarity", "common"))
			else:
				var equip_data: Dictionary = DataManager.get_equipment(item_id)
				border_color = pause_menu._get_rarity_color(equip_data.get("rarity", "common"))
		draw_rect(rect, border_color, false, 1.0)

		# 텍스트
		var text := slot_icon + " -"
		var text_color := Color(0.4, 0.4, 0.4)
		if not item_id.is_empty():
			if is_rune:
				var rune_data: Dictionary = DataManager.get_rune(item_id)
				text = "%s %s" % [rune_data.get("icon", slot_icon), rune_data.get("name", "?")]
				text_color = pause_menu._get_rarity_color(rune_data.get("rarity", "common"))
			else:
				var equip_data: Dictionary = DataManager.get_equipment(item_id)
				text = "%s %s" % [slot_icon, equip_data.get("name", "?")]
				text_color = pause_menu._get_rarity_color(equip_data.get("rarity", "common"))

		var font: Font = ThemeDB.fallback_font
		var font_size: int = 9
		var text_pos := Vector2(4, size.y / 2 + 4)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, font_size, text_color)

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item_id.is_empty():
			return null

		# 드래그 프리뷰 생성
		var preview := Label.new()
		if is_rune:
			var rune_data: Dictionary = DataManager.get_rune(item_id)
			preview.text = "%s %s" % [rune_data.get("icon", "🔮"), rune_data.get("name", "?")]
			preview.add_theme_color_override("font_color", pause_menu._get_rarity_color(rune_data.get("rarity", "common")))
		else:
			var equip_data: Dictionary = DataManager.get_equipment(item_id)
			preview.text = "%s %s" % [slot_icon, equip_data.get("name", "?")]
			preview.add_theme_color_override("font_color", pause_menu._get_rarity_color(equip_data.get("rarity", "common")))
		preview.add_theme_font_size_override("font_size", 10)
		set_drag_preview(preview)

		return {
			"type": "rune" if is_rune else "equipment",
			"item_id": item_id,
			"source_hero": hero,
			"source_slot": slot
		}

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if data == null or not data is Dictionary:
			return false

		var drag_data: Dictionary = data as Dictionary

		# 룬 슬롯에는 룬만
		if is_rune:
			return drag_data.get("type", "") == "rune"

		# 장비 슬롯에는 장비만
		if drag_data.get("type", "") != "equipment":
			return false

		# 해당 슬롯에 장착 가능한 타입인지 확인
		var drag_item_id: String = drag_data.get("item_id", "")
		if drag_item_id.is_empty():
			return false

		var equip_data: Dictionary = DataManager.get_equipment(drag_item_id)
		var equip_slot: String = equip_data.get("slot", "")
		var slot_type_map: Dictionary = {"main_hand": "weapon", "off_hand": "shield", "head": "head", "body": "body", "acc1": "accessory", "acc2": "accessory"}
		var target_type: String = slot_type_map.get(slot, "")

		if equip_slot != target_type:
			return false

		# 영웅이 장착 가능한지
		return hero.can_equip(drag_item_id)

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if data == null or not data is Dictionary:
			return

		var drag_data: Dictionary = data as Dictionary
		var drag_item_id: String = drag_data.get("item_id", "")
		var source_hero: Hero = drag_data.get("source_hero", null)
		var source_slot: String = drag_data.get("source_slot", "")

		if is_rune:
			pause_menu._handle_rune_drop(hero, drag_item_id, source_hero, source_slot)
		else:
			pause_menu._handle_equipment_drop(hero, slot, drag_item_id, source_hero, source_slot)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				# 클릭으로도 팝업 열기 (드래그 아닐 때)
				if is_rune:
					pause_menu._on_rune_slot_pressed(hero)
				else:
					pause_menu._on_equipment_slot_pressed(hero, slot)


class DraggableInventoryItem extends Control:
	## 인벤토리 아이템 (드래그 앤 드롭 지원)
	var pause_menu: PauseMenu = null
	var item_id: String = ""
	var is_rune: bool = false
	var quantity: int = 1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 20)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func setup(p_menu: PauseMenu, p_item_id: String, p_qty: int, p_rune: bool) -> void:
		pause_menu = p_menu
		item_id = p_item_id
		quantity = p_qty
		is_rune = p_rune
		queue_redraw()

	func _draw() -> void:
		var text := ""
		var text_color := Color.WHITE
		var slot_icon := ""

		if is_rune:
			var rune_data: Dictionary = DataManager.get_rune(item_id)
			text = "%s %s x%d" % [rune_data.get("icon", "🔮"), rune_data.get("name", item_id), quantity]
			text_color = pause_menu._get_rarity_color(rune_data.get("rarity", "common"))
		else:
			var equip_data: Dictionary = DataManager.get_equipment(item_id)
			var slot: String = equip_data.get("slot", "")
			var slot_icons: Dictionary = {"weapon": "⚔", "shield": "🛡", "head": "👒", "body": "👕", "accessory": "💍"}
			slot_icon = slot_icons.get(slot, "?")
			text = "%s %s x%d" % [slot_icon, equip_data.get("name", item_id), quantity]
			text_color = pause_menu._get_rarity_color(equip_data.get("rarity", "common"))

		var font: Font = ThemeDB.fallback_font
		var font_size: int = 9
		var text_pos := Vector2(0, size.y / 2 + 4)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, size.x, font_size, text_color)

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item_id.is_empty():
			return null

		# 드래그 프리뷰 생성
		var preview := Label.new()
		if is_rune:
			var rune_data: Dictionary = DataManager.get_rune(item_id)
			preview.text = "%s %s" % [rune_data.get("icon", "🔮"), rune_data.get("name", "?")]
			preview.add_theme_color_override("font_color", pause_menu._get_rarity_color(rune_data.get("rarity", "common")))
		else:
			var equip_data: Dictionary = DataManager.get_equipment(item_id)
			preview.text = "%s" % equip_data.get("name", "?")
			preview.add_theme_color_override("font_color", pause_menu._get_rarity_color(equip_data.get("rarity", "common")))
		preview.add_theme_font_size_override("font_size", 10)
		set_drag_preview(preview)

		return {
			"type": "rune" if is_rune else "equipment",
			"item_id": item_id,
			"source_hero": null,
			"source_slot": "inventory"
		}


func _handle_equipment_drop(target_hero: Hero, target_slot: String, drag_item_id: String, source_hero: Hero, source_slot: String) -> void:
	## 장비 드롭 처리
	# 현재 슬롯에 있는 아이템
	var current_item: String = target_hero.equipment.get(target_slot, "")

	if source_slot == "inventory":
		# 인벤토리에서 슬롯으로
		if not current_item.is_empty():
			InventoryManager.add_item(current_item)
		InventoryManager.remove_item(drag_item_id)
		target_hero.equip_item(drag_item_id, target_slot)
	else:
		# 슬롯에서 슬롯으로
		if source_hero == target_hero and source_slot == target_slot:
			return  # 같은 슬롯이면 무시

		# 소스 슬롯 해제
		source_hero.unequip_slot(source_slot)

		if source_hero == target_hero:
			# 같은 영웅 내에서 슬롯 이동
			if not current_item.is_empty():
				source_hero.equip_item(current_item, source_slot)
			target_hero.equip_item(drag_item_id, target_slot)
		else:
			# 다른 영웅에게 이동
			if not current_item.is_empty():
				# 소스 영웅이 현재 아이템을 장착할 수 있는지 확인
				if source_hero.can_equip(current_item):
					source_hero.equip_item(current_item, source_slot)
				else:
					InventoryManager.add_item(current_item)
			target_hero.equip_item(drag_item_id, target_slot)

	_refresh_all()


func _handle_rune_drop(target_hero: Hero, drag_rune_id: String, source_hero: Hero, source_slot: String) -> void:
	## 룬 드롭 처리
	var current_rune: String = target_hero.equipped_rune_id

	if source_slot == "inventory":
		# 인벤토리에서 룬 슬롯으로
		if not current_rune.is_empty():
			InventoryManager.add_item(current_rune)
		InventoryManager.remove_item(drag_rune_id)
		target_hero.equip_rune(drag_rune_id)
	else:
		# 슬롯에서 슬롯으로
		if source_hero == target_hero:
			return  # 같은 슬롯이면 무시

		source_hero.unequip_rune()
		if not current_rune.is_empty():
			source_hero.equip_rune(current_rune)
		target_hero.equip_rune(drag_rune_id)

	# FieldHUD 갱신
	var field_hud = get_tree().get_first_node_in_group("field_hud")
	if field_hud and field_hud.has_method("refresh_traits"):
		field_hud.refresh_traits()

	_refresh_all()


func _refresh_all() -> void:
	_refresh_hero_cards()
	_refresh_equipment_inventory()
	_refresh_rune_inventory()
#endregion
