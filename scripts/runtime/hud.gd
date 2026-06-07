class_name HUD
extends CanvasLayer

## Field HUD (slimmed). The always-on overlays that survived the OS-desktop
## redesign:
##   • bottom party-member boxes (HP / EXP / equipment)
##   • top-left gold chip
##   • tier-unlock popup ("○○ 해금!")
##   • opening name prompt ("이름을 입력하세요")
## The old top status bar (Field / timer / Gold label) and the +1000 / END debug
## buttons moved to the MENU BAR; inventory now lives in the right panel's 장비 tab.
## Pure presentation: state from GameState, change notifications via EventBus.

const MEMBER_BOX_SCENE: PackedScene = preload("res://scenes/ui/party_member_box.tscn")
const HUD_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
## Design viewport width (canvas_items stretch) — center the popup on the TRUE
## viewport center, ignoring the side panels.
const VIEWPORT_DESIGN_WIDTH: float = 640.0

@onready var _member_row: HBoxContainer = %MemberRow

## Live member box references, parallel to GameState.party. Rebuilt from scratch
## on party_changed so indices never go stale after a recruit or wipe.
var _member_boxes: Array[PartyMemberBox] = []
## Measured gold income per second (sampled each 1s), shown next to the total.
var _income_timer: float = 0.0
var _income_marker: int = 0
var _income_per_sec: int = 0
## Always-on big gold readout, pinned top-left (gold is the #1 info).
var _gold_center: PanelContainer
var _gold_center_label: Label
var _dq_status: PanelContainer   ## DQ top status window (manual combat)
var _dq_grid: GridContainer
## Big centered "○○ 해금!" popup with the enemy sprite (tier unlock moment).
var _unlock_popup: PanelContainer
var _unlock_sprite: TextureRect
var _unlock_label: Label
var _unlock_tween: Tween
## Opening name prompt — shown before anything else.
var _name_overlay: Control
var _name_line_edit: LineEdit


func _ready() -> void:
	EventBus.party_changed.connect(_rebuild_member_boxes)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.party_member_xp_changed.connect(_on_party_member_xp_changed)
	EventBus.party_member_downed.connect(_on_party_member_downed)
	EventBus.party_member_revived.connect(_on_party_member_revived)
	EventBus.party_equipment_changed.connect(_on_party_equipment_changed)
	EventBus.armor_equipped.connect(_on_armor_equipped.unbind(1))
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.tier_available.connect(_on_tier_unlocked)  # popup when the tile APPEARS
	# Dragon-Quest top status window (manual combat only): NAME / LV / HP / MP.
	EventBus.battle_window_opened.connect(_on_battle_opened_dq.unbind(1))
	EventBus.all_battles_resolved.connect(_hide_dq_status)
	EventBus.party_member_hp_changed.connect(_refresh_dq_status.unbind(3))
	EventBus.party_member_xp_changed.connect(_refresh_dq_status.unbind(4))
	EventBus.party_changed.connect(_refresh_dq_status)
	_build_dq_status()
	_income_marker = GameState.total_gold_earned
	_build_gold_center()  # prominent gold chip, top-left next to the placement dock
	_build_unlock_popup()
	if not GameState.name_entered:
		_build_name_overlay()
	_refresh_gold()
	_rebuild_member_boxes()


# ─── Dragon-Quest top status window (NAME / LV / HP / MP) ──────────────
func _build_dq_status() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_dq_status = PanelContainer.new()
	_dq_status.add_theme_stylebox_override("panel", style)
	_dq_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dq_status.visible = false
	_dq_status.anchor_left = 0.5
	_dq_status.anchor_right = 0.5
	_dq_status.anchor_top = 0.0
	_dq_status.anchor_bottom = 0.0
	_dq_status.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dq_status.grow_vertical = Control.GROW_DIRECTION_END
	_dq_status.offset_top = 4.0
	_dq_grid = GridContainer.new()
	_dq_grid.columns = 4
	_dq_grid.add_theme_constant_override("h_separation", 10)
	_dq_grid.add_theme_constant_override("v_separation", 0)
	_dq_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dq_status.add_child(_dq_grid)
	add_child(_dq_status)


func _on_battle_opened_dq() -> void:
	if GameState.auto_battle_unlocked:
		return  # auto combat = card game, no DQ status window
	_dq_status.visible = true
	_refresh_dq_status()


func _hide_dq_status() -> void:
	if _dq_status != null:
		_dq_status.visible = false


func _refresh_dq_status() -> void:
	if _dq_status == null or not _dq_status.visible:
		return
	for c in _dq_grid.get_children():
		c.queue_free()
	_dq_cell("NAME", HORIZONTAL_ALIGNMENT_LEFT, 50.0)
	_dq_cell("LV", HORIZONTAL_ALIGNMENT_RIGHT, 22.0)
	_dq_cell("HP", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
	_dq_cell("MP", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
	for i in GameState.party_size():
		_dq_cell(GameState.party[i].display_name, HORIZONTAL_ALIGNMENT_LEFT, 50.0)
		_dq_cell(str(GameState.party_level(i)), HORIZONTAL_ALIGNMENT_RIGHT, 22.0)
		_dq_cell(str(GameState.party_hp[i]) if i < GameState.party_hp.size() else "-", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)
		_dq_cell(str(GameState.party_mp[i]) if i < GameState.party_mp.size() else "-", HORIZONTAL_ALIGNMENT_RIGHT, 30.0)


func _dq_cell(text: String, align: int, min_w: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HUD_FONT)
	l.add_theme_font_size_override("font_size", 9)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	l.horizontal_alignment = align
	l.custom_minimum_size = Vector2(min_w, 0.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dq_grid.add_child(l)


func _process(delta: float) -> void:
	_income_timer += delta
	if _income_timer >= 1.0:
		_income_per_sec = maxi(0, GameState.total_gold_earned - _income_marker)
		_income_marker = GameState.total_gold_earned
		_income_timer = 0.0
		_refresh_gold()


# ─── Bottom row (party member boxes) ───────────────────────────────────
func _rebuild_member_boxes() -> void:
	for box in _member_boxes:
		if is_instance_valid(box):
			box.queue_free()
	_member_boxes.clear()
	for i in GameState.party_size():
		# Layout flags are authored on the box scene root, so each member keeps
		# its natural size and stays pinned to the bottom row.
		var box: PartyMemberBox = MEMBER_BOX_SCENE.instantiate()
		_member_row.add_child(box)
		box.setup(i, GameState.party[i])
		_member_boxes.append(box)


func _on_party_member_hp_changed(index: int, new_hp: int, max_hp: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_hp(new_hp, max_hp)


## XP gauge (party level-up). Drives the exp bar + LV label.
func _on_party_member_xp_changed(index: int, xp: int, xp_to_next: int, level: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	var ratio: float = 1.0 if level >= GameState.MAX_CHARACTER_LEVEL else clampf(float(xp) / float(maxi(1, xp_to_next)), 0.0, 1.0)
	_member_boxes[index].set_exp_ratio(ratio)
	_member_boxes[index].set_level(level)


## Global armor changed — reflect the equipped armor badge on every box.
func _on_armor_equipped() -> void:
	for box in _member_boxes:
		if is_instance_valid(box):
			box.set_armor(GameState.armor_level, GameState.current_armor_name())


func _on_party_member_downed(index: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_downed(true)


func _on_party_member_revived(index: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_downed(false)


func _on_party_equipment_changed(index: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	_member_boxes[index].set_equipment(GameState.equipment_for_member(index))


# ─── Tier-unlock popup (big sprite + "○○ 해금!") ───────────────────────
func _build_unlock_popup() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.35, 1.0)  # gold frame
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 6
	_unlock_popup = PanelContainer.new()
	_unlock_popup.add_theme_stylebox_override("panel", style)
	_unlock_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unlock_popup.add_child(col)
	_unlock_sprite = TextureRect.new()
	_unlock_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp big pixels
	_unlock_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_unlock_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_unlock_sprite.custom_minimum_size = Vector2(48, 48)
	_unlock_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_unlock_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_unlock_sprite)
	_unlock_label = Label.new()
	_unlock_label.add_theme_font_override("font", HUD_FONT)
	_unlock_label.add_theme_font_size_override("font_size", 13)
	_unlock_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55, 1.0))
	_unlock_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_unlock_label.add_theme_constant_override("shadow_offset_x", 1)
	_unlock_label.add_theme_constant_override("shadow_offset_y", 1)
	_unlock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unlock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_unlock_label)
	add_child(_unlock_popup)
	_unlock_popup.visible = false


func _on_tier_unlocked(tier_id: StringName) -> void:
	if _unlock_popup == null:
		return
	var tier: Dictionary = Balance.tier_by_id(tier_id)
	_unlock_label.text = "%s 해금!" % str(tier.get("name", "?"))
	_unlock_sprite.texture = _tier_sprite(tier)
	_unlock_popup.visible = true
	_unlock_popup.modulate = Color(1, 1, 1, 1)
	_unlock_popup.scale = Vector2.ONE
	# Centered on the true viewport center (panels just overlay the edges).
	await get_tree().process_frame  # let it size to content first
	var center_x: float = VIEWPORT_DESIGN_WIDTH * 0.5
	_unlock_popup.pivot_offset = _unlock_popup.size * 0.5
	_unlock_popup.position = Vector2(center_x, 120.0) - _unlock_popup.size * 0.5
	if _unlock_tween != null and _unlock_tween.is_valid():
		_unlock_tween.kill()
	_unlock_popup.scale = Vector2(0.6, 0.6)
	_unlock_tween = create_tween()
	_unlock_tween.tween_property(_unlock_popup, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_unlock_tween.tween_interval(1.4)
	_unlock_tween.tween_property(_unlock_popup, "modulate:a", 0.0, 0.5)
	_unlock_tween.tween_callback(func() -> void: _unlock_popup.visible = false)


func _tier_sprite(tier: Dictionary) -> Texture2D:
	var path: String = str(tier.get("enemy_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ed := load(path) as EnemyData
	return ed.sprite if ed != null else null


# ─── Opening: name the hero ────────────────────────────────────────────
func _build_name_overlay() -> void:
	_name_overlay = Control.new()
	_name_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # block the world behind
	add_child(_name_overlay)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.45)  # dim, but the lone hero still shows through
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_overlay.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_overlay.add_child(center)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.13, 0.98)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.85, 0.35, 0.9)
	style.set_corner_radius_all(7)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)

	var title := Label.new()
	title.text = "이름을 입력하세요"
	title.add_theme_font_override("font", HUD_FONT)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_name_line_edit = LineEdit.new()
	_name_line_edit.custom_minimum_size = Vector2(160.0, 22.0)
	_name_line_edit.placeholder_text = "용사"
	_name_line_edit.max_length = 10
	_name_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_line_edit.add_theme_font_override("font", HUD_FONT)
	_name_line_edit.add_theme_font_size_override("font_size", 12)
	_name_line_edit.text_submitted.connect(_on_name_submitted)
	col.add_child(_name_line_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	row.add_child(_make_name_button("확인", Color(1.0, 0.85, 0.35, 1.0), _on_name_confirm))
	row.add_child(_make_name_button("랜덤", Color(0.6, 0.78, 0.95, 1.0), _on_name_random))

	_name_line_edit.call_deferred("grab_focus")


func _make_name_button(text: String, accent: Color, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56.0, 22.0)
	b.add_theme_font_override("font", HUD_FONT)
	b.add_theme_font_size_override("font_size", 11)
	for st in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(st, Color(0.08, 0.07, 0.05, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = accent
	normal.set_corner_radius_all(3)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = accent.lightened(0.18)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.pressed.connect(handler)
	return b


func _on_name_submitted(_text: String) -> void:
	_on_name_confirm()


func _on_name_confirm() -> void:
	GameState.set_player_name(_name_line_edit.text if _name_line_edit != null else "")
	_dismiss_name_overlay()


func _on_name_random() -> void:
	if _name_line_edit != null:
		_name_line_edit.text = GameState.random_hero_name()  # fill so the player sees it


func _dismiss_name_overlay() -> void:
	if _name_overlay != null:
		_name_overlay.queue_free()
		_name_overlay = null


# ─── Gold chip — TOP-LEFT, right where gold is SPENT (the placement dock) ──
func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold()


func _refresh_gold() -> void:
	if _gold_center_label == null:
		return
	# Coin icon already signals "gold" → show just the number (+ income).
	if _income_per_sec > 0:
		_gold_center_label.text = "%d  +%d/s" % [GameState.gold, _income_per_sec]
	else:
		_gold_center_label.text = "%d" % GameState.gold
	_reposition_gold_center()


## Gold's most-used spot is enemy placement on the left, so the readout lives there
## (big + bright). Unified white-bordered window chrome.
func _build_gold_center() -> void:
	var style := OSWindow.body_style(Color(0.1, 0.09, 0.04, 0.95))  # white border, gold-dark fill
	style.content_margin_left = 6
	style.content_margin_right = 7
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_gold_center = PanelContainer.new()
	_gold_center.add_theme_stylebox_override("panel", style)
	# Click the gold chip → +1000 (debug grant; replaces the removed top-bar button).
	_gold_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_gold_center.gui_input.connect(_on_gold_center_input)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_gold_center.add_child(row)
	var coin := TextureRect.new()
	coin.texture = load("res://assets/sprites/icons/gold.png")
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.custom_minimum_size = Vector2(12, 12)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin)
	_gold_center_label = Label.new()
	_gold_center_label.add_theme_font_override("font", HUD_FONT)
	_gold_center_label.add_theme_font_size_override("font_size", 9)  # small + minimal
	_gold_center_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4, 1.0))
	_gold_center_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_gold_center_label.add_theme_constant_override("shadow_offset_x", 1)
	_gold_center_label.add_theme_constant_override("shadow_offset_y", 1)
	_gold_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_center_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_gold_center_label)
	add_child(_gold_center)
	_gold_center.position = Vector2(5.0, 17.0)  # top-left, below the menu bar, above the dock


## Click the top-left gold chip to grant +1000 gold (debug). A quick pop sells it.
func _on_gold_center_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.add_gold(1000)
		if _gold_center != null:
			_gold_center.pivot_offset = _gold_center.size * 0.5
			var t := create_tween()
			t.tween_property(_gold_center, "scale", Vector2(1.18, 1.18), 0.07).set_trans(Tween.TRANS_QUAD)
			t.tween_property(_gold_center, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Pinned top-left (grows rightward as the number widens).
func _reposition_gold_center() -> void:
	if _gold_center != null:
		_gold_center.position = Vector2(5.0, 17.0)
