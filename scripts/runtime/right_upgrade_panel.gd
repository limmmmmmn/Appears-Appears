class_name RightUpgradePanel
extends PanelContainer

## Right zone = the village. Inverted causality:
##   • The UPGRADE LIST (lower) is what the player spends gold on — visible and
##     buyable from the start (공격 강화 등).
##   • Buildings are the RESULT: the first time an upgrade category is bought, its
##     building pops into the grid (visualization). Companions auto-join off the
##     building (count for 기사/도둑, on-build for 마법사/사제). No gold recruit.
##   • Exception: 모닥불 / 성소 are DIRECT-build — click their tile to build (gold).
##   • A built tile = filter tab: click to show only its upgrades, click to clear.
## All data-driven from Balance.BUILDINGS / WEAPON_TYPES.

const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const GRID_COLUMNS: int = 3

## Bold per-category colors — the WHOLE card is filled with these.
const KIND_COLOR: Dictionary = {
	&"weapons": Color(0.86, 0.24, 0.22, 1.0),    # 검 = red
	&"armor": Color(0.26, 0.5, 0.92, 1.0),       # 방어 = blue
	&"luck": Color(0.93, 0.77, 0.16, 1.0),       # 운 = yellow (fortune/gold)
	&"scale": Color(0.34, 0.46, 0.9, 1.0),       # 전투창 = blue (indigo)
	&"open_speed": Color(0.95, 0.54, 0.16, 1.0), # 보상 = orange
}

var _selected_building: StringName = &""   ## "" = show all
var _gold_label: Label
var _grid: GridContainer
var _grid_tiles: Dictionary = {}            ## building id → {button, glyph, tag}
var _cards: Array[Dictionary] = []          ## upgrade cards (flat, fixed order)
## Measured gold income/sec (moved here from the HUD so there's one Gold display).
var _income_timer: float = 0.0
var _income_marker: int = 0
var _income_per_sec: int = 0


func _ready() -> void:
	var x: float = UITheme.right_panel_left()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(x, 0.0)
	custom_minimum_size = Vector2(UITheme.RIGHT_PANEL_WIDTH, 360.0)
	offset_left = x
	offset_top = 0.0
	offset_right = 640.0
	offset_bottom = 360.0
	# The frame itself draws NOTHING (no black wall) — only the floating opaque
	# group panels are visible, and they size to their content.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", _frame_style())
	_build_layout()
	_connect_events()
	_income_marker = GameState.total_gold_earned
	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	_income_timer += delta
	if _income_timer >= 1.0:
		_income_per_sec = maxi(0, GameState.total_gold_earned - _income_marker)
		_income_marker = GameState.total_gold_earned
		_income_timer = 0.0
		_update_gold_text()


func _update_gold_text() -> void:
	if _income_per_sec > 0:
		_gold_label.text = "Gold %d  +%d/s" % [GameState.gold, _income_per_sec]
	else:
		_gold_label.text = "Gold %d" % GameState.gold


func _connect_events() -> void:
	EventBus.gold_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_failed.connect(_on_changed.unbind(1))
	EventBus.building_built.connect(_on_changed.unbind(1))
	EventBus.companion_appeared.connect(_on_changed.unbind(1))
	EventBus.companion_recruited.connect(_on_changed.unbind(1))
	EventBus.party_changed.connect(_on_changed)


func _on_changed() -> void:
	_refresh()


# ─── Layout ────────────────────────────────────────────────────────────
## A top-aligned column of FLOATING OPAQUE GROUPS. Each group sizes to its own
## content; the column's leftover space stays transparent (no black wall), so the
## panel visibly grows as more upgrades/buildings unlock.
func _build_layout() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 5)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN  # pack at top; empty space below
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE  # empty area passes through to field
	add_child(col)

	# Gold (its own little floating pill).
	var gold_box: VBoxContainer = _add_group(col)
	_gold_label = _make_label("Gold 0", UITheme.FONT_GOLD, Color(1.0, 0.91, 0.48, 1.0))
	gold_box.add_child(_gold_label)

	# 마을 group — the village grid (buildings appear as a result of upgrades).
	var village_box: VBoxContainer = _add_group(col)
	village_box.add_child(_make_label("마을", UITheme.FONT_SECTION, Color(0.78, 0.82, 0.74, 0.5)))
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	village_box.add_child(_grid)
	for i in Balance.building_count():
		_add_grid_tile(Balance.building_at(i))

	# 강화 group — the upgrade list (the protagonist; buyable from the start).
	var upgrade_box: VBoxContainer = _add_group(col)
	upgrade_box.add_child(_make_label("강화", UITheme.FONT_SECTION, Color(0.78, 0.82, 0.74, 0.5)))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", UITheme.LIST_SEPARATION)
	upgrade_box.add_child(list)
	# Fixed card order: weapons (per type) → armor → luck → scale → open_speed.
	for t in Balance.weapon_type_count():
		_add_card(list, &"weapons", Balance.weapon_type_at(t)["id"], &"weapon_shop")
	_add_card(list, &"armor", &"", &"armory")
	_add_card(list, &"luck", &"", &"thieves_guild")
	_add_card(list, &"scale", &"", &"war_council")
	# Abstract relic (no dedicated building) — always shown in 전체보기.
	_add_card(list, &"open_speed", &"", &"")


## Create one floating opaque group panel (content-sized) and return its inner
## VBox to fill. The panel never stretches vertically — it hugs its content.
func _add_group(col: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _group_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	return box


# ─── Layer 1: grid tiles ───────────────────────────────────────────────
func _add_grid_tile(building: Dictionary) -> void:
	var id: StringName = building["id"]
	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = UITheme.GRID_TILE_SIZE
	tile.pressed.connect(_on_tile_pressed.bind(id))
	var glyph := _make_label(str(building.get("short", "?")), UITheme.FONT_TILE_GLYPH, Color.WHITE)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(glyph)
	var tag := _make_label("", UITheme.FONT_TILE_TAG, Color(1.0, 0.92, 0.6, 1.0))
	tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tag.offset_top = -8.0
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.add_child(tag)
	_grid_tiles[id] = {"button": tile, "glyph": glyph, "tag": tag}
	_grid.add_child(tile)


func _on_tile_pressed(id: StringName) -> void:
	if GameState.is_building_built(id):
		_selected_building = &"" if _selected_building == id else id
		_refresh()
	elif GameState.can_purchase_building(id):
		# Direct-build (모닥불/성소). Auto buildings can't be built by click.
		GameState.purchase_building(id)


func _refresh_grid() -> void:
	for i in Balance.building_count():
		var building: Dictionary = Balance.building_at(i)
		var id: StringName = building["id"]
		var refs: Dictionary = _grid_tiles[id]
		var tile: Button = refs["button"]
		var glyph: Label = refs["glyph"]
		var tag: Label = refs["tag"]
		var accent: Color = building.get("color", Color.WHITE)
		var built: bool = GameState.is_building_built(id)
		var is_direct: bool = StringName(building.get("mode", &"")) == &"direct"
		var buildable: bool = is_direct and not built and GameState.is_building_unlocked(id)
		# Auto buildings only show once raised; direct buildings show once unlocked.
		tile.visible = built or buildable
		if not tile.visible:
			continue
		glyph.text = str(building.get("short", "?"))
		if built:
			var selected: bool = _selected_building == id
			tile.add_theme_stylebox_override("normal", _tile_style(2, accent, selected))
			tile.add_theme_stylebox_override("hover", _tile_style(2, accent, true))
			tile.add_theme_stylebox_override("pressed", _tile_style(2, accent, true))
			glyph.add_theme_color_override("font_color", Color.WHITE)
			tag.text = "필터" if selected else ""
			tag.visible = selected
			tag.add_theme_color_override("font_color", accent)
			tile.tooltip_text = "%s\n%s\n클릭: 강화 필터 %s" % [building["name"], building.get("desc", ""), "해제" if selected else "보기"]
		else:
			var cost: int = GameState.building_cost(id)
			tile.add_theme_stylebox_override("normal", _tile_style(1, accent, false))
			tile.add_theme_stylebox_override("hover", _tile_style(1, accent, true))
			tile.add_theme_stylebox_override("pressed", _tile_style(1, accent, false))
			glyph.add_theme_color_override("font_color", Color(0.85, 0.87, 0.8, 1.0))
			tag.text = "+%d" % cost
			tag.visible = true
			tag.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6, 1.0) if GameState.gold >= cost else Color(0.7, 0.55, 0.4, 1.0))
			tile.tooltip_text = "%s — 직접 짓기 %dG\n%s" % [building["name"], cost, building.get("desc", "")]


# ─── Layer 2: upgrade cards ────────────────────────────────────────────
func _add_card(parent: VBoxContainer, kind: StringName, param: StringName, building: StringName) -> void:
	var accent: Color = KIND_COLOR.get(kind, Color.WHITE)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	# Card is filled with the category color → text must contrast (dark on bright,
	# light on dark) for readability.
	var tc: Color = _text_on(accent)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	# Name row: NAME (base size, prominent) + current value (smaller, dim).
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 3)
	box.add_child(name_row)
	var name_lbl := _make_label("", UITheme.FONT_CARD_NAME, tc)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.clip_text = true  # never overrun into the value
	name_row.add_child(name_lbl)
	var value_lbl := _make_label("", UITheme.FONT_CARD_VALUE, Color(tc.r, tc.g, tc.b, 0.82))
	value_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	value_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(value_lbl)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, UITheme.CARD_BUTTON_HEIGHT)
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", UITheme.FONT_CARD_BUTTON)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(state, tc)
	button.add_theme_stylebox_override("normal", _card_button_style(tc, false))
	button.add_theme_stylebox_override("hover", _card_button_style(tc, true))
	button.add_theme_stylebox_override("pressed", _card_button_style(tc, false))
	button.add_theme_stylebox_override("disabled", _card_button_style(tc, false))
	button.pressed.connect(_on_card_pressed.bind(kind, param))
	box.add_child(button)
	_cards.append({"kind": kind, "param": param, "building": building, "card": card, "name": name_lbl, "value": value_lbl, "button": button})


func _on_card_pressed(kind: StringName, param: StringName) -> void:
	match kind:
		&"weapons":
			GameState.upgrade_weapon(param)
		&"armor":
			GameState.upgrade_armor()
		&"luck":
			GameState.upgrade_luck()
		&"scale":
			GameState.upgrade_scale()
		&"open_speed":
			GameState.upgrade_open_speed()


func _refresh_cards() -> void:
	for card: Dictionary in _cards:
		var kind: StringName = card["kind"]
		var param: StringName = card["param"]
		var building: StringName = card["building"]
		var available: bool = _card_available(kind, param)
		var passes_filter: bool = _selected_building == &"" or _selected_building == building
		var vis: bool = available and passes_filter
		card["card"].visible = vis
		if vis:
			_fill_card(card)


## Whether this upgrade is purchasable at all (independent of the filter).
func _card_available(kind: StringName, param: StringName) -> bool:
	match kind:
		&"weapons":
			return GameState.owned_weapon_types().has(param)
	return true  # armor / luck / scale / open_speed buyable from the start


## Sets NAME (prominent) + current VALUE (small) + buy button (next + cost, small).
## Tracks affordability so the WHOLE card can go dark when you can't afford it
## (kept distinct from a maxed card, which stays lit).
func _fill_card(card: Dictionary) -> void:
	var name_lbl: Label = card["name"]
	var value_lbl: Label = card["value"]
	var button: Button = card["button"]
	var affordable: bool = true
	var maxed: bool = false
	match card["kind"]:
		&"weapons":
			var p: StringName = card["param"]
			var tname: String = str(Balance.weapon_type_by_id(p).get("name", "무기"))
			name_lbl.text = "%s·%s" % [tname, GameState.current_weapon_name(p)]
			value_lbl.text = "×%s" % _fmt_mult(GameState.weapon_attack_multiplier(p))
			var nm: float = Balance.effect_multiplier(GameState.weapon_level(p) + 1)
			affordable = GameState.can_upgrade_weapon(p)
			_set_buy_button(button, "%s ×%s  %dG" % [GameState.next_weapon_name(p), _fmt_mult(nm), GameState.weapon_upgrade_cost(p)], affordable)
		&"armor":
			name_lbl.text = "방어구"
			value_lbl.text = "Lv%d 방어+%d" % [GameState.armor_level, GameState.armor_defense_bonus()]
			var nd: int = Balance.armor_defense_for_level(GameState.armor_level + 1)
			affordable = GameState.can_upgrade_armor()
			_set_buy_button(button, "%s 방어+%d  %dG" % [GameState.next_armor_name(), nd, GameState.armor_upgrade_cost()], affordable)
		&"luck":
			name_lbl.text = "운"
			value_lbl.text = "대박 %.0f%%" % (GameState.luck_jackpot_chance() * 100.0)
			if GameState.luck_is_maxed():
				maxed = true
				_set_buy_button(button, "운 최대", false)
			else:
				var nc: float = GameState.luck_jackpot_chance_for_level(GameState.luck_level + 1)
				affordable = GameState.can_upgrade_luck()
				_set_buy_button(button, "대박 %.0f%%  %dG" % [nc * 100.0, GameState.luck_upgrade_cost()], affordable)
		&"scale":
			name_lbl.text = "전투창"
			value_lbl.text = "%d개" % GameState.scale_window_count()
			if GameState.scale_is_maxed():
				maxed = true
				_set_buy_button(button, "최대", false)
			else:
				var nc: int = Balance.scale_window_count(GameState.scale_purchases + 1)
				affordable = GameState.can_upgrade_scale()
				_set_buy_button(button, "+창 → %d개  %dG" % [nc, GameState.scale_upgrade_cost()], affordable)
		&"open_speed":
			name_lbl.text = "보상 개봉"
			value_lbl.text = "%.2fs" % GameState.chest_hover_duration()
			if GameState.open_speed_is_maxed():
				maxed = true
				_set_buy_button(button, "개봉 최속", false)
			else:
				var no: float = Balance.chest_open_duration(GameState.open_speed_level + 1)
				affordable = GameState.can_upgrade_open_speed()
				_set_buy_button(button, "개봉↑ %.2fs  %dG" % [no, GameState.open_speed_upgrade_cost()], affordable)
	# 돈 모자라서 못 사는 카드 = 확 어둡게(전체 모듈레이트). 최대치 카드는 그대로 밝게.
	var lit: bool = affordable or maxed
	card["card"].modulate = Color(1, 1, 1, 1) if lit else Color(0.34, 0.34, 0.4, 1.0)


# ─── Refresh ───────────────────────────────────────────────────────────
func _refresh() -> void:
	# If the filter points at a building that no longer qualifies, clear it.
	if _selected_building != &"" and not GameState.is_building_built(_selected_building):
		_selected_building = &""
	_update_gold_text()
	_refresh_grid()
	_refresh_cards()


# ─── Styles / helpers ──────────────────────────────────────────────────
func _set_buy_button(button: Button, text: String, affordable: bool) -> void:
	button.text = text
	button.disabled = not affordable
	button.modulate = Color(1, 1, 1, 1) if affordable else Color(0.62, 0.62, 0.66, 1.0)


func _fmt_mult(v: float) -> String:
	return "%.2f" % v


func _make_label(text: String, pt: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", PANEL_FONT)
	label.add_theme_font_size_override("font_size", pt)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The outer frame draws nothing — it just insets the groups so they float off
## the screen's right/top edges (the field shows through the empty space).
func _frame_style() -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 2
	style.content_margin_right = 5    # gap from the screen's right edge
	style.content_margin_top = 6      # gap from the top
	style.content_margin_bottom = 4
	return style


## One floating group: OPAQUE, crisp, rounded, no shadow.
func _group_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.085, 0.095, 0.11, 1.0)  # opaque
	style.set_corner_radius_all(7)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.1)
	style.content_margin_left = UITheme.PANEL_CONTENT_MARGIN
	style.content_margin_top = UITheme.PANEL_CONTENT_MARGIN
	style.content_margin_right = UITheme.PANEL_CONTENT_MARGIN
	style.content_margin_bottom = UITheme.PANEL_CONTENT_MARGIN
	return style


## Whole card filled with the category color (bold).
func _card_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = accent.darkened(0.35)
	style.content_margin_left = UITheme.CARD_MARGIN_H
	style.content_margin_top = UITheme.CARD_MARGIN_V
	style.content_margin_right = UITheme.CARD_MARGIN_H
	style.content_margin_bottom = UITheme.CARD_MARGIN_V
	return style


## Contrast text color for a filled background: dark BROWN on bright cards
## (yellow/orange), bright white on dark cards (red/blue).
func _text_on(bg: Color) -> Color:
	var lum: float = bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
	return Color(0.13, 0.07, 0.02, 1.0) if lum > 0.55 else Color(0.99, 0.99, 1.0, 1.0)


## Buy-button inset on a colored card. Contrasts the card so the button reads:
## light inset under dark text, dark inset under light text.
func _card_button_style(tc: Color, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if tc.r < 0.5:  # dark text → bright card → light button
		style.bg_color = Color(1, 1, 1, 0.6 if hover else 0.42)
	else:           # light text → dark card → dark button
		style.bg_color = Color(0, 0, 0, 0.42 if hover else 0.28)
	style.set_corner_radius_all(3)
	return style


## Grid tile background. state: 1 buildable / 2 built.
func _tile_style(state: int, accent: Color, highlight: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_border_width_all(2)
	if state == 2:
		style.bg_color = accent.darkened(0.55)
		style.border_color = accent
	else:
		style.bg_color = Color(0.12, 0.13, 0.15, 1.0)
		style.border_color = accent.darkened(0.25)
	if highlight:
		style.bg_color = style.bg_color.lightened(0.12)
	return style
