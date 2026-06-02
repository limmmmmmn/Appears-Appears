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

## macOS-window EXPERIMENT — each upgrade is a little desktop window: a category-
## colored title bar (Resurrect 64 palette) + close pip, rounded corners, dark
## neutral interior so the color pops. Buyable = lit color, locked/too-poor = grey.
## Title-bar colors (Resurrect 64).
const KIND_COLOR: Dictionary = {
	&"weapons": Color(0.910, 0.231, 0.231, 1.0),   # 검 = #e83b3b red
	&"armor": Color(0.302, 0.396, 0.706, 1.0),     # 방어 = #4d65b4 blue
	&"luck": Color(0.984, 1.0, 0.525, 1.0),        # 운 = #fbff86 yellow
	&"scale": Color(0.055, 0.686, 0.608, 1.0),     # 전투창 = #0eaf9b teal
	&"open_speed": Color(0.902, 0.565, 0.306, 1.0),# 보상 = #e6904e orange
	&"auto_pickup": Color(0.412, 0.792, 0.353, 1.0),# 자동줍기 = #69ca5a green
}
## 16×16 dot icons per category (fall back to an accent dot when missing).
const KIND_ICON: Dictionary = {
	&"weapons": "res://assets/sprites/icons/hero_sword.png",
	&"armor": "res://assets/sprites/icons/shield.png",
	&"luck": "res://assets/sprites/icons/gold.png",
	&"scale": "",
	&"open_speed": "res://assets/sprites/icons/gold.png",
	&"auto_pickup": "res://assets/sprites/icons/gold.png",
}
const WINDOW_BG: Color = Color(0.180, 0.133, 0.184, 1.0)    # #2e222f dark neutral
const LOCKED_GREY: Color = Color(0.384, 0.333, 0.396, 1.0)  # #625565 locked/too-poor
const WINDOW_CORNER: int = 5

var _selected_building: StringName = &""   ## "" = show all
var _gold_label: Label
## Floating group panels — shown progressively (opening sequence). Gold is always
## up; 강화 reveals after the first reward; 마을 reveals when a building exists.
var _village_group: PanelContainer
var _upgrade_group: PanelContainer
var _town_button: Button                    ## opens the big 마을 modal (shops/stats)
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

	# 마을 group — now just the 마을 button that opens the big town modal (shops +
	# stats live in there). The building grid is kept (hidden) so the building /
	# companion system + _refresh_grid keep working; its UI moved into the window.
	var village_box: VBoxContainer = _add_group(col)
	_village_group = village_box.get_parent() as PanelContainer
	_town_button = Button.new()
	_town_button.text = "마을 들어가기"
	_town_button.focus_mode = Control.FOCUS_NONE
	_town_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_town_button.add_theme_font_override("font", PANEL_FONT)
	_town_button.add_theme_font_size_override("font_size", UITheme.FONT_CARD_NAME)
	_town_button.add_theme_stylebox_override("normal", _town_button_style(Color(0.055, 0.686, 0.608, 1.0)))
	_town_button.add_theme_stylebox_override("hover", _town_button_style(Color(0.13, 0.78, 0.7, 1.0)))
	_town_button.add_theme_stylebox_override("pressed", _town_button_style(Color(0.04, 0.55, 0.49, 1.0)))
	_town_button.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_town_button.pressed.connect(_open_town)
	village_box.add_child(_town_button)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	_grid.visible = false  # building UI moved to the town window
	village_box.add_child(_grid)
	for i in Balance.building_count():
		_add_grid_tile(Balance.building_at(i))

	# 강화 group — the upgrade list. Hidden until the FIRST reward is earned, so
	# the opening screen stays minimal (it appears after the first battle).
	var upgrade_box: VBoxContainer = _add_group(col)
	_upgrade_group = upgrade_box.get_parent() as PanelContainer
	upgrade_box.add_child(_make_label("강화", UITheme.FONT_SECTION, Color(0.78, 0.82, 0.74, 0.5)))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", UITheme.LIST_SEPARATION)
	upgrade_box.add_child(list)
	# Card order: weapon-loot → armor-loot → luck → scale → open_speed. Weapon is
	# now ONE card (raises the loot level for ALL weapon types, not per-type).
	_add_card(list, &"weapons", &"", &"weapon_shop")
	_add_card(list, &"armor", &"", &"armory")
	_add_card(list, &"luck", &"", &"thieves_guild")
	_add_card(list, &"scale", &"", &"war_council")
	# Abstract relics (no dedicated building) — always shown in 전체보기.
	_add_card(list, &"open_speed", &"", &"")
	_add_card(list, &"auto_pickup", &"", &"")


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
	# ── The window frame (dark interior, rounded, content flush to the edges).
	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", _window_style())
	window.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	window.clip_contents = true  # keep the title bar's color inside the rounded frame
	parent.add_child(window)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	window.add_child(col)

	# ── Title bar (category color) — icon + name + macOS close pip.
	var titlebar := PanelContainer.new()
	titlebar.add_theme_stylebox_override("panel", _titlebar_style(accent))
	titlebar.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(titlebar)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 3)
	titlebar.add_child(bar_row)
	var icon: Control = _make_card_icon(kind, accent)
	bar_row.add_child(icon)
	var name_lbl := _make_label("", UITheme.FONT_CARD_NAME, _text_on(accent))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_lbl.clip_text = true
	bar_row.add_child(name_lbl)
	var close_btn := _make_close_button()
	bar_row.add_child(close_btn)

	# ── Body (dark interior shows through) — value + buy button. Hides on minimize.
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 4)
	body.add_theme_constant_override("margin_right", 4)
	body.add_theme_constant_override("margin_top", 2)
	body.add_theme_constant_override("margin_bottom", 3)
	col.add_child(body)
	var body_col := VBoxContainer.new()
	body_col.add_theme_constant_override("separation", 2)
	body.add_child(body_col)
	var value_lbl := _make_label("", UITheme.FONT_CARD_VALUE, Color(0.86, 0.84, 0.88, 1.0))
	value_lbl.clip_text = true  # long text clips instead of widening the window
	body_col.add_child(value_lbl)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, UITheme.CARD_BUTTON_HEIGHT)
	button.clip_text = true  # FIXED width — text never forces the window wider
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", UITheme.FONT_CARD_BUTTON)
	button.pressed.connect(_on_card_pressed.bind(kind, param))
	body_col.add_child(button)

	var card: Dictionary = {
		"kind": kind, "param": param, "building": building,
		"window": window, "titlebar": titlebar, "icon": icon, "name": name_lbl,
		"value": value_lbl, "button": button, "body": body, "accent": accent, "minimized": false,
	}
	_cards.append(card)
	close_btn.pressed.connect(_toggle_card_minimize.bind(card))
	titlebar.gui_input.connect(_on_titlebar_input.bind(card))


## macOS minimize: collapse the body to just the colored title bar; click the bar
## (or the pip) again to expand. Pure presentation — no game state involved.
func _toggle_card_minimize(card: Dictionary) -> void:
	card["minimized"] = not bool(card["minimized"])
	card["body"].visible = not bool(card["minimized"])


func _on_titlebar_input(event: InputEvent, card: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_card_minimize(card)


func _on_card_pressed(kind: StringName, param: StringName) -> void:
	match kind:
		&"weapons":
			GameState.upgrade_weapon_loot()
		&"armor":
			GameState.upgrade_armor_loot()
		&"luck":
			GameState.upgrade_luck()
		&"scale":
			GameState.upgrade_scale()
		&"open_speed":
			GameState.upgrade_open_speed()
		&"auto_pickup":
			GameState.unlock_auto_pickup()


func _refresh_cards() -> void:
	for card: Dictionary in _cards:
		var kind: StringName = card["kind"]
		var param: StringName = card["param"]
		var building: StringName = card["building"]
		var available: bool = _card_available(kind, param)
		var passes_filter: bool = _selected_building == &"" or _selected_building == building
		var vis: bool = available and passes_filter
		card["window"].visible = vis
		if vis:
			_fill_card(card)


## Whether this upgrade is purchasable at all (independent of the filter).
func _card_available(_kind: StringName, _param: StringName) -> bool:
	return true  # all upgrades buyable from the start


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
			name_lbl.text = "무기 루팅"
			value_lbl.text = "Lv%d 장비 드롭" % GameState.weapon_loot_level
			affordable = GameState.can_upgrade_weapon_loot()
			_set_buy_button(button, "%dG  Lv%d" % [GameState.weapon_loot_cost(), GameState.weapon_loot_level + 1], affordable)
		&"armor":
			name_lbl.text = "방어 루팅"
			value_lbl.text = "Lv%d 장비 드롭" % GameState.armor_loot_level
			affordable = GameState.can_upgrade_armor_loot()
			_set_buy_button(button, "%dG  Lv%d" % [GameState.armor_loot_cost(), GameState.armor_loot_level + 1], affordable)
		&"luck":
			name_lbl.text = "운"
			value_lbl.text = "대박 %.0f%%" % (GameState.luck_jackpot_chance() * 100.0)
			if GameState.luck_is_maxed():
				maxed = true
				_set_buy_button(button, "운 최대", false)
			else:
				var nc: float = GameState.luck_jackpot_chance_for_level(GameState.luck_level + 1)
				affordable = GameState.can_upgrade_luck()
				_set_buy_button(button, "%dG  %.0f%%" % [GameState.luck_upgrade_cost(), nc * 100.0], affordable)
		&"scale":
			name_lbl.text = "멀티 전투창"
			if GameState.scale_is_maxed():
				value_lbl.text = "무제한"
				maxed = true
				_set_buy_button(button, "멀티 ON", false)
			else:
				value_lbl.text = "1개"
				affordable = GameState.can_upgrade_scale()
				_set_buy_button(button, "%dG  멀티 열기" % GameState.scale_upgrade_cost(), affordable)
		&"open_speed":
			name_lbl.text = "보상 개봉"
			value_lbl.text = "%.2fs" % GameState.chest_hover_duration()
			if GameState.open_speed_is_maxed():
				maxed = true
				_set_buy_button(button, "개봉 최속", false)
			else:
				var no: float = Balance.chest_open_duration(GameState.open_speed_level + 1)
				affordable = GameState.can_upgrade_open_speed()
				_set_buy_button(button, "%dG  %.2fs" % [GameState.open_speed_upgrade_cost(), no], affordable)
		&"auto_pickup":
			name_lbl.text = "자동 줍기"
			if GameState.auto_pickup_unlocked:
				value_lbl.text = "자동"
				maxed = true
				_set_buy_button(button, "자동 ON", false)
			else:
				value_lbl.text = "수동(호버)"
				affordable = GameState.can_unlock_auto_pickup()
				_set_buy_button(button, "%dG  자동 줍기" % GameState.auto_pickup_cost(), affordable)
	# Window state: lit (buyable or maxed) → category color; locked/too-poor → grey.
	var lit: bool = affordable or maxed
	var accent: Color = card["accent"]
	var bar_color: Color = accent if lit else LOCKED_GREY
	var tc: Color = _text_on(bar_color)
	card["titlebar"].add_theme_stylebox_override("panel", _titlebar_style(bar_color))
	card["name"].add_theme_color_override("font_color", tc)
	card["icon"].modulate = Color(1, 1, 1, 1) if lit else Color(0.62, 0.6, 0.66, 1.0)
	# Buy button: accent CTA when affordable, grey when not (still readable).
	var btn_bg: Color = accent if affordable else LOCKED_GREY
	var btn_tc: Color = _text_on(btn_bg)
	button.add_theme_stylebox_override("normal", _buy_button_style(btn_bg, false))
	button.add_theme_stylebox_override("hover", _buy_button_style(btn_bg, true))
	button.add_theme_stylebox_override("pressed", _buy_button_style(btn_bg, false))
	button.add_theme_stylebox_override("disabled", _buy_button_style(btn_bg, false))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(st, btn_tc)


# ─── Refresh ───────────────────────────────────────────────────────────
func _refresh() -> void:
	# If the filter points at a building that no longer qualifies, clear it.
	if _selected_building != &"" and not GameState.is_building_built(_selected_building):
		_selected_building = &""
	_update_gold_text()
	_refresh_grid()
	_refresh_cards()
	_refresh_group_visibility()


## Sequential opening reveal: Gold pill always; 강화 once the first reward lands;
## 마을 once at least one building tile is shown.
func _refresh_group_visibility() -> void:
	if _upgrade_group != null:
		_upgrade_group.visible = GameState.total_gold_earned > 0
	# 마을 button reveals with the first reward (you need gold/loot to shop).
	if _village_group != null:
		_village_group.visible = GameState.total_gold_earned > 0


## Open the big 마을 modal (looked up by group so the panel stays decoupled).
func _open_town() -> void:
	var tw: Node = get_tree().get_first_node_in_group("town_window")
	if tw != null and tw.has_method("open"):
		tw.call("open")


func _town_button_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(4)
	s.set_content_margin_all(4)
	s.shadow_color = Color(0, 0, 0, 0.3)
	s.shadow_size = 2
	return s


func _any_grid_tile_visible() -> bool:
	for id in _grid_tiles:
		var tile: Button = _grid_tiles[id]["button"]
		if tile != null and tile.visible:
			return true
	return false


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


# ─── macOS-window styling ──────────────────────────────────────────────
## The window frame: dark neutral interior, rounded, soft shadow. content_margin
## 0 so the title bar fills edge-to-edge.
func _window_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WINDOW_BG
	style.set_corner_radius_all(WINDOW_CORNER)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.12)
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 3
	return style


## The title bar: category (or grey) color, rounded TOP corners only so it nests
## against the window's rounded top; square bottom meets the body.
func _titlebar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = WINDOW_CORNER
	style.corner_radius_top_right = WINDOW_CORNER
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 4
	style.content_margin_right = 3
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


## Buy button on the dark interior — solid accent CTA (grey when locked).
func _buy_button_style(bg: Color, hover: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg.lightened(0.12) if hover else bg
	style.set_corner_radius_all(3)
	return style


## macOS-style close/minimize pip. A light circle with a dark outline so it reads
## on ANY title-bar color (red/blue/yellow/teal/orange); reddens on hover.
func _make_close_button() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(9.0, 9.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "최소화"
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.96, 0.94, 0.9, 1.0)
	normal.set_corner_radius_all(5)
	normal.set_border_width_all(1)
	normal.border_color = Color(0, 0, 0, 0.55)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.95, 0.3, 0.28, 1.0)  # macOS red on hover
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	return b


## 16×16 pixel icon for a category, or a small accent dot if none is mapped.
func _make_card_icon(kind: StringName, accent: Color) -> Control:
	var path: String = str(KIND_ICON.get(kind, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(16.0, 16.0)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(11.0, 11.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = accent
	dot_style.set_corner_radius_all(6)
	dot.add_theme_stylebox_override("panel", dot_style)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


## Contrast text color for a filled background: dark on bright (yellow/teal),
## bright white on dark (red/blue/grey).
func _text_on(bg: Color) -> Color:
	var lum: float = bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
	return Color(0.13, 0.07, 0.02, 1.0) if lum > 0.55 else Color(0.99, 0.99, 1.0, 1.0)


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
