extends CanvasLayer
class_name LootSelectUI
## 3지선다 아이템 선택 UI

signal item_selected(item_id: String)

var panel: PanelContainer
var title_label: Label
var item_buttons: Array[Button] = []
var item_ids: Array[String] = []


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()


func _build_ui() -> void:
	# 어두운 배경
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	# 중앙 패널
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(400, 280)
	panel.position = Vector2(-200, -140)
	add_child(panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	# 타이틀
	title_label = Label.new()
	title_label.text = "🎁 전리품을 선택하세요!"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color.GOLD)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)
	
	# 구분선
	var separator := HSeparator.new()
	vbox.add_child(separator)
	
	# 아이템 버튼 3개
	var button_container := VBoxContainer.new()
	button_container.add_theme_constant_override("separation", 10)
	vbox.add_child(button_container)
	
	for i in range(3):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(350, 50)
		btn.pressed.connect(_on_item_selected.bind(i))
		button_container.add_child(btn)
		item_buttons.append(btn)


func show_loot_selection(items: Array[String]) -> void:
	item_ids = items
	
	for i in range(3):
		if i < items.size():
			var item_id: String = items[i]
			var item_data: Dictionary = _get_item_data(item_id)
			var item_name: String = str(item_data.get("name", item_id))
			var rarity: String = str(item_data.get("rarity", "common"))
			var stats_text: String = _get_stats_text(item_data)
			
			# 등급별 색상
			var color: Color = _get_rarity_color(rarity)
			var rarity_text: String = _get_rarity_text(rarity)
			
			item_buttons[i].text = "[%s] %s\n%s" % [rarity_text, item_name, stats_text]
			item_buttons[i].add_theme_color_override("font_color", color)
			item_buttons[i].visible = true
		else:
			item_buttons[i].visible = false
	
	show()
	get_tree().paused = true


func _get_item_data(item_id: String) -> Dictionary:
	# 장비인지 아이템인지 확인
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	if not equip_data.is_empty():
		return equip_data
	return DataManager.get_item(item_id)


func _get_stats_text(data: Dictionary) -> String:
	var parts: Array[String] = []
	var stats: Dictionary = data.get("stats", {})
	
	if stats.has("atk") and int(stats.get("atk", 0)) > 0:
		parts.append("ATK +%d" % int(stats.get("atk", 0)))
	if stats.has("def") and int(stats.get("def", 0)) > 0:
		parts.append("DEF +%d" % int(stats.get("def", 0)))
	if stats.has("hp") and int(stats.get("hp", 0)) > 0:
		parts.append("HP +%d" % int(stats.get("hp", 0)))
	if stats.has("mp") and int(stats.get("mp", 0)) > 0:
		parts.append("MP +%d" % int(stats.get("mp", 0)))
	if stats.has("str") and int(stats.get("str", 0)) > 0:
		parts.append("STR +%d" % int(stats.get("str", 0)))
	if stats.has("int") and int(stats.get("int", 0)) > 0:
		parts.append("INT +%d" % int(stats.get("int", 0)))
	if stats.has("dex") and int(stats.get("dex", 0)) > 0:
		parts.append("DEX +%d" % int(stats.get("dex", 0)))
	if stats.has("luk") and int(stats.get("luk", 0)) > 0:
		parts.append("LUK +%d" % int(stats.get("luk", 0)))
	
	if parts.is_empty():
		var desc: String = str(data.get("description", ""))
		if not desc.is_empty():
			return desc
		return "일반 아이템"
	
	return ", ".join(parts)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"legendary":
			return Color.ORANGE
		"magic":
			return Color.DODGER_BLUE
		_:
			return Color.WHITE


func _get_rarity_text(rarity: String) -> String:
	match rarity:
		"legendary":
			return "전설"
		"magic":
			return "마법"
		_:
			return "일반"


func _on_item_selected(index: int) -> void:
	if index < item_ids.size():
		var selected_id: String = item_ids[index]
		item_selected.emit(selected_id)
	
	get_tree().paused = false
	hide()
