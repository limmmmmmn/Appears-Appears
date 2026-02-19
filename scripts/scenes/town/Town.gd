extends Control

const GRID_COLS: int = 3
const GRID_ROWS: int = 3
const CELL_COUNT: int = GRID_COLS * GRID_ROWS

const COMMERCIAL_BUILDINGS: Array[Dictionary] = [
	{"name": "상점", "kind": "상가", "desc": "장비와 소모품을 거래하는 곳"},
	{"name": "여관", "kind": "상가", "desc": "파티를 쉬게 하고 정비하는 곳"},
	{"name": "교회", "kind": "상가", "desc": "축복과 회복 의식을 진행하는 곳"},
]

const EVENT_BUILDINGS: Array[Dictionary] = [
	{"name": "집", "kind": "이벤트", "desc": "주민 이벤트가 열리는 민가"},
	{"name": "집2", "kind": "이벤트", "desc": "수상한 소문이 도는 두 번째 집"},
	{"name": "분수대", "kind": "이벤트", "desc": "사람들이 모이는 중심 광장"},
]

const EXTRA_BUILDINGS: Array[Dictionary] = [
	{"name": "광장", "kind": "이벤트", "desc": "잠깐 쉬어가기 좋은 열린 공간"},
	{"name": "창고", "kind": "상가", "desc": "물자 보관과 납품 의뢰가 있는 장소"},
	{"name": "우물", "kind": "이벤트", "desc": "마을 소문의 시작점"},
]

const STREET_THEME := {
	"상점": {"color": Color(0.22, 0.28, 0.38, 0.95), "label": "상점 앞 거리"},
	"여관": {"color": Color(0.34, 0.24, 0.19, 0.95), "label": "여관 앞 휴식 거리"},
	"교회": {"color": Color(0.24, 0.22, 0.34, 0.95), "label": "교회 앞 조용한 거리"},
	"집": {"color": Color(0.25, 0.33, 0.23, 0.95), "label": "주택가 골목"},
	"집2": {"color": Color(0.31, 0.27, 0.21, 0.95), "label": "주택가 안쪽 골목"},
	"분수대": {"color": Color(0.2, 0.32, 0.34, 0.95), "label": "분수대 광장"},
	"광장": {"color": Color(0.28, 0.28, 0.24, 0.95), "label": "중앙 광장"},
	"창고": {"color": Color(0.3, 0.25, 0.2, 0.95), "label": "창고 구역"},
	"우물": {"color": Color(0.24, 0.3, 0.28, 0.95), "label": "우물가"},
}

var top_bar: PanelContainer
var title_label: Label
var back_button: Button

var grid_panel: PanelContainer
var grid: GridContainer
var grid_buttons: Array[Button] = []
var layout_data: Array[Dictionary] = []

var building_popup: PanelContainer
var popup_title: Label
var popup_kind: Label
var popup_desc: Label

var street_panel: PanelContainer
var street_title: Label
var street_runway: Control
var street_bg: ColorRect

var walkers: Array[Dictionary] = []
var shop_trinket_granted_this_visit: bool = false
var event_trinket_granted_this_visit: bool = false

func _ready() -> void:
	randomize()
	_build_ui()
	_generate_building_layout()
	_render_grid()
	_spawn_party_walkers()
	_set_selected_building(0)


func _process(delta: float) -> void:
	_update_walkers(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_call_update_layout_sizes_deferred()


func _call_update_layout_sizes_deferred() -> void:
	if not is_inside_tree():
		return
	call_deferred("_update_layout_sizes")


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.07, 0.1, 1.0)
	add_child(bg)

	top_bar = PanelContainer.new()
	top_bar.anchor_left = 0.5
	top_bar.anchor_top = 0.0
	top_bar.anchor_right = 0.5
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = -360
	top_bar.offset_top = 16
	top_bar.offset_right = 360
	top_bar.offset_bottom = 66
	top_bar.add_theme_stylebox_override("panel", _make_style(Color(0.12, 0.14, 0.2, 0.95), Color(0.38, 0.44, 0.6, 0.9), 8, 2))
	add_child(top_bar)

	var top_h := HBoxContainer.new()
	top_h.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_h.add_theme_constant_override("separation", 12)
	top_bar.add_child(top_h)

	title_label = Label.new()
	title_label.text = "마을"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86, 1.0))
	top_h.add_child(title_label)

	back_button = Button.new()
	back_button.text = "필드로"
	back_button.custom_minimum_size = Vector2(120, 36)
	back_button.add_theme_font_size_override("font_size", 14)
	back_button.add_theme_stylebox_override("normal", _make_style(Color(0.2, 0.35, 0.22, 0.95), Color(0.45, 0.7, 0.5, 1.0), 6, 2))
	back_button.pressed.connect(_on_back_pressed)
	top_h.add_child(back_button)

	grid_panel = PanelContainer.new()
	grid_panel.anchor_left = 0.5
	grid_panel.anchor_top = 0.5
	grid_panel.anchor_right = 0.5
	grid_panel.anchor_bottom = 0.5
	grid_panel.offset_left = -280
	grid_panel.offset_top = -220
	grid_panel.offset_right = 280
	grid_panel.offset_bottom = 220
	grid_panel.add_theme_stylebox_override("panel", _make_style(Color(0.1, 0.11, 0.16, 0.95), Color(0.34, 0.4, 0.58, 0.8), 10, 2))
	add_child(grid_panel)

	grid = GridContainer.new()
	grid.columns = GRID_COLS
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.offset_left = 18
	grid.offset_top = 18
	grid.offset_right = -18
	grid.offset_bottom = -18
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid_panel.add_child(grid)

	for i in range(CELL_COUNT):
		var b := Button.new()
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(110, 110)
		b.add_theme_font_size_override("font_size", 15)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_stylebox_override("normal", _make_style(Color(0.14, 0.16, 0.23, 0.95), Color(0.32, 0.38, 0.55, 0.9), 8, 2))
		b.add_theme_stylebox_override("hover", _make_style(Color(0.18, 0.2, 0.3, 0.98), Color(0.65, 0.72, 0.95, 1.0), 8, 2))
		b.pressed.connect(_on_grid_pressed.bind(i))
		grid.add_child(b)
		grid_buttons.append(b)

	building_popup = PanelContainer.new()
	building_popup.anchor_left = 0.5
	building_popup.anchor_top = 0.5
	building_popup.anchor_right = 0.5
	building_popup.anchor_bottom = 0.5
	building_popup.offset_left = 300
	building_popup.offset_top = -130
	building_popup.offset_right = 560
	building_popup.offset_bottom = 130
	building_popup.add_theme_stylebox_override("panel", _make_style(Color(0.1, 0.12, 0.19, 0.95), Color(0.62, 0.68, 0.88, 0.95), 8, 2))
	add_child(building_popup)

	var pop_v := VBoxContainer.new()
	pop_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	pop_v.offset_left = 12
	pop_v.offset_top = 12
	pop_v.offset_right = -12
	pop_v.offset_bottom = -12
	pop_v.add_theme_constant_override("separation", 8)
	building_popup.add_child(pop_v)

	popup_title = Label.new()
	popup_title.add_theme_font_size_override("font_size", 22)
	popup_title.add_theme_color_override("font_color", Color(1, 0.92, 0.76, 1))
	pop_v.add_child(popup_title)

	popup_kind = Label.new()
	popup_kind.add_theme_font_size_override("font_size", 14)
	popup_kind.add_theme_color_override("font_color", Color(0.75, 0.84, 1.0, 1))
	pop_v.add_child(popup_kind)

	popup_desc = Label.new()
	popup_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	popup_desc.add_theme_font_size_override("font_size", 14)
	popup_desc.add_theme_color_override("font_color", Color(0.9, 0.92, 0.98, 1))
	popup_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pop_v.add_child(popup_desc)

	street_panel = PanelContainer.new()
	street_panel.anchor_left = 0.5
	street_panel.anchor_top = 1.0
	street_panel.anchor_right = 0.5
	street_panel.anchor_bottom = 1.0
	street_panel.offset_left = -430
	street_panel.offset_top = -185
	street_panel.offset_right = 430
	street_panel.offset_bottom = -22
	street_panel.add_theme_stylebox_override("panel", _make_style(Color(0.18, 0.24, 0.3, 0.95), Color(0.45, 0.56, 0.7, 0.95), 10, 2))
	add_child(street_panel)

	var street_v := VBoxContainer.new()
	street_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	street_v.offset_left = 12
	street_v.offset_top = 10
	street_v.offset_right = -12
	street_v.offset_bottom = -10
	street_v.add_theme_constant_override("separation", 8)
	street_panel.add_child(street_v)

	street_title = Label.new()
	street_title.add_theme_font_size_override("font_size", 15)
	street_title.add_theme_color_override("font_color", Color(0.96, 0.96, 0.95, 1))
	street_v.add_child(street_title)

	street_runway = Control.new()
	street_runway.custom_minimum_size = Vector2(100, 110)
	street_runway.size_flags_vertical = Control.SIZE_EXPAND_FILL
	street_runway.clip_contents = true
	street_v.add_child(street_runway)

	street_bg = ColorRect.new()
	street_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	street_bg.color = Color(0.22, 0.28, 0.38, 0.95)
	street_runway.add_child(street_bg)
	street_runway.move_child(street_bg, 0)

	_update_layout_sizes()


func _update_layout_sizes() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var square: float = clampf(minf(vp.x * 0.52, vp.y * 0.56), 300.0, 520.0)
	grid_panel.offset_left = -square * 0.5
	grid_panel.offset_top = -square * 0.5
	grid_panel.offset_right = square * 0.5
	grid_panel.offset_bottom = square * 0.5

	street_panel.offset_left = -minf(vp.x * 0.44, 460.0)
	street_panel.offset_right = minf(vp.x * 0.44, 460.0)
	street_panel.offset_top = -minf(vp.y * 0.28, 200.0)
	street_panel.offset_bottom = -22

	if vp.x < 1120:
		building_popup.offset_left = -square * 0.5
		building_popup.offset_right = square * 0.5
		building_popup.offset_top = square * 0.55
		building_popup.offset_bottom = square * 0.55 + 180
	else:
		building_popup.offset_left = square * 0.6
		building_popup.offset_right = square * 0.6 + 260
		building_popup.offset_top = -130
		building_popup.offset_bottom = 130


func _generate_building_layout() -> void:
	layout_data.clear()
	for b in COMMERCIAL_BUILDINGS:
		layout_data.append((b as Dictionary).duplicate())
	for b in EVENT_BUILDINGS:
		layout_data.append((b as Dictionary).duplicate())

	var all_pool: Array[Dictionary] = []
	for b in COMMERCIAL_BUILDINGS:
		all_pool.append((b as Dictionary).duplicate())
	for b in EVENT_BUILDINGS:
		all_pool.append((b as Dictionary).duplicate())
	for b in EXTRA_BUILDINGS:
		all_pool.append((b as Dictionary).duplicate())

	while layout_data.size() < CELL_COUNT:
		var pick: Dictionary = (all_pool[randi() % all_pool.size()] as Dictionary).duplicate()
		layout_data.append(pick)

	layout_data.shuffle()


func _render_grid() -> void:
	for i in range(mini(grid_buttons.size(), layout_data.size())):
		var b: Button = grid_buttons[i]
		var data: Dictionary = layout_data[i]
		b.text = "%s\n[%s]" % [str(data.get("name", "빈칸")), str(data.get("kind", "구역"))]


func _set_selected_building(index: int) -> void:
	if index < 0 or index >= layout_data.size():
		return
	var data: Dictionary = layout_data[index]
	var bname: String = str(data.get("name", "알 수 없는 장소"))
	var bkind: String = str(data.get("kind", "구역"))
	var bdesc: String = str(data.get("desc", "이 장소에 대한 정보가 아직 없다."))

	popup_title.text = bname
	popup_kind.text = "%s 패널" % bkind
	popup_desc.text = bdesc
	building_popup.visible = true

	for i in range(grid_buttons.size()):
		var btn: Button = grid_buttons[i]
		if i == index:
			btn.add_theme_stylebox_override("normal", _make_style(Color(0.26, 0.21, 0.12, 0.98), Color(0.95, 0.78, 0.36, 1.0), 8, 2))
		else:
			btn.add_theme_stylebox_override("normal", _make_style(Color(0.14, 0.16, 0.23, 0.95), Color(0.32, 0.38, 0.55, 0.9), 8, 2))

	_apply_street_theme(bname)


func _apply_street_theme(building_name: String) -> void:
	var entry: Dictionary = STREET_THEME.get(building_name, {"color": Color(0.2, 0.22, 0.28, 0.95), "label": "마을 골목"})
	street_bg.color = entry.get("color", Color(0.2, 0.22, 0.28, 0.95)) as Color
	street_title.text = str(entry.get("label", "마을 골목"))


func _spawn_party_walkers() -> void:
	walkers.clear()
	for child in street_runway.get_children():
		if child is TextureRect:
			child.queue_free()

	var hero_ids: Array[String] = []
	if PartyManager != null:
		for hero_any in PartyManager.get_party():
			var hero: Hero = hero_any as Hero
			if hero != null:
				hero_ids.append(hero.id)

	if hero_ids.is_empty():
		hero_ids = ["roland", "luna", "gareth", "shadow"]

	var run_w: float = maxf(120.0, street_runway.size.x)
	var run_h: float = maxf(80.0, street_runway.size.y)

	for i in range(mini(hero_ids.size(), 6)):
		var hero_id: String = hero_ids[i]
		var tex: Texture2D = _get_hero_field_texture(hero_id)
		if tex == null:
			continue
		var sprite := TextureRect.new()
		sprite.texture = tex
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP
		sprite.custom_minimum_size = tex.get_size() * 1.85
		sprite.size = sprite.custom_minimum_size
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		street_runway.add_child(sprite)

		var min_x: float = 12.0
		var max_x: float = maxf(min_x + 40.0, run_w - sprite.size.x - 12.0)
		var start_x: float = lerpf(min_x, max_x, float(i + 1) / float(mini(hero_ids.size(), 6) + 1))
		var base_y: float = run_h - sprite.size.y - 12.0 - float(i % 2) * 8.0
		sprite.position = Vector2(start_x, maxf(4.0, base_y))

		var spd: float = randf_range(28.0, 44.0)
		if randf() < 0.5:
			spd = -spd
		sprite.flip_h = spd < 0.0

		walkers.append({
			"node": sprite,
			"speed": spd,
			"min_x": min_x,
			"max_x": max_x,
			"base_y": maxf(4.0, base_y),
			"phase": randf_range(0.0, TAU),
		})


func _update_walkers(delta: float) -> void:
	if walkers.is_empty():
		return
	var run_w: float = maxf(120.0, street_runway.size.x)
	var run_h: float = maxf(80.0, street_runway.size.y)

	for w in walkers:
		var node: TextureRect = w.get("node", null) as TextureRect
		if node == null or not is_instance_valid(node):
			continue

		var min_x: float = 12.0
		var max_x: float = maxf(min_x + 40.0, run_w - node.size.x - 12.0)
		w["min_x"] = min_x
		w["max_x"] = max_x

		var spd: float = float(w.get("speed", 30.0))
		var x: float = node.position.x + spd * delta
		if x <= min_x:
			x = min_x
			spd = absf(spd)
		elif x >= max_x:
			x = max_x
			spd = -absf(spd)
		w["speed"] = spd
		node.flip_h = spd < 0.0

		var phase: float = float(w.get("phase", 0.0)) + delta * 4.0
		w["phase"] = phase
		var bob: float = sin(phase) * 1.5
		var base_y: float = minf(maxf(4.0, float(w.get("base_y", 4.0))), run_h - node.size.y - 4.0)
		node.position = Vector2(x, base_y + bob)


func _get_hero_field_texture(hero_id: String) -> Texture2D:
	if SpriteManager == null:
		return null
	var frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero_id)
	if frames == null:
		return null

	var candidates := ["walk_right", "walk_down", "walk_left", "walk_up"]
	for anim in candidates:
		if frames.has_animation(anim) and frames.get_frame_count(anim) > 0:
			var frame_idx: int = mini(1, frames.get_frame_count(anim) - 1)
			var tex: Texture2D = frames.get_frame_texture(anim, frame_idx)
			if tex != null:
				return tex
	return null


func _on_grid_pressed(index: int) -> void:
	_set_selected_building(index)
	_try_grant_town_trinket(index)


func _on_back_pressed() -> void:
	if GameManager != null and GameManager.has_method("go_to_area"):
		if FieldManager != null and FieldManager.get_current_area_type() == "town":
			GameManager.go_to_next_from_area()
		else:
			GameManager.go_to_area()
	else:
		if FieldManager != null:
			if FieldManager.current_act_id.is_empty():
				FieldManager.set_current_act("act_1")
			if FieldManager.current_area_id.is_empty():
				var first_area_id: String = FieldManager.get_first_area_id(FieldManager.current_act_id)
				if not first_area_id.is_empty():
					FieldManager.set_current_area(first_area_id)
			var fallback_scene: String = FieldManager.get_current_area_scene()
			if not fallback_scene.is_empty():
				get_tree().change_scene_to_file(fallback_scene)
			else:
				push_error("[Town] 돌아갈 에어리어 씬을 찾을 수 없습니다.")


func _try_grant_town_trinket(index: int) -> void:
	if index < 0 or index >= layout_data.size():
		return
	if GameManager == null or not GameManager.has_method("grant_random_trinket"):
		return

	var data: Dictionary = layout_data[index]
	var kind: String = str(data.get("kind", ""))
	var source: String = ""
	var source_name: String = ""

	if kind == "상가":
		if shop_trinket_granted_this_visit:
			return
		source = "shop"
		source_name = "상점"
	elif kind == "이벤트":
		if event_trinket_granted_this_visit:
			return
		source = "event"
		source_name = "이벤트"
	else:
		return

	var gained_trinket_id: String = str(GameManager.call("grant_random_trinket", source))
	if gained_trinket_id.is_empty():
		return

	if source == "shop":
		shop_trinket_granted_this_visit = true
	else:
		event_trinket_granted_this_visit = true

	var tdata: Dictionary = DataManager.get_trinket(gained_trinket_id) if DataManager != null else {}
	var tname: String = str(tdata.get("name", gained_trinket_id))
	var temoji: String = str(tdata.get("emoji", "🧿"))
	var append_msg: String = "\n\n%s [%s] 트링켓 획득: %s" % [temoji, source_name, tname]
	if popup_desc != null:
		popup_desc.text += append_msg


func _make_style(bg: Color, border: Color, radius: int = 6, width: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = width
	s.border_width_top = width
	s.border_width_right = width
	s.border_width_bottom = width
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	return s
