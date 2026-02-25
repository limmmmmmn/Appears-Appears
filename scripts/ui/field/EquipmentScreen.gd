extends CanvasLayer
class_name EquipmentScreen
## 정비 화면 — ESC / 햄버거 버튼으로 열고 닫기
## 탭: 정비 | 스킬 | 작전

const FACE_PATH := "res://assets/sprites/heroes/%s.png"
const FIELD_SPRITE_PATH := "res://assets/sprites/heroes/%s.png"

# 슬롯 정의
const SLOT_DISPLAY := [
	{"slot": "main_hand", "label": "손", "icon": "⚔"},
	{"slot": "off_hand", "label": "손", "icon": "🛡"},
	{"slot": "head", "label": "투구", "icon": "⛑"},
	{"slot": "body", "label": "갑옷", "icon": "🛡"},
	{"slot": "acc1", "label": "악세1", "icon": "💍"},
	{"slot": "acc2", "label": "악세2", "icon": "💎"},
]

# 스킬 아이콘
const SKILL_ICONS := {
	"basic_attack": "⚔️", "power_strike": "💥", "fireball": "🔥",
	"heal": "💚", "backstab": "⚡", "aimed_shot": "🏹",
	"shield_bash": "🛡️", "ice_bolt": "❄️", "blessing": "✨",
	"double_shot": "🎯",
}

# 스타일
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
	"text_blue":  Color(0.4, 0.6, 1.0),
	"text_yellow": Color(1.0, 0.85, 0.3),
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
var current_tab: int = 0  # 0=장비, 1=스킬, 2=작전

# 주요 노드
var root: Control
var gold_label: Label
var party_list_container: VBoxContainer
var hero_sprite: TextureRect
var hero_name_label: Label
var hero_class_label: Label
var stats_container: VBoxContainer

# 탭 버튼
var _tab_buttons: Array[Button] = []

# 중앙 패널 (탭별 전환)
var equip_panel: VBoxContainer
var skills_panel: VBoxContainer
var tactics_panel: VBoxContainer

# 장비 탭
var equip_slots_container: VBoxContainer
var _slot_rows: Array = []

# 인벤토리
var inv_panel: VBoxContainer  # 장비 탭일 때만 보임
var inv_scroll: ScrollContainer
var inv_list: VBoxContainer
var item_desc_label: RichTextLabel

# 스탯 행 참조 (프리뷰용)
var _stat_labels: Array = []  # [{key, val_label, diff_label}]
var _base_stat_values: Array = []  # 원본 스탯 값

# 파티 엔트리
var _party_entries: Array = []


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
	current_tab = 0
	_refresh_all()


func open_with_hero_id(hero_id: String) -> void:
	if not is_open:
		is_open = true
		visible = true
		get_tree().paused = true
		current_tab = 0
	selected_hero_index = 0

	var party := PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		var hero: Hero = party[i]
		if hero != null and hero.id == hero_id:
			selected_hero_index = i
			break
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

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.7)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimmer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.02; panel.anchor_right = 0.98
	panel.anchor_top = 0.03; panel.anchor_bottom = 0.97
	panel.offset_left = 0; panel.offset_right = 0
	panel.offset_top = 0; panel.offset_bottom = 0
	var ps := _make_style(S.bg_dark, S.border_gold, 4, 2)
	ps.content_margin_left = 8; ps.content_margin_right = 8
	ps.content_margin_top = 4; ps.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", ps)
	root.add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	panel.add_child(main_vbox)

	_build_top_bar(main_vbox)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", S.border)
	main_vbox.add_child(sep)

	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 6)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	_build_party_list(content_hbox)
	content_hbox.add_child(_make_vsep())
	_build_hero_preview(content_hbox)
	content_hbox.add_child(_make_vsep())
	_build_center_panels(content_hbox)
	content_hbox.add_child(_make_vsep())
	_build_inventory_panel(content_hbox)


func _build_top_bar(parent: VBoxContainer) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var close_btn := Button.new()
	close_btn.text = "× 정비"
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.add_theme_color_override("font_color", S.text_gold)
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	hbox.add_child(close_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

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

	hero_name_label = Label.new()
	hero_name_label.add_theme_font_size_override("font_size", 12)
	hero_name_label.add_theme_color_override("font_color", S.text)
	hero_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hero_name_label)

	hero_class_label = Label.new()
	hero_class_label.add_theme_font_size_override("font_size", 10)
	hero_class_label.add_theme_color_override("font_color", S.text_dim)
	hero_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hero_class_label)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("separator", S.border)
	vbox.add_child(sep2)

	stats_container = VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 1)
	vbox.add_child(stats_container)


func _build_center_panels(parent: HBoxContainer) -> void:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_stretch_ratio = 1.2
	wrapper.add_theme_constant_override("separation", 3)
	parent.add_child(wrapper)

	# 탭 바
	var tab_hbox := HBoxContainer.new()
	tab_hbox.add_theme_constant_override("separation", 2)
	wrapper.add_child(tab_hbox)

	_tab_buttons.clear()
	var tab_names := ["정비", "스킬", "작전"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_color_override("font_color", S.text)
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size.y = 22
		var idx := i
		btn.pressed.connect(func(): _switch_tab(idx))
		tab_hbox.add_child(btn)
		_tab_buttons.append(btn)

	# 장비 패널
	equip_panel = VBoxContainer.new()
	equip_panel.add_theme_constant_override("separation", 2)
	equip_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_child(equip_panel)

	equip_slots_container = equip_panel
	_slot_rows.clear()
	for slot_info in SLOT_DISPLAY:
		var row := _build_equip_slot_row(slot_info)
		equip_panel.add_child(row["panel"])
		_slot_rows.append(row)

	# 스킬 패널
	skills_panel = VBoxContainer.new()
	skills_panel.add_theme_constant_override("separation", 3)
	skills_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skills_panel.visible = false
	wrapper.add_child(skills_panel)

	# 작전 패널
	tactics_panel = VBoxContainer.new()
	tactics_panel.add_theme_constant_override("separation", 3)
	tactics_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tactics_panel.visible = false
	wrapper.add_child(tactics_panel)



func _build_equip_slot_row(slot_info: Dictionary) -> Dictionary:
	var panel := PanelContainer.new()
	var normal_style := _make_style(S.bg_slot, S.border, 3, 1)
	normal_style.content_margin_left = 6; normal_style.content_margin_right = 6
	normal_style.content_margin_top = 5; normal_style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", normal_style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

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

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", S.text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_label)

	var stat_label := Label.new()
	stat_label.add_theme_font_size_override("font_size", 11)
	stat_label.add_theme_color_override("font_color", S.text)
	stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stat_label.custom_minimum_size.x = 60
	stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(stat_label)

	var slot_key: String = slot_info["slot"]

	# 호버 효과
	var hover_style := _make_style(S.bg_slot_hover, S.border_gold, 3, 1)
	hover_style.content_margin_left = 6; hover_style.content_margin_right = 6
	hover_style.content_margin_top = 5; hover_style.content_margin_bottom = 5

	panel.mouse_entered.connect(func():
		panel.add_theme_stylebox_override("panel", hover_style)
	)
	panel.mouse_exited.connect(func():
		panel.add_theme_stylebox_override("panel", normal_style)
	)

	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_on_equip_slot_clicked(slot_key)
	)

	return {"panel": panel, "name_label": name_label, "stat_label": stat_label, "slot_key": slot_key}


func _build_inventory_panel(parent: HBoxContainer) -> void:
	inv_panel = VBoxContainer.new()
	inv_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_panel.size_flags_stretch_ratio = 1.3
	inv_panel.add_theme_constant_override("separation", 3)
	parent.add_child(inv_panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	inv_panel.add_child(header)

	var inv_title := Label.new()
	inv_title.text = "인벤토리"
	inv_title.add_theme_font_size_override("font_size", 11)
	inv_title.add_theme_color_override("font_color", S.text)
	inv_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(inv_title)

	inv_scroll = ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_panel.add_child(inv_scroll)

	inv_list = VBoxContainer.new()
	inv_list.add_theme_constant_override("separation", 1)
	inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inv_list)

	var desc_panel := PanelContainer.new()
	desc_panel.custom_minimum_size.y = 48
	var dp_style := _make_style(Color(0.05, 0.05, 0.08, 0.9), S.border, 3, 1)
	dp_style.content_margin_left = 6; dp_style.content_margin_right = 6
	dp_style.content_margin_top = 3; dp_style.content_margin_bottom = 3
	desc_panel.add_theme_stylebox_override("panel", dp_style)
	inv_panel.add_child(desc_panel)

	item_desc_label = RichTextLabel.new()
	item_desc_label.bbcode_enabled = true
	item_desc_label.fit_content = true
	item_desc_label.scroll_active = false
	item_desc_label.add_theme_font_size_override("normal_font_size", 9)
	item_desc_label.add_theme_color_override("default_color", S.text_dim)
	desc_panel.add_child(item_desc_label)
#endregion


#region 탭 전환
func _switch_tab(tab_index: int) -> void:
	current_tab = tab_index
	_update_tab_styles()
	equip_panel.visible = (tab_index == 0)
	skills_panel.visible = (tab_index == 1)
	tactics_panel.visible = (tab_index == 2)
	inv_panel.visible = (tab_index == 0)

	match tab_index:
		0: _refresh_equip_slots(); _refresh_inventory()
		1: _refresh_skills()
		2: _refresh_tactics()


func _update_tab_styles() -> void:
	for i in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		var style_normal: StyleBoxFlat
		var style_hover: StyleBoxFlat
		var style_pressed: StyleBoxFlat
		if i == current_tab:
			style_normal = _make_style(Color(0.16, 0.16, 0.22, 0.98), S.border_gold, 3, 1)
			style_hover = _make_style(Color(0.18, 0.18, 0.24, 0.98), S.border_gold, 3, 1)
			style_pressed = _make_style(Color(0.14, 0.14, 0.2, 0.98), S.border_gold, 3, 1)
			btn.add_theme_color_override("font_color", S.text_gold)
			btn.add_theme_color_override("font_hover_color", S.text_gold)
			btn.add_theme_color_override("font_pressed_color", S.text_gold)
			btn.add_theme_color_override("font_focus_color", S.text_gold)
		else:
			style_normal = _make_style(Color(0.08, 0.08, 0.12, 0.95), S.border, 3, 1)
			style_hover = _make_style(Color(0.12, 0.12, 0.18, 0.98), S.border, 3, 1)
			style_pressed = _make_style(Color(0.1, 0.1, 0.16, 0.98), S.border, 3, 1)
			btn.add_theme_color_override("font_color", S.text)
			btn.add_theme_color_override("font_hover_color", S.text)
			btn.add_theme_color_override("font_pressed_color", S.text)
			btn.add_theme_color_override("font_focus_color", S.text)

		for style in [style_normal, style_hover, style_pressed]:
			style.content_margin_left = 10; style.content_margin_right = 10
			style.content_margin_top = 2; style.content_margin_bottom = 2

		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.add_theme_stylebox_override("focus", style_hover)
#endregion


#region 갱신
func _refresh_all() -> void:
	_update_gold()
	_refresh_party_list()
	_refresh_hero_preview()
	_update_tab_styles()
	_switch_tab(current_tab)


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
	for child in party_list_container.get_children():
		child.queue_free()
	_party_entries.clear()

	var party := PartyManager.get_party()
	for i in range(party.size()):
		var entry := _create_party_entry(party[i], i)
		party_list_container.add_child(entry["panel"])
		_party_entries.append(entry)
	_update_party_selection()


func _create_party_entry(hero: Hero, index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(68, 50)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := _make_style(S.bg_slot, S.border, 4, 1)
	style.content_margin_left = 3; style.content_margin_right = 3
	style.content_margin_top = 3; style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = hero.hero_name
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", S.text)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var level_lbl := Label.new()
	level_lbl.text = "Lv.%d" % int(hero.level)
	level_lbl.add_theme_font_size_override("font_size", 9)
	level_lbl.add_theme_color_override("font_color", S.text_dim)
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(level_lbl)

	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected_hero_index = index
			_refresh_all()
	)
	return {"panel": panel}


func _update_party_selection() -> void:
	for i in range(_party_entries.size()):
		var style: StyleBoxFlat
		if i == selected_hero_index:
			style = _make_style(Color(0.12, 0.1, 0.05, 0.95), S.border_sel, 4, 2)
		else:
			style = _make_style(S.bg_slot, S.border, 4, 1)
		style.content_margin_left = 3; style.content_margin_right = 3
		style.content_margin_top = 3; style.content_margin_bottom = 3
		_party_entries[i]["panel"].add_theme_stylebox_override("panel", style)


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

	var face_path := ""
	if not hero.portrait.is_empty():
		face_path = FACE_PATH % hero.portrait
	elif not hero.field_sprite.is_empty():
		face_path = FACE_PATH % hero.field_sprite
	if not face_path.is_empty() and ResourceLoader.exists(face_path):
		hero_sprite.texture = load(face_path)
	else:
		hero_sprite.texture = null

	hero_name_label.text = hero.hero_name
	hero_class_label.text = "%s · Lv.%d" % [hero.hero_class_name, int(hero.level)]
	_refresh_stats()


func _refresh_stats() -> void:
	var hero := _get_hero()
	if hero == null:
		return

	for child in stats_container.get_children():
		child.queue_free()
	_stat_labels.clear()
	_base_stat_values.clear()

	var stats := [
		["LV", str(int(hero.level)), "lv"],
		["EXP", "%d/%d" % [int(hero.current_exp), int(hero.get_exp_to_next_level())], "exp"],
		["HP", "%d/%d" % [hero.current_hp, hero.get_max_hp()], "hp"],
		["ASPD", "%.1fs" % hero.get_action_delay(), "aspd"],
		["ATK", str(hero.get_atk()), "atk"],
		["DEF", str(hero.get_def()), "def"],
		["MATK", str(hero.get_magic_attack()), "matk"],
		["CRIT", "%.1f%%" % hero.get_crit(), "crit"],
		["HIT", "%.1f%%" % hero.get_hit_rate(), "hit"],
		["EVA", "%.1f%%" % hero.get_eva(), "eva"],
		["SPD", str(hero.get_spd()), "spd"],
		["STR", str(hero.get_str()), "str"],
		["AGI", str(hero.get_dex()), "agi"],
		["WIS", str(hero.get_base_stat("wis")), "wis"],
		["LUK", str(hero.get_luk()), "luk"],
	]

	for stat in stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

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

		# 비교 화살표 (기본 숨김)
		var diff := Label.new()
		diff.add_theme_font_size_override("font_size", 9)
		diff.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		diff.custom_minimum_size.x = 36
		diff.text = ""
		row.add_child(diff)

		stats_container.add_child(row)
		_stat_labels.append({"key": stat[2], "val_label": val, "diff_label": diff, "original_text": stat[1]})


func _show_stat_preview(item_id: String) -> void:
	## 인벤토리 아이템 호버 시 스탯 변화 프리뷰
	var hero := _get_hero()
	if hero == null:
		return

	var diffs := _calc_per_stat_diff(hero, item_id)

	for entry in _stat_labels:
		var stat_key: String = entry["key"]
		var diff_label: Label = entry["diff_label"]
		var val_label: Label = entry["val_label"]
		var d: int = diffs.get(stat_key, 0)

		if d > 0:
			diff_label.text = "▲%d" % d
			diff_label.add_theme_color_override("font_color", S.text_green)
			val_label.add_theme_color_override("font_color", S.text_green)
		elif d < 0:
			diff_label.text = "▼%d" % absi(d)
			diff_label.add_theme_color_override("font_color", S.text_red)
			val_label.add_theme_color_override("font_color", S.text_red)
		else:
			diff_label.text = ""
			val_label.add_theme_color_override("font_color", S.text)


func _clear_stat_preview() -> void:
	for entry in _stat_labels:
		var diff_label: Label = entry["diff_label"]
		var val_label: Label = entry["val_label"]
		diff_label.text = ""
		val_label.add_theme_color_override("font_color", S.text)


func _calc_per_stat_diff(hero: Hero, item_id: String) -> Dictionary:
	var data: Dictionary = DataManager.get_equipment(item_id)
	if data.is_empty():
		return {}
	var new_stats: Dictionary = data.get("stats", {})
	var target_slot: String = _resolve_target_slot_for_item(hero, data)
	if target_slot.is_empty():
		return {}

	var current_id: String = hero.equipment.get(target_slot, "")
	var current_stats: Dictionary = {}
	if not current_id.is_empty():
		var cd: Dictionary = DataManager.get_equipment(current_id)
		current_stats = cd.get("stats", {})

	var result: Dictionary = {}
	var keys := ["atk", "def", "str", "int", "wis", "dex", "agi", "luk", "hp", "spd", "mag", "hit", "acc", "eva"]
	for key in keys:
		var nv: int = int(new_stats.get(key, 0))
		var cv: int = int(current_stats.get(key, 0))
		if nv == cv:
			continue
		match key:
			"int", "wis":
				result["wis"] = int(result.get("wis", 0)) + (nv - cv)
				result["matk"] = int(result.get("matk", 0)) + (nv - cv)
			"dex", "agi":
				result["agi"] = int(result.get("agi", 0)) + (nv - cv)
			"mag":
				result["matk"] = int(result.get("matk", 0)) + (nv - cv)
			"acc", "hit":
				result["hit"] = int(result.get("hit", 0)) + (nv - cv)
			_:
				result[key] = int(result.get(key, 0)) + (nv - cv)
	return result
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
			var rarity: String = data.get("rarity", "common")
			name_lbl.text = data.get("name", equip_id)
			name_lbl.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, S.text))
			stat_lbl.text = _get_main_stat_text(data)
			stat_lbl.add_theme_color_override("font_color", S.text)

		if slot_key == "off_hand" and hero.is_off_hand_disabled():
			name_lbl.text = "— 양손무기 —"
			name_lbl.add_theme_color_override("font_color", S.text_dim)
			stat_lbl.text = ""


func _get_main_stat_text(data: Dictionary) -> String:
	var stats: Dictionary = data.get("stats", {})
	var parts: Array = []
	for key in ["atk", "def", "mag", "str", "wis", "int", "hp", "agi", "dex", "luk", "spd", "hit", "eva"]:
		var val: int = int(stats.get(key, 0))
		if val != 0:
			parts.append("%s %d" % [key.to_upper(), val])
	if parts.is_empty():
		return ""
	return " ".join(parts.slice(0, 3))


func _on_equip_slot_clicked(slot_key: String) -> void:
	var hero := _get_hero()
	if hero == null:
		return
	var equip_id: String = hero.equipment.get(slot_key, "")
	if equip_id.is_empty():
		return
	InventoryManager.unequip_item(hero, slot_key)
	_refresh_all()
#endregion


#region 스킬 탭
func _refresh_skills() -> void:
	for child in skills_panel.get_children():
		child.queue_free()

	var hero := _get_hero()
	if hero == null:
		return

	var available_skills: Array = hero.get_available_skills()
	for skill_id in available_skills:
		var sid: String = str(skill_id)
		var card := _create_skill_card(hero, sid)
		skills_panel.add_child(card)


func _create_skill_card(hero: Hero, skill_id: String) -> PanelContainer:
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var skill_name: String = skill_data.get("name", skill_id)
	var skill_desc: String = str(skill_data.get("description", "")).strip_edges()
	var skill_type: String = skill_data.get("type", "physical")
	var target: String = skill_data.get("target", "single_enemy")
	var is_enabled: bool = hero.is_skill_enabled(skill_id)
	var is_basic_attack: bool = (skill_id == "basic_attack")
	var is_toggle_allowed: bool = not is_basic_attack

	var panel := PanelContainer.new()
	var bg_color := Color(0.1, 0.1, 0.14, 0.9) if is_enabled else Color(0.06, 0.06, 0.09, 0.7)
	var border_c := S.border_gold if is_enabled else S.border
	var normal_style := _make_style(bg_color, border_c, 4, 1)
	normal_style.content_margin_left = 8; normal_style.content_margin_right = 8
	normal_style.content_margin_top = 6; normal_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", normal_style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# 아이콘
	var icon := Label.new()
	icon.text = SKILL_ICONS.get(skill_id, "✦")
	icon.add_theme_font_size_override("font_size", 18)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	# 정보
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info)

	# 이름 + 타입 뱃지
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = skill_name
	name_lbl.add_theme_font_size_override("font_size", 12)
	var name_color: Color = S.text if is_enabled else S.text_dim
	name_lbl.add_theme_color_override("font_color", name_color)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(name_lbl)

	# 타입 뱃지
	var badge_text := ""
	var badge_color := S.text_dim
	match skill_type:
		"physical":
			badge_text = "공격"
			badge_color = Color(1.0, 0.5, 0.3)
		"magic":
			badge_text = "마법"
			badge_color = S.text_blue
		"heal":
			badge_text = "보조"
			badge_color = S.text_green

	if not badge_text.is_empty():
		var badge := Label.new()
		badge.text = badge_text
		badge.add_theme_font_size_override("font_size", 8)
		badge.add_theme_color_override("font_color", badge_color)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(badge)

	# ATB 코스트
	var atb_cost: float = float(skill_data.get("atb_cost", 0.0))

	# 설명 행
	var desc_parts: Array = []
	# 타겟
	match target:
		"single_enemy": desc_parts.append("단일")
		"all_enemies": desc_parts.append("전체")
		"single_ally": desc_parts.append("아군")
		"all_allies": desc_parts.append("아군전체")
		"self": desc_parts.append("자신")

	# ATB 소모량
	if atb_cost > 0:
		desc_parts.append("ATB %.1fs" % atb_cost)

	# 데미지 배율
	var scaling: Dictionary = skill_data.get("damage_scaling", {})
	if not scaling.is_empty():
		var mult: float = float(scaling.get("multiplier", 1.0))
		desc_parts.append("ATK x%s" % str(mult))

	# 쿨다운 속도
	var desc_lbl := Label.new()
	desc_lbl.text = " | ".join(desc_parts)
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.add_theme_color_override("font_color", S.text_dim)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(desc_lbl)

	if not skill_desc.is_empty():
		var detail_lbl := Label.new()
		detail_lbl.text = skill_desc
		detail_lbl.add_theme_font_size_override("font_size", 9)
		detail_lbl.add_theme_color_override("font_color", S.text)
		detail_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(detail_lbl)

	var state_lbl := Label.new()
	state_lbl.add_theme_font_size_override("font_size", 9)
	state_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_basic_attack:
		state_lbl.text = "기본 공격 (항상 사용)"
		state_lbl.add_theme_color_override("font_color", S.text_blue)
	else:
		state_lbl.text = "활성" if is_enabled else "비활성"
		state_lbl.add_theme_color_override("font_color", S.text_green if is_enabled else S.text_red)
	info.add_child(state_lbl)

	# 호버 효과
	var hover_style := _make_style(Color(0.15, 0.15, 0.22, 0.95), S.border_gold, 4, 1)
	hover_style.content_margin_left = 8; hover_style.content_margin_right = 8
	hover_style.content_margin_top = 6; hover_style.content_margin_bottom = 6

	panel.mouse_entered.connect(func():
		panel.add_theme_stylebox_override("panel", hover_style)
	)
	panel.mouse_exited.connect(func():
		panel.add_theme_stylebox_override("panel", normal_style)
	)

	# 클릭 → 토글
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_toggle_allowed:
				hero.toggle_skill(skill_id)
				_refresh_skills()
	)

	return panel
#endregion


#region 작전 탭
func _refresh_tactics() -> void:
	for child in tactics_panel.get_children():
		child.queue_free()

	var hero := _get_hero()
	if hero == null:
		return

	# 헤더
	var header := Label.new()
	header.text = "스킬 사용 우선순위"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", S.text_gold)
	tactics_panel.add_child(header)

	var desc := Label.new()
	desc.text = "위에 있을수록 먼저 사용. 클릭으로 활성/비활성 전환."
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", S.text_dim)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	tactics_panel.add_child(desc)

	# 스킬 목록 (우선순위 순)
	var priority_list: Array = hero.get_skill_priority_list()
	for i in range(priority_list.size()):
		var skill_id: String = str(priority_list[i])
		var row := _create_tactics_row(hero, skill_id, i, priority_list.size())
		tactics_panel.add_child(row)

	# 기본공격 (항상 마지막, 이동 불가)
	var ba_row := _create_basic_attack_row()
	tactics_panel.add_child(ba_row)


func _create_tactics_row(hero: Hero, skill_id: String, index: int, total: int) -> PanelContainer:
	var skill_data: Dictionary = DataManager.get_skill(skill_id)
	var skill_name: String = skill_data.get("name", skill_id)
	var is_enabled: bool = hero.is_skill_enabled(skill_id)
	var atb_cost: float = float(skill_data.get("atb_cost", 0.0))

	var panel := PanelContainer.new()
	var bg_color := Color(0.1, 0.1, 0.14, 0.9) if is_enabled else Color(0.06, 0.06, 0.09, 0.6)
	var border_c := S.border_gold if is_enabled else S.border
	var normal_style := _make_style(bg_color, border_c, 3, 1)
	normal_style.content_margin_left = 6; normal_style.content_margin_right = 6
	normal_style.content_margin_top = 4; normal_style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", normal_style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# 우선순위 번호
	var num_lbl := Label.new()
	num_lbl.text = "%d." % (index + 1)
	num_lbl.add_theme_font_size_override("font_size", 10)
	num_lbl.add_theme_color_override("font_color", S.text_gold if is_enabled else S.text_dim)
	num_lbl.custom_minimum_size.x = 18
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(num_lbl)

	# 아이콘
	var icon := Label.new()
	icon.text = SKILL_ICONS.get(skill_id, "✦")
	icon.add_theme_font_size_override("font_size", 14)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	# 스킬 이름 + 정보
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = skill_name
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", S.text if is_enabled else S.text_dim)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_lbl)

	# ATB 비용 행
	var sub_parts: Array = []
	if atb_cost > 0.0:
		sub_parts.append("ATB %.1fs" % atb_cost)

	var sub_lbl := Label.new()
	sub_lbl.text = " | ".join(sub_parts)
	sub_lbl.add_theme_font_size_override("font_size", 8)
	sub_lbl.add_theme_color_override("font_color", S.text_dim)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(sub_lbl)

	# 상태 뱃지 (활성/비활성)
	var state := Label.new()
	state.add_theme_font_size_override("font_size", 9)
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_enabled:
		state.text = "ON"
		state.add_theme_color_override("font_color", S.text_green)
	else:
		state.text = "OFF"
		state.add_theme_color_override("font_color", S.text_red)
	state.custom_minimum_size.x = 24
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(state)

	# 위/아래 이동 버튼
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 0)
	hbox.add_child(btn_vbox)

	var up_btn := Button.new()
	up_btn.text = "▲"
	up_btn.add_theme_font_size_override("font_size", 8)
	up_btn.custom_minimum_size = Vector2(20, 14)
	up_btn.flat = true
	up_btn.focus_mode = Control.FOCUS_NONE
	up_btn.disabled = (index == 0)
	up_btn.add_theme_color_override("font_color", S.text if index > 0 else S.text_dim)
	var sid_up := skill_id
	up_btn.pressed.connect(func():
		hero.move_skill_priority(sid_up, -1)
		_refresh_tactics()
	)
	btn_vbox.add_child(up_btn)

	var down_btn := Button.new()
	down_btn.text = "▼"
	down_btn.add_theme_font_size_override("font_size", 8)
	down_btn.custom_minimum_size = Vector2(20, 14)
	down_btn.flat = true
	down_btn.focus_mode = Control.FOCUS_NONE
	down_btn.disabled = (index == total - 1)
	down_btn.add_theme_color_override("font_color", S.text if index < total - 1 else S.text_dim)
	var sid_down := skill_id
	down_btn.pressed.connect(func():
		hero.move_skill_priority(sid_down, 1)
		_refresh_tactics()
	)
	btn_vbox.add_child(down_btn)

	# 호버 효과
	var hover_style := _make_style(Color(0.14, 0.14, 0.2, 0.95), S.border_gold, 3, 1)
	hover_style.content_margin_left = 6; hover_style.content_margin_right = 6
	hover_style.content_margin_top = 4; hover_style.content_margin_bottom = 4

	panel.mouse_entered.connect(func():
		panel.add_theme_stylebox_override("panel", hover_style)
	)
	panel.mouse_exited.connect(func():
		panel.add_theme_stylebox_override("panel", normal_style)
	)

	# 클릭 → ON/OFF 토글
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			hero.toggle_skill(skill_id)
			_refresh_tactics()
	)

	return panel


func _create_basic_attack_row() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _make_style(Color(0.08, 0.08, 0.12, 0.7), S.border, 3, 1)
	style.content_margin_left = 6; style.content_margin_right = 6
	style.content_margin_top = 4; style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	var dot_lbl := Label.new()
	dot_lbl.text = "—"
	dot_lbl.add_theme_font_size_override("font_size", 10)
	dot_lbl.add_theme_color_override("font_color", S.text_dim)
	dot_lbl.custom_minimum_size.x = 18
	dot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(dot_lbl)

	var icon := Label.new()
	icon.text = "⚔️"
	icon.add_theme_font_size_override("font_size", 14)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = "기본 공격 (스킬 사용 불가 시 자동)"
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", S.text_blue)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_lbl)

	return panel
#endregion


#region 인벤토리
func _refresh_inventory() -> void:
	for child in inv_list.get_children():
		child.queue_free()
	if item_desc_label:
		item_desc_label.text = ""
	_clear_stat_preview()

	var hero := _get_hero()
	var all_items: Array = InventoryManager.get_equipment_items()

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
	var can_equip := hero != null and hero.can_equip(item_id)

	var panel := PanelContainer.new()
	var normal_style := _make_style(Color(0.06, 0.06, 0.09, 0.8), Color.TRANSPARENT, 2, 0)
	normal_style.content_margin_left = 5; normal_style.content_margin_right = 5
	normal_style.content_margin_top = 3; normal_style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", normal_style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	var slot: String = data.get("slot", "")
	var icon_lbl := Label.new()
	icon_lbl.text = _get_slot_icon(slot)
	icon_lbl.add_theme_font_size_override("font_size", 11)
	icon_lbl.custom_minimum_size.x = 16
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_lbl)

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
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = _get_main_stat_text(data)
	sub_lbl.add_theme_font_size_override("font_size", 8)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(sub_lbl)

	var diff_lbl := Label.new()
	diff_lbl.add_theme_font_size_override("font_size", 10)
	diff_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	diff_lbl.custom_minimum_size.x = 40
	diff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(diff_lbl)

	if not can_equip:
		# 장착 불가 — 회색 처리, 호버 없음
		name_lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.38))
		sub_lbl.add_theme_color_override("font_color", Color(0.25, 0.25, 0.28))
		icon_lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.33))
		diff_lbl.text = ""
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		name_lbl.add_theme_color_override("font_color", rarity_color)
		sub_lbl.add_theme_color_override("font_color", S.text_dim)

		# 비교 수치
		if hero != null:
			var diff := _calc_total_diff(hero, item_id)
			if diff > 0:
				diff_lbl.text = "+%d" % diff
				diff_lbl.add_theme_color_override("font_color", S.text_green)
			elif diff < 0:
				diff_lbl.text = "%d" % diff
				diff_lbl.add_theme_color_override("font_color", S.text_red)

		# 호버 효과 + 스탯 프리뷰
		var hover_style := _make_style(Color(0.12, 0.12, 0.18, 0.95), S.border, 2, 1)
		hover_style.content_margin_left = 5; hover_style.content_margin_right = 5
		hover_style.content_margin_top = 3; hover_style.content_margin_bottom = 3

		panel.mouse_entered.connect(func():
			panel.add_theme_stylebox_override("panel", hover_style)
			_show_item_desc(data)
			_show_stat_preview(item_id)
		)
		panel.mouse_exited.connect(func():
			panel.add_theme_stylebox_override("panel", normal_style)
			_clear_stat_preview()
		)

		# 클릭 → 장착
		panel.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_on_inv_item_clicked(item_id)
		)

	return panel


func _calc_total_diff(hero: Hero, item_id: String) -> int:
	var diffs := _calc_per_stat_diff(hero, item_id)
	var total: int = 0
	for v in diffs.values():
		total += v
	return total


func _on_inv_item_clicked(item_id: String) -> void:
	var hero := _get_hero()
	if hero == null or not hero.can_equip(item_id):
		return

	var data: Dictionary = DataManager.get_equipment(item_id)
	var target_slot: String = _resolve_target_slot_for_item(hero, data)
	if target_slot.is_empty():
		return

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
	item_desc_label.text = "[color=#%s]%s[/color]\n%s" % [color.to_html(false), name_str, desc]


func _get_slot_icon(slot: String) -> String:
	match slot:
		"main_hand": return "⚔"
		"off_hand": return "🛡"
		"body": return "🧥"
		"head": return "⛑"
		"acc1", "acc2", "acc", "ring", "necklace", "boots", "shoes", "gloves": return "💍"
		_: return "•"


func _resolve_target_slot_for_item(hero: Hero, data: Dictionary) -> String:
	if hero == null or data.is_empty():
		return ""
	var slot_norm: String = Hero.normalize_equipment_slot(str(data.get("slot", "")))
	if slot_norm == "acc":
		if hero.equipment.get("acc1", "").is_empty():
			return "acc1"
		if hero.equipment.get("acc2", "").is_empty():
			return "acc2"
		return "acc1"
	if slot_norm == "main_hand":
		if hero.equipment.get("main_hand", "").is_empty():
			return "main_hand"
		if hero.can_dual_wield() and hero.equipment.get("off_hand", "").is_empty() and not hero.is_off_hand_disabled():
			return "off_hand"
		return "main_hand"
	if slot_norm == "off_hand" and hero.is_off_hand_disabled():
		return ""
	return slot_norm
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
