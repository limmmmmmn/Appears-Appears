extends PanelContainer
class_name EquippedItemTooltip
## 장착 아이템 툴팁 (Loop Hero 스타일)
## "장비 중:" 형태로 현재 장착된 아이템 정보를 표시

var item_id: String = ""
var item_data: Dictionary = {}
var slot_name: String = ""

const STAT_NAMES: Dictionary = {
	"hp": "최대 hp",
	"mp": "최대 mp",
	"str": "힘",
	"def": "방어력",
	"int": "지능",
	"dex": "민첩",
	"luk": "행운",
	"atk": "공격력"
}

const SLOT_NAMES_KR: Dictionary = {
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	visible = true
	
	_setup_style()


func _setup_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.98)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.4, 0.4, 0.45)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)


func setup(p_item_id: String, p_slot_name: String, anchor_rect: Rect2) -> void:
	## 툴팁 설정
	## anchor_rect: 파티 슬롯의 global_rect (툴팁을 왼쪽에 배치하기 위해)
	item_id = p_item_id
	slot_name = p_slot_name
	
	if item_id.is_empty():
		# 빈 슬롯이면 빈 슬롯 툴팁 표시
		_build_empty_slot_tooltip()
	else:
		item_data = DataManager.get_equipment(item_id)
		if item_data.is_empty():
			queue_free()
			return
		_build_tooltip()
	
	# 위치 설정 (파티 슬롯 왼쪽에 배치)
	call_deferred("_update_position", anchor_rect)


func _update_position(anchor_rect: Rect2) -> void:
	# 툴팁을 앵커(파티 슬롯) 왼쪽에 배치
	var tooltip_x: float = anchor_rect.position.x - size.x - 8
	var tooltip_y: float = anchor_rect.position.y
	
	# 화면 왼쪽 밖으로 나가지 않게
	if tooltip_x < 5:
		tooltip_x = 5
	
	# 화면 아래로 나가지 않게
	var viewport_size: Vector2 = get_viewport_rect().size
	if tooltip_y + size.y > viewport_size.y - 5:
		tooltip_y = viewport_size.y - size.y - 5
	
	global_position = Vector2(tooltip_x, tooltip_y)


func _build_empty_slot_tooltip() -> void:
	## 빈 슬롯 툴팁
	for child in get_children():
		child.queue_free()
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	
	# 헤더: 장비 중:
	var header := Label.new()
	header.text = "장비 중:"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(header)
	
	# 슬롯 이름
	var slot_label := Label.new()
	slot_label.text = SLOT_NAMES_KR.get(slot_name, slot_name)
	slot_label.add_theme_font_size_override("font_size", 12)
	slot_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(slot_label)
	
	# 비어있음 표시
	var empty_label := Label.new()
	empty_label.text = "(비어있음)"
	empty_label.add_theme_font_size_override("font_size", 10)
	empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	vbox.add_child(empty_label)


func _build_tooltip() -> void:
	## 장착 아이템 툴팁 빌드 (Loop Hero 스타일)
	for child in get_children():
		child.queue_free()
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	
	# 헤더: "장비 중:"
	var header := Label.new()
	header.text = "장비 중:"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(header)
	
	# 구분선
	var sep1 := HSeparator.new()
	vbox.add_child(sep1)
	
	# 아이템 이름 (등급 색상 적용)
	var name_label := Label.new()
	name_label.text = str(item_data.get("name", item_id))
	name_label.add_theme_font_size_override("font_size", 12)
	
	var rarity: String = str(item_data.get("rarity", "common"))
	match rarity:
		"magic":
			name_label.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
		"legendary":
			name_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
		_:
			name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(name_label)
	
	# 슬롯 타입
	var slot_display: String = SLOT_NAMES_KR.get(str(item_data.get("slot", "")), "")
	if not slot_display.is_empty():
		var slot_label := Label.new()
		slot_label.text = slot_display
		slot_label.add_theme_font_size_override("font_size", 9)
		slot_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		vbox.add_child(slot_label)
	
	# 구분선
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)
	
	# 스탯 목록 (Loop Hero 스타일: 스탯명 + 값)
	var stats: Dictionary = item_data.get("stats", {})
	if stats.is_empty():
		var no_stat := Label.new()
		no_stat.text = "(스탯 없음)"
		no_stat.add_theme_font_size_override("font_size", 9)
		no_stat.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		vbox.add_child(no_stat)
	else:
		for stat_key in stats:
			var stat_value: int = int(stats[stat_key])
			_add_stat_row(vbox, stat_key, stat_value)


func _add_stat_row(parent: VBoxContainer, stat_key: String, value: int) -> void:
	## 스탯 행 추가 (Loop Hero 스타일)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)
	
	# 스탯 이름
	var name_label := Label.new()
	name_label.text = STAT_NAMES.get(stat_key, stat_key.to_upper())
	name_label.custom_minimum_size.x = 60
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hbox.add_child(name_label)
	
	# 스탯 값
	var value_label := Label.new()
	if value > 0:
		value_label.text = "+%d" % value
		value_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	else:
		value_label.text = "%d" % value
		value_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(value_label)
