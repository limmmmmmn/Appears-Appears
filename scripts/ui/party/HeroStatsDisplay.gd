extends VBoxContainer
class_name HeroStatsDisplay
## 영웅 스탯 및 장비 표시 UI

signal equip_slot_pressed(slot: String)

var stat_labels: Dictionary = {}
var equip_buttons: Dictionary = {}
var preview_label: RichTextLabel

const SLOT_NAMES := {
	"main_hand": "주무기",
	"off_hand": "보조",
	"head": "머리",
	"body": "몸통",
	"acc1": "장신구1",
	"acc2": "장신구2"
}


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	_build_ui()


func _build_ui() -> void:
	# 스탯 그리드
	var stat_grid := GridContainer.new()
	stat_grid.columns = 4
	stat_grid.add_theme_constant_override("h_separation", 15)
	stat_grid.add_theme_constant_override("v_separation", 2)
	add_child(stat_grid)
	
	for stat_name in ["HP", "MP", "STR", "DEF", "INT", "DEX", "LUK", "ATK"]:
		var lbl := Label.new()
		lbl.text = "%s: ---" % stat_name
		stat_grid.add_child(lbl)
		stat_labels[stat_name] = lbl
	
	add_child(HSeparator.new())
	
	# 장비 섹션
	var equip_title := Label.new()
	equip_title.text = "--- 장비 (클릭 = 해제) ---"
	add_child(equip_title)
	
	var equip_grid := GridContainer.new()
	equip_grid.columns = 2
	equip_grid.add_theme_constant_override("h_separation", 10)
	equip_grid.add_theme_constant_override("v_separation", 3)
	add_child(equip_grid)
	
	for slot in SLOT_NAMES:
		var slot_lbl := Label.new()
		slot_lbl.text = SLOT_NAMES[slot] + ":"
		slot_lbl.custom_minimum_size.x = 60
		equip_grid.add_child(slot_lbl)
		
		var equip_btn := Button.new()
		equip_btn.text = "(빈 슬롯)"
		equip_btn.custom_minimum_size.x = 140
		equip_btn.pressed.connect(func(): equip_slot_pressed.emit(slot))
		equip_grid.add_child(equip_btn)
		equip_buttons[slot] = equip_btn
	
	add_child(HSeparator.new())
	
	# 프리뷰
	var preview_title := Label.new()
	preview_title.text = "--- 장착 시 변화 ---"
	add_child(preview_title)
	
	preview_label = RichTextLabel.new()
	preview_label.bbcode_enabled = true
	preview_label.fit_content = true
	preview_label.custom_minimum_size = Vector2(0, 40)
	preview_label.text = "인벤토리에서 장비에 마우스를 올려보세요."
	add_child(preview_label)


func update_display(hero: Hero) -> void:
	if not hero:
		_clear_display()
		return
	
	# 스탯 업데이트
	stat_labels["HP"].text = "HP: %d/%d" % [hero.current_hp, hero.get_max_hp()]
	stat_labels["MP"].text = "MP: %d/%d" % [hero.current_mp, hero.get_max_mp()]
	stat_labels["STR"].text = "STR: %d" % hero.get_str()
	stat_labels["DEF"].text = "DEF: %d" % hero.get_def()
	stat_labels["INT"].text = "INT: %d" % hero.get_int()
	stat_labels["DEX"].text = "DEX: %d" % hero.get_dex()
	stat_labels["LUK"].text = "LUK: %d" % hero.get_luk()
	stat_labels["ATK"].text = "ATK: %d" % hero.get_atk()
	
	# 장비 업데이트
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


func _clear_display() -> void:
	for stat_name in stat_labels:
		stat_labels[stat_name].text = "%s: ---" % stat_name
	for slot in equip_buttons:
		equip_buttons[slot].text = "(없음)"
		equip_buttons[slot].disabled = true


func show_equip_preview(hero: Hero, item_id: String) -> void:
	if not hero:
		preview_label.text = "영웅을 선택해주세요."
		return
	
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	if equip_data.is_empty():
		preview_label.text = "장비가 아닙니다."
		return
	
	if not hero.can_equip(item_id):
		preview_label.text = "[color=gray]%s: 장착 불가[/color]" % hero.hero_name
		return
	
	var changes := StatCompareUtil.calculate_stat_changes(hero, item_id)
	var text := "[%s] → %s\n" % [equip_data.get("name", "???"), hero.hero_name]
	text += StatCompareUtil.format_all_changes(changes)
	
	preview_label.text = text


func clear_preview() -> void:
	preview_label.text = "인벤토리에서 장비에 마우스를 올려보세요."


func show_seed_result(hero_name: String, item_name: String, stat: String, value: int) -> void:
	preview_label.text = "[color=lime]%s이(가) %s을(를) 사용했습니다![/color]\n%s +%d" % [
		hero_name, item_name, stat.to_upper(), value
	]
