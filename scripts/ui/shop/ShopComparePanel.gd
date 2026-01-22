extends PanelContainer
class_name ShopComparePanel
## 상점 장비 비교 패널

signal buy_and_equip_pressed(item_id: String, price: int, hero: Hero, slot: String)

var scroll: ScrollContainer
var container: VBoxContainer


func _ready() -> void:
	_setup_ui()
	visible = false


func _setup_ui() -> void:
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	
	container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 5)
	scroll.add_child(container)


func show_comparison(item_id: String) -> void:
	_clear()
	
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	
	# 일반 아이템 (장비 아님)
	if equip_data.is_empty():
		_show_item_info(item_id)
		return
	
	visible = true
	
	# 장비 이름
	var name_lbl := Label.new()
	name_lbl.text = equip_data.get("name", "???")
	container.add_child(name_lbl)
	
	# 장비 스탯
	var stats: Dictionary = equip_data.get("stats", {})
	var stats_lbl := Label.new()
	stats_lbl.text = StatCompareUtil.format_equipment_stats(stats)
	container.add_child(stats_lbl)
	
	container.add_child(HSeparator.new())
	
	# 파티원별 비교
	var party := PartyManager.get_party()
	
	if party.is_empty():
		var no_party := Label.new()
		no_party.text = "파티원이 없습니다."
		container.add_child(no_party)
		return
	
	var title := Label.new()
	title.text = "--- 장착 시 변화 ---"
	container.add_child(title)
	
	var slot: String = equip_data.get("slot", "")
	var price: int = _get_price(equip_data)
	
	for hero in party:
		_add_hero_comparison(hero, item_id, stats, slot, price)
		container.add_child(HSeparator.new())


func _show_item_info(item_id: String) -> void:
	var item_data: Dictionary = DataManager.get_item(item_id)
	if item_data.is_empty():
		visible = false
		return
	
	visible = true
	
	var name_lbl := Label.new()
	name_lbl.text = item_data.get("name", "???")
	container.add_child(name_lbl)
	
	var desc_lbl := Label.new()
	desc_lbl.text = item_data.get("description", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	container.add_child(desc_lbl)


func _add_hero_comparison(hero: Hero, item_id: String, stats: Dictionary, slot: String, price: int) -> void:
	var hero_box := VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 2)
	
	var can_equip := hero.can_equip(item_id)
	
	# 영웅 이름
	var name_lbl := Label.new()
	name_lbl.text = "%s (%s)" % [hero.hero_name, hero.hero_class_name]
	if not can_equip:
		name_lbl.add_theme_color_override("font_color", Color.GRAY)
		name_lbl.text += " [장착불가]"
	hero_box.add_child(name_lbl)
	
	if can_equip:
		# 스탯 변화
		var changes := StatCompareUtil.calculate_stat_changes(hero, item_id)
		var change_text := StatCompareUtil.format_all_changes(changes)
		
		var rich_label := RichTextLabel.new()
		rich_label.bbcode_enabled = true
		rich_label.fit_content = true
		rich_label.custom_minimum_size.y = 20
		rich_label.text = change_text
		hero_box.add_child(rich_label)
		
		# 구매 후 장착 버튼
		var target_slot := StatCompareUtil.determine_equip_slot(hero, slot)
		
		var equip_btn := Button.new()
		equip_btn.text = "구매 후 장착"
		equip_btn.custom_minimum_size = Vector2(100, 25)
		equip_btn.disabled = GameManager.gold < price
		equip_btn.pressed.connect(func(): buy_and_equip_pressed.emit(item_id, price, hero, target_slot))
		hero_box.add_child(equip_btn)
	
	container.add_child(hero_box)


func _get_price(equip_data: Dictionary) -> int:
	var price: int = int(equip_data.get("buy_price", 0))
	if price == 0:
		price = int(equip_data.get("gear_score", 10)) * 10
	return price


func _clear() -> void:
	for child in container.get_children():
		child.queue_free()


func hide_panel() -> void:
	_clear()
	visible = false
