extends "res://scripts/ui/window/WindowShell.gd"
class_name RewardWindow
## 보물상자 3지선다 UI (가로 카드 + 장착 영웅 선택)

signal item_selected(item_id: String)

const PANEL_SIZE := Vector2(360, 240)
const CARD_SIZE := Vector2(108, 124)

const TYPE_ICONS: Dictionary = {
	"sword": "⚔",
	"dagger": "🗡",
	"staff": "🪄",
	"bow": "🏹",
	"axe": "🪓",
	"mace": "🔨",
	"spear": "🗡",
	"shield": "🛡",
	"armor": "👕",
	"robe": "🧥",
	"light_armor": "👔",
	"helmet": "⛑",
	"hat": "🎩",
	"gloves": "🧤",
	"boots": "🥾",
	"ring": "💍",
	"amulet": "💎",
}

const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔",
	"off_hand": "🛡",
	"head": "⛑",
	"body": "👕",
	"acc1": "💍",
	"acc2": "💎",
	"acc": "💎",
}

const RARITY_COLORS: Dictionary = {
	"magic": Color(0.45, 0.75, 1.0, 1.0),
	"rare": Color(0.73, 0.56, 1.0, 1.0),
	"epic": Color(1.0, 0.66, 0.35, 1.0),
	"legendary": Color(1.0, 0.86, 0.4, 1.0),
	"common": Color(0.75, 0.75, 0.75, 1.0),
	"uncommon": Color(0.58, 0.9, 0.58, 1.0),
}

var header_label: Label
var subtitle_label: Label
var cards_separator: HSeparator
var cards_row: HBoxContainer
var hero_pick_panel: PanelContainer
var hero_pick_label: Label
var hero_pick_row: HBoxContainer

var item_ids: Array[String] = []
var selected_item_id: String = ""
var selected_hero_id: String = ""
var card_buttons: Array[Button] = []
var _forced_pause_applied: bool = false
var _prev_tree_paused: bool = false
var _prev_battle_paused: bool = false
var _is_shell_hovered: bool = false
var _pause_anim_t: float = 0.0
var _card_drag_tracking: bool = false
var _card_drag_started: bool = false
var _card_drag_start_pos: Vector2 = Vector2.ZERO
const CARD_DRAG_THRESHOLD: float = 6.0


func _ready() -> void:
	super._ready()
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("reward_windows")
	set_process(true)
	title_text = "보상윈도우"
	set_title(title_text)
	set_window_size(PANEL_SIZE)
	random_spawn = true
	draggable = true
	pause_policy = PausePolicy.NONE
	if close_button:
		close_button.visible = false
	if shell_panel:
		if not shell_panel.mouse_entered.is_connected(_on_shell_mouse_entered):
			shell_panel.mouse_entered.connect(_on_shell_mouse_entered)
		if not shell_panel.mouse_exited.is_connected(_on_shell_mouse_exited):
			shell_panel.mouse_exited.connect(_on_shell_mouse_exited)
	if not shell_closed.is_connected(_on_shell_closed):
		shell_closed.connect(_on_shell_closed)
	_build_ui()
	visible = false


func get_selected_hero_id() -> String:
	return selected_hero_id


func show_loot_selection(items: Array[String]) -> void:
	item_ids = items
	selected_item_id = ""
	selected_hero_id = ""
	cards_row.visible = true
	cards_separator.visible = true
	hero_pick_panel.visible = false
	subtitle_label.text = "원하는 아이템 카드를 선택하세요."
	_build_item_cards()
	_apply_reward_auto_pause(false)
	open_shell()


func _process(delta: float) -> void:
	var paused_now: bool = false
	if get_tree():
		paused_now = get_tree().paused
	if shell_panel and is_instance_valid(shell_panel):
		_is_shell_hovered = shell_panel.get_global_rect().has_point(get_viewport().get_mouse_position())
	if paused_now:
		var dim := 1.0 if _is_shell_hovered else 0.62
		modulate = Color(dim, dim, dim, 1.0)
	else:
		modulate = Color.WHITE

	_pause_anim_t += delta
	for i in range(card_buttons.size()):
		var btn: Button = card_buttons[i]
		if btn == null or not is_instance_valid(btn):
			continue
		if paused_now:
			var pulse: float = 1.0 + 0.02 * sin(_pause_anim_t * 4.0 + float(i) * 0.7)
			btn.scale = Vector2.ONE * pulse
			var glow: float = 0.9 + 0.1 * (0.5 + 0.5 * sin(_pause_anim_t * 3.4 + float(i) * 1.1))
			btn.modulate = Color(glow, glow, glow, 1.0)
		else:
			btn.scale = Vector2.ONE
			btn.modulate = Color.WHITE


func _build_ui() -> void:
	if content_root == null:
		return

	for child in content_root.get_children():
		child.queue_free()

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.14, 0.98)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.76, 0.67, 0.35, 0.95)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	if shell_panel:
		shell_panel.add_theme_stylebox_override("panel", panel_style)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	content_root.add_child(main_vbox)

	subtitle_label = Label.new()
	subtitle_label.text = "원하는 아이템 카드를 선택하세요."
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 10)
	subtitle_label.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 0.95))
	main_vbox.add_child(subtitle_label)

	cards_separator = HSeparator.new()
	main_vbox.add_child(cards_separator)

	cards_row = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 6)
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(cards_row)

	hero_pick_panel = PanelContainer.new()
	hero_pick_panel.visible = false
	var hero_style := StyleBoxFlat.new()
	hero_style.bg_color = Color(0.11, 0.12, 0.18, 0.97)
	hero_style.border_width_left = 1
	hero_style.border_width_top = 1
	hero_style.border_width_right = 1
	hero_style.border_width_bottom = 1
	hero_style.border_color = Color(0.7, 0.7, 0.86, 0.45)
	hero_style.corner_radius_top_left = 7
	hero_style.corner_radius_top_right = 7
	hero_style.corner_radius_bottom_left = 7
	hero_style.corner_radius_bottom_right = 7
	hero_style.content_margin_left = 10
	hero_style.content_margin_right = 10
	hero_style.content_margin_top = 8
	hero_style.content_margin_bottom = 8
	hero_pick_panel.add_theme_stylebox_override("panel", hero_style)
	main_vbox.add_child(hero_pick_panel)

	var hero_vbox := VBoxContainer.new()
	hero_vbox.add_theme_constant_override("separation", 6)
	hero_pick_panel.add_child(hero_vbox)

	hero_pick_label = Label.new()
	hero_pick_label.text = "장착할 영웅을 선택해주세요."
	hero_pick_label.add_theme_font_size_override("font_size", 11)
	hero_pick_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 1.0))
	hero_pick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hero_vbox.add_child(hero_pick_label)

	hero_pick_row = HBoxContainer.new()
	hero_pick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_pick_row.add_theme_constant_override("separation", 3)
	hero_vbox.add_child(hero_pick_row)


func _build_item_cards() -> void:
	card_buttons.clear()
	for child in cards_row.get_children():
		child.queue_free()

	for i in range(3):
		var card_btn := Button.new()
		card_btn.text = ""
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card_btn.custom_minimum_size = CARD_SIZE # 카드 비율(세로형)
		card_btn.focus_mode = Control.FOCUS_NONE
		card_btn.clip_contents = false
		card_btn.pressed.connect(_on_item_card_pressed.bind(i))
		card_btn.gui_input.connect(_on_item_card_gui_input.bind(card_btn))
		_apply_card_style(card_btn, i == 0 and i < item_ids.size(), i)
		cards_row.add_child(card_btn)
		card_buttons.append(card_btn)

		if i < item_ids.size():
			_populate_item_card(card_btn, item_ids[i])
		else:
			_populate_empty_card(card_btn)
		_make_children_click_through(card_btn)


func _on_item_card_gui_input(event: InputEvent, card_btn: Button) -> void:
	if card_btn == null or not is_instance_valid(card_btn):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_card_drag_tracking = true
				_card_drag_started = false
				_card_drag_start_pos = mb.global_position
				begin_shell_drag(mb.global_position)
				_is_shell_hovered = true
			else:
				if _card_drag_started:
					end_shell_drag()
					_card_drag_tracking = false
					_card_drag_started = false
					card_btn.accept_event()
				else:
					end_shell_drag()
					_card_drag_tracking = false
					_card_drag_started = false
	elif event is InputEventMouseMotion and _card_drag_tracking:
		var mm := event as InputEventMouseMotion
		if not _card_drag_started and mm.global_position.distance_to(_card_drag_start_pos) >= CARD_DRAG_THRESHOLD:
			_card_drag_started = true
		if _card_drag_started:
			drag_shell_to(mm.global_position)
			_is_shell_hovered = true
			card_btn.accept_event()


func _populate_empty_card(card_btn: Button) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_btn.add_child(center)

	var label := Label.new()
	label.text = "빈 보상"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.58, 0.58, 0.68))
	center.add_child(label)


func _populate_item_card(card_btn: Button, item_id: String) -> void:
	var data: Dictionary = _get_item_data(item_id)
	var rarity: String = str(data.get("rarity", "common"))
	var rarity_color: Color = _get_rarity_color(rarity)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	card_btn.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	var rarity_label := Label.new()
	rarity_label.text = "[%s]" % _get_rarity_text(rarity)
	rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_label.add_theme_font_size_override("font_size", 10)
	rarity_label.add_theme_color_override("font_color", rarity_color)
	vbox.add_child(rarity_label)

	var icon_name_row := HBoxContainer.new()
	icon_name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_name_row.add_theme_constant_override("separation", 4)
	vbox.add_child(icon_name_row)

	var icon_label := Label.new()
	icon_label.text = _get_item_icon(data)
	icon_label.add_theme_font_size_override("font_size", 16)
	icon_label.add_theme_color_override("font_color", rarity_color)
	icon_name_row.add_child(icon_label)

	var name_label := Label.new()
	name_label.text = str(data.get("name", item_id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	icon_name_row.add_child(name_label)

	var stats_label := Label.new()
	stats_label.text = _get_stats_text(data)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_label.add_theme_font_size_override("font_size", 8)
	stats_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 0.95))
	stats_label.custom_minimum_size = Vector2(0, 18)
	vbox.add_child(stats_label)

	var hero_row := HBoxContainer.new()
	hero_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_row.add_theme_constant_override("separation", 4)
	vbox.add_child(hero_row)

	var equipable: Array[Hero] = _get_equipable_heroes(item_id)
	if equipable.is_empty():
		var none_label := Label.new()
		none_label.text = "없음"
		none_label.add_theme_font_size_override("font_size", 8)
		none_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78, 1.0))
		hero_row.add_child(none_label)
		return

	for hero in equipable:
		hero_row.add_child(_create_hero_badge(hero))


func _create_hero_badge(hero: Hero) -> Control:
	var icon_holder := PanelContainer.new()
	icon_holder.custom_minimum_size = Vector2(26, 26)
	var holder_style := StyleBoxFlat.new()
	holder_style.bg_color = Color(0.09, 0.1, 0.14, 1.0)
	holder_style.border_width_left = 1
	holder_style.border_width_top = 1
	holder_style.border_width_right = 1
	holder_style.border_width_bottom = 1
	holder_style.border_color = Color(0.52, 0.56, 0.7, 0.75)
	holder_style.corner_radius_top_left = 5
	holder_style.corner_radius_top_right = 5
	holder_style.corner_radius_bottom_left = 5
	holder_style.corner_radius_bottom_right = 5
	icon_holder.add_theme_stylebox_override("panel", holder_style)

	var icon_center := CenterContainer.new()
	icon_holder.add_child(icon_center)

	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(20, 20)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.texture = _get_hero_field_texture(hero)
	icon_center.add_child(tex)
	return icon_holder


func _create_hero_preview(hero: Hero) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.custom_minimum_size = Vector2(34, 44)
	wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	wrapper.add_theme_constant_override("separation", 1)

	var icon_holder := PanelContainer.new()
	icon_holder.custom_minimum_size = Vector2(28, 28)
	var holder_style := StyleBoxFlat.new()
	holder_style.bg_color = Color(0.09, 0.1, 0.14, 1.0)
	holder_style.border_width_left = 1
	holder_style.border_width_top = 1
	holder_style.border_width_right = 1
	holder_style.border_width_bottom = 1
	holder_style.border_color = Color(0.52, 0.56, 0.7, 0.75)
	holder_style.corner_radius_top_left = 5
	holder_style.corner_radius_top_right = 5
	holder_style.corner_radius_bottom_left = 5
	holder_style.corner_radius_bottom_right = 5
	icon_holder.add_theme_stylebox_override("panel", holder_style)
	wrapper.add_child(icon_holder)

	var icon_center := CenterContainer.new()
	icon_holder.add_child(icon_center)

	var tex := TextureRect.new()
	tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(22, 22)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.texture = _get_hero_field_texture(hero)
	icon_center.add_child(tex)

	var name_label := Label.new()
	name_label.text = hero.hero_name
	name_label.add_theme_font_size_override("font_size", 7)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wrapper.add_child(name_label)

	return wrapper


func _get_hero_field_texture(hero: Hero) -> Texture2D:
	if hero == null:
		return null
	if SpriteManager:
		var frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero.id)
		if frames and frames.has_animation("walk_down"):
			var frame_count := frames.get_frame_count("walk_down")
			if frame_count > 1:
				return frames.get_frame_texture("walk_down", 1)
			elif frame_count > 0:
				return frames.get_frame_texture("walk_down", 0)
		return SpriteManager.get_hero_face_sprite(hero.id)
	return null


func _on_item_card_pressed(index: int) -> void:
	if index < 0 or index >= item_ids.size():
		return

	selected_item_id = item_ids[index]
	selected_hero_id = ""
	subtitle_label.text = "아이템 선택 완료. 아래에서 장착할 영웅을 선택하세요."

	for i in range(card_buttons.size()):
		_apply_card_style(card_buttons[i], i == index, i)

	_show_hero_pick_for_item(selected_item_id)


func _show_hero_pick_for_item(item_id: String) -> void:
	for child in hero_pick_row.get_children():
		child.queue_free()

	var equipable: Array[Hero] = _get_equipable_heroes(item_id)
	cards_row.visible = false
	if cards_separator:
		cards_separator.visible = false
	hero_pick_panel.visible = true

	if equipable.is_empty():
		hero_pick_label.text = "장착 가능한 영웅이 없어 인벤토리로 획득합니다."
		var only_btn := Button.new()
		only_btn.text = "인벤토리로 받기"
		only_btn.custom_minimum_size = Vector2(140, 28)
		only_btn.add_theme_font_size_override("font_size", 10)
		only_btn.focus_mode = Control.FOCUS_NONE
		only_btn.pressed.connect(_on_confirm_inventory_only)
		hero_pick_row.add_child(only_btn)
		return

	hero_pick_label.text = "장착할 영웅을 선택해주세요."
	for hero in equipable:
		var hero_btn := Button.new()
		hero_btn.text = ""
		hero_btn.custom_minimum_size = Vector2(38, 54)
		hero_btn.focus_mode = Control.FOCUS_NONE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.12, 0.16, 1.0)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.83, 0.75, 0.42, 0.85)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		hero_btn.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.border_color = Color(1.0, 0.88, 0.45, 1.0)
		hover.bg_color = Color(0.15, 0.16, 0.22, 1.0)
		hero_btn.add_theme_stylebox_override("hover", hover)
		hero_btn.add_child(_create_hero_preview(hero))
		hero_btn.pressed.connect(_on_hero_pick_pressed.bind(hero.id))
		hero_pick_row.add_child(hero_btn)
		_make_children_click_through(hero_btn)


func _on_confirm_inventory_only() -> void:
	selected_hero_id = ""
	_finalize_selection()


func _on_hero_pick_pressed(hero_id: String) -> void:
	selected_hero_id = hero_id
	_finalize_selection()


func _finalize_selection() -> void:
	if selected_item_id.is_empty():
		return
	_apply_reward_auto_pause(false)
	item_selected.emit(selected_item_id)
	close_shell("reward_selected")


func _on_shell_closed(_reason: String) -> void:
	_apply_reward_auto_pause(false)


func _on_shell_mouse_entered() -> void:
	_is_shell_hovered = true


func _on_shell_mouse_exited() -> void:
	_is_shell_hovered = false


func _apply_reward_auto_pause(enable: bool) -> void:
	# 보상윈도우는 더 이상 자동으로 게임을 멈추지 않는다.
	# 일시정지는 스페이스/전역 정지 토글에서만 제어한다.
	_forced_pause_applied = false


func _exit_tree() -> void:
	_apply_reward_auto_pause(false)


func release_pause_lock() -> void:
	## 외부(전투창 클릭 재개)에서 호출: 창은 유지하고 전역 pause 강제만 해제
	if _forced_pause_applied:
		_forced_pause_applied = false


func _apply_card_style(card_btn: Button, selected: bool, index: int) -> void:
	var rarity := "common"
	if index >= 0 and index < item_ids.size():
		var data: Dictionary = _get_item_data(item_ids[index])
		rarity = str(data.get("rarity", "common"))
	var border_color: Color = _get_rarity_color(rarity)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.2, 0.95)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = border_color.darkened(0.3) if not selected else border_color
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	card_btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.17, 0.25, 0.98)
	hover.border_color = border_color
	card_btn.add_theme_stylebox_override("hover", hover)

	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.2, 0.2, 0.28, 1.0)
	card_btn.add_theme_stylebox_override("pressed", pressed)


func _get_item_data(item_id: String) -> Dictionary:
	var equip_data: Dictionary = DataManager.get_equipment(item_id)
	if not equip_data.is_empty():
		return equip_data
	return DataManager.get_item(item_id)


func _get_item_icon(data: Dictionary) -> String:
	var item_type: String = str(data.get("type", ""))
	var slot: String = Hero.normalize_equipment_slot(str(data.get("slot", "")))
	var icon: String = str(TYPE_ICONS.get(item_type, ""))
	if icon.is_empty():
		icon = str(SLOT_ICONS.get(slot, "📦"))
	return icon


func _get_equipable_heroes(item_id: String) -> Array[Hero]:
	var result: Array[Hero] = []
	if not PartyManager:
		return result
	for hero in PartyManager.get_party():
		if hero == null:
			continue
		if hero.can_equip(item_id):
			result.append(hero)
	return result


func _get_stats_text(data: Dictionary) -> String:
	var parts: Array[String] = []
	var stats: Dictionary = data.get("stats", {})

	if int(stats.get("atk", 0)) != 0:
		parts.append("ATK %+d" % int(stats.get("atk", 0)))
	if int(stats.get("def", 0)) != 0:
		parts.append("DEF %+d" % int(stats.get("def", 0)))
	if int(stats.get("matk", 0)) != 0:
		parts.append("MATK %+d" % int(stats.get("matk", 0)))
	if int(stats.get("mdef", 0)) != 0:
		parts.append("MDEF %+d" % int(stats.get("mdef", 0)))
	if int(stats.get("hp", 0)) != 0:
		parts.append("HP %+d" % int(stats.get("hp", 0)))
	if int(stats.get("mp", 0)) != 0:
		parts.append("MP %+d" % int(stats.get("mp", 0)))
	if int(stats.get("str", 0)) != 0:
		parts.append("STR %+d" % int(stats.get("str", 0)))
	if int(stats.get("int", 0)) != 0:
		parts.append("INT %+d" % int(stats.get("int", 0)))
	if int(stats.get("dex", 0)) != 0:
		parts.append("DEX %+d" % int(stats.get("dex", 0)))
	if int(stats.get("spd", 0)) != 0:
		parts.append("SPD %+d" % int(stats.get("spd", 0)))
	if int(stats.get("luk", 0)) != 0:
		parts.append("LUK %+d" % int(stats.get("luk", 0)))

	if parts.is_empty():
		var desc: String = str(data.get("description", ""))
		if not desc.is_empty():
			return desc
		return "스탯 변화 없음"
	return ", ".join(parts)


func _get_rarity_color(rarity: String) -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)


func _get_rarity_text(rarity: String) -> String:
	match rarity:
		"legendary":
			return "전설"
		"epic":
			return "에픽"
		"rare":
			return "레어"
		"magic":
			return "마법"
		"uncommon":
			return "고급"
		_:
			return "일반"


func _make_children_click_through(root_control: Control) -> void:
	if root_control == null:
		return
	for child in root_control.get_children():
		if child is Control:
			var c: Control = child
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_make_children_click_through(c)
