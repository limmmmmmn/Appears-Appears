@tool
extends Control

const BG_COLOR := Color(0.06, 0.08, 0.12, 1.0)
const PANEL_COLOR := Color(0.12, 0.15, 0.22, 0.96)
const PANEL_BORDER := Color(0.35, 0.46, 0.72, 0.95)
const LOCKED_NODE_COLOR := Color(0.18, 0.18, 0.2, 0.9)

const PANEL_MIN_SIZE := Vector2(920, 0)
const PANEL_CONTENT_MARGIN := Vector4(28, 22, 28, 18)
const NODE_BUTTON_MIN_SIZE := Vector2(120, 76)
const FLOW_SEPARATION := 6

const PARTY_SLOT_OFFSETS: Array[Vector2] = [
	Vector2(-18, 18),
	Vector2(-4, 14),
	Vector2(10, 18),
	Vector2(24, 14),
]

const TOKEN_STAGGER_DELAY := 0.07
const TOKEN_ARC_PEAK := -14.0

const TYPE_COLORS := {
	"field": Color(0.2, 0.33, 0.24, 0.98),
	"town": Color(0.24, 0.22, 0.34, 0.98),
	"event": Color(0.3, 0.24, 0.18, 0.98),
	"dungeon": Color(0.23, 0.18, 0.18, 0.98),
	"boss": Color(0.33, 0.17, 0.17, 0.98),
}

const TYPE_BORDERS := {
	"field": Color(0.5, 0.78, 0.58, 0.95),
	"town": Color(0.55, 0.62, 0.9, 0.95),
	"event": Color(0.82, 0.7, 0.42, 0.95),
	"dungeon": Color(0.78, 0.54, 0.5, 0.95),
	"boss": Color(0.95, 0.45, 0.45, 0.95),
}

@onready var background: ColorRect = $Background
@onready var node_map_panel: PanelContainer = $CenterContainer/NodeMapPanel
@onready var root_vbox: VBoxContainer = $CenterContainer/NodeMapPanel/RootVBox
@onready var title_label: Label = $CenterContainer/NodeMapPanel/RootVBox/TitleLabel
@onready var subtitle_label: Label = $CenterContainer/NodeMapPanel/RootVBox/SubtitleLabel
@onready var node_flow: HBoxContainer = $CenterContainer/NodeMapPanel/RootVBox/NodeFlow
@onready var hint_label: Label = $CenterContainer/NodeMapPanel/RootVBox/HintLabel
@onready var party_overlay: Control = $CenterContainer/NodeMapPanel/PartyOverlay
@onready var node_button_slots: Array[Button] = [
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/NodeButton1,
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/NodeButton2,
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/NodeButton3,
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/NodeButton4,
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/NodeButton5,
]
@onready var node_arrow_slots: Array[Label] = [
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/Arrow1,
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/Arrow2,
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/Arrow3,
	$CenterContainer/NodeMapPanel/RootVBox/NodeFlow/Arrow4,
]

var act_id: String = "act_1"
var start_area_id: String = ""
var act_areas: Array[Dictionary] = []
var node_buttons_by_area: Dictionary = {}
var node_centers_local: Dictionary = {}
var party_tokens: Array[Control] = []
var is_transition_running: bool = false
var is_editor_preview: bool = false

# 시너지/합체공격 표시
var synergy_label: Label = null
var unite_label: Label = null


func _ready() -> void:
	is_editor_preview = Engine.is_editor_hint()
	if is_editor_preview:
		_build_editor_preview_areas()
	else:
		_resolve_act_and_nodes()
	_setup_static_ui()
	_rebuild_node_flow()
	call_deferred("_finalize_node_map_entry")


func _resolve_act_and_nodes() -> void:
	if FieldManager == null:
		return
	FieldManager.ensure_runtime_acts()

	if GameManager != null and GameManager.has_method("has_pending_node_travel") and GameManager.has_pending_node_travel():
		var pending: Dictionary = GameManager.get_pending_node_travel()
		var pending_act_id: String = str(pending.get("act_id", ""))
		if not pending_act_id.is_empty():
			act_id = pending_act_id
	elif GameManager != null and not String(GameManager.current_act_id).is_empty():
		act_id = GameManager.current_act_id

	if not FieldManager.set_current_act(act_id):
		var acts: Array[Dictionary] = FieldManager.get_runtime_acts()
		if not acts.is_empty():
			act_id = str((acts[0] as Dictionary).get("id", "act_1"))
			FieldManager.set_current_act(act_id)

	start_area_id = FieldManager.get_first_area_id(act_id)
	act_areas.clear()

	var act_data: Dictionary = FieldManager.get_runtime_act(act_id)
	var areas_any: Array = act_data.get("areas", []) as Array
	for area_any in areas_any:
		var area: Dictionary = area_any as Dictionary
		if area.is_empty():
			continue
		act_areas.append(area.duplicate(true))


func _setup_static_ui() -> void:
	background.color = BG_COLOR

	var panel_style := _make_style(PANEL_COLOR, PANEL_BORDER, 12, 2)
	panel_style.content_margin_left = PANEL_CONTENT_MARGIN.x
	panel_style.content_margin_top = PANEL_CONTENT_MARGIN.y
	panel_style.content_margin_right = PANEL_CONTENT_MARGIN.z
	panel_style.content_margin_bottom = PANEL_CONTENT_MARGIN.w
	node_map_panel.custom_minimum_size = PANEL_MIN_SIZE
	node_map_panel.add_theme_stylebox_override("panel", panel_style)

	root_vbox.add_theme_constant_override("separation", 16)

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.text = "%s 전체 노드" % _get_act_name()

	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 13)
	subtitle_label.modulate = Color(0.85, 0.9, 1.0, 0.95)
	subtitle_label.text = "파티가 노드를 이동한 뒤 해당 구역으로 진입합니다."

	node_flow.add_theme_constant_override("separation", FLOW_SEPARATION)

	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.modulate = Color(0.9, 0.95, 1.0, 0.95)
	hint_label.text = "이전 노드로는 돌아갈 수 없습니다."

	party_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 시너지/합체공격 정보 표시
	_build_composition_info()


func _rebuild_node_flow() -> void:
	node_buttons_by_area.clear()

	var pending_travel: bool = GameManager != null and GameManager.has_method("has_pending_node_travel") and GameManager.has_pending_node_travel()
	var allow_start: bool = is_editor_preview or (not pending_travel and GameManager != null and String(GameManager.current_area_id).is_empty())
	var area_count: int = mini(act_areas.size(), node_button_slots.size())

	for i in range(node_button_slots.size()):
		var node_btn: Button = node_button_slots[i]
		if node_btn == null:
			continue
		node_btn.custom_minimum_size = NODE_BUTTON_MIN_SIZE
		node_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node_btn.add_theme_font_size_override("font_size", 13)
		node_btn.visible = i < area_count
		node_btn.disabled = true
		node_btn.text = ""
		node_btn.set_meta("area_id", "")

		var cb := Callable(self, "_on_node_slot_pressed").bind(node_btn)
		if node_btn.pressed.is_connected(cb):
			node_btn.pressed.disconnect(cb)

		if i >= area_count:
			continue

		var area: Dictionary = act_areas[i] as Dictionary
		var area_id: String = str(area.get("id", ""))
		var area_type: String = str(area.get("type", "field"))
		var area_name: String = str(area.get("name", area_id))
		var is_start: bool = area_id == start_area_id

		node_btn.text = "%d. %s\n%s" % [i + 1, _get_area_type_label(area_type), area_name]
		node_btn.add_theme_stylebox_override("normal", _make_style(_get_type_color(area_type), _get_type_border(area_type), 10, 2))
		node_btn.add_theme_stylebox_override("disabled", _make_style(LOCKED_NODE_COLOR, Color(0.4, 0.4, 0.44, 0.9), 10, 1))
		node_btn.set_meta("area_id", area_id)
		node_buttons_by_area[area_id] = node_btn

		if allow_start and is_start:
			node_btn.disabled = false
			node_btn.pressed.connect(cb)

	for i in range(node_arrow_slots.size()):
		var arrow: Label = node_arrow_slots[i]
		if arrow == null:
			continue
		arrow.visible = i < area_count - 1
		arrow.text = "→"
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		arrow.add_theme_font_size_override("font_size", 18)
		arrow.modulate = Color(0.72, 0.8, 0.98, 0.96)


func _finalize_node_map_entry() -> void:
	if is_transition_running:
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_cache_node_centers()
	_spawn_party_tokens()

	var initial_area_id: String = _resolve_display_area_id()
	if not initial_area_id.is_empty():
		_set_party_tokens_at_area(initial_area_id)

	if is_editor_preview:
		_set_editor_preview_party_position()
		return

	if GameManager != null and GameManager.has_method("has_pending_node_travel") and GameManager.has_pending_node_travel():
		await _play_pending_travel()


func _cache_node_centers() -> void:
	node_centers_local.clear()
	for key in node_buttons_by_area.keys():
		var area_id: String = str(key)
		var node_btn: Button = node_buttons_by_area[area_id] as Button
		if node_btn == null:
			continue
		var global_rect: Rect2 = node_btn.get_global_rect()
		var global_center: Vector2 = global_rect.position + global_rect.size * 0.5
		var local_center: Vector2 = party_overlay.get_global_transform().affine_inverse() * global_center
		node_centers_local[area_id] = local_center


func _spawn_party_tokens() -> void:
	for old in party_tokens:
		if old != null and is_instance_valid(old):
			old.queue_free()
	party_tokens.clear()

	var hero_ids: Array[String] = []
	if PartyManager != null:
		for hero_any in PartyManager.get_party():
			var hero: Hero = hero_any as Hero
			if hero != null and not hero.id.is_empty():
				hero_ids.append(hero.id)
	if hero_ids.is_empty():
		hero_ids.append("roland")

	var max_tokens: int = mini(4, hero_ids.size())
	for i in range(max_tokens):
		var hero_id: String = hero_ids[i]
		var tex: Texture2D = _get_hero_field_texture(hero_id)
		var token: Control
		if tex != null:
			var sprite := TextureRect.new()
			sprite.texture = tex
			sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite.stretch_mode = TextureRect.STRETCH_KEEP
			var size: Vector2 = tex.get_size() * 1.5
			sprite.custom_minimum_size = size
			sprite.size = size
			sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
			token = sprite
		else:
			var fallback := ColorRect.new()
			fallback.color = Color(0.95, 0.85, 0.4, 0.95)
			fallback.custom_minimum_size = Vector2(14, 14)
			fallback.size = Vector2(14, 14)
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			token = fallback
		party_overlay.add_child(token)
		party_tokens.append(token)


func _play_pending_travel() -> void:
	if GameManager == null:
		return
	if not GameManager.has_method("get_pending_node_travel"):
		return
	if is_transition_running:
		return
	is_transition_running = true
	_set_all_node_buttons_disabled(true)

	var pending: Dictionary = GameManager.get_pending_node_travel()
	var target_area_id: String = str(pending.get("to_area_id", ""))
	var from_area_id: String = str(pending.get("from_area_id", ""))

	if target_area_id.is_empty():
		GameManager.clear_pending_node_travel()
		is_transition_running = false
		return

	if from_area_id.is_empty() or not node_centers_local.has(from_area_id):
		from_area_id = _resolve_display_area_id()
	if from_area_id.is_empty():
		from_area_id = start_area_id

	if not from_area_id.is_empty():
		_set_party_tokens_at_area(from_area_id)

	if node_centers_local.has(target_area_id):
		await _animate_party_tokens_to_area(target_area_id, 0.55)
	else:
		await get_tree().create_timer(0.2).timeout

	GameManager.clear_pending_node_travel()
	is_transition_running = false
	GameManager.go_to_area(act_id, target_area_id)


func _set_party_tokens_at_area(area_id: String, extra_offset: Vector2 = Vector2.ZERO) -> void:
	if not node_centers_local.has(area_id):
		return
	var center: Vector2 = Vector2(node_centers_local[area_id])
	for i in range(party_tokens.size()):
		var token: Control = party_tokens[i] as Control
		if token == null:
			continue
		token.position = center + _get_party_slot_offset(i) + extra_offset


func _animate_party_tokens_to_area(area_id: String, duration: float) -> void:
	if not node_centers_local.has(area_id):
		return
	var center: Vector2 = Vector2(node_centers_local[area_id])
	var last_tween: Tween = null

	for i in range(party_tokens.size()):
		var token: Control = party_tokens[i] as Control
		if token == null:
			continue
		var target_pos: Vector2 = center + _get_party_slot_offset(i)
		var start_pos: Vector2 = token.position
		var delay: float = float(i) * TOKEN_STAGGER_DELAY
		var arc_peak: float = TOKEN_ARC_PEAK

		var tween := create_tween()
		if delay > 0.0:
			tween.tween_interval(delay)

		tween.tween_method(
			func(t: float) -> void:
				var x_val: float = lerpf(start_pos.x, target_pos.x, t)
				var y_base: float = lerpf(start_pos.y, target_pos.y, t)
				var y_arc: float = arc_peak * sin(t * PI)
				token.position = Vector2(x_val, y_base + y_arc),
			0.0, 1.0, duration
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

		last_tween = tween

	if last_tween != null:
		await last_tween.finished


func _get_party_slot_offset(index: int) -> Vector2:
	if index >= 0 and index < PARTY_SLOT_OFFSETS.size():
		return PARTY_SLOT_OFFSETS[index]
	return Vector2(26 + float(index - PARTY_SLOT_OFFSETS.size()) * 14.0, 24.0)


func _set_all_node_buttons_disabled(disabled: bool) -> void:
	for key in node_buttons_by_area.keys():
		var area_id: String = str(key)
		var node_btn: Button = node_buttons_by_area[area_id] as Button
		if node_btn == null:
			continue
		node_btn.disabled = disabled


func _resolve_display_area_id() -> String:
	if GameManager != null and GameManager.has_method("has_pending_node_travel") and GameManager.has_pending_node_travel():
		var pending: Dictionary = GameManager.get_pending_node_travel()
		var pending_from: String = str(pending.get("from_area_id", ""))
		if not pending_from.is_empty() and node_centers_local.has(pending_from):
			return pending_from
	if GameManager != null and not String(GameManager.current_area_id).is_empty() and node_centers_local.has(GameManager.current_area_id):
		return String(GameManager.current_area_id)
	if not start_area_id.is_empty() and node_centers_local.has(start_area_id):
		return start_area_id
	return ""


func _on_start_area_pressed(area_id: String) -> void:
	if area_id.is_empty():
		return
	if is_editor_preview:
		_set_party_tokens_at_area(area_id)
		return
	if is_transition_running:
		return
	is_transition_running = true
	_set_all_node_buttons_disabled(true)

	_set_party_tokens_at_area(area_id, Vector2(-60, 0))
	await _animate_party_tokens_to_area(area_id, 0.4)
	GameManager.go_to_area(act_id, area_id)


func _on_node_slot_pressed(node_btn: Button) -> void:
	if node_btn == null:
		return
	var area_id: String = str(node_btn.get_meta("area_id", ""))
	if area_id.is_empty():
		return
	_on_start_area_pressed(area_id)


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


func _get_act_name() -> String:
	if FieldManager == null or not FieldManager.has_method("get_current_act_name"):
		return "Act 1"
	var name: String = String(FieldManager.get_current_act_name())
	if name.is_empty():
		return "Act 1"
	return name


func _get_area_type_label(area_type: String) -> String:
	match area_type:
		"field":
			return "필드"
		"town":
			return "마을"
		"event":
			return "이벤트"
		"dungeon":
			return "던전"
		"boss":
			return "보스"
		_:
			return "노드"


func _get_type_color(area_type: String) -> Color:
	return TYPE_COLORS.get(area_type, TYPE_COLORS["field"]) as Color


func _get_type_border(area_type: String) -> Color:
	return TYPE_BORDERS.get(area_type, TYPE_BORDERS["field"]) as Color


func _make_style(bg: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _build_composition_info() -> void:
	## 시너지/합체공격 표시 영역 생성
	if is_editor_preview:
		return
	if PartyManager == null:
		return

	PartyManager.refresh_synergies_and_unite()

	# 시너지 라벨
	synergy_label = Label.new()
	synergy_label.add_theme_font_size_override("font_size", 11)
	synergy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	synergy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(synergy_label)

	# 합체공격 라벨
	unite_label = Label.new()
	unite_label.add_theme_font_size_override("font_size", 12)
	unite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(unite_label)

	_refresh_composition_info()


func _refresh_composition_info() -> void:
	if synergy_label == null or unite_label == null:
		return
	if PartyManager == null:
		return

	# 시너지 텍스트
	var synergy_lines: Array[String] = []
	for synergy_id in PartyManager.active_synergies:
		var data: Dictionary = DataManager.get_synergy(synergy_id)
		var name: String = str(data.get("name", ""))
		var desc: String = str(data.get("description", ""))
		# 히든 태그로만 발동하면 발견 전까지 "???" 표시
		if PartyManager.is_synergy_uses_hidden_tag(synergy_id) and not PartyManager.discovered_synergies.has(synergy_id):
			synergy_lines.append("??? — ???")
		else:
			synergy_lines.append("%s — %s" % [name, desc])

	if synergy_lines.is_empty():
		synergy_label.text = ""
		synergy_label.visible = false
	else:
		synergy_label.text = "[ 시너지 ] " + " / ".join(synergy_lines)
		synergy_label.modulate = Color(0.5, 1.0, 0.5, 0.95)
		synergy_label.visible = true

	# 합체공격 텍스트
	var unite_data: Dictionary = PartyManager.get_current_unite_attack_data()
	var unite_id: String = str(unite_data.get("id", "default_unite"))
	var unite_name: String = str(unite_data.get("name", "총공격"))

	if unite_id != "default_unite" and PartyManager.is_unite_uses_hidden_tag(unite_id) and not PartyManager.discovered_unite_attacks.has(unite_id):
		unite_name = "???"

	unite_label.text = "합체공격: %s" % unite_name
	if unite_id == "default_unite":
		unite_label.modulate = Color(0.7, 0.7, 0.75, 0.9)
	else:
		unite_label.modulate = Color(1.0, 0.85, 0.3, 0.95)


func _build_editor_preview_areas() -> void:
	act_id = "act_1"
	start_area_id = "preview_1"
	act_areas = [
		{"id":"preview_1","type":"field","name":"Field1_1"},
		{"id":"preview_2","type":"town","name":"Town"},
		{"id":"preview_3","type":"field","name":"Field1_2"},
		{"id":"preview_4","type":"town","name":"Town"},
		{"id":"preview_5","type":"field","name":"Field1_3"},
	]


func _set_editor_preview_party_position() -> void:
	if node_centers_local.has(start_area_id):
		_set_party_tokens_at_area(start_area_id)
