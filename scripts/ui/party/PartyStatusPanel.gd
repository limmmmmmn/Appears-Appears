extends Control
class_name PartyStatusPanel  # ← 2번째 줄에 추가!
## PartyStatusPanel: ...
## PartyStatusPanel: 파티 상태창 (스탯, 장비 장착, 인벤토리) + 장비 프리뷰

signal closed

var selected_hero_index: int = 0
var hovered_item_id: String = ""

var hero_buttons: Array[Button] = []
var stat_labels: Dictionary = {}
var equip_buttons: Dictionary = {}
var inventory_container: VBoxContainer
var preview_label: RichTextLabel

const SLOT_NAMES := {
	"main_hand": "주무기",
	"off_hand": "보조",
	"head": "머리",
	"body": "몸통",
	"acc1": "악세1",
	"acc2": "악세2",
	"acc3": "악세3",
	"acc4": "악세4"
}


func _ready() -> void:
	_build_ui()
	_refresh_all()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close_pressed()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.15, 0.95)
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
	main_vbox.add_theme_constant_override("separation", 5)
	margin.add_child(main_vbox)
	
	# 타이틀
	var title_hbox := HBoxContainer.new()
	main_vbox.add_child(title_hbox)
	
	var title := Label.new()
	title.text = "[ 파티 상태 ]"
	title_hbox.add_child(title)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(spacer)
	
	var close_btn := Button.new()
	close_btn.text = "닫기 (ESC)"
	close_btn.pressed.connect(_on_close_pressed)
	title_hbox.add_child(close_btn)
	
	main_vbox.add_child(HSeparator.new())
	
	# 영웅 선택
	var hero_select := HBoxContainer.new()
	hero_select.add_theme_constant_override("separation", 5)
	main_vbox.add_child(hero_select)
	
	for i in range(4):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(90, 25)
		btn.pressed.connect(_on_hero_selected.bind(i))
		hero_select.add_child(btn)
		hero_buttons.append(btn)
	
	main_vbox.add_child(HSeparator.new())
	
	# 메인 컨텐츠
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 15)
	main_vbox.add_child(content)
	
	# 좌측: 스탯 + 장비
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	content.add_child(left)
	
	# 스탯
	var stat_grid := GridContainer.new()
	stat_grid.columns = 4
	stat_grid.add_theme_constant_override("h_separation", 15)
	stat_grid.add_theme_constant_override("v_separation", 2)
	left.add_child(stat_grid)
	
	for stat_name in ["HP", "STR", "DEF", "INT", "DEX", "LUK", "ATK"]:
		var lbl := Label.new()
		lbl.text = "%s: ---" % stat_name
		stat_grid.add_child(lbl)
		stat_labels[stat_name] = lbl
	
	left.add_child(HSeparator.new())
	
	# 장비
	var equip_lbl := Label.new()
	equip_lbl.text = "--- 장비 (클릭 = 해제) ---"
	left.add_child(equip_lbl)
	
	var equip_grid := GridContainer.new()
	equip_grid.columns = 2
	equip_grid.add_theme_constant_override("h_separation", 10)
	equip_grid.add_theme_constant_override("v_separation", 3)
	left.add_child(equip_grid)
	
	for slot in SLOT_NAMES:
		var slot_lbl := Label.new()
		slot_lbl.text = SLOT_NAMES[slot] + ":"
		slot_lbl.custom_minimum_size.x = 60
		equip_grid.add_child(slot_lbl)
		
		var equip_btn := Button.new()
		equip_btn.text = "(빈 슬롯)"
		equip_btn.custom_minimum_size.x = 140
		equip_btn.pressed.connect(_on_equip_slot_pressed.bind(slot))
		equip_grid.add_child(equip_btn)
		equip_buttons[slot] = equip_btn
	
	left.add_child(HSeparator.new())
	
	# 프리뷰
	var preview_title := Label.new()
	preview_title.text = "--- 장착 시 변화 ---"
	left.add_child(preview_title)
	
	preview_label = RichTextLabel.new()
	preview_label.bbcode_enabled = true
	preview_label.fit_content = true
	preview_label.custom_minimum_size = Vector2(0, 40)
	preview_label.text = "인벤토리에서 장비에 마우스를 올려보세요."
	left.add_child(preview_label)
	
	# 우측: 인벤토리
	content.add_child(VSeparator.new())
	
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 3)
	content.add_child(right)
	
	var inv_title := Label.new()
	inv_title.text = "--- 인벤토리 (클릭 = 장착) ---"
	right.add_child(inv_title)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	
	inventory_container = VBoxContainer.new()
	inventory_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_container.add_theme_constant_override("separation", 2)
	scroll.add_child(inventory_container)


func _refresh_all() -> void:
	_refresh_hero_buttons()
	_refresh_hero_info()
	_refresh_inventory()


func _refresh_hero_buttons() -> void:
	var party := PartyManager.get_party()
	for i in range(4):
		if i < party.size():
			var hero: Hero = party[i]
			hero_buttons[i].text = hero.hero_name
			hero_buttons[i].disabled = false
			hero_buttons[i].modulate = Color.WHITE if not hero.is_dead else Color(1, 0.5, 0.5)
		else:
			hero_buttons[i].text = "(없음)"
			hero_buttons[i].disabled = true
	
	for i in range(4):
		if i == selected_hero_index:
			hero_buttons[i].add_theme_color_override("font_color", Color.YELLOW)
		else:
			hero_buttons[i].remove_theme_color_override("font_color")


func _refresh_hero_info() -> void:
	var party := PartyManager.get_party()
	if selected_hero_index >= party.size():
		selected_hero_index = 0
	
	if party.is_empty():
		for stat_name in stat_labels:
			stat_labels[stat_name].text = "%s: ---" % stat_name
		for slot in equip_buttons:
			equip_buttons[slot].text = "(없음)"
			equip_buttons[slot].disabled = true
		return
	
	var hero: Hero = party[selected_hero_index]
	
	stat_labels["HP"].text = "HP: %d/%d" % [hero.current_hp, hero.get_max_hp()]
	stat_labels["STR"].text = "STR: %d" % hero.get_str()
	stat_labels["DEF"].text = "DEF: %d" % hero.get_def()
	stat_labels["INT"].text = "INT: %d" % hero.get_int()
	stat_labels["DEX"].text = "DEX: %d" % hero.get_dex()
	stat_labels["LUK"].text = "LUK: %d" % hero.get_luk()
	stat_labels["ATK"].text = "ATK: %d" % hero.get_atk()
	
	for slot in equip_buttons:
		var equip_id: String = hero.equipment.get(slot, "")
		if equip_id.is_empty():
			equip_buttons[slot].text = "(빈 슬롯)"
		else:
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			equip_buttons[slot].text = equip_data.get("name", "???")
		
		if slot == "off_hand" and hero.is_off_hand_disabled():
			equip_buttons[slot].text = "(양손무기)"
			equip_buttons[slot].disabled = true
		else:
			equip_buttons[slot].disabled = false


func _refresh_inventory() -> void:
	for child in inventory_container.get_children():
		child.queue_free()
	
	await get_tree().process_frame
	
	var inventory := PartyManager.get_all_items()
	
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "(비어있음)"
		inventory_container.add_child(empty)
		return
	
	var equipments: Array = []

	for item_id in inventory:
		var count: int = inventory[item_id]
		var equip_data: Dictionary = DataManager.get_equipment(item_id)
		if not equip_data.is_empty():
			equipments.append({"id": item_id, "count": count, "data": equip_data})

	if not equipments.is_empty():
		var equip_title := Label.new()
		equip_title.text = "[장비]"
		inventory_container.add_child(equip_title)

		for item in equipments:
			var btn := Button.new()
			btn.text = "%s x%d" % [item["data"].get("name", "???"), item["count"]]
			btn.custom_minimum_size.x = 160
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_on_inventory_item_pressed.bind(item["id"]))
			btn.mouse_entered.connect(_on_item_hovered.bind(item["id"]))
			btn.focus_entered.connect(_on_item_hovered.bind(item["id"]))
			btn.mouse_exited.connect(_on_item_unhovered)
			btn.focus_exited.connect(_on_item_unhovered)
			inventory_container.add_child(btn)


func _on_hero_selected(index: int) -> void:
	var party := PartyManager.get_party()
	if index < party.size():
		selected_hero_index = index
		_refresh_hero_buttons()
		_refresh_hero_info()
		if not hovered_item_id.is_empty():
			_update_preview(hovered_item_id)


func _on_equip_slot_pressed(slot: String) -> void:
	var party := PartyManager.get_party()
	if selected_hero_index >= party.size():
		return
	
	var hero: Hero = party[selected_hero_index]
	var current_equip: String = hero.equipment.get(slot, "")
	
	if not current_equip.is_empty():
		PartyManager.unequip_from_hero(hero, slot)
		_refresh_all()


func _on_item_hovered(item_id: String) -> void:
	hovered_item_id = item_id
	_update_preview(item_id)


func _on_item_unhovered() -> void:
	hovered_item_id = ""
	preview_label.text = "인벤토리에서 장비에 마우스를 올려보세요."


func _update_preview(item_id: String) -> void:
	var party := PartyManager.get_party()
	if selected_hero_index >= party.size():
		preview_label.text = "영웅을 선택해주세요."
		return
	
	var hero: Hero = party[selected_hero_index]
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	
	if equip_data.is_empty():
		preview_label.text = "장비가 아닙니다."
		return
	
	if not hero.can_equip(item_id):
		preview_label.text = "[color=gray]%s: 장착 불가[/color]" % hero.hero_name
		return
	
	var new_stats: Dictionary = equip_data.get("stats", {})
	var slot: String = equip_data.get("slot", "")
	var target_slot := slot
	if slot in ["acc", "ring", "necklace", "shoes", "ring1", "ring2"]:
		target_slot = "acc1"

	var current_equip_id: String = hero.equipment.get(target_slot, "")
	var current_equip: Dictionary = DataManager.get_equipment(current_equip_id) if current_equip_id else {}
	var current_stats: Dictionary = current_equip.get("stats", {})
	
	var text := "[%s] → %s\n" % [equip_data.get("name", "???"), hero.hero_name]
	var changes := ""
	
	# ATK
	if new_stats.has("atk") or current_stats.has("atk"):
		var cur := hero.get_atk()
		var old_bonus: int = int(current_stats.get("atk", 0))
		var new_bonus: int = int(new_stats.get("atk", 0))
		var new_val := cur - old_bonus + new_bonus
		var diff := new_val - cur
		changes += _format_stat_change("ATK", cur, new_val, diff)
	
	# DEF
	if new_stats.has("p_def") or new_stats.has("def") or current_stats.has("p_def") or current_stats.has("def"):
		var cur := hero.get_p_def()
		var old_bonus: int = int(current_stats.get("p_def", current_stats.get("def", 0)))
		var new_bonus: int = int(new_stats.get("p_def", new_stats.get("def", 0)))
		var new_val := cur - old_bonus + new_bonus
		var diff := new_val - cur
		changes += _format_stat_change("DEF", cur, new_val, diff)
	
	# INT
	if new_stats.has("int") or current_stats.has("int"):
		var cur := hero.get_int()
		var old_bonus: int = int(current_stats.get("int", 0))
		var new_bonus: int = int(new_stats.get("int", 0))
		var new_val := cur - old_bonus + new_bonus
		var diff := new_val - cur
		changes += _format_stat_change("INT", cur, new_val, diff)
	
	# DEX
	if new_stats.has("dex") or current_stats.has("dex"):
		var cur := hero.get_dex()
		var old_bonus: int = int(current_stats.get("dex", 0))
		var new_bonus: int = int(new_stats.get("dex", 0))
		var new_val := cur - old_bonus + new_bonus
		var diff := new_val - cur
		changes += _format_stat_change("DEX", cur, new_val, diff)
	
	# LUK
	if new_stats.has("luk") or current_stats.has("luk"):
		var cur := hero.get_luk()
		var old_bonus: int = int(current_stats.get("luk", 0))
		var new_bonus: int = int(new_stats.get("luk", 0))
		var new_val := cur - old_bonus + new_bonus
		var diff := new_val - cur
		changes += _format_stat_change("LUK", cur, new_val, diff)
	
	# HP
	if new_stats.has("hp") or current_stats.has("hp"):
		var cur := hero.get_max_hp()
		var old_bonus: int = int(current_stats.get("hp", 0))
		var new_bonus: int = int(new_stats.get("hp", 0))
		var new_val := cur - old_bonus + new_bonus
		var diff := new_val - cur
		changes += _format_stat_change("HP", cur, new_val, diff)

	if changes.is_empty():
		changes = "(스탯 변화 없음)"
	
	preview_label.text = text + changes


func _format_stat_change(stat_name: String, cur: int, new_val: int, diff: int) -> String:
	if diff > 0:
		return "%s: %d → %d ([color=lime]+%d[/color])  " % [stat_name, cur, new_val, diff]
	elif diff < 0:
		return "%s: %d → %d ([color=red]%d[/color])  " % [stat_name, cur, new_val, diff]
	else:
		return "%s: %d → %d  " % [stat_name, cur, new_val]


func _on_inventory_item_pressed(item_id: String) -> void:
	var party := PartyManager.get_party()
	if selected_hero_index >= party.size():
		return
	
	var hero: Hero = party[selected_hero_index]
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	
	if equip_data.is_empty():
		return
	
	if not hero.can_equip(item_id):
		return
	
	var slot: String = equip_data.get("slot", "")
	if slot in ["acc", "ring", "necklace", "shoes", "ring1", "ring2"]:
		slot = "acc1"
		for s in ["acc1", "acc2", "acc3", "acc4"]:
			if hero.equipment[s].is_empty():
				slot = s
				break

	PartyManager.equip_to_hero(hero, item_id, slot)
	_refresh_all()


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()


func _on_seed_used(item_id: String) -> void:
	var party := PartyManager.get_party()
	if selected_hero_index >= party.size():
		return
	
	var hero: Hero = party[selected_hero_index]
	var item_data: Dictionary = DataManager.get_item(item_id)
	
	if item_data.is_empty():
		return
	
	var effect: Dictionary = item_data.get("effect", {})
	if effect.get("type", "") != "permanent_stat":
		return
	
	var stat: String = effect.get("stat", "")
	var value: int = int(effect.get("value", 0))
	
	# 영구 스탯 증가 적용 (seed_bonus 사용)
	if hero.seed_bonus.has(stat):
		hero.seed_bonus[stat] += value
	
	# 아이템 소모
	PartyManager.remove_item(item_id)
	
	# 메시지 표시
	preview_label.text = "[color=lime]%s이(가) %s을(를) 사용했습니다![/color]\n%s +%d" % [
		hero.hero_name, item_data.get("name", ""), stat.to_upper(), value
	]
	
	_refresh_all()
