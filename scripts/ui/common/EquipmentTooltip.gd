extends PanelContainer
class_name EquipmentTooltip
## 장비 비교 툴팁: 모든 파티원 비교 (루프히어로 스타일 - 패널 왼쪽 고정)

var item_id: String = ""
var item_data: Dictionary = {}

# 고정 위치 앵커 (인벤토리 패널 왼쪽에 붙임)
var anchor_control: Control = null
var anchor_offset: Vector2 = Vector2(-8, 0)

const STAT_NAMES: Dictionary = {
	"hp": "HP",
	"mp": "MP",
	"str": "STR",
	"def": "DEF",
	"int": "INT",
	"dex": "DEX",
	"luk": "LUK",
	"atk": "ATK"
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	visible = true
	
	# 스타일 설정
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.98)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.55)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)


func setup_for_item(p_item_id: String, p_anchor: Control = null) -> void:
	item_id = p_item_id
	anchor_control = p_anchor
	
	# 장비인지 소비 아이템인지 확인
	item_data = DataManager.get_equipment(p_item_id)
	if item_data.is_empty():
		# 소비 아이템 체크
		item_data = DataManager.get_item(p_item_id)
		if not item_data.is_empty() and item_data.get("type", "") == "consumable":
			_build_consumable_tooltip()
		else:
			return
	else:
		_build_tooltip_all_heroes()
	
	call_deferred("_update_position")


# 기존 호환성 유지
func setup(p_hero: Hero, equipped_id: String, inventory_id: String, p_anchor: Control = null) -> void:
	setup_for_item(inventory_id, p_anchor)


func _update_position() -> void:
	if anchor_control and is_instance_valid(anchor_control):
		# 앵커 컨트롤(인벤토리 패널)의 왼쪽에 배치
		var anchor_rect: Rect2 = anchor_control.get_global_rect()
		
		# 툴팁을 앵커 왼쪽에 배치
		var tooltip_x: float = anchor_rect.position.x - size.x + anchor_offset.x
		var tooltip_y: float = anchor_rect.position.y + anchor_offset.y
		
		# 화면 왼쪽 밖으로 나가지 않게
		if tooltip_x < 5:
			tooltip_x = 5
		
		# 화면 아래로 나가지 않게
		var viewport_size: Vector2 = get_viewport_rect().size
		if tooltip_y + size.y > viewport_size.y - 5:
			tooltip_y = viewport_size.y - size.y - 5
		
		global_position = Vector2(tooltip_x, tooltip_y)
	else:
		# 앵커가 없으면 화면 중앙에 표시
		global_position = Vector2(100, 100)


func _build_tooltip_all_heroes() -> void:
	# 기존 내용 제거
	for child in get_children():
		child.queue_free()
	
	if item_data.is_empty():
		return
	
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	add_child(main_vbox)
	
	# === 아이템 정보 ===
	var item_panel := _create_item_info_panel()
	main_vbox.add_child(item_panel)
	
	# 구분선
	var sep := HSeparator.new()
	main_vbox.add_child(sep)
	
	# === 각 파티원별 비교 ===
	var party: Array = PartyManager.get_party() if PartyManager else []
	var item_slot: String = str(item_data.get("slot", ""))
	
	for hero in party:
		# 장착 가능 여부 체크
		if not _can_hero_equip(hero, item_slot):
			continue
		
		var hero_compare := _create_hero_compare_panel(hero, item_slot)
		main_vbox.add_child(hero_compare)


func _create_item_info_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2)
	
	# 아이템 이름
	var name_label := Label.new()
	name_label.text = str(item_data.get("name", item_id))
	name_label.add_theme_font_size_override("font_size", 11)
	
	var rarity: String = str(item_data.get("rarity", "common"))
	match rarity:
		"magic":
			name_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
		"legendary":
			name_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
		_:
			name_label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(name_label)
	
	# 슬롯 타입
	var slot_label := Label.new()
	var slot_name: String = str(item_data.get("slot", ""))
	var slot_display: Dictionary = {
		"main_hand": "주무기", "off_hand": "보조", "head": "머리",
		"body": "몸통", "shoes": "신발", "necklace": "목걸이", "ring1": "반지", "ring2": "반지"
	}
	slot_label.text = slot_display.get(slot_name, slot_name)
	slot_label.add_theme_font_size_override("font_size", 8)
	slot_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	panel.add_child(slot_label)
	
	# 스탯
	var stats: Dictionary = item_data.get("stats", {})
	for stat_key in stats:
		var stat_value: int = int(stats[stat_key])
		var stat_hbox := HBoxContainer.new()
		
		var stat_name := Label.new()
		stat_name.text = STAT_NAMES.get(stat_key, stat_key.to_upper())
		stat_name.custom_minimum_size.x = 30
		stat_name.add_theme_font_size_override("font_size", 9)
		stat_name.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		stat_hbox.add_child(stat_name)
		
		var stat_val := Label.new()
		stat_val.text = "+%d" % stat_value if stat_value > 0 else "%d" % stat_value
		stat_val.add_theme_font_size_override("font_size", 9)
		stat_hbox.add_child(stat_val)
		
		panel.add_child(stat_hbox)
	
	return panel


func _create_hero_compare_panel(hero: Hero, item_slot: String) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	
	# 영웅 이름
	var name_label := Label.new()
	name_label.text = hero.hero_name
	name_label.custom_minimum_size.x = 45
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	hbox.add_child(name_label)
	
	# 비교할 슬롯 결정
	var check_slot := item_slot
	if item_slot in ["ring", "ring1", "ring2"]:
		check_slot = "ring1"
	
	# 현재 장착 아이템
	var equipped_id: String = hero.equipment.get(check_slot, "")
	var equipped_data: Dictionary = DataManager.get_equipment(equipped_id) if equipped_id else {}
	
	# 스탯 차이 계산
	var new_stats: Dictionary = item_data.get("stats", {})
	var old_stats: Dictionary = equipped_data.get("stats", {}) if equipped_data else {}
	
	# 모든 스탯 키
	var all_keys: Array = []
	for k in new_stats.keys():
		if k not in all_keys:
			all_keys.append(k)
	for k in old_stats.keys():
		if k not in all_keys:
			all_keys.append(k)
	
	# 변화량 표시
	var changes_text: String = ""
	for stat_key in all_keys:
		var new_val: int = int(new_stats.get(stat_key, 0))
		var old_val: int = int(old_stats.get(stat_key, 0))
		var diff: int = new_val - old_val
		
		if diff != 0:
			var stat_short: String = STAT_NAMES.get(stat_key, stat_key.to_upper())
			if diff > 0:
				changes_text += "[color=lime]%s+%d[/color] " % [stat_short, diff]
			else:
				changes_text += "[color=red]%s%d[/color] " % [stat_short, diff]
	
	if changes_text.is_empty():
		changes_text = "[color=gray]변화없음[/color]"
	
	var changes_label := RichTextLabel.new()
	changes_label.bbcode_enabled = true
	changes_label.fit_content = true
	changes_label.scroll_active = false
	changes_label.custom_minimum_size.x = 100
	changes_label.add_theme_font_size_override("normal_font_size", 8)
	changes_label.text = changes_text
	hbox.add_child(changes_label)
	
	return hbox


func _can_hero_equip(hero: Hero, item_slot: String) -> bool:
	# 기본적으로 모든 영웅이 장착 가능
	# 나중에 직업별 제한 추가 가능
	if hero.is_dead:
		return false
	return true


func _build_consumable_tooltip() -> void:
	## 소비 아이템용 툴팁 빌드
	for child in get_children():
		child.queue_free()
	
	if item_data.is_empty():
		return
	
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	add_child(main_vbox)
	
	# 아이템 이름
	var name_label := Label.new()
	name_label.text = str(item_data.get("name", item_id))
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))  # 녹색 계열
	main_vbox.add_child(name_label)
	
	# 카테고리
	var category: String = str(item_data.get("category", ""))
	var category_display: Dictionary = {
		"recovery": "회복",
		"revival": "부활",
		"camping": "야영",
		"escape": "도주",
		"seed": "씨앗"
	}
	var category_label := Label.new()
	category_label.text = category_display.get(category, category)
	category_label.add_theme_font_size_override("font_size", 8)
	category_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	main_vbox.add_child(category_label)
	
	# 구분선
	var sep := HSeparator.new()
	main_vbox.add_child(sep)
	
	# 설명
	var desc_label := Label.new()
	desc_label.text = str(item_data.get("description", ""))
	desc_label.add_theme_font_size_override("font_size", 9)
	desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size.x = 150
	main_vbox.add_child(desc_label)
	
	# 사용 가능 여부
	var usable_hbox := HBoxContainer.new()
	usable_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(usable_hbox)
	
	var field_usable: bool = item_data.get("usable_in_field", false)
	var battle_usable: bool = item_data.get("usable_in_battle", false)
	
	var field_label := Label.new()
	field_label.text = "필드: " + ("⭕" if field_usable else "❌")
	field_label.add_theme_font_size_override("font_size", 8)
	field_label.add_theme_color_override("font_color", Color.LIME if field_usable else Color.GRAY)
	usable_hbox.add_child(field_label)
	
	var battle_label := Label.new()
	battle_label.text = "전투: " + ("⭕" if battle_usable else "❌")
	battle_label.add_theme_font_size_override("font_size", 8)
	battle_label.add_theme_color_override("font_color", Color.LIME if battle_usable else Color.GRAY)
	usable_hbox.add_child(battle_label)
	
	# 드래그 힌트
	var hint_label := Label.new()
	hint_label.text = "▶ 파티원에게 드래그하여 사용"
	hint_label.add_theme_font_size_override("font_size", 8)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	main_vbox.add_child(hint_label)
