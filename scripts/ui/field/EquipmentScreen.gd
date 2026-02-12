extends CanvasLayer
class_name EquipmentScreen
## 장비 화면 — ESC / 햄버거 버튼으로 열고 닫기
## 구성: 좌측 파티 목록 | 영웅 프리뷰+스탯 | 장비 슬롯 | 인벤토리

const FACE_PATH := "res://assets/sprites/heroes/%s.png"
const FIELD_SPRITE_PATH := "res://assets/sprites/heroes/%s.png"

# 슬롯 정의
const SLOT_DISPLAY := [
	{"slot": "main_hand", "label": "무기", "icon": "⚔"},
	{"slot": "off_hand", "label": "방패", "icon": "🛡"},
	{"slot": "body", "label": "갑옷", "icon": "🛡"},
	{"slot": "head", "label": "투구", "icon": "⛑"},
	{"slot": "acc1", "label": "장신구", "icon": "💍"},
	{"slot": "acc2", "label": "장신구", "icon": "💎"},
]

# 스타일 (FieldHUD.STYLE 참조)
const S := {
	"bg_dark":    Color(0.04, 0.04, 0.07, 0.95),
	"bg_panel":   Color(0.06, 0.06, 0.09, 0.95),
	"bg_slot":    Color(0.08, 0.08, 0.12, 0.9),
	"bg_slot_hover": Color(0.14, 0.14, 0.2, 0.95),
	"bg_btn":     Color(0.12, 0.12, 0.16, 0.9),
	"border":     Color(0.35, 0.3, 0.2, 0.8),
	"border_gold": Color(0.7, 0.55, 0.2, 0.9),
	"border_sel":  Color(0.9, 0.7, 0.2),
	"text":       Color(0.85, 0.85, 0.9),
	"text_dim":   Color(0.5, 0.5, 0.55),
	"text_gold":  Color(1.0, 0.85, 0.3),
	"text_green": Color(0.45, 1.0, 0.45),
	"text_red":   Color(1.0, 0.45, 0.45),
	"empty_slot": Color(0.4, 0.4, 0.45),
}

const RARITY_COLORS := {
	"common": Color(0.7, 0.7, 0.7),
	"uncommon": Color(0.4, 0.8, 0.4),
	"magic": Color(0.4, 0.6, 1.0),
	"rare": Color(0.8, 0.5, 1.0),
	"epic": Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.8, 0.2),
}

signal closed

var is_open: bool = false
var selected_hero_index: int = 0
var selected_slot: String = ""  # 현재 선택된 장비 슬롯 (필터링용)

# 주요 노드
var root: Control
var gold_label: Label
var party_list_container: VBoxContainer
var hero_sprite: TextureRect
var hero_name_label: Label
var hero_class_label: Label
var stats_container: VBoxContainer
var equip_slots_container: VBoxContainer
var inv_scroll: ScrollContainer
var inv_list: VBoxContainer
var item_desc_label: RichTextLabel

# 파티 엔트리 배열
var _party_entries: Array = []  # [{panel, face, hp_bar, mp_bar, border_style}]
# 장비 슬롯 행 배열
var _slot_rows: Array = []  # [{panel, name_label, stat_label, slot_key}]


func _ready() -> void:
	layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


#region 열기 / 닫기
func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	get_tree().paused = true
	selected_hero_index = 0
	_refresh_all()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if not BattleManager or not BattleManager.is_battle_paused:
		get_tree().paused = false
	closed.emit()
#endregion


#region UI 빌드
func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root)

	# 어두운 배경
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.7)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimmer)

	# 메인 패널
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.02
	panel.anchor_right = 0.98
	panel.anchor_top = 0.03
	panel.anchor_bottom = 0.97
	panel.offset_left = 0; panel.offset_right = 0
	panel.offset_top = 0; panel.offset_bottom = 0
	var panel_style := _make_style(S.bg_dark, S.border_gold, 4, 2)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	panel.add_child(main_vbox)

	# 상단 바
	_build_top_bar(main_vbox)

	# 구분선
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", S.border)
	main_vbox.add_child(sep)

	# 콘텐츠 영역
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 6)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	# 1) 파티 목록 (좌측)
	_build_party_list(content_hbox)

	# 구분선
	content_hbox.add_child(_make_vsep())

	# 2) 영웅 프리뷰 (중앙 좌)
	_build_hero_preview(content_hbox)

	# 구분선
	content_hbox.add_child(_make_vsep())

	# 3) 장비 슬롯 (중앙)
	_build_equip_panel(content_hbox)

	# 구분선
	content_hbox.add_child(_make_vsep())

	# 4) 인벤토리 (우측)
	_build_inventory_panel(content_hbox)


func _build_top_bar(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	# 닫기 + 타이틀
	var close_btn := Button.new()
	close_btn.text = "× 장비"
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.add_theme_color_override("font_color", S.text_gold)
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	hbox.add_child(close_btn)

	# 스페이서
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# 골드
	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 13)
	gold_label.add_theme_color_override("font_color", S.text_gold)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(gold_label)


func _build_party_list(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = 72
	vbox.add_theme_constant_override("separation", 4)
	parent.add_child(vbox)
	party_list_container = vbox


func _build_hero_preview(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size.x = 120
	vbox.add_theme_constant_override("separation", 2)
	parent.add_child(vbox)

	# 큰 스프라이트
	var sprite_container := PanelContainer.new()
	var sc_style := _make_style(Color(0.05, 0.05, 0.08, 0.9), S.border, 4, 1)
	sc_style.content_margin_left = 4; sc_style.content_margin_right = 4
	sc_style.content_margin_top = 4; sc_style.content_margin_bottom = 4
	sprite_container.add_theme_stylebox_override("panel", sc_style)
	sprite_container.custom_minimum_size = Vector2(112, 112)
	vbox.add_child(sprite_container)

	hero_sprite = TextureRect.new()
	hero_sprite.custom_minimum_size = Vector2(104, 104)
	hero_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite_container.add_child(hero_sprite)

	# 이름
	hero_name_label = Label.new()
	hero_name_label.add_theme_font_size_override("font_size", 12)
	hero_name_label.add_theme_color_override("font_color", S.text)
	hero_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hero_name_label)

	# 클래스
	hero_class_label = Label.new()
	hero_class_label.add_theme_font_size_override("font_size", 10)
	hero_class_label.add_theme_color_override("font_color", S.text_dim)
	hero_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hero_class_label)

	# 구분선
	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", S.border)
	vbox.add_child(sep2)

	# 스탯 영역
	stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 1)
	vbox.add_child(stats_container)


func _build_equip_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 1.2
	vbox.add_theme_constant_override("separation", 3)
	parent.add_child(vbox)

	# 탭 바
	var tab_hbox := HBoxContainer.new()
	tab_hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(tab_hbox)

	var tab_names := ["장비", "소모", "환전"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.add_theme_font_size_override("font_size", 10)
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size.y = 22
		var style: StyleBoxFlat
		if i == 0:
			style = _make_style(Color(0.15, 0.15, 0.2), S.border_gold, 3, 1)
		else:
			style = _make_style(Color(0.08, 0.08, 0.12), S.border, 3, 1)
		style.content_margin_left = 10; style.content_margin_right = 10
		style.content_margin_top = 2; style.content_margin_bottom = 2
		btn.add_theme_stylebox_override("normal", style)
		tab_hbox.add_child(btn)

	# 슬롯 목록
	equip_slots_container = VBoxContainer.new()
	equip_slots_container.add_theme_constant_override("separation", 2)
	equip_slots_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(equip_slots_container)

	_slot_rows.clear()
	for slot_info in SLOT_DISPLAY:
		var row := _build_equip_slot_row(slot_info)
		equip_slots_container.add_child(row["panel"])
		_slot_rows.append(row)


func _build_equip_slot_row(slot_info: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	var style := _make_style(S.bg_slot, S.border, 3, 1)
	style.content_margin_left = 6; style.content_margin_right = 6
	style.content_margin_top = 5; style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# 슬롯 아이콘 + 라벨
	var icon_lbl := Label.new()
	icon_lbl.text = slot_info["icon"]
	icon_lbl.add_theme_font_size_override("font_size", 12)
	icon_lbl.custom_minimum_size.x = 18
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_lbl)

	var slot_lbl := Label.new()
	slot_lbl.text = slot_info["label"]
	slot_lbl.add_theme_font_size_override("font_size", 10)
	slot_lbl.add_theme_color_override("font_color", S.text_dim)
	slot_lbl.custom_minimum_size.x = 36
	slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(slot_lbl)

	# 장비 이름
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", S.text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	# 메인 스탯
	var stat_label := Label.new()
	stat_label.add_theme_font_size_override("font_size", 11)
	stat_label.add_theme_color_override("font_color", S.text)
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_label.custom_minimum_size.x = 60
	stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(stat_label)

	# 클릭 이벤트 — 장비 해제
	var slot_key: String = slot_info["slot"]
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_equip_slot_clicked(slot_key)
	)

	return {"panel": panel, "name_label": name_label, "stat_label": stat_label, "slot_key": slot_key}


func _build_inventory_panel(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_stretch_ratio = 1.3
	vbox.add_theme_constant_override("separation", 3)
	parent.add_child(vbox)

	# 인벤토리 헤더
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)

	var inv_title := Label.new()
	inv_title.text = "인벤토리"
	inv_title.add_theme_font_size_override("font_size", 11)
	inv_title.add_theme_color_override("font_color", S.text)
	inv_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(inv_title)

	# 스크롤 리스트
	inv_scroll = ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(inv_scroll)

	inv_list = VBoxContainer.new()
	inv_list.add_theme_constant_override("separation", 1)
	inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inv_list)

	# 아이템 설명
	var desc_panel := PanelContainer.new()
	desc_panel.custom_minimum_size.y = 48
	var dp_style := _make_style(Color(0.05, 0.05, 0.08, 0.9), S.border, 3, 1)
	dp_style.content_margin_left = 6; dp_style.content_margin_right = 6
	dp_style.content_margin_top = 3; dp_style.content_margin_bottom = 3
	desc_panel.add_theme_stylebox_override("panel", dp_style)
	vbox.add_child(desc_panel)

	item_desc_label = RichTextLabel.new()
	item_desc_label.bbcode_enabled = true
	item_desc_label.fit_content = true
	item_desc_label.scroll_active = false
	item_desc_label.add_theme_font_size_override("normal_font_size", 9)
	item_desc_label.add_theme_color_override("default_color", S.text_dim)
	desc_panel.add_child(item_desc_label)
#endregion


#region 갱신
func _refresh_all() -> void:
	_update_gold()
	_refresh_party_list()
	_refresh_hero_preview()
	_refresh_equip_slots()
	_refresh_inventory()


func _update_gold() -> void:
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold


func _get_hero() -> Hero:
	var party := PartyManager.get_party()
	if selected_hero_index >= 0 and selected_hero_index < party.size():
		return party[selected_hero_index]
	return null
#endregion


#region 파티 목록
func _refresh_party_list() -> void:
	# 기존 삭제
	for child in party_list_container.get_children():
		child.queue_free()
	_party_entries.clear()

	var party := PartyManager.get_party()
	for i in range(party.size()):
		var hero := party[i]
		var entry := _create_party_entry(hero, i)
		party_list_container.add_child(entry["panel"])
		_party_entries.append(entry)

	_update_party_selection()


func _create_party_entry(hero: Hero, index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(68, 58)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := _make_style(S.bg_slot, S.border, 4, 1)
	style.content_margin_left = 3; style.content_margin_right = 3
	style.content_margin_top = 3; style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# 페이스칩
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(40, 40)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face_path := ""
	if not hero.portrait.is_empty():
		face_path = FACE_PATH % hero.portrait
	elif not hero.field_sprite.is_empty():
		face_path = FACE_PATH % hero.field_sprite
	if not face_path.is_empty() and ResourceLoader.exists(face_path):
		face.texture = load(face_path)
	hbox.add_child(face)

	# HP/MP 바 (간이)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 2)
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(bars)

	var hp_bar := _make_mini_bar(
		hero.current_hp, hero.get_max_hp(),
		Color(0.25, 0.78, 0.25), 20, 5
	)
	bars.add_child(hp_bar)

	var mp_bar := _make_mini_bar(
		hero.current_mp, hero.get_max_mp(),
		Color(0.25, 0.45, 0.95), 20, 4
	)
	bars.add_child(mp_bar)

	# 클릭
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected_hero_index = index
			_refresh_all()
	)

	return {"panel": panel, "style": style}


func _update_party_selection() -> void:
	for i in range(_party_entries.size()):
		var entry: Dictionary = _party_entries[i]
		var style: StyleBoxFlat
		if i == selected_hero_index:
			style = _make_style(Color(0.12, 0.1, 0.05, 0.95), S.border_sel, 4, 2)
		else:
			style = _make_style(S.bg_slot, S.border, 4, 1)
		style.content_margin_left = 3; style.content_margin_right = 3
		style.content_margin_top = 3; style.content_margin_bottom = 3
		entry["panel"].add_theme_stylebox_override("panel", style)


func _make_mini_bar(current: int, max_val: int, color: Color, w: int, h: int) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(w, h)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.size = Vector2(w, h)
	bg.color = Color(0.1, 0.1, 0.15, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)

	var fill := ColorRect.new()
	var ratio := clampf(float(current) / float(max_val), 0.0, 1.0) if max_val > 0 else 1.0
	fill.size = Vector2(w * ratio, h)
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(fill)

	return container
#endregion


#region 영웅 프리뷰 + 스탯
func _refresh_hero_preview() -> void:
	var hero := _get_hero()
	if hero == null:
		return

	# 큰 스프라이트
	var sprite_path := ""
	if not hero.field_sprite.is_empty():
		sprite_path = FIELD_SPRITE_PATH % hero.field_sprite
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		hero_sprite.texture = load(sprite_path)
	else:
		hero_sprite.texture = null

	hero_name_label.text = hero.hero_name
	hero_class_label.text = hero.hero_class_name

	# 스탯
	for child in stats_container.get_children():
		child.queue_free()

	var stats := [
		["HP", "%d/%d" % [hero.current_hp, hero.get_max_hp()]],
		["ATK", str(hero.get_atk())],
		["DEF", str(hero.get_def())],
		["SPD", str(hero.get_spd())],
		["STR", str(hero.get_str())],
		["INT", str(hero.get_int())],
		["DEX", str(hero.get_dex())],
		["LUK", str(hero.get_luk())],
	]

	for stat in stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var key := Label.new()
		key.text = stat[0]
		key.add_theme_font_size_override("font_size", 9)
		key.add_theme_color_override("font_color", S.text_dim)
		key.custom_minimum_size.x = 28
		row.add_child(key)

		var val := Label.new()
		val.text = stat[1]
		val.add_theme_font_size_override("font_size", 10)
		val.add_theme_color_override("font_color", S.text)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)

		stats_container.add_child(row)
#endregion


#region 장비 슬롯
func _refresh_equip_slots() -> void:
	var hero := _get_hero()
	if hero == null:
		return

	for row_data in _slot_rows:
		var slot_key: String = row_data["slot_key"]
		var name_lbl: Label = row_data["name_label"]
		var stat_lbl: Label = row_data["stat_label"]
		var equip_id: String = hero.equipment.get(slot_key, "")

		if equip_id.is_empty():
			name_lbl.text = "— 비어있음 —"
			name_lbl.add_theme_color_override("font_color", S.empty_slot)
			stat_lbl.text = ""
		else:
			var data: Dictionary = DataManager.get_equipment(equip_id)
			var item_name: String = data.get("name", equip_id)
			var rarity: String = data.get("rarity", "common")
			name_lbl.text = item_name
			name_lbl.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, S.text))

			# 메인 스탯 표시
			stat_lbl.text = _get_main_stat_text(data)
			stat_lbl.add_theme_color_override("font_color", S.text)

		# 양손무기 시 off_hand 비활성화 표시
		if slot_key == "off_hand" and hero.is_off_hand_disabled():
			name_lbl.text = "— 양손무기 —"
			name_lbl.add_theme_color_override("font_color", S.text_dim)
			stat_lbl.text = ""


func _get_main_stat_text(data: Dictionary) -> String:
	var stats: Dictionary = data.get("stats", {})
	var parts: Array = []
	# 주요 스탯 우선 표시
	for key in ["atk", "def", "str", "int", "hp", "mp", "dex", "luk", "spd"]:
		var val: int = int(stats.get(key, 0))
		if val != 0:
			parts.append("%s %d" % [key.to_upper(), val])
	if parts.is_empty():
		return ""
	return " ".join(parts.slice(0, 3))  # 최대 3개


func _on_equip_slot_clicked(slot_key: String) -> void:
	var hero := _get_hero()
	if hero == null:
		return
	var equip_id: String = hero.equipment.get(slot_key, "")
	if equip_id.is_empty():
		return
	# 장비 해제
	InventoryManager.unequip_item(hero, slot_key)
	_refresh_all()
#endregion


#region 인벤토리
func _refresh_inventory() -> void:
	for child in inv_list.get_children():
		child.queue_free()

	if item_desc_label:
		item_desc_label.text = ""

	var hero := _get_hero()
	var all_items: Array = InventoryManager.get_equipment_items()

	# gear_score 기준 내림차순 정렬
	all_items.sort_custom(func(a, b):
		var sa: int = int(a["data"].get("gear_score", 0))
		var sb: int = int(b["data"].get("gear_score", 0))
		return sa > sb
	)

	for item_info in all_items:
		var row := _create_inv_item_row(item_info, hero)
		inv_list.add_child(row)


func _create_inv_item_row(item_info: Dictionary, hero: Hero) -> PanelContainer:
	var item_id: String = item_info["id"]
	var qty: int = item_info["quantity"]
	var data: Dictionary = item_info["data"]
	var rarity: String = data.get("rarity", "common")
	var item_name: String = data.get("name", item_id)
	var rarity_color: Color = RARITY_COLORS.get(rarity, S.text)

	var panel := PanelContainer.new()
	var style := _make_style(Color(0.06, 0.06, 0.09, 0.8), Color.TRANSPARENT, 2, 0)
	style.content_margin_left = 5; style.content_margin_right = 5
	style.content_margin_top = 3; style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# 아이콘 (슬롯 타입 텍스트)
	var slot: String = data.get("slot", "")
	var type_name: String = InventoryManager.ITEM_TYPE_NAMES.get(data.get("type", ""), "")
	var icon_lbl := Label.new()
	icon_lbl.text = _get_slot_icon(slot)
	icon_lbl.add_theme_font_size_override("font_size", 11)
	icon_lbl.custom_minimum_size.x = 16
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_lbl)

	# 이름 + 스탯
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 0)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info_vbox)

	var name_lbl := Label.new()
	var display_name := item_name
	if qty > 1:
		display_name += " x%d" % qty
	name_lbl.text = display_name
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", rarity_color)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = _get_main_stat_text(data)
	sub_lbl.add_theme_font_size_override("font_size", 8)
	sub_lbl.add_theme_color_override("font_color", S.text_dim)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(sub_lbl)

	# 비교 수치
	var diff_lbl := Label.new()
	diff_lbl.add_theme_font_size_override("font_size", 10)
	diff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	diff_lbl.custom_minimum_size.x = 40
	diff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(diff_lbl)

	if hero != null:
		var diff := _calc_stat_diff(hero, item_id)
		if diff != 0:
			if diff > 0:
				diff_lbl.text = "+%d" % diff
				diff_lbl.add_theme_color_override("font_color", S.text_green)
			else:
				diff_lbl.text = "%d" % diff
				diff_lbl.add_theme_color_override("font_color", S.text_red)

		# 장착 불가 표시
		if not hero.can_equip(item_id):
			name_lbl.add_theme_color_override("font_color", Color(rarity_color, 0.4))
			diff_lbl.text = ""

	# 호버 효과
	panel.mouse_entered.connect(func():
		var hover_style := _make_style(Color(0.12, 0.12, 0.18, 0.95), S.border, 2, 1)
		hover_style.content_margin_left = 5; hover_style.content_margin_right = 5
		hover_style.content_margin_top = 3; hover_style.content_margin_bottom = 3
		panel.add_theme_stylebox_override("panel", hover_style)
		# 설명 표시
		_show_item_desc(data)
	)
	panel.mouse_exited.connect(func():
		panel.add_theme_stylebox_override("panel", style)
	)

	# 클릭 → 장착
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_inv_item_clicked(item_id)
	)

	return panel


func _calc_stat_diff(hero: Hero, item_id: String) -> int:
	## 아이템 교체 시 총 스탯 차이 (간략: 주요 전투력 차이)
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		return 0
	var new_stats: Dictionary = data.get("stats", {})
	var item_slot: String = data.get("slot", "")

	# 대상 슬롯 결정
	var target_slot: String = item_slot
	if item_slot in ["acc", "ring", "necklace", "shoes"]:
		# 빈 슬롯 우선, 아니면 acc1
		if hero.equipment.get("acc1", "").is_empty():
			target_slot = "acc1"
		elif hero.equipment.get("acc2", "").is_empty():
			target_slot = "acc2"
		else:
			target_slot = "acc1"

	var current_id: String = hero.equipment.get(target_slot, "")
	var current_stats: Dictionary = {}
	if not current_id.is_empty():
		var cd: Dictionary = DataManager.get_equipment(current_id)
		current_stats = cd.get("stats", {})

	# 주요 스탯 합산 차이
	var diff: int = 0
	var keys := ["atk", "def", "str", "int", "dex", "luk", "hp", "mp", "spd"]
	for key in keys:
		var nv: int = int(new_stats.get(key, 0))
		var cv: int = int(current_stats.get(key, 0))
		diff += nv - cv
	return diff


func _on_inv_item_clicked(item_id: String) -> void:
	var hero := _get_hero()
	if hero == null:
		return
	if not hero.can_equip(item_id):
		return

	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_slot: String = data.get("slot", "")
	var target_slot: String = item_slot

	# acc 슬롯 결정
	if item_slot in ["acc", "ring", "necklace", "shoes"]:
		if hero.equipment.get("acc1", "").is_empty():
			target_slot = "acc1"
		elif hero.equipment.get("acc2", "").is_empty():
			target_slot = "acc2"
		else:
			target_slot = "acc1"

	# 양손무기 체크
	if data.get("two_handed", false) and target_slot == "main_hand":
		if not hero.equipment.get("off_hand", "").is_empty():
			InventoryManager.unequip_item(hero, "off_hand")

	InventoryManager.equip_item(hero, item_id, target_slot)
	_refresh_all()


func _show_item_desc(data: Dictionary) -> void:
	if item_desc_label == null:
		return
	var name_str: String = data.get("name", "")
	var desc: String = data.get("description", "")
	var rarity: String = data.get("rarity", "common")
	var color: Color = RARITY_COLORS.get(rarity, S.text)
	var hex := color.to_html(false)
	item_desc_label.text = "[color=#%s]%s[/color]\n%s" % [hex, name_str, desc]


func _get_slot_icon(slot: String) -> String:
	match slot:
		"main_hand": return "⚔"
		"off_hand": return "🛡"
		"body": return "🧥"
		"head": return "⛑"
		"acc", "ring", "necklace", "shoes": return "💍"
		_: return "•"
#endregion


#region 스타일 유틸
func _make_style(bg: Color, border_color: Color = Color.TRANSPARENT,
		radius: int = 4, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border_color != Color.TRANSPARENT and border_w > 0:
		s.border_width_left = border_w
		s.border_width_top = border_w
		s.border_width_right = border_w
		s.border_width_bottom = border_w
		s.border_color = border_color
	return s


func _make_vsep() -> VSeparator:
	var sep := VSeparator.new()
	sep.add_theme_color_override("separator", S.border)
	return sep
#endregion
