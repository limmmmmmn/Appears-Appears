class_name LeftEnemyBar
extends PanelContainer

## Left zone of the ㄷ-shaped layout: the enemy toggle bar — the player's
## difficulty / farming-stage knob.
##   • Unlocked + ON   → glowing accent border (this tier spawns on the field)
##   • Unlocked + OFF  → gray (won't spawn)
##   • Locked          → lock glyph + unlock cost (click to buy)
## Click a locked icon to unlock it (auto-toggles ON); click an unlocked icon to
## toggle it ON/OFF. Several tiers can be ON at once — that's how the screen
## fills with windows.

const BAR_WIDTH: float = 46.0
const ICON_SIZE: Vector2 = Vector2(38.0, 38.0)
const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

## tier id → {"button": Button, "glyph": Label, "cost": Label}
var _icons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	custom_minimum_size = Vector2(BAR_WIDTH, 360.0)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = BAR_WIDTH
	offset_bottom = 360.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())
	_build()
	EventBus.gold_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))
	# Kill progress fires often — update only the cheap Lv/gauge, not styleboxes.
	EventBus.enemy_progress_changed.connect(_on_progress_changed.unbind(1))
	EventBus.enemy_leveled_up.connect(_on_progress_changed.unbind(2))
	_refresh()


func _on_changed() -> void:
	_refresh()


func _on_progress_changed() -> void:
	for id in _icons.keys():
		_update_icon_progress(id)


func _update_icon_progress(id: StringName) -> void:
	if not _icons.has(id):
		return
	var refs: Dictionary = _icons[id]
	var unlocked: bool = GameState.is_tier_unlocked(id)
	refs["lv"].visible = unlocked
	refs["prog"].visible = unlocked
	if unlocked:
		refs["lv"].text = "Lv%d" % GameState.enemy_level(id)
		refs["prog"].value = GameState.enemy_level_progress_ratio(id)


func _build() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 5)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(col)

	for i in Balance.tier_count():
		var tier: Dictionary = Balance.tier_at(i)
		col.add_child(_make_icon(tier))


func _make_icon(tier: Dictionary) -> Control:
	var id: StringName = tier["id"]

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = ICON_SIZE
	button.text = ""
	button.tooltip_text = str(tier["name"])
	button.pressed.connect(_on_icon_pressed.bind(id))

	var glyph := _make_label(str(tier.get("short", "?")), 14, Color.WHITE)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(glyph)

	var cost := _make_label("", 7, Color(1.0, 0.92, 0.6, 1.0))
	cost.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	cost.offset_top = -9.0
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_child(cost)

	# System 1 growth, made visible: a tiny "Lv N" badge (top-left) + a thin
	# kill-progress gauge along the bottom edge, so accumulation is felt.
	var lv := _make_label("", 7, Color(0.75, 1.0, 0.85, 1.0))
	lv.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lv.position = Vector2(2.0, 1.0)
	button.add_child(lv)

	var prog := ProgressBar.new()
	prog.show_percentage = false
	prog.max_value = 1.0
	prog.value = 0.0
	prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prog.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prog.offset_top = -3.0
	prog.offset_left = 2.0
	prog.offset_right = -2.0
	prog.add_theme_stylebox_override("background", _prog_bg_style())
	prog.add_theme_stylebox_override("fill", _prog_fill_style())
	button.add_child(prog)

	_icons[id] = {"button": button, "glyph": glyph, "cost": cost, "lv": lv, "prog": prog}
	return button


func _refresh() -> void:
	for i in Balance.tier_count():
		var tier: Dictionary = Balance.tier_at(i)
		var id: StringName = tier["id"]
		if not _icons.has(id):
			continue
		var refs: Dictionary = _icons[id]
		var button: Button = refs["button"]
		var glyph: Label = refs["glyph"]
		var cost: Label = refs["cost"]
		var unlocked: bool = GameState.is_tier_unlocked(id)
		var active: bool = GameState.is_tier_active(id)
		var state: int = 2 if (unlocked and active) else (1 if unlocked else 0)

		button.add_theme_stylebox_override("normal", _icon_style(state))
		button.add_theme_stylebox_override("hover", _icon_style(state, true))
		button.add_theme_stylebox_override("pressed", _icon_style(state))
		button.add_theme_stylebox_override("disabled", _icon_style(state))

		match state:
			2:  # unlocked + ON
				glyph.text = str(tier.get("short", "?"))
				glyph.add_theme_color_override("font_color", Color.WHITE)
				cost.text = ""
				button.disabled = false
				button.tooltip_text = "%s — ON (필드에 등장 중)\n클릭하면 끄기" % tier["name"]
			1:  # unlocked + OFF
				glyph.text = str(tier.get("short", "?"))
				glyph.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6, 1.0))
				cost.text = ""
				button.disabled = false
				button.tooltip_text = "%s — OFF\n클릭하면 켜기" % tier["name"]
			_:  # locked — show the glyph dimmed (pixel font has no emoji) + cost
				glyph.text = str(tier.get("short", "?"))
				glyph.add_theme_color_override("font_color", Color(0.42, 0.4, 0.36, 1.0))
				var unlock_cost: int = int(tier["unlock_cost"])
				cost.text = _short_cost(unlock_cost)
				var affordable: bool = GameState.gold >= unlock_cost
				button.disabled = false
				button.modulate = Color(1, 1, 1, 1) if affordable else Color(0.7, 0.7, 0.74, 1.0)
				button.tooltip_text = "%s — 잠김\n해금 비용 %dG (처치 골드 %d)" % [tier["name"], unlock_cost, int(tier["kill_gold"])]
		if state != 0:
			button.modulate = Color(1, 1, 1, 1)
		# Lv badge + kill-progress gauge (System 1).
		_update_icon_progress(id)


func _on_icon_pressed(id: StringName) -> void:
	if GameState.is_tier_unlocked(id):
		GameState.toggle_tier(id)
	else:
		GameState.unlock_tier(id)


# ─── Styles / helpers ──────────────────────────────────────────────────
func _icon_style(state: int, hover: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.set_border_width_all(2)
	match state:
		2:  # ON — glowing accent
			style.bg_color = Color(0.18, 0.26, 0.2, 1.0)
			style.border_color = Color(0.55, 1.0, 0.66, 1.0)
		1:  # OFF — gray
			style.bg_color = Color(0.12, 0.13, 0.14, 1.0)
			style.border_color = Color(0.34, 0.36, 0.38, 1.0)
		_:  # locked — dark
			style.bg_color = Color(0.08, 0.085, 0.09, 1.0)
			style.border_color = Color(0.24, 0.2, 0.16, 1.0)
	if hover:
		style.bg_color = style.bg_color.lightened(0.12)
	return style


func _make_label(text: String, pt: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", PANEL_FONT)
	label.add_theme_font_size_override("font_size", pt)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _short_cost(c: int) -> String:
	if c >= 1000:
		return "%.0fk" % (float(c) / 1000.0)
	return str(c)


func _prog_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.05, 0.9)
	return style


func _prog_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 1.0, 0.66, 1.0)
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.038, 0.045, 1.0)
	style.border_width_right = 1
	style.border_color = Color(0.78, 0.86, 0.72, 1.0)
	style.content_margin_left = 4
	style.content_margin_top = 5
	style.content_margin_right = 4
	style.content_margin_bottom = 5
	return style
