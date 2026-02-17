extends Control
## Town: 마을 씬 컨트롤러
## 3x3 격자 건물 배치 + 하단 상가 뷰 패널 + 파티원 좌우 이동

signal exit_town

#region 상수
const VIEWPORT_SIZE := Vector2(960, 540)

# 그리드 레이아웃
const GRID_COLS: int = 3
const GRID_ROWS: int = 3
const GRID_MARGIN_TOP: float = 24.0
const GRID_MARGIN_SIDE: float = 160.0
const GRID_CELL_GAP: float = 8.0
const GRID_AREA_HEIGHT: float = 300.0

# 하단 패널
const BOTTOM_PANEL_HEIGHT: float = 180.0
const BOTTOM_PANEL_MARGIN: float = 8.0

# 파티원 이동
const PARTY_WALK_SPEED: float = 48.0
const PARTY_SPRITE_SCALE: float = 2.0
const PARTY_Y_OFFSET: float = 130.0

# 건물 타입
const BUILDING_SHOPS: Array[Dictionary] = [
	{"id": "shop", "name": "상점", "icon": "🏪", "color": Color(0.3, 0.5, 0.2)},
	{"id": "inn", "name": "여관", "icon": "🏨", "color": Color(0.4, 0.3, 0.15)},
	{"id": "church", "name": "교회", "icon": "⛪", "color": Color(0.5, 0.4, 0.6)},
]
const BUILDING_EVENTS: Array[Dictionary] = [
	{"id": "house1", "name": "집", "icon": "🏠", "color": Color(0.35, 0.25, 0.2)},
	{"id": "house2", "name": "집2", "icon": "🏡", "color": Color(0.25, 0.35, 0.25)},
	{"id": "fountain", "name": "분수대", "icon": "⛲", "color": Color(0.2, 0.3, 0.5)},
	{"id": "smithy", "name": "대장간", "icon": "🔨", "color": Color(0.4, 0.2, 0.15)},
	{"id": "tavern", "name": "주점", "icon": "🍺", "color": Color(0.45, 0.35, 0.1)},
	{"id": "library", "name": "서재", "icon": "📚", "color": Color(0.25, 0.2, 0.4)},
]

# 스타일
const STYLE := {
	"bg_dark": Color(0.04, 0.04, 0.07, 0.92),
	"bg_panel": Color(0.06, 0.06, 0.09, 0.95),
	"bg_btn": Color(0.12, 0.12, 0.16, 0.9),
	"border_default": Color(0.3, 0.33, 0.45, 0.7),
	"border_gold": Color(0.5, 0.42, 0.25, 0.7),
	"border_accent": Color(0.4, 0.6, 0.9, 0.8),
	"text_normal": Color(0.85, 0.85, 0.9),
	"text_dim": Color(0.55, 0.55, 0.6),
	"text_gold": Color(1.0, 0.85, 0.3),
	"corner_radius": 6,
	"font_tiny": 8,
	"font_small": 9,
	"font_normal": 11,
	"font_medium": 12,
	"font_large": 14,
	"font_title": 16,
}
#endregion


#region 변수
var grid_buildings: Array[Dictionary] = []  # 3x3 건물 배치 데이터
var grid_buttons: Array[Button] = []        # 3x3 건물 버튼
var selected_building: Dictionary = {}      # 현재 선택된 건물

# 하단 패널
var bottom_panel: PanelContainer = null
var bottom_content: Control = null
var bottom_title_label: Label = null
var bottom_desc_label: Label = null
var bottom_interior_root: Control = null

# 파티원 스프라이트
var party_sprites: Array[AnimatedSprite2D] = []
var party_positions: Array[float] = []
var party_directions: Array[int] = []  # -1=left, 1=right
var party_walk_timer: float = 0.0

# 그리드 영역
var grid_root: Control = null

# 상단 바
var top_bar: PanelContainer = null
var gold_label: Label = null
var stage_label: Label = null
#endregion


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_generate_grid_layout()
	_build_ui()
	_spawn_party_in_bottom()


func _process(delta: float) -> void:
	_update_party_walk(delta)


#region 건물 배치 생성
func _generate_grid_layout() -> void:
	## 3x3 격자에 건물 랜덤 배치 (상점 3 + 이벤트 6 중 랜덤 6 = 총 9칸)
	grid_buildings.clear()

	# 상점은 반드시 포함
	var shops: Array[Dictionary] = BUILDING_SHOPS.duplicate()

	# 이벤트 건물 중 6개 랜덤 선택
	var events: Array[Dictionary] = BUILDING_EVENTS.duplicate()
	events.shuffle()
	var event_pick: Array[Dictionary] = []
	for i in range(mini(6, events.size())):
		event_pick.append(events[i])

	# 합쳐서 셔플
	var all_buildings: Array[Dictionary] = []
	for s in shops:
		all_buildings.append(s)
	for e in event_pick:
		all_buildings.append(e)
	all_buildings.shuffle()

	# 9칸 채우기
	for i in range(GRID_COLS * GRID_ROWS):
		if i < all_buildings.size():
			grid_buildings.append(all_buildings[i])
		else:
			grid_buildings.append({"id": "empty", "name": "빈 터", "icon": "🌿", "color": Color(0.15, 0.2, 0.12)})
#endregion


#region UI 구성
func _build_ui() -> void:
	# 배경
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.08, 0.04)
	add_child(bg)

	# 상단 바
	_build_top_bar()

	# 3x3 그리드
	_build_grid()

	# 하단 패널
	_build_bottom_panel()

	# 나가기 버튼
	_build_exit_button()


func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 28
	var style := _make_flat_style(STYLE.bg_dark, STYLE.border_default, 0, 1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	top_bar.add_theme_stylebox_override("panel", style)
	add_child(top_bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	top_bar.add_child(hbox)

	stage_label = Label.new()
	stage_label.text = "마을"
	stage_label.add_theme_font_size_override("font_size", STYLE.font_large)
	stage_label.add_theme_color_override("font_color", STYLE.text_normal)
	hbox.add_child(stage_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", STYLE.font_large)
	gold_label.add_theme_color_override("font_color", STYLE.text_gold)
	hbox.add_child(gold_label)
	_update_gold_display()


func _build_grid() -> void:
	grid_root = Control.new()
	grid_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	grid_root.offset_top = GRID_MARGIN_TOP + 28
	grid_root.offset_bottom = GRID_MARGIN_TOP + 28 + GRID_AREA_HEIGHT
	add_child(grid_root)

	var grid_width: float = VIEWPORT_SIZE.x - GRID_MARGIN_SIDE * 2.0
	var cell_w: float = (grid_width - GRID_CELL_GAP * (GRID_COLS - 1)) / GRID_COLS
	var cell_h: float = (GRID_AREA_HEIGHT - GRID_CELL_GAP * (GRID_ROWS - 1)) / GRID_ROWS

	grid_buttons.clear()
	for i in range(grid_buildings.size()):
		var row: int = i / GRID_COLS
		var col: int = i % GRID_COLS
		var building: Dictionary = grid_buildings[i]

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(cell_w, cell_h)
		btn.position = Vector2(
			GRID_MARGIN_SIDE + col * (cell_w + GRID_CELL_GAP),
			row * (cell_h + GRID_CELL_GAP)
		)
		btn.size = Vector2(cell_w, cell_h)
		btn.focus_mode = Control.FOCUS_NONE

		# 건물 텍스트
		btn.text = "%s\n%s" % [str(building.get("icon", "")), str(building.get("name", ""))]

		# 스타일
		var bg_color: Color = building.get("color", Color(0.15, 0.15, 0.15)) as Color
		var normal_style := _make_flat_style(bg_color, STYLE.border_default, STYLE.corner_radius, 1)
		normal_style.content_margin_top = 8
		normal_style.content_margin_bottom = 8
		btn.add_theme_stylebox_override("normal", normal_style)

		var hover_style := normal_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = bg_color.lightened(0.15)
		hover_style.border_color = STYLE.border_gold
		hover_style.border_width_left = 2
		hover_style.border_width_top = 2
		hover_style.border_width_right = 2
		hover_style.border_width_bottom = 2
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style := normal_style.duplicate() as StyleBoxFlat
		pressed_style.bg_color = bg_color.lightened(0.25)
		pressed_style.border_color = Color(1.0, 0.85, 0.3)
		pressed_style.border_width_left = 2
		pressed_style.border_width_top = 2
		pressed_style.border_width_right = 2
		pressed_style.border_width_bottom = 2
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.add_theme_font_size_override("font_size", STYLE.font_medium)
		btn.add_theme_color_override("font_color", STYLE.text_normal)

		var idx: int = i
		btn.pressed.connect(_on_building_pressed.bind(idx))
		grid_root.add_child(btn)
		grid_buttons.append(btn)


func _build_bottom_panel() -> void:
	bottom_panel = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_top = VIEWPORT_SIZE.y - BOTTOM_PANEL_HEIGHT - BOTTOM_PANEL_MARGIN
	bottom_panel.offset_bottom = VIEWPORT_SIZE.y - BOTTOM_PANEL_MARGIN
	bottom_panel.offset_left = BOTTOM_PANEL_MARGIN
	bottom_panel.offset_right = VIEWPORT_SIZE.x - BOTTOM_PANEL_MARGIN

	var panel_style := _make_flat_style(Color(0.03, 0.04, 0.06, 0.95), STYLE.border_default, 8, 1)
	panel_style.content_margin_left = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_bottom = 0
	bottom_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(bottom_panel)

	# 내부 콘텐츠 루트
	bottom_content = Control.new()
	bottom_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom_panel.add_child(bottom_content)

	# 기본 메시지
	_show_default_bottom()


func _show_default_bottom() -> void:
	## 하단 패널 기본 상태 (건물 선택 전)
	_clear_bottom_content()

	var label := Label.new()
	label.text = "건물을 클릭하면 내부를 볼 수 있습니다."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", STYLE.font_large)
	label.add_theme_color_override("font_color", STYLE.text_dim)
	bottom_content.add_child(label)


func _clear_bottom_content() -> void:
	if bottom_content == null:
		return
	# 파티 스프라이트는 보존
	for child in bottom_content.get_children():
		var is_party: bool = false
		for ps in party_sprites:
			if child == ps:
				is_party = true
				break
		if not is_party:
			child.queue_free()
	bottom_title_label = null
	bottom_desc_label = null
	bottom_interior_root = null


func _build_exit_button() -> void:
	var btn := Button.new()
	btn.text = "🚪 필드로"
	btn.custom_minimum_size = Vector2(80, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", STYLE.font_normal)

	var style := _make_flat_style(Color(0.15, 0.12, 0.2, 0.9), Color(0.4, 0.3, 0.6, 0.8), STYLE.corner_radius, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.18, 0.3, 0.95)
	hover.border_color = Color(0.6, 0.5, 0.9)
	btn.add_theme_stylebox_override("hover", hover)

	btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	btn.offset_left = 8
	btn.offset_top = -BOTTOM_PANEL_HEIGHT - BOTTOM_PANEL_MARGIN - 40
	btn.offset_right = 98
	btn.offset_bottom = -BOTTOM_PANEL_HEIGHT - BOTTOM_PANEL_MARGIN - 8
	btn.pressed.connect(_on_exit_pressed)
	add_child(btn)
#endregion


#region 건물 클릭 처리
func _on_building_pressed(index: int) -> void:
	if index < 0 or index >= grid_buildings.size():
		return
	selected_building = grid_buildings[index]

	# 그리드 버튼 선택 표시 업데이트
	_update_grid_selection(index)

	# 하단 패널을 해당 건물 내부로 교체
	_show_building_interior(selected_building)


func _update_grid_selection(selected_index: int) -> void:
	for i in range(grid_buttons.size()):
		var btn: Button = grid_buttons[i]
		var building: Dictionary = grid_buildings[i]
		var bg_color: Color = building.get("color", Color(0.15, 0.15, 0.15)) as Color

		if i == selected_index:
			var sel_style := _make_flat_style(bg_color.lightened(0.25), Color(1.0, 0.85, 0.3), STYLE.corner_radius, 2)
			sel_style.content_margin_top = 8
			sel_style.content_margin_bottom = 8
			btn.add_theme_stylebox_override("normal", sel_style)
		else:
			var normal_style := _make_flat_style(bg_color, STYLE.border_default, STYLE.corner_radius, 1)
			normal_style.content_margin_top = 8
			normal_style.content_margin_bottom = 8
			btn.add_theme_stylebox_override("normal", normal_style)


func _show_building_interior(building: Dictionary) -> void:
	_clear_bottom_content()

	var building_id: String = str(building.get("id", ""))
	var building_name: String = str(building.get("name", ""))
	var building_icon: String = str(building.get("icon", ""))
	var bg_color: Color = building.get("color", Color(0.15, 0.15, 0.15)) as Color

	# 인테리어 배경색
	var interior_bg := ColorRect.new()
	interior_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	interior_bg.color = bg_color.darkened(0.6)
	interior_bg.color.a = 0.5
	bottom_content.add_child(interior_bg)

	# 바닥선
	var floor_line := ColorRect.new()
	floor_line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	floor_line.offset_top = -40
	floor_line.color = bg_color.darkened(0.4)
	floor_line.color.a = 0.6
	bottom_content.add_child(floor_line)

	# 건물 이름 (좌상단)
	bottom_title_label = Label.new()
	bottom_title_label.text = "%s %s" % [building_icon, building_name]
	bottom_title_label.position = Vector2(12, 8)
	bottom_title_label.add_theme_font_size_override("font_size", STYLE.font_title)
	bottom_title_label.add_theme_color_override("font_color", STYLE.text_gold)
	bottom_content.add_child(bottom_title_label)

	# 건물별 콘텐츠
	bottom_interior_root = Control.new()
	bottom_interior_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom_interior_root.offset_top = 30
	bottom_content.add_child(bottom_interior_root)

	match building_id:
		"shop":
			_build_shop_interior()
		"inn":
			_build_inn_interior()
		"church":
			_build_church_interior()
		"fountain":
			_build_fountain_interior()
		_:
			_build_generic_interior(building_name, building_icon)

	# 파티 스프라이트를 최상위로
	for ps in party_sprites:
		if ps.get_parent() == bottom_content:
			bottom_content.move_child(ps, bottom_content.get_child_count() - 1)


func _build_shop_interior() -> void:
	var desc := Label.new()
	desc.text = "아이템과 장비를 사고 팔 수 있습니다."
	desc.position = Vector2(12, 8)
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	bottom_interior_root.add_child(desc)

	# 상점 버튼들
	var btn_box := HBoxContainer.new()
	btn_box.position = Vector2(12, 32)
	btn_box.add_theme_constant_override("separation", 8)
	bottom_interior_root.add_child(btn_box)

	var buy_btn := _make_interior_button("구매", Color(0.2, 0.35, 0.2))
	buy_btn.pressed.connect(func(): _show_shop_notice("상점 기능은 아직 준비 중입니다."))
	btn_box.add_child(buy_btn)

	var sell_btn := _make_interior_button("판매", Color(0.35, 0.2, 0.2))
	sell_btn.pressed.connect(func(): _show_shop_notice("판매 기능은 아직 준비 중입니다."))
	btn_box.add_child(sell_btn)

	# NPC 텍스트
	var npc := Label.new()
	npc.text = "👤 \"어서 오세요, 모험가님!\""
	npc.position = Vector2(12, 72)
	npc.add_theme_font_size_override("font_size", STYLE.font_normal)
	npc.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	bottom_interior_root.add_child(npc)


func _build_inn_interior() -> void:
	var desc := Label.new()
	desc.text = "휴식하여 HP를 회복할 수 있습니다."
	desc.position = Vector2(12, 8)
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	bottom_interior_root.add_child(desc)

	var rest_btn := _make_interior_button("휴식 (100G)", Color(0.3, 0.25, 0.15))
	rest_btn.position = Vector2(12, 32)
	rest_btn.pressed.connect(_on_inn_rest)
	bottom_interior_root.add_child(rest_btn)

	var npc := Label.new()
	npc.text = "👤 \"오늘 밤은 푹 쉬어 가세요.\""
	npc.position = Vector2(12, 72)
	npc.add_theme_font_size_override("font_size", STYLE.font_normal)
	npc.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6))
	bottom_interior_root.add_child(npc)


func _build_church_interior() -> void:
	var desc := Label.new()
	desc.text = "기도하여 상태이상을 회복합니다."
	desc.position = Vector2(12, 8)
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	bottom_interior_root.add_child(desc)

	var pray_btn := _make_interior_button("기도 (50G)", Color(0.35, 0.3, 0.45))
	pray_btn.position = Vector2(12, 32)
	pray_btn.pressed.connect(_on_church_pray)
	bottom_interior_root.add_child(pray_btn)

	var npc := Label.new()
	npc.text = "👤 \"신의 가호가 함께하기를.\""
	npc.position = Vector2(12, 72)
	npc.add_theme_font_size_override("font_size", STYLE.font_normal)
	npc.add_theme_color_override("font_color", Color(0.75, 0.7, 0.9))
	bottom_interior_root.add_child(npc)


func _build_fountain_interior() -> void:
	var desc := Label.new()
	desc.text = "마을의 분수대. 물소리가 마음을 편안하게 합니다."
	desc.position = Vector2(12, 8)
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	bottom_interior_root.add_child(desc)

	var drink_btn := _make_interior_button("물 마시기 (무료)", Color(0.15, 0.25, 0.4))
	drink_btn.position = Vector2(12, 32)
	drink_btn.pressed.connect(_on_fountain_drink)
	bottom_interior_root.add_child(drink_btn)

	var flavor := Label.new()
	flavor.text = "✨ 반짝이는 물줄기가 하늘로 치솟는다..."
	flavor.position = Vector2(12, 72)
	flavor.add_theme_font_size_override("font_size", STYLE.font_normal)
	flavor.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	bottom_interior_root.add_child(flavor)


func _build_generic_interior(building_name: String, building_icon: String) -> void:
	var lines: Array[String] = _get_flavor_lines(building_name)
	var line: String = lines[randi() % lines.size()] if not lines.is_empty() else "조용한 분위기다."

	var desc := Label.new()
	desc.text = line
	desc.position = Vector2(12, 8)
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	bottom_interior_root.add_child(desc)

	# 조사 버튼
	var search_btn := _make_interior_button("조사하기", Color(0.2, 0.2, 0.3))
	search_btn.position = Vector2(12, 36)
	search_btn.pressed.connect(func(): _show_shop_notice(_get_search_result(building_name)))
	bottom_interior_root.add_child(search_btn)


func _get_flavor_lines(building_name: String) -> Array[String]:
	match building_name:
		"집":
			return ["평범한 민가다. 주인은 외출 중인 것 같다.", "따뜻한 난로가 있는 집이다.", "벽에 오래된 지도가 걸려있다."]
		"집2":
			return ["작은 정원이 있는 집이다.", "누군가의 웃음소리가 들린다.", "아이들이 뛰어노는 소리가 난다."]
		"대장간":
			return ["쇠를 두드리는 소리가 울린다.", "뜨거운 열기가 얼굴에 와닿는다.", "갖가지 무기가 진열되어 있다."]
		"주점":
			return ["왁자지껄한 소리가 새어나온다.", "맛있는 음식 냄새가 풍긴다.", "용맹한 모험담이 오가고 있다."]
		"서재":
			return ["먼지 냄새가 코를 찌른다.", "오래된 마법서가 가득하다.", "조용히 책장을 넘기는 소리만 들린다."]
		_:
			return ["주변을 둘러보았다.", "특별한 것은 보이지 않는다."]


func _get_search_result(building_name: String) -> String:
	var results: Array[String] = [
		"특별한 것은 발견하지 못했다.",
		"먼지투성이 상자를 발견했지만 비어있었다.",
		"벽에 낙서가 있다: '여기 왔다감'",
		"구석에서 동전 하나를 주웠다!",
		"누군가 숨겨둔 메모를 발견했다.",
	]
	return results[randi() % results.size()]
#endregion


#region 상가 상호작용
func _on_inn_rest() -> void:
	if not GameManager.can_afford(100):
		_show_shop_notice("골드가 부족합니다!")
		return
	GameManager.spend_gold(100)
	_update_gold_display()

	# 파티 전원 HP 회복
	if PartyManager:
		for hero in PartyManager.get_party():
			if hero != null and not hero.is_dead:
				hero.heal(hero.get_max_hp())
	_show_shop_notice("푹 쉬었다! 전원 HP 완전 회복!")


func _on_church_pray() -> void:
	if not GameManager.can_afford(50):
		_show_shop_notice("골드가 부족합니다!")
		return
	GameManager.spend_gold(50)
	_update_gold_display()

	# 전사자 부활
	var revived: int = 0
	if PartyManager:
		for hero in PartyManager.get_party():
			if hero != null and hero.is_dead:
				hero.is_dead = false
				hero.current_hp = int(hero.get_max_hp() * 0.5)
				revived += 1
	if revived > 0:
		_show_shop_notice("%d명의 동료가 부활했습니다!" % revived)
	else:
		_show_shop_notice("신의 축복이 내렸다. (전원 건강)")


func _on_fountain_drink() -> void:
	# 소량 회복
	if PartyManager:
		for hero in PartyManager.get_party():
			if hero != null and not hero.is_dead:
				hero.heal(int(hero.get_max_hp() * 0.1))
	_show_shop_notice("시원한 물을 마셨다! 전원 HP 10% 회복.")


func _show_shop_notice(msg: String) -> void:
	## 하단 패널 안에 일시적 알림 표시
	if bottom_interior_root == null:
		return

	# 기존 알림 제거
	var old := bottom_interior_root.get_node_or_null("NoticeLabel")
	if old:
		old.queue_free()

	var notice := Label.new()
	notice.name = "NoticeLabel"
	notice.text = msg
	notice.position = Vector2(12, 100)
	notice.add_theme_font_size_override("font_size", STYLE.font_medium)
	notice.add_theme_color_override("font_color", Color(1.0, 1.0, 0.7))
	bottom_interior_root.add_child(notice)

	# 3초 후 제거
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(notice):
		notice.queue_free()


func _on_exit_pressed() -> void:
	exit_town.emit()
	GameManager.go_to_field()
#endregion


#region 파티원 하단 스프라이트
func _spawn_party_in_bottom() -> void:
	## 하단 패널에 파티원 AnimatedSprite2D 배치
	if not PartyManager:
		return
	var party: Array = PartyManager.get_party()
	if party.is_empty():
		return

	party_sprites.clear()
	party_positions.clear()
	party_directions.clear()

	var panel_width: float = VIEWPORT_SIZE.x - BOTTOM_PANEL_MARGIN * 2.0
	var start_x: float = panel_width * 0.3
	var spacing: float = 28.0

	for i in range(party.size()):
		var hero: Hero = party[i]
		if hero == null:
			continue

		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = SpriteManager.get_hero_sprite_frames(hero.id)
		sprite.play("walk_right")
		sprite.scale = Vector2(PARTY_SPRITE_SCALE, PARTY_SPRITE_SCALE)
		sprite.z_index = 10

		var x_pos: float = start_x + i * spacing
		sprite.position = Vector2(x_pos, PARTY_Y_OFFSET)
		bottom_content.add_child(sprite)

		party_sprites.append(sprite)
		party_positions.append(x_pos)
		party_directions.append(1)  # 시작: 오른쪽


func _update_party_walk(delta: float) -> void:
	## 파티원 좌우 이동 (하단 패널 내)
	if party_sprites.is_empty() or bottom_panel == null:
		return

	var panel_width: float = VIEWPORT_SIZE.x - BOTTOM_PANEL_MARGIN * 2.0
	var margin: float = 24.0

	for i in range(party_sprites.size()):
		var sprite: AnimatedSprite2D = party_sprites[i]
		if not is_instance_valid(sprite):
			continue

		var dir: int = party_directions[i]
		party_positions[i] += dir * PARTY_WALK_SPEED * delta

		# 벽에 부딪히면 반전
		if party_positions[i] > panel_width - margin:
			party_positions[i] = panel_width - margin
			party_directions[i] = -1
			sprite.play("walk_left")
		elif party_positions[i] < margin:
			party_positions[i] = margin
			party_directions[i] = 1
			sprite.play("walk_right")

		sprite.position.x = party_positions[i]
#endregion


#region 유틸
func _update_gold_display() -> void:
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold


func _make_interior_button(text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 28)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", STYLE.font_normal)

	var style := _make_flat_style(bg_color, STYLE.border_default, 4, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = bg_color.lightened(0.2)
	hover.border_color = STYLE.border_gold
	btn.add_theme_stylebox_override("hover", hover)

	return btn


static func _make_flat_style(
	bg: Color, border: Color = Color.TRANSPARENT,
	radius: int = 6, border_w: int = 1
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border != Color.TRANSPARENT:
		s.border_width_left = border_w
		s.border_width_top = border_w
		s.border_width_right = border_w
		s.border_width_bottom = border_w
		s.border_color = border
	return s
#endregion
