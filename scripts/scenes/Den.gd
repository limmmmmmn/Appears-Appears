extends Control
## Den(기지): 3구역(훈련/영웅/작업) 건물 관리 허브
## 좌: 훈련구역, 중앙: 영웅구역, 우: 작업구역

signal exit_requested

# === 건물 데이터 ===
const ZONES: Array = [
	{
		"name": "🏋️ 훈련구역",
		"color": Color(0.15, 0.25, 0.15),
		"buildings": [
			{
				"id": "gym_atk",
				"name": "체력단련장",
				"icon": "⚔",
				"desc": "ATK 증가 (골드로 업그레이드)",
				"category": "training",
			},
			{
				"id": "gym_def",
				"name": "방어술 교관소",
				"icon": "🛡",
				"desc": "DEF 증가 (골드로 업그레이드)",
				"category": "training",
			},
			{
				"id": "gym_spd",
				"name": "민첩 수련장",
				"icon": "💨",
				"desc": "DEX 증가 (골드로 업그레이드)",
				"category": "training",
			},
			{
				"id": "gym_int",
				"name": "마법 서재",
				"icon": "📖",
				"desc": "INT 증가 (골드로 업그레이드)",
				"category": "training",
			},
		]
	},
	{
		"name": "👥 영웅구역",
		"color": Color(0.15, 0.15, 0.25),
		"buildings": [
			{
				"id": "supply",
				"name": "보급소",
				"icon": "📦",
				"desc": "파견대 출발/귀환 관리",
				"category": "hero",
			},
			{
				"id": "party_hall",
				"name": "파티 편성소",
				"icon": "👥",
				"desc": "메인 파티 편성, 영웅 배치",
				"category": "hero",
			},
			{
				"id": "equip_shop",
				"name": "장비 정비소",
				"icon": "🔧",
				"desc": "전체 영웅 장비 관리",
				"category": "hero",
			},
			{
				"id": "infirmary",
				"name": "치료소",
				"icon": "💊",
				"desc": "부상 영웅 회복",
				"category": "hero",
			},
		]
	},
	{
		"name": "⚒️ 작업구역",
		"color": Color(0.25, 0.15, 0.15),
		"buildings": [
			{
				"id": "blacksmith",
				"name": "대장장이",
				"icon": "⚒",
				"desc": "장비 합성, 상위 장비 제작",
				"category": "work",
			},
			{
				"id": "tavern",
				"name": "주점",
				"icon": "🍺",
				"desc": "영웅 합류, 영웅 목록 열람",
				"category": "work",
			},
			{
				"id": "market",
				"name": "시장",
				"icon": "🏪",
				"desc": "아이템 구매/판매",
				"category": "work",
			},
			{
				"id": "warehouse",
				"name": "창고",
				"icon": "🏚",
				"desc": "아이템 보관, 정리",
				"category": "work",
			},
		]
	},
]

# === UI 참조 ===
var zone_containers: Array = []  # 3개 구역 컨테이너
var popup_layer: CanvasLayer = null
var popup_panel: PanelContainer = null
var gold_label: Label = null


func _ready() -> void:
	_build_ui()
	_update_gold_display()
	if GameManager.has_signal("gold_changed"):
		GameManager.gold_changed.connect(_on_gold_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if popup_layer and popup_layer.visible:
			_close_popup()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	## 전체 UI 구성
	# 배경
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 메인 VBox
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# === 상단 헤더 ===
	_build_header(root_vbox)

	# === 3구역 본문 ===
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 2)
	root_vbox.add_child(body_hbox)

	for zone_data in ZONES:
		var zone := _build_zone(zone_data)
		body_hbox.add_child(zone)
		zone_containers.append(zone)

	# === 팝업 레이어 (숨김) ===
	_build_popup_layer()


func _build_header(parent: VBoxContainer) -> void:
	## 상단 헤더: 기지 이름 + 골드 + 나가기 버튼
	var header := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.1, 0.1, 0.15)
	header_style.content_margin_left = 16
	header_style.content_margin_right = 16
	header_style.content_margin_top = 8
	header_style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", header_style)
	parent.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	header.add_child(hbox)

	# 기지 이름
	var title := Label.new()
	title.text = "🏰 기지"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	hbox.add_child(title)

	# 스페이서
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# 골드 표시
	var gold_hbox := HBoxContainer.new()
	gold_hbox.add_theme_constant_override("separation", 4)
	hbox.add_child(gold_hbox)

	var gold_icon := Label.new()
	gold_icon.text = "💰"
	gold_icon.add_theme_font_size_override("font_size", 16)
	gold_hbox.add_child(gold_icon)

	gold_label = Label.new()
	gold_label.text = "0"
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	gold_hbox.add_child(gold_label)

	# 나가기 버튼
	var exit_btn := Button.new()
	exit_btn.text = "출발"
	exit_btn.custom_minimum_size = Vector2(70, 30)
	exit_btn.add_theme_font_size_override("font_size", 14)
	exit_btn.pressed.connect(_on_exit_pressed)
	hbox.add_child(exit_btn)


func _build_zone(zone_data: Dictionary) -> PanelContainer:
	## 하나의 구역 (좌/중/우) 생성
	var zone := PanelContainer.new()
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var zone_style := StyleBoxFlat.new()
	zone_style.bg_color = zone_data["color"]
	zone_style.content_margin_left = 8
	zone_style.content_margin_right = 8
	zone_style.content_margin_top = 8
	zone_style.content_margin_bottom = 8
	zone_style.border_width_left = 1
	zone_style.border_width_right = 1
	zone_style.border_color = Color(0.3, 0.3, 0.35, 0.5)
	zone.add_theme_stylebox_override("panel", zone_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	zone.add_child(vbox)

	# 구역 타이틀
	var title := Label.new()
	title.text = zone_data["name"]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 구분선
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# 그리드 (2열)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	# 건물 버튼들
	var buildings: Array = zone_data["buildings"]
	for bld in buildings:
		var btn := _create_building_button(bld)
		grid.add_child(btn)

	return zone


func _create_building_button(bld: Dictionary) -> Button:
	## 건물 슬롯 버튼 생성
	var btn := Button.new()
	btn.text = "%s\n%s" % [bld["icon"], bld["name"]]
	btn.custom_minimum_size = Vector2(100, 70)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)

	# 버튼 스타일
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	normal_style.border_width_left = 1
	normal_style.border_width_top = 1
	normal_style.border_width_right = 1
	normal_style.border_width_bottom = 1
	normal_style.border_color = Color(0.35, 0.35, 0.45)
	normal_style.corner_radius_top_left = 6
	normal_style.corner_radius_top_right = 6
	normal_style.corner_radius_bottom_left = 6
	normal_style.corner_radius_bottom_right = 6
	normal_style.content_margin_top = 8
	normal_style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate()
	hover_style.bg_color = Color(0.18, 0.18, 0.25, 0.95)
	hover_style.border_color = Color(0.5, 0.5, 0.7)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.1, 0.14)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.pressed.connect(_on_building_pressed.bind(bld))
	return btn


func _build_popup_layer() -> void:
	## 건물 정보 팝업 (CanvasLayer)
	popup_layer = CanvasLayer.new()
	popup_layer.layer = 50
	popup_layer.visible = false
	add_child(popup_layer)

	# 반투명 배경 (클릭 시 닫기)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_popup_dim_input)
	popup_layer.add_child(dim)

	# 팝업 센터
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup_layer.add_child(center)

	popup_panel = PanelContainer.new()
	popup_panel.custom_minimum_size = Vector2(280, 200)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.6, 0.8)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	popup_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(popup_panel)


func _on_building_pressed(bld: Dictionary) -> void:
	## 건물 버튼 클릭 → 팝업 표시
	_show_building_popup(bld)


func _show_building_popup(bld: Dictionary) -> void:
	## 건물 정보 팝업 열기
	# 기존 내용 제거
	for child in popup_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	popup_panel.add_child(vbox)

	# 아이콘
	var icon_label := Label.new()
	icon_label.text = bld["icon"]
	icon_label.add_theme_font_size_override("font_size", 36)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(icon_label)

	# 건물 이름
	var name_label := Label.new()
	name_label.text = bld["name"]
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# 설명
	var desc_label := Label.new()
	desc_label.text = bld["desc"]
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_label)

	# 구분선
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 상태/버튼 (카테고리별)
	match bld["category"]:
		"training":
			_build_training_popup_content(vbox, bld)
		"hero":
			_build_hero_popup_content(vbox, bld)
		"work":
			_build_work_popup_content(vbox, bld)

	# 닫기 버튼
	var close_btn := Button.new()
	close_btn.text = "닫기"
	close_btn.custom_minimum_size = Vector2(80, 30)
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(_close_popup)
	vbox.add_child(close_btn)

	popup_layer.visible = true


func _build_training_popup_content(parent: VBoxContainer, bld: Dictionary) -> void:
	## 훈련구역 팝업: 현재 레벨 + 업그레이드 버튼
	var info := Label.new()
	info.text = "현재 레벨: 0\n다음 비용: 💰 100"
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(info)

	var upgrade_btn := Button.new()
	upgrade_btn.text = "💰 업그레이드"
	upgrade_btn.custom_minimum_size = Vector2(120, 32)
	upgrade_btn.add_theme_font_size_override("font_size", 13)
	parent.add_child(upgrade_btn)


func _build_hero_popup_content(parent: VBoxContainer, bld: Dictionary) -> void:
	## 영웅구역 팝업: 상태 정보
	var info := Label.new()
	var hero_count: int = PartyManager.get_alive_heroes().size() if PartyManager else 0
	info.text = "활성 영웅: %d명" % hero_count
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.9))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(info)

	var open_btn := Button.new()
	open_btn.text = "열기"
	open_btn.custom_minimum_size = Vector2(120, 32)
	open_btn.add_theme_font_size_override("font_size", 13)
	parent.add_child(open_btn)


func _build_work_popup_content(parent: VBoxContainer, bld: Dictionary) -> void:
	## 작업구역 팝업: 기능 설명
	var info := Label.new()
	info.text = "준비 중..."
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_color_override("font_color", Color(0.9, 0.6, 0.6))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(info)

	var open_btn := Button.new()
	open_btn.text = "열기"
	open_btn.custom_minimum_size = Vector2(120, 32)
	open_btn.add_theme_font_size_override("font_size", 13)
	parent.add_child(open_btn)


func _close_popup() -> void:
	popup_layer.visible = false


func _on_popup_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_popup()


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = str(GameManager.gold)


func _on_gold_changed(_new_gold: int) -> void:
	_update_gold_display()


func _on_exit_pressed() -> void:
	exit_requested.emit()
	GameManager.go_to_field()
