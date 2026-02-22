extends Control
@export var town_label: String = ""

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

const GRID_H_DEFAULT := Vector2(-170, 170)
const GRID_H_SELECTED := Vector2(-444, -104)
const DETAIL_H_VISIBLE := Vector2(-84, 460)
const DETAIL_H_HIDDEN := Vector2(460, 1004)
const PANEL_V := Vector2(-170, 170)
const SLIDE_DURATION := 0.35
const SLIDE_DELAY := 0.08

const BTN_NORMAL_BG := Color(0.14, 0.16, 0.23, 0.95)
const BTN_NORMAL_BORDER := Color(0.32, 0.38, 0.55, 0.9)
const BTN_HOVER_BG := Color(0.18, 0.2, 0.3, 0.98)
const BTN_HOVER_BORDER := Color(0.65, 0.72, 0.95, 1.0)
const BTN_SELECTED_BG := Color(0.26, 0.21, 0.12, 0.98)
const BTN_SELECTED_BORDER := Color(0.95, 0.78, 0.36, 1.0)

var top_bar: PanelContainer
var title_label: Label
var back_button: Button

var main_content: Control
var grid_panel: PanelContainer
var grid: GridContainer
var grid_buttons: Array[Button] = []

var detail_panel: PanelContainer
var detail_title: Label
var detail_kind: Label
var detail_info: Label

var street_panel: PanelContainer
var street_title: Label
var street_runway: Control
var street_bg: ColorRect

var layout_data: Array[Dictionary] = []
var walkers: Array[Dictionary] = []
var is_grid_shifted: bool = false
var selected_index: int = -1
var shop_trinket_granted_this_visit: bool = false
var event_trinket_granted_this_visit: bool = false
var town_visit_order_in_act: int = 1
var town_area_order_in_act: int = 1
var town_act_order: int = 1


func _ready() -> void:
	randomize()
	_resolve_town_stage_context()
	_build_ui()
	_apply_town_title()
	_generate_building_layout()
	_render_grid()
	_apply_street_theme("")
	call_deferred("_spawn_party_walkers")


func _process(delta: float) -> void:
	_update_walkers(delta)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.07, 0.1, 1.0)
	add_child(bg)

	_build_top_bar()
	_build_main_content()
	_build_street_strip()


func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_top = 0.0
	top_bar.anchor_right = 1.0
	top_bar.anchor_bottom = 0.0
	top_bar.offset_left = 20
	top_bar.offset_top = 10
	top_bar.offset_right = -20
	top_bar.offset_bottom = 52
	top_bar.add_theme_stylebox_override("panel", _make_style(Color(0.12, 0.14, 0.2, 0.95), Color(0.38, 0.44, 0.6, 0.9), 8, 2))
	add_child(top_bar)

	var top_h := HBoxContainer.new()
	top_h.set_anchors_preset(Control.PRESET_FULL_RECT)
	top_h.offset_left = 14
	top_h.offset_right = -14
	top_h.add_theme_constant_override("separation", 12)
	top_bar.add_child(top_h)

	title_label = Label.new()
	title_label.text = "마을"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86, 1.0))
	top_h.add_child(title_label)

	back_button = Button.new()
	back_button.text = "나가기"
	back_button.custom_minimum_size = Vector2(100, 30)
	back_button.add_theme_font_size_override("font_size", 13)
	back_button.add_theme_stylebox_override("normal", _make_style(Color(0.2, 0.35, 0.22, 0.95), Color(0.45, 0.7, 0.5, 1.0), 6, 2))
	back_button.pressed.connect(_on_back_pressed)
	top_h.add_child(back_button)


func _build_main_content() -> void:
	main_content = Control.new()
	main_content.anchor_left = 0.0
	main_content.anchor_top = 0.0
	main_content.anchor_right = 1.0
	main_content.anchor_bottom = 1.0
	main_content.offset_top = 58
	main_content.offset_bottom = -84
	add_child(main_content)

	grid_panel = PanelContainer.new()
	grid_panel.anchor_left = 0.5
	grid_panel.anchor_top = 0.5
	grid_panel.anchor_right = 0.5
	grid_panel.anchor_bottom = 0.5
	grid_panel.offset_left = GRID_H_DEFAULT.x
	grid_panel.offset_top = PANEL_V.x
	grid_panel.offset_right = GRID_H_DEFAULT.y
	grid_panel.offset_bottom = PANEL_V.y
	grid_panel.add_theme_stylebox_override("panel", _make_style(Color(0.1, 0.11, 0.16, 0.95), Color(0.34, 0.4, 0.58, 0.8), 10, 2))
	main_content.add_child(grid_panel)

	grid = GridContainer.new()
	grid.columns = GRID_COLS
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.offset_left = 14
	grid.offset_top = 14
	grid.offset_right = -14
	grid.offset_bottom = -14
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid_panel.add_child(grid)

	for i in range(CELL_COUNT):
		var b := Button.new()
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 96)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_stylebox_override("normal", _make_style(BTN_NORMAL_BG, BTN_NORMAL_BORDER, 8, 2))
		b.add_theme_stylebox_override("hover", _make_style(BTN_HOVER_BG, BTN_HOVER_BORDER, 8, 2))
		b.pressed.connect(_on_grid_pressed.bind(i))
		grid.add_child(b)
		grid_buttons.append(b)

	detail_panel = PanelContainer.new()
	detail_panel.anchor_left = 0.5
	detail_panel.anchor_top = 0.5
	detail_panel.anchor_right = 0.5
	detail_panel.anchor_bottom = 0.5
	detail_panel.offset_left = DETAIL_H_HIDDEN.x
	detail_panel.offset_top = PANEL_V.x
	detail_panel.offset_right = DETAIL_H_HIDDEN.y
	detail_panel.offset_bottom = PANEL_V.y
	detail_panel.visible = false
	detail_panel.add_theme_stylebox_override("panel", _make_style(Color(0.1, 0.12, 0.19, 0.95), Color(0.48, 0.54, 0.72, 0.9), 10, 2))
	main_content.add_child(detail_panel)

	var detail_v := VBoxContainer.new()
	detail_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	detail_v.offset_left = 18
	detail_v.offset_top = 18
	detail_v.offset_right = -18
	detail_v.offset_bottom = -18
	detail_v.add_theme_constant_override("separation", 8)
	detail_panel.add_child(detail_v)

	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 20)
	detail_title.add_theme_color_override("font_color", Color(1, 0.92, 0.76, 1))
	detail_v.add_child(detail_title)

	detail_kind = Label.new()
	detail_kind.add_theme_font_size_override("font_size", 13)
	detail_kind.add_theme_color_override("font_color", Color(0.75, 0.84, 1.0, 0.8))
	detail_v.add_child(detail_kind)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_v.add_child(spacer)

	detail_info = Label.new()
	detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_info.add_theme_font_size_override("font_size", 13)
	detail_info.add_theme_color_override("font_color", Color(0.9, 0.92, 0.98, 0.9))
	detail_v.add_child(detail_info)


func _build_street_strip() -> void:
	street_panel = PanelContainer.new()
	street_panel.anchor_left = 0.0
	street_panel.anchor_top = 1.0
	street_panel.anchor_right = 1.0
	street_panel.anchor_bottom = 1.0
	street_panel.offset_left = 20
	street_panel.offset_top = -78
	street_panel.offset_right = -20
	street_panel.offset_bottom = -8
	street_panel.add_theme_stylebox_override("panel", _make_style(Color(0.14, 0.18, 0.24, 0.95), Color(0.35, 0.44, 0.58, 0.9), 8, 2))
	add_child(street_panel)

	var street_v := VBoxContainer.new()
	street_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	street_v.offset_left = 10
	street_v.offset_top = 6
	street_v.offset_right = -10
	street_v.offset_bottom = -6
	street_v.add_theme_constant_override("separation", 2)
	street_panel.add_child(street_v)

	street_title = Label.new()
	street_title.add_theme_font_size_override("font_size", 11)
	street_title.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92, 0.9))
	street_v.add_child(street_title)

	street_runway = Control.new()
	street_runway.custom_minimum_size = Vector2(100, 40)
	street_runway.size_flags_vertical = Control.SIZE_EXPAND_FILL
	street_runway.clip_contents = true
	street_v.add_child(street_runway)

	street_bg = ColorRect.new()
	street_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	street_bg.color = Color(0.2, 0.22, 0.28, 0.95)
	street_runway.add_child(street_bg)
	street_runway.move_child(street_bg, 0)


func _apply_town_title() -> void:
	var resolved: String = town_label.strip_edges()
	if resolved.is_empty() and FieldManager != null:
		resolved = str(FieldManager.get_current_area_name()).strip_edges()
	if resolved.is_empty():
		resolved = "마을"
	var stage_suffix: String = " [A%d-T%d]" % [town_act_order, town_visit_order_in_act]
	if title_label != null:
		title_label.text = resolved + stage_suffix


func _generate_building_layout() -> void:
	layout_data.clear()
	var profile: Dictionary = _get_town_stage_profile()
	_append_random_pool_items(COMMERCIAL_BUILDINGS, int(profile.get("commercial_slots", 3)))
	_append_random_pool_items(EVENT_BUILDINGS, int(profile.get("event_slots", 3)))
	_append_random_pool_items(EXTRA_BUILDINGS, int(profile.get("extra_slots", 1)))

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


func _select_building(index: int) -> void:
	if index < 0 or index >= layout_data.size():
		return

	selected_index = index
	_update_grid_highlights()
	_update_detail_content()

	var bname: String = str(layout_data[index].get("name", ""))
	_apply_street_theme(bname)

	if not is_grid_shifted:
		is_grid_shifted = true
		_animate_grid_shift()


func _animate_grid_shift() -> void:
	detail_panel.visible = true
	detail_panel.offset_left = DETAIL_H_HIDDEN.x
	detail_panel.offset_right = DETAIL_H_HIDDEN.y
	detail_panel.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(grid_panel, "offset_left", GRID_H_SELECTED.x, SLIDE_DURATION)
	tween.tween_property(grid_panel, "offset_right", GRID_H_SELECTED.y, SLIDE_DURATION)

	tween.tween_property(detail_panel, "offset_left", DETAIL_H_VISIBLE.x, SLIDE_DURATION).set_delay(SLIDE_DELAY)
	tween.tween_property(detail_panel, "offset_right", DETAIL_H_VISIBLE.y, SLIDE_DURATION).set_delay(SLIDE_DELAY)
	tween.tween_property(detail_panel, "modulate:a", 1.0, 0.25).set_delay(SLIDE_DELAY + 0.05)


func _update_detail_content() -> void:
	if selected_index < 0 or selected_index >= layout_data.size():
		return
	var data: Dictionary = layout_data[selected_index]
	detail_title.text = str(data.get("name", ""))
	detail_kind.text = "[%s]" % str(data.get("kind", ""))
	detail_info.text = ""


func _update_grid_highlights() -> void:
	for i in range(grid_buttons.size()):
		var btn: Button = grid_buttons[i]
		if i == selected_index:
			btn.add_theme_stylebox_override("normal", _make_style(BTN_SELECTED_BG, BTN_SELECTED_BORDER, 8, 2))
		else:
			btn.add_theme_stylebox_override("normal", _make_style(BTN_NORMAL_BG, BTN_NORMAL_BORDER, 8, 2))


func _apply_street_theme(building_name: String) -> void:
	var entry: Dictionary = STREET_THEME.get(building_name, {"color": Color(0.2, 0.22, 0.28, 0.95), "label": "마을 거리"})
	street_bg.color = entry.get("color", Color(0.2, 0.22, 0.28, 0.95)) as Color
	street_title.text = str(entry.get("label", "마을 거리"))


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
	var run_h: float = maxf(40.0, street_runway.size.y)

	for i in range(mini(hero_ids.size(), 6)):
		var hero_id: String = hero_ids[i]
		var tex: Texture2D = _get_hero_field_texture(hero_id)
		if tex == null:
			continue
		var sprite := TextureRect.new()
		sprite.texture = tex
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP
		sprite.custom_minimum_size = tex.get_size() * 1.2
		sprite.size = sprite.custom_minimum_size
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		street_runway.add_child(sprite)

		var min_x: float = 8.0
		var max_x: float = maxf(min_x + 30.0, run_w - sprite.size.x - 8.0)
		var start_x: float = lerpf(min_x, max_x, float(i + 1) / float(mini(hero_ids.size(), 6) + 1))
		var base_y: float = run_h - sprite.size.y - 4.0 - float(i % 2) * 4.0
		sprite.position = Vector2(start_x, maxf(2.0, base_y))

		var spd: float = randf_range(22.0, 36.0)
		if randf() < 0.5:
			spd = -spd
		sprite.flip_h = spd < 0.0

		walkers.append({
			"node": sprite,
			"speed": spd,
			"min_x": min_x,
			"max_x": max_x,
			"base_y": maxf(2.0, base_y),
			"phase": randf_range(0.0, TAU),
		})


func _update_walkers(delta: float) -> void:
	if walkers.is_empty():
		return
	var run_w: float = maxf(120.0, street_runway.size.x)
	var run_h: float = maxf(40.0, street_runway.size.y)

	for w in walkers:
		var node: TextureRect = w.get("node", null) as TextureRect
		if node == null or not is_instance_valid(node):
			continue

		var min_x: float = 8.0
		var max_x: float = maxf(min_x + 30.0, run_w - node.size.x - 8.0)
		w["min_x"] = min_x
		w["max_x"] = max_x

		var spd: float = float(w.get("speed", 25.0))
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
		var bob: float = sin(phase) * 1.0
		var base_y: float = minf(maxf(2.0, float(w.get("base_y", 2.0))), run_h - node.size.y - 2.0)
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
	_select_building(index)
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
	if detail_info != null:
		detail_info.text = "%s [%s] 트링켓 획득: %s" % [temoji, source_name, tname]


func _resolve_town_stage_context() -> void:
	town_visit_order_in_act = 1
	town_area_order_in_act = 1
	town_act_order = 1
	if FieldManager == null:
		return

	var act_id: String = str(FieldManager.current_act_id)
	var area_id: String = str(FieldManager.current_area_id)
	town_act_order = maxi(1, _extract_numeric_suffix_int(act_id))
	town_area_order_in_act = maxi(1, _extract_runtime_area_order(area_id))
	town_visit_order_in_act = maxi(1, _count_town_visits_until_area(act_id, area_id))


func _get_town_stage_profile() -> Dictionary:
	var progression_tier: int = ((town_act_order - 1) * 2) + (town_visit_order_in_act - 1)
	var commercial_slots: int = clampi(3 - int(floor(float(progression_tier) * 0.5)), 1, 3)
	var event_slots: int = clampi(2 + int(ceil(float(progression_tier) * 0.5)), 2, 4)
	var extra_slots: int = clampi(1 + int(floor(float(progression_tier) * 0.5)), 1, 4)

	while commercial_slots + event_slots + extra_slots > CELL_COUNT:
		if extra_slots > 1:
			extra_slots -= 1
		elif event_slots > 2:
			event_slots -= 1
		else:
			break

	return {
		"commercial_slots": commercial_slots,
		"event_slots": event_slots,
		"extra_slots": extra_slots,
	}


func _append_random_pool_items(pool: Array[Dictionary], count: int) -> void:
	if pool.is_empty() or count <= 0:
		return
	for i in range(count):
		var pick: Dictionary = (pool[randi() % pool.size()] as Dictionary).duplicate()
		layout_data.append(pick)


func _count_town_visits_until_area(act_id: String, area_id: String) -> int:
	if FieldManager == null:
		return 1
	var act_data: Dictionary = FieldManager.get_runtime_act(act_id)
	if act_data.is_empty():
		return 1
	var areas: Array = act_data.get("areas", []) as Array
	var count: int = 0
	for area_any in areas:
		var area: Dictionary = area_any as Dictionary
		if str(area.get("type", "")) == "town":
			count += 1
		if str(area.get("id", "")) == area_id:
			return maxi(1, count)
	return 1


func _extract_runtime_area_order(area_id: String) -> int:
	if area_id.is_empty():
		return 1
	var marker: String = "_area_"
	var marker_idx: int = area_id.rfind(marker)
	if marker_idx < 0:
		return 1
	var suffix: String = area_id.substr(marker_idx + marker.length())
	if suffix.is_empty():
		return 1
	if suffix.is_valid_int():
		return maxi(1, int(suffix))
	return 1


func _extract_numeric_suffix_int(raw_id: String) -> int:
	if raw_id.is_empty():
		return 1
	var digits: String = ""
	for i in range(raw_id.length() - 1, -1, -1):
		var ch: String = raw_id.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		elif not digits.is_empty():
			break
	if digits.is_empty():
		return 1
	return maxi(1, int(digits))


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
