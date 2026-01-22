extends Control
class_name ShopPanel  # ← 2번째 줄에 추가!
## ShopPanel: ...
## ShopPanel: 장비 구매 시 능력치 비교 가능한 상점

signal closed
signal item_purchased(item_id: String)

var shop_id: String = ""
var current_tab: String = "buy"
var selected_item_id: String = ""

# UI 참조
var title_label: Label
var gold_label: Label
var buy_tab_btn: Button
var sell_tab_btn: Button
var item_list_container: VBoxContainer
var compare_panel: PanelContainer
var compare_container: VBoxContainer
var message_label: Label

var item_buttons: Array[Button] = []


func _ready() -> void:
	_build_ui()
	_refresh_shop()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func setup(p_shop_id: String) -> void:
	shop_id = p_shop_id


func _build_ui() -> void:
	# 배경
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)
	
	# 상단: 타이틀 + 골드 + 닫기
	var top_hbox := HBoxContainer.new()
	main_vbox.add_child(top_hbox)
	
	title_label = Label.new()
	title_label.text = "[ 상점 ]"
	top_hbox.add_child(title_label)
	
	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer1)
	
	gold_label = Label.new()
	gold_label.text = "보유: 0 G"
	top_hbox.add_child(gold_label)
	
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.x = 20
	top_hbox.add_child(spacer2)
	
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.pressed.connect(_on_close_pressed)
	top_hbox.add_child(close_btn)
	
	main_vbox.add_child(HSeparator.new())
	
	# 탭 버튼
	var tab_hbox := HBoxContainer.new()
	tab_hbox.add_theme_constant_override("separation", 5)
	main_vbox.add_child(tab_hbox)
	
	buy_tab_btn = Button.new()
	buy_tab_btn.text = "구매"
	buy_tab_btn.pressed.connect(_on_tab_changed.bind("buy"))
	tab_hbox.add_child(buy_tab_btn)
	
	sell_tab_btn = Button.new()
	sell_tab_btn.text = "판매"
	sell_tab_btn.pressed.connect(_on_tab_changed.bind("sell"))
	tab_hbox.add_child(sell_tab_btn)
	
	main_vbox.add_child(HSeparator.new())
	
	# 메인 컨텐츠: 좌(아이템 목록) + 우(비교 패널)
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(content_hbox)
	
	# 좌측: 아이템 목록
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(left_panel)
	
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)
	
	item_list_container = VBoxContainer.new()
	item_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list_container.add_theme_constant_override("separation", 3)
	left_scroll.add_child(item_list_container)
	
	# 우측: 비교 패널
	compare_panel = PanelContainer.new()
	compare_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare_panel.visible = false
	content_hbox.add_child(compare_panel)
	
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compare_panel.add_child(right_scroll)
	
	compare_container = VBoxContainer.new()
	compare_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compare_container.add_theme_constant_override("separation", 5)
	right_scroll.add_child(compare_container)
	
	# 하단 메시지
	main_vbox.add_child(HSeparator.new())
	
	message_label = Label.new()
	message_label.text = "장비를 선택하면 능력치 변화를 확인할 수 있습니다."
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(message_label)


func _refresh_shop() -> void:
	_update_header()
	_update_tabs()
	_update_item_list()
	_clear_compare_panel()


func _update_header() -> void:
	var shop_data: Dictionary = DataManager.get_shop(shop_id)
	title_label.text = "[ %s ]" % shop_data.get("name", "상점")
	gold_label.text = "보유: %d G" % GameManager.gold


func _update_tabs() -> void:
	buy_tab_btn.disabled = (current_tab == "buy")
	sell_tab_btn.disabled = (current_tab == "sell")


func _update_item_list() -> void:
	# 기존 목록 제거
	for child in item_list_container.get_children():
		child.queue_free()
	item_buttons.clear()
	selected_item_id = ""
	
	await get_tree().process_frame
	
	if current_tab == "buy":
		_build_buy_list()
	else:
		_build_sell_list()


func _build_buy_list() -> void:
	var item_list: Array = DataManager.get_shop_items(shop_id)
	
	for item_id in item_list:
		var item_data: Dictionary = DataManager.get_item(item_id)
		if item_data.is_empty():
			continue
		
		var price: int = int(item_data.get("buy_price", 0))
		if price == 0:
			price = int(item_data.get("gear_score", 10)) * 10
		
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		
		var item_btn := Button.new()
		item_btn.text = item_data.get("name", "???")
		item_btn.custom_minimum_size.x = 120
		item_btn.focus_entered.connect(_on_item_focused.bind(item_id))
		item_btn.mouse_entered.connect(_on_item_focused.bind(item_id))
		item_btn.pressed.connect(_on_buy_pressed.bind(item_id, price))
		hbox.add_child(item_btn)
		item_buttons.append(item_btn)
		
		var price_lbl := Label.new()
		price_lbl.text = "%d G" % price
		price_lbl.custom_minimum_size.x = 60
		if GameManager.gold < price:
			price_lbl.add_theme_color_override("font_color", Color.RED)
		hbox.add_child(price_lbl)
		
		# 장비 슬롯 표시
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if not equip_data.is_empty():
			var slot_lbl := Label.new()
			var slot: String = equip_data.get("slot", "")
			slot_lbl.text = "[%s]" % _get_slot_display_name(slot)
			slot_lbl.add_theme_color_override("font_color", Color.GRAY)
			hbox.add_child(slot_lbl)
		
		item_list_container.add_child(hbox)
	
	# 첫 버튼에 포커스
	await get_tree().process_frame
	if item_buttons.size() > 0:
		item_buttons[0].grab_focus()


func _build_sell_list() -> void:
	# InventoryManager 사용
	var items: Array = []
	if InventoryManager:
		items = InventoryManager.get_all_items()
	
	if items.is_empty():
		var empty := Label.new()
		empty.text = "판매할 아이템이 없습니다."
		item_list_container.add_child(empty)
		return
	
	for item_info in items:
		var item_id: String = str(item_info.get("id", ""))
		var count: int = int(item_info.get("quantity", 1))
		var item_data: Dictionary = item_info.get("data", {})
		
		if item_data.is_empty():
			item_data = DataManager.get_item(item_id)
		if item_data.is_empty():
			continue
		
		var sell_price: int = int(item_data.get("sell_price", 0))
		if sell_price == 0:
			sell_price = int(item_data.get("gear_score", 5)) * 5
		
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		
		var item_btn := Button.new()
		item_btn.text = "%s x%d" % [item_data.get("name", "???"), count]
		item_btn.custom_minimum_size.x = 150
		item_btn.focus_entered.connect(_on_item_focused.bind(item_id))
		item_btn.mouse_entered.connect(_on_item_focused.bind(item_id))
		item_btn.pressed.connect(_on_sell_pressed.bind(item_id, sell_price))
		hbox.add_child(item_btn)
		item_buttons.append(item_btn)
		
		var price_lbl := Label.new()
		price_lbl.text = "+%d G" % sell_price
		price_lbl.custom_minimum_size.x = 60
		price_lbl.add_theme_color_override("font_color", Color.GOLD)
		hbox.add_child(price_lbl)
		
		item_list_container.add_child(hbox)
	
	# 첫 버튼에 포커스
	await get_tree().process_frame
	if item_buttons.size() > 0:
		item_buttons[0].grab_focus()


func _on_item_focused(item_id: String) -> void:
	selected_item_id = item_id
	_show_equipment_comparison(item_id)


func _show_equipment_comparison(item_id: String) -> void:
	# 기존 비교 패널 내용 제거
	for child in compare_container.get_children():
		child.queue_free()
	
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	if equip_data.is_empty():
		# 장비가 아닌 일반 아이템
		var item_data: Dictionary = DataManager.get_item(item_id)
		if item_data.is_empty():
			compare_panel.visible = false
			return
		
		compare_panel.visible = true
		
		var item_name := Label.new()
		item_name.text = item_data.get("name", "???")
		compare_container.add_child(item_name)
		
		var item_desc := Label.new()
		item_desc.text = item_data.get("description", "")
		item_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		compare_container.add_child(item_desc)
		
		message_label.text = "소비 아이템입니다."
		return
	
	compare_panel.visible = true
	
	# 장비 이름
	var equip_name := Label.new()
	equip_name.text = equip_data.get("name", "???")
	compare_container.add_child(equip_name)
	
	# 장비 스탯
	var stats: Dictionary = equip_data.get("stats", {})
	var equip_stats := Label.new()
	var stat_text := ""
	if stats.has("atk"):
		stat_text += "ATK +%d  " % int(stats["atk"])
	if stats.has("p_def") or stats.has("def"):
		var def_val: int = int(stats.get("p_def", stats.get("def", 0)))
		stat_text += "DEF +%d  " % def_val
	if stats.has("int"):
		stat_text += "INT +%d  " % int(stats["int"])
	if stats.has("spd"):
		stat_text += "SPD +%d  " % int(stats["spd"])
	if stats.has("str"):
		stat_text += "STR +%d  " % int(stats["str"])
	if stats.has("luk"):
		stat_text += "LUK +%d  " % int(stats["luk"])
	if stats.has("hp"):
		stat_text += "HP +%d  " % int(stats["hp"])
	if stats.has("mp"):
		stat_text += "MP +%d  " % int(stats["mp"])
	equip_stats.text = stat_text if stat_text else "(스탯 없음)"
	compare_container.add_child(equip_stats)
	
	compare_container.add_child(HSeparator.new())
	
	# 파티원별 비교
	var party := PartyManager.get_party()
	var slot: String = equip_data.get("slot", "")
	
	if party.is_empty():
		var no_party := Label.new()
		no_party.text = "파티원이 없습니다."
		compare_container.add_child(no_party)
		return
	
	var compare_title := Label.new()
	compare_title.text = "--- 장착 시 변화 ---"
	compare_container.add_child(compare_title)
	
	for hero in party:
		var hero_box := VBoxContainer.new()
		hero_box.add_theme_constant_override("separation", 2)
		
		# 장착 가능 여부
		var can_equip := hero.can_equip(item_id)
		
		var name_label := Label.new()
		name_label.text = "%s (%s)" % [hero.hero_name, hero.hero_class_name]
		if not can_equip:
			name_label.add_theme_color_override("font_color", Color.GRAY)
			name_label.text += " [장착불가]"
		hero_box.add_child(name_label)
		
		if can_equip:
			# 현재 장비 vs 새 장비 비교
			var target_slot := slot
			if slot == "accessory":
				target_slot = "acc1"
			
			var current_equip_id: String = hero.equipment.get(target_slot, "")
			var current_equip: Dictionary = DataManager.get_equipment(current_equip_id) if current_equip_id else {}
			var current_stats: Dictionary = current_equip.get("stats", {})
			var new_stats: Dictionary = stats
			
			var compare_text := ""
			
			# ATK 비교
			if new_stats.has("atk") or current_stats.has("atk"):
				var current_atk := hero.get_atk()
				var old_atk_bonus: int = int(current_stats.get("atk", 0))
				var new_atk_bonus: int = int(new_stats.get("atk", 0))
				var new_atk := current_atk - old_atk_bonus + new_atk_bonus
				var atk_diff := new_atk - current_atk
				
				if atk_diff > 0:
					compare_text += "ATK: %d → %d ([color=lime]+%d[/color])  " % [current_atk, new_atk, atk_diff]
				elif atk_diff < 0:
					compare_text += "ATK: %d → %d ([color=red]%d[/color])  " % [current_atk, new_atk, atk_diff]
				else:
					compare_text += "ATK: %d → %d  " % [current_atk, new_atk]
			
			# DEF 비교
			if new_stats.has("p_def") or new_stats.has("def") or current_stats.has("p_def") or current_stats.has("def"):
				var current_def := hero.get_p_def()
				var old_def_bonus: int = int(current_stats.get("p_def", current_stats.get("def", 0)))
				var new_def_bonus: int = int(new_stats.get("p_def", new_stats.get("def", 0)))
				var new_def := current_def - old_def_bonus + new_def_bonus
				var def_diff := new_def - current_def
				
				if def_diff > 0:
					compare_text += "DEF: %d → %d ([color=lime]+%d[/color])  " % [current_def, new_def, def_diff]
				elif def_diff < 0:
					compare_text += "DEF: %d → %d ([color=red]%d[/color])  " % [current_def, new_def, def_diff]
				else:
					compare_text += "DEF: %d → %d  " % [current_def, new_def]
			
			# INT 비교
			if new_stats.has("int") or current_stats.has("int"):
				var current_int := hero.get_int()
				var old_int_bonus: int = int(current_stats.get("int", 0))
				var new_int_bonus: int = int(new_stats.get("int", 0))
				var new_int := current_int - old_int_bonus + new_int_bonus
				var int_diff := new_int - current_int
				
				if int_diff > 0:
					compare_text += "INT: %d → %d ([color=lime]+%d[/color])  " % [current_int, new_int, int_diff]
				elif int_diff < 0:
					compare_text += "INT: %d → %d ([color=red]%d[/color])  " % [current_int, new_int, int_diff]
				else:
					compare_text += "INT: %d → %d  " % [current_int, new_int]
			
			# SPD 비교
			if new_stats.has("spd") or current_stats.has("spd"):
				var current_spd := hero.get_spd()
				var old_spd_bonus: int = int(current_stats.get("spd", 0))
				var new_spd_bonus: int = int(new_stats.get("spd", 0))
				var new_spd := current_spd - old_spd_bonus + new_spd_bonus
				var spd_diff := new_spd - current_spd
				
				if spd_diff > 0:
					compare_text += "SPD: %d → %d ([color=lime]+%d[/color])  " % [current_spd, new_spd, spd_diff]
				elif spd_diff < 0:
					compare_text += "SPD: %d → %d ([color=red]%d[/color])  " % [current_spd, new_spd, spd_diff]
				else:
					compare_text += "SPD: %d → %d  " % [current_spd, new_spd]
			
			# LUK 비교
			if new_stats.has("luk") or current_stats.has("luk"):
				var current_luk := hero.get_luk()
				var old_luk_bonus: int = int(current_stats.get("luk", 0))
				var new_luk_bonus: int = int(new_stats.get("luk", 0))
				var new_luk := current_luk - old_luk_bonus + new_luk_bonus
				var luk_diff := new_luk - current_luk
				
				if luk_diff > 0:
					compare_text += "LUK: %d → %d ([color=lime]+%d[/color])  " % [current_luk, new_luk, luk_diff]
				elif luk_diff < 0:
					compare_text += "LUK: %d → %d ([color=red]%d[/color])  " % [current_luk, new_luk, luk_diff]
				else:
					compare_text += "LUK: %d → %d  " % [current_luk, new_luk]
			
			# HP 비교
			if new_stats.has("hp") or current_stats.has("hp"):
				var current_hp := hero.get_max_hp()
				var old_hp_bonus: int = int(current_stats.get("hp", 0))
				var new_hp_bonus: int = int(new_stats.get("hp", 0))
				var new_hp := current_hp - old_hp_bonus + new_hp_bonus
				var hp_diff := new_hp - current_hp
				
				if hp_diff > 0:
					compare_text += "HP: %d → %d ([color=lime]+%d[/color])  " % [current_hp, new_hp, hp_diff]
				elif hp_diff < 0:
					compare_text += "HP: %d → %d ([color=red]%d[/color])  " % [current_hp, new_hp, hp_diff]
				else:
					compare_text += "HP: %d → %d  " % [current_hp, new_hp]
			
			# MP 비교
			if new_stats.has("mp") or current_stats.has("mp"):
				var current_mp := hero.get_max_mp()
				var old_mp_bonus: int = int(current_stats.get("mp", 0))
				var new_mp_bonus: int = int(new_stats.get("mp", 0))
				var new_mp := current_mp - old_mp_bonus + new_mp_bonus
				var mp_diff := new_mp - current_mp
				
				if mp_diff > 0:
					compare_text += "MP: %d → %d ([color=lime]+%d[/color])  " % [current_mp, new_mp, mp_diff]
				elif mp_diff < 0:
					compare_text += "MP: %d → %d ([color=red]%d[/color])  " % [current_mp, new_mp, mp_diff]
				else:
					compare_text += "MP: %d → %d  " % [current_mp, new_mp]
			
			if compare_text.is_empty():
				compare_text = "(스탯 변화 없음)"
			
			var rich_label := RichTextLabel.new()
			rich_label.bbcode_enabled = true
			rich_label.fit_content = true
			rich_label.custom_minimum_size.y = 20
			rich_label.text = compare_text
			hero_box.add_child(rich_label)
			
			# 구매 후 장착 버튼
			var equip_btn := Button.new()
			equip_btn.text = "구매 후 장착"
			equip_btn.custom_minimum_size = Vector2(100, 25)
			var price: int = int(equip_data.get("buy_price", 0))
			if price == 0:
				price = int(equip_data.get("gear_score", 10)) * 10
			equip_btn.disabled = GameManager.gold < price
			equip_btn.pressed.connect(_on_buy_and_equip.bind(item_id, price, hero, target_slot))
			hero_box.add_child(equip_btn)
		
		compare_container.add_child(hero_box)
		compare_container.add_child(HSeparator.new())
	
	message_label.text = "클릭하면 구매, '구매 후 장착'으로 바로 장착 가능"


func _clear_compare_panel() -> void:
	for child in compare_container.get_children():
		child.queue_free()
	compare_panel.visible = false
	message_label.text = "장비를 선택하면 능력치 변화를 확인할 수 있습니다."


func _get_slot_display_name(slot: String) -> String:
	match slot:
		"main_hand": return "주무기"
		"off_hand": return "보조"
		"head": return "머리"
		"body": return "몸통"
		"accessory": return "장신구"
		_: return slot


func _on_tab_changed(tab: String) -> void:
	current_tab = tab
	_refresh_shop()


func _on_buy_pressed(item_id: String, price: int) -> void:
	if GameManager.gold < price:
		message_label.text = "골드가 부족합니다!"
		return
	
	if GameManager.spend_gold(price):
		# InventoryManager에 추가!
		if InventoryManager:
			InventoryManager.add_item(item_id, 1)
		var item_data: Dictionary = DataManager.get_item(item_id)
		message_label.text = "%s 구매 완료!" % item_data.get("name", "")
		item_purchased.emit(item_id)
		_refresh_shop()


func _on_buy_and_equip(item_id: String, price: int, hero: Hero, slot: String) -> void:
	if GameManager.gold < price:
		message_label.text = "골드가 부족합니다!"
		return
	
	if GameManager.spend_gold(price):
		# InventoryManager에 추가 후 장착
		if InventoryManager:
			InventoryManager.add_item(item_id, 1)
			InventoryManager.equip_item(hero, item_id, slot)
		var item_data: Dictionary = DataManager.get_item(item_id)
		message_label.text = "%s → %s 장착!" % [item_data.get("name", ""), hero.hero_name]
		item_purchased.emit(item_id)
		_refresh_shop()


func _on_sell_pressed(item_id: String, price: int) -> void:
	# InventoryManager에서 제거
	if InventoryManager and InventoryManager.remove_item(item_id, 1):
		GameManager.add_gold(price)
		var item_data: Dictionary = DataManager.get_item(item_id)
		message_label.text = "%s 판매 완료! (+%d G)" % [item_data.get("name", ""), price]
		_refresh_shop()


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
