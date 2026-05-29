class_name RightUpgradePanel
extends PanelContainer

## Right zone = the village. Two layers:
##   1) 마을 격자 — building icon tiles. Click an empty/buildable tile to build it
##      (gold, one-time); click a built tile to filter the list to it (toggle).
##   2) 강화 목록 — upgrades of all built buildings (show-all by default), or just
##      the selected building's when one is filtered.
## Buildings host every upgrade category (weapons/armor/greed/scale/relics) AND
## unlock their owner companion on build. Everything is data-driven from
## Balance.BUILDINGS — adding a building just appends a row there.

const PANEL_WIDTH: float = 160.0
const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const GRID_COLUMNS: int = 3
const TILE_SIZE: Vector2 = Vector2(46.0, 40.0)

## Per upgrade-kind accent color.
const KIND_COLOR: Dictionary = {
	&"weapons": Color(0.95, 0.42, 0.38, 1.0),
	&"armor": Color(0.62, 0.82, 0.86, 1.0),
	&"greed": Color(0.98, 0.82, 0.34, 1.0),
	&"scale": Color(0.46, 0.68, 1.0, 1.0),
	&"open_speed": Color(1.0, 0.6, 0.3, 1.0),
	&"recruit": Color(0.92, 0.82, 0.55, 1.0),
}

var _selected_building: StringName = &""   ## "" = show all built buildings
var _gold_label: Label
var _grid: GridContainer
var _grid_tiles: Dictionary = {}            ## building id → Button
var _upgrade_list: VBoxContainer
## building id → {"header": Label, "cards": Array[Dictionary]}
var _groups: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(480.0, 0.0)
	custom_minimum_size = Vector2(PANEL_WIDTH, 360.0)
	offset_left = 480.0
	offset_top = 0.0
	offset_right = 640.0
	offset_bottom = 360.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())
	_build_layout()
	_connect_events()
	_refresh()


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
func _build_layout() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	add_child(root)

	_gold_label = _make_label("Gold 0", 13, Color(1.0, 0.91, 0.48, 1.0))
	root.add_child(_gold_label)

	# Layer 1: village grid.
	root.add_child(_make_label("마을", 10, Color(0.86, 0.9, 0.82, 1.0)))
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	root.add_child(_grid)
	for i in Balance.building_count():
		_add_grid_tile(Balance.building_at(i))

	root.add_child(HSeparator.new())
	root.add_child(_make_label("강화", 10, Color(0.86, 0.9, 0.82, 1.0)))

	# Layer 2: upgrade list (per-building groups, visibility-toggled).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_upgrade_list = VBoxContainer.new()
	_upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_upgrade_list)
	for i in Balance.building_count():
		_add_upgrade_group(Balance.building_at(i))


# ─── Layer 1: grid tiles ───────────────────────────────────────────────
func _add_grid_tile(building: Dictionary) -> void:
	var id: StringName = building["id"]
	var tile := Button.new()
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = TILE_SIZE
	tile.text = ""
	tile.pressed.connect(_on_tile_pressed.bind(id))

	var glyph := _make_label(str(building.get("short", "?")), 13, Color.WHITE)
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(glyph)

	var tag := _make_label("", 7, Color(1.0, 0.92, 0.6, 1.0))
	tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tag.offset_top = -9.0
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.add_child(tag)

	_grid_tiles[id] = {"button": tile, "glyph": glyph, "tag": tag}
	_grid.add_child(tile)


func _on_tile_pressed(id: StringName) -> void:
	if GameState.is_building_built(id):
		# Toggle the list filter onto / off this building.
		_selected_building = &"" if _selected_building == id else id
		_refresh()
	else:
		# Empty slot → build it (no-op if locked or unaffordable).
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
		var unlocked: bool = GameState.is_building_unlocked(id)
		var selected: bool = built and _selected_building == id

		glyph.text = str(building.get("short", "?"))
		if built:
			tile.add_theme_stylebox_override("normal", _tile_style(2, accent, selected))
			tile.add_theme_stylebox_override("hover", _tile_style(2, accent, true))
			tile.add_theme_stylebox_override("pressed", _tile_style(2, accent, true))
			glyph.add_theme_color_override("font_color", Color.WHITE)
			tag.text = "필터" if selected else ""
			tag.visible = selected
			tag.add_theme_color_override("font_color", accent)
			tile.tooltip_text = "%s — 지어짐\n%s\n클릭: 강화 필터 %s" % [building["name"], building.get("desc", ""), "해제" if selected else "보기"]
		elif unlocked:
			tile.add_theme_stylebox_override("normal", _tile_style(1, accent, false))
			tile.add_theme_stylebox_override("hover", _tile_style(1, accent, true))
			tile.add_theme_stylebox_override("pressed", _tile_style(1, accent, false))
			glyph.add_theme_color_override("font_color", Color(0.85, 0.87, 0.8, 1.0))
			var cost: int = GameState.building_cost(id)
			tag.text = "+%d" % cost
			tag.visible = true
			tag.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6, 1.0) if GameState.gold >= cost else Color(0.7, 0.55, 0.4, 1.0))
			tile.tooltip_text = "%s — 짓기 %dG\n%s" % [building["name"], cost, building.get("desc", "")]
		else:
			tile.add_theme_stylebox_override("normal", _tile_style(0, accent, false))
			tile.add_theme_stylebox_override("hover", _tile_style(0, accent, false))
			tile.add_theme_stylebox_override("pressed", _tile_style(0, accent, false))
			glyph.add_theme_color_override("font_color", Color(0.4, 0.4, 0.44, 1.0))
			tag.text = "잠김"
			tag.visible = true
			tag.add_theme_color_override("font_color", Color(0.5, 0.5, 0.54, 1.0))
			tile.tooltip_text = "%s — 잠김\n%s" % [building["name"], _unlock_hint(building)]


func _unlock_hint(building: Dictionary) -> String:
	var cond: Dictionary = building.get("unlock", {})
	var need: int = int(cond.get("value", 0))
	match StringName(cond.get("type", &"")):
		&"kills": return "적 %d처치 시 해금" % need
		&"downs": return "동료 %d회 쓰러지면 해금" % need
		&"gold_earned": return "누적 %dG 모으면 해금" % need
	return "해금 조건 미정"


# ─── Layer 2: upgrade groups ───────────────────────────────────────────
func _add_upgrade_group(building: Dictionary) -> void:
	var id: StringName = building["id"]
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	_upgrade_list.add_child(box)

	var header := _make_label(str(building["name"]), 9, building.get("color", Color.WHITE))
	box.add_child(header)

	var cards: Array[Dictionary] = []
	for desc: Dictionary in building.get("upgrades", []):
		var kind: StringName = desc["kind"]
		if kind == &"weapons":
			# One card per weapon type (shown only for types the party wields).
			for t in Balance.weapon_type_count():
				cards.append(_make_upgrade_card(id, &"weapons", box, Balance.weapon_type_at(t)["id"]))
		elif kind == &"recruit":
			cards.append(_make_upgrade_card(id, &"recruit", box, StringName(desc.get("companion", &""))))
		else:
			cards.append(_make_upgrade_card(id, kind, box, &""))

	_groups[id] = {"header": header, "cards": cards}


## Builds one upgrade card and returns its descriptor for refresh.
func _make_upgrade_card(building_id: StringName, kind: StringName, parent: VBoxContainer, param: StringName) -> Dictionary:
	var accent: Color = KIND_COLOR.get(kind, Color.WHITE)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(accent))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	card.add_child(box)
	var title := _make_label("", 9, accent)
	box.add_child(title)
	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 20.0)
	button.add_theme_font_override("font", PANEL_FONT)
	button.add_theme_font_size_override("font_size", 8)
	button.pressed.connect(_on_card_pressed.bind(kind, param))
	box.add_child(button)
	return {"building": building_id, "kind": kind, "param": param, "card": card, "title": title, "button": button}


func _on_card_pressed(kind: StringName, param: StringName) -> void:
	match kind:
		&"weapons":
			GameState.upgrade_weapon(param)
		&"armor":
			GameState.upgrade_armor()
		&"greed":
			GameState.upgrade_greed()
		&"scale":
			GameState.upgrade_scale()
		&"open_speed":
			GameState.upgrade_open_speed()
		&"recruit":
			GameState.recruit_companion(param)


func _refresh_groups() -> void:
	for i in Balance.building_count():
		var id: StringName = Balance.building_at(i)["id"]
		var group: Dictionary = _groups[id]
		# A building's group shows when it's built AND passes the filter.
		var shown: bool = GameState.is_building_built(id) and (_selected_building == &"" or _selected_building == id)
		group["header"].visible = shown
		for card: Dictionary in group["cards"]:
			_refresh_card(card, shown)


func _refresh_card(card: Dictionary, group_shown: bool) -> void:
	var kind: StringName = card["kind"]
	var param: StringName = card["param"]
	var title: Label = card["title"]
	var button: Button = card["button"]
	var panel: PanelContainer = card["card"]
	var vis: bool = group_shown
	match kind:
		&"weapons":
			vis = group_shown and GameState.owned_weapon_types().has(param)
			if vis:
				var tname: String = str(Balance.weapon_type_by_id(param).get("name", "무기"))
				title.text = "%s · %s ×%s" % [tname, GameState.current_weapon_name(param), _fmt_mult(GameState.weapon_attack_multiplier(param))]
				var nmult: float = Balance.effect_multiplier(GameState.weapon_level(param) + 1)
				_set_buy_button(button, "%s ×%s  %dG" % [GameState.next_weapon_name(param), _fmt_mult(nmult), GameState.weapon_upgrade_cost(param)], GameState.can_upgrade_weapon(param))
		&"armor":
			if vis:
				title.text = "방어구 Lv%d · 방어 +%d" % [GameState.armor_level, GameState.armor_defense_bonus()]
				var nd: int = Balance.armor_defense_for_level(GameState.armor_level + 1)
				_set_buy_button(button, "%s 방어+%d  %dG" % [GameState.next_armor_name(), nd, GameState.armor_upgrade_cost()], GameState.can_upgrade_armor())
		&"greed":
			if vis:
				title.text = "골드 ×%s" % _fmt_mult(GameState.greed_gold_multiplier())
				var nm: float = Balance.effect_multiplier(GameState.greed_level + 1)
				_set_buy_button(button, "다음 ×%s  %dG" % [_fmt_mult(nm), GameState.greed_upgrade_cost()], GameState.can_upgrade_greed())
		&"scale":
			if vis:
				title.text = "전투창 %d개" % GameState.scale_window_count()
				if GameState.scale_is_maxed():
					_set_buy_button(button, "최대", false)
				else:
					var nc: int = Balance.scale_window_count(GameState.scale_purchases + 1)
					_set_buy_button(button, "+창 → %d개  %dG" % [nc, GameState.scale_upgrade_cost()], GameState.can_upgrade_scale())
		&"open_speed":
			if vis:
				title.text = "보상 개봉 %.2fs" % GameState.chest_hover_duration()
				if GameState.open_speed_is_maxed():
					_set_buy_button(button, "개봉 최속", false)
				else:
					var nd2: float = Balance.chest_open_duration(GameState.open_speed_level + 1)
					_set_buy_button(button, "개봉↑ %.2fs  %dG" % [nd2, GameState.open_speed_upgrade_cost()], GameState.can_upgrade_open_speed())
		&"recruit":
			if vis:
				var cname: String = str(Balance.companion_by_id(param).get("name", "동료"))
				var trait_id: StringName = Balance.character_trait(param)
				title.text = "%s · %s" % [cname, str(Balance.TRAIT_NAMES.get(trait_id, ""))]
				if GameState.is_companion_recruited(param):
					_set_buy_button(button, "영입됨", false)
				else:
					_set_buy_button(button, "영입  %dG" % GameState.companion_recruit_cost(param), GameState.can_recruit_companion(param))
	panel.visible = vis


# ─── Refresh entry ─────────────────────────────────────────────────────
func _refresh() -> void:
	_gold_label.text = "Gold %d" % GameState.gold
	_refresh_grid()
	_refresh_groups()


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


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.038, 0.045, 1.0)
	style.border_width_left = 1
	style.border_color = Color(0.78, 0.86, 0.72, 1.0)
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style


func _card_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.13, 1.0)
	style.border_width_left = 2
	style.border_color = accent
	style.set_corner_radius_all(2)
	style.content_margin_left = 5
	style.content_margin_top = 3
	style.content_margin_right = 5
	style.content_margin_bottom = 3
	return style


## Grid tile background. state: 0 locked / 1 buildable / 2 built.
func _tile_style(state: int, accent: Color, highlight: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_border_width_all(2)
	match state:
		2:  # built
			style.bg_color = accent.darkened(0.55)
			style.border_color = accent
		1:  # buildable
			style.bg_color = Color(0.12, 0.13, 0.15, 1.0)
			style.border_color = accent.darkened(0.25)
		_:  # locked
			style.bg_color = Color(0.08, 0.085, 0.09, 1.0)
			style.border_color = Color(0.24, 0.25, 0.27, 1.0)
	if highlight:
		style.bg_color = style.bg_color.lightened(0.12)
	return style
