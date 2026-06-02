class_name LeftEnemyBar
extends Control

## Left dock — styled like the macOS dock.
##   • A smooth translucent rounded panel floats off the left edge (the field
##     shows through). Rendered at native resolution via the project's
##     `canvas_items` stretch, so corners/translucency are crisp, not pixelated.
##   • The ICONS are 16-ish px pixel-art (nearest filter) — sharp pixels on a
##     smooth tray, the macOS contrast.
##   • Hover magnification (distance falloff to neighbors) + tooltip.
##   • Active dot beside toggled-ON enemies (the "running" dot).
## Behavior is UNCHANGED — same toggle / unlock / place / upgrade calls.

const PANEL_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const DOCK_MARGIN_LEFT: float = 5.0
const DOCK_TOP_MARGIN: float = 6.0   ## top-aligned (matches the right panel's top)
const DOCK_PAD: float = 7.0
const ICON_BASE: float = 18.0      ## resting display size
const ICON_MAG: float = 30.0       ## magnified size under the cursor
const SLOT: float = 24.0           ## fixed vertical slot per icon
const SLOT_SPACING: float = 3.0
const MAG_RANGE: float = 54.0      ## vertical falloff distance of magnification
const DIVIDER_H: float = 8.0
const SCALE_LERP: float = 16.0     ## magnification smoothing

## Each item: {id, kind(&"enemy"/&"tile"), slot:Control, icon:Control, dot:Control,
##             center_y:float (in self-space), tier/tile dict}
var _items: Array[Dictionary] = []
## The enemy tier ids currently built into the dock (visible ones only). When the
## visible set grows — a tier crosses its cumulative-gold milestone — we rebuild.
var _built_enemy_ids: Array[StringName] = []
## Whether the dock was built in the post-world-start layout (enemies + campfire)
## vs the opening layout (just the grass tile). Rebuild when it flips.
var _built_world_started: bool = false
## Whether the dock was built with the name already entered (grass tile shows).
var _built_name_entered: bool = false
## Deadlock state: gold 0, no enemies / fights / loot left → the run can't make
## money. When true the dock offers ONE free "rescue slime" at the top. Polled in
## _process; flipping it rebuilds the dock (show/hide the rescue slot).
var _was_deadlocked: bool = false
var _built_deadlocked: bool = false
var _pulse_t: float = 0.0
var _dock_panel: Panel
## Custom macOS-style tooltip (pill + left tail) shown to the RIGHT of the
## hovered icon. Drawn on the smooth UI layer.
var _tooltip: Control
var _tooltip_pill: Panel
var _tooltip_label: Label
var _tooltip_tail: Polygon2D
const TOOLTIP_FONT: int = 9
const TOOLTIP_PAD: float = 5.0
const TOOLTIP_GAP: float = 3.0      ## space between icon and tail tip
const TOOLTIP_TAIL_W: float = 5.0
const TOOLTIP_TAIL_H: float = 8.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	custom_minimum_size = Vector2(50.0, 360.0)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 50.0
	offset_bottom = 360.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the dock slots catch input
	clip_contents = false
	_build()
	EventBus.gold_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))
	EventBus.enemy_progress_changed.connect(_on_changed.unbind(1))
	EventBus.enemy_leveled_up.connect(_on_changed.unbind(2))
	EventBus.campfire_placed.connect(_on_changed)
	EventBus.world_started.connect(_on_changed)
	EventBus.player_named.connect(_on_changed.unbind(1))
	set_process(true)
	_refresh()


func _on_changed() -> void:
	_refresh()


# ─── Build the dock ────────────────────────────────────────────────────
## Only VISIBLE enemy tiers get a slot (locked-below-threshold tiers are blank /
## absent). Tiles (campfire) are always shown.
func _visible_enemy_tiers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not GameState.world_started:
		return out  # opening: no enemies until the grass is laid
	for i in Balance.tier_count():
		var tier: Dictionary = Balance.tier_at(i)
		if GameState.is_tier_visible(tier["id"]):
			out.append(tier)
	return out


## Tiles below the enemy roster: before the world starts → ONLY the grass
## world-start tile; after → the campfire (and future) tiles.
func _dock_tiles() -> Array[Dictionary]:
	if not GameState.world_started:
		# Opening: nothing until the hero is named, then ONLY the grass tile.
		if not GameState.name_entered:
			return []
		return [{"id": &"grass", "name": "초원", "short": "초",
			"color": Color(0.55, 0.85, 0.42, 1.0), "kind": &"grass"}]
	var out: Array[Dictionary] = []
	for i in Balance.tile_count():
		out.append(Balance.tile_at(i))
	return out


func _build() -> void:
	_built_world_started = GameState.world_started
	_built_name_entered = GameState.name_entered
	_built_deadlocked = _was_deadlocked
	var enemy_tiers: Array[Dictionary] = _visible_enemy_tiers()
	_built_enemy_ids.clear()
	for tier: Dictionary in enemy_tiers:
		_built_enemy_ids.append(tier["id"])
	var tiles: Array[Dictionary] = _dock_tiles()
	var rescue: bool = _was_deadlocked
	var rescue_n: int = 1 if rescue else 0
	var enemy_n: int = enemy_tiers.size()
	var tile_n: int = tiles.size()
	var total: int = rescue_n + enemy_n + tile_n
	# One divider between each pair of adjacent non-empty sections (rescue|enemies|tiles).
	var sections: int = (1 if rescue_n > 0 else 0) + (1 if enemy_n > 0 else 0) + (1 if tile_n > 0 else 0)
	var dividers: int = maxi(0, sections - 1)
	var height: float = DOCK_PAD * 2.0 + total * SLOT + maxf(0.0, total - 1) * SLOT_SPACING + dividers * DIVIDER_H
	var dock_w: float = SLOT + DOCK_PAD * 2.0
	var y0: float = DOCK_TOP_MARGIN  # top-aligned with the right panel

	_dock_panel = Panel.new()
	_dock_panel.add_theme_stylebox_override("panel", _dock_style())
	_dock_panel.position = Vector2(DOCK_MARGIN_LEFT, y0)
	_dock_panel.size = Vector2(dock_w, height)
	_dock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_panel.clip_contents = false
	add_child(_dock_panel)

	var cx: float = dock_w * 0.5
	var cy: float = DOCK_PAD
	var placed_section: bool = false
	# Rescue slime — pinned at the TOP so the way out is the first thing you see.
	if rescue:
		_add_item(&"rescue", _rescue_data(), Vector2(cx, cy + SLOT * 0.5), _slime_texture(), y0)
		cy += SLOT + SLOT_SPACING
		placed_section = true
	if enemy_n > 0:
		if placed_section:
			_add_divider(Vector2(cx, cy + DIVIDER_H * 0.5), dock_w)
			cy += DIVIDER_H
		for tier: Dictionary in enemy_tiers:
			_add_item(&"enemy", tier, Vector2(cx, cy + SLOT * 0.5), _tier_texture(tier), y0)
			cy += SLOT + SLOT_SPACING
		placed_section = true
	if tile_n > 0:
		if placed_section:
			_add_divider(Vector2(cx, cy + DIVIDER_H * 0.5), dock_w)
			cy += DIVIDER_H
		for tile: Dictionary in tiles:
			var tk: StringName = StringName(tile.get("kind", &"tile"))
			_add_item(tk, tile, Vector2(cx, cy + SLOT * 0.5), null, y0)
			cy += SLOT + SLOT_SPACING
		placed_section = true
	_build_tooltip()


## Tear the dock down and rebuild it — used when a tier crosses its milestone and
## a new slot must appear (the slot list is positioned in one pass in _build).
func _rebuild() -> void:
	if _dock_panel != null:
		_dock_panel.queue_free()
		_dock_panel = null
	if _tooltip != null:
		_tooltip.queue_free()
		_tooltip = null
	_items.clear()
	_build()


func _add_divider(center: Vector2, dock_w: float) -> void:
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.14)
	line.size = Vector2(dock_w * 0.55, 1.0)
	line.position = center - line.size * 0.5
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_panel.add_child(line)


func _add_item(kind: StringName, data: Dictionary, center: Vector2, texture: Texture2D, y0: float) -> void:
	var id: StringName = data["id"]
	var slot := Control.new()
	slot.size = Vector2(SLOT, SLOT)
	slot.position = center - slot.size * 0.5
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.clip_contents = false
	slot.gui_input.connect(_on_item_input.bind(kind, id))
	_dock_panel.add_child(slot)

	var icon: Control
	if texture != null:
		var tr := TextureRect.new()
		tr.texture = texture
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel art
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(ICON_BASE, ICON_BASE)
		tr.position = (slot.size - tr.size) * 0.5
		tr.pivot_offset = tr.size * 0.5
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tr)
		icon = tr
	else:
		var lb := _make_label(str(data.get("short", "?")), 13, data.get("color", Color.WHITE))
		lb.size = Vector2(ICON_BASE, ICON_BASE)
		lb.position = (slot.size - lb.size) * 0.5
		lb.pivot_offset = lb.size * 0.5
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(lb)
		icon = lb

	# Active "running" dot — a small round pip OUTSIDE the icon's left (screen-edge
	# side), exactly where macOS puts its running indicator.
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", _dot_style(Color(1.0, 1.0, 0.95, 1.0)))  # bright — pops on the green tray
	dot.size = Vector2(4.0, 4.0)
	dot.position = Vector2(-3.0, SLOT * 0.5 - 2.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.visible = false
	slot.add_child(dot)

	# Tiles (campfire) show their gold price pinned to the bottom edge of the
	# slot — like the right-panel cards — so you can see what it costs to place.
	var price: Label = null
	if kind == &"tile":
		price = _make_label("", 6, Color(1.0, 0.92, 0.55, 1.0))
		price.size = Vector2(SLOT, 7.0)
		price.position = Vector2(0.0, SLOT - 1.0)  # tucked into the bottom pad, below the glyph
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_child(price)

	_items.append({
		"id": id, "kind": kind, "slot": slot, "icon": icon, "dot": dot, "price": price,
		"center_y": y0 + slot.position.y + SLOT * 0.5,
		"right_x": DOCK_MARGIN_LEFT + center.x + SLOT * 0.5,  # tooltip anchor (icon right)
		"data": data,
	})


# ─── Magnification + tooltip (macOS dock) ──────────────────────────────
func _process(delta: float) -> void:
	_pulse_t += delta
	var pulse: float = (sin(_pulse_t * 5.0) + 1.0) * 0.5  # 0..1 glow for claimable
	var mouse: Vector2 = get_local_mouse_position()
	var over: bool = _dock_panel != null and Rect2(_dock_panel.position, _dock_panel.size).grow(14.0).has_point(mouse)
	var grow: float = ICON_MAG / ICON_BASE
	var hovered: Dictionary = {}
	for item: Dictionary in _items:
		var target: float = 1.0
		if over:
			var t: float = maxf(0.0, 1.0 - absf(mouse.y - float(item["center_y"])) / MAG_RANGE)
			target = lerpf(1.0, grow, t * t)  # eased falloff
			# The icon whose fixed slot the cursor is in owns the tooltip.
			if _slot_rect(item).has_point(mouse):
				hovered = item
		var icon: Control = item["icon"]
		var cur: float = icon.scale.x
		icon.scale = Vector2.ONE * lerpf(cur, target, clampf(delta * SCALE_LERP, 0.0, 1.0))
		# Pulse claimable ("해금!") icons so the new unlock is unmissable.
		if item.get("claimable", false):
			icon.modulate = Color(1.0, 0.9, 0.45, 1.0).lerp(Color(1.0, 1.0, 0.8, 1.0), pulse)
		# The rescue slime pulses a hopeful green so the way out stands out.
		elif item["kind"] == &"rescue":
			icon.modulate = Color(0.55, 1.0, 0.5, 1.0).lerp(Color(0.95, 1.0, 0.85, 1.0), pulse)
	if hovered.is_empty():
		_tooltip.visible = false
	else:
		_show_tooltip(hovered)
	_check_deadlock()


# ─── Deadlock rescue ("구제 슬라임") ─────────────────────────────────────
## True when the run is stuck: world running, gold can't even buy the cheapest
## enemy (slime), and nothing is in progress to earn more (no live enemies, no
## active fights, no uncollected loot). Polled cheaply each frame.
func _is_deadlocked() -> bool:
	if not GameState.world_started:
		return false
	if GameState.gold >= GameState.tier_place_cost(&"slime"):
		return false  # can still afford to place → not stuck
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	if not tree.get_nodes_in_group("field_enemy").is_empty():
		return false  # something alive to kill → gold incoming
	if not tree.get_nodes_in_group("field_pickup").is_empty():
		return false  # loot on the ground → gold within reach
	var bm: Node = tree.get_first_node_in_group("battle_manager")
	if bm != null and bm.has_method("active_window_count") and int(bm.active_window_count()) > 0:
		return false  # a fight is still resolving
	return true


## Detect deadlock onset/clear each frame; rebuild the dock so the rescue slot
## appears/disappears, and flash the "[저런..]" intervention line on onset.
func _check_deadlock() -> void:
	var dl: bool = _is_deadlocked()
	if dl == _was_deadlocked:
		return
	_was_deadlocked = dl
	if dl:
		EventBus.rescue_offered.emit()  # Field flashes "[저런..]"
	_rebuild()


## The synthetic dock entry for the free rescue slime.
func _rescue_data() -> Dictionary:
	return {"id": &"slime", "name": "구제 슬라임", "short": "슬",
		"color": Color(0.7, 1.0, 0.55, 1.0), "kind": &"rescue",
		"enemy_res": str(Balance.tier_by_id(&"slime").get("enemy_res", ""))}


## The slime sprite, reused for the rescue icon.
func _slime_texture() -> Texture2D:
	return _tier_texture(Balance.tier_by_id(&"slime"))


## A slot's rect in self-space (slots live inside _dock_panel).
func _slot_rect(item: Dictionary) -> Rect2:
	var slot: Control = item["slot"]
	return Rect2(_dock_panel.position + slot.position, slot.size)


# ─── Custom tooltip (pill + left tail, frosted bright) ─────────────────
func _build_tooltip() -> void:
	_tooltip = Control.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.z_index = 50  # above icons
	_tooltip.visible = false
	add_child(_tooltip)
	# Left-pointing tail (tip at _tooltip origin).
	_tooltip_tail = Polygon2D.new()
	_tooltip_tail.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(TOOLTIP_TAIL_W, -TOOLTIP_TAIL_H * 0.5),
		Vector2(TOOLTIP_TAIL_W, TOOLTIP_TAIL_H * 0.5),
	])
	_tooltip_tail.color = Color(0.95, 0.96, 0.99, 0.86)
	_tooltip.add_child(_tooltip_tail)
	# Pill (bright translucent rounded — frosted look over the dark field).
	_tooltip_pill = Panel.new()
	_tooltip_pill.add_theme_stylebox_override("panel", _pill_style())
	_tooltip_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_pill)
	_tooltip_label = _make_label("", TOOLTIP_FONT, Color(0.09, 0.1, 0.13, 1.0))
	_tooltip_label.remove_theme_color_override("font_shadow_color")
	_tooltip_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.4))
	_tooltip_pill.add_child(_tooltip_label)


func _show_tooltip(item: Dictionary) -> void:
	var name_text: String = str(item["data"].get("name", "?"))
	var kind: StringName = item["kind"]
	var id: StringName = item["id"]
	if kind == &"grass":
		name_text = "초원 깔기"
	elif kind == &"rescue":
		name_text = "구제 슬라임  무료"
	elif kind == &"enemy":
		if GameState.is_tier_unlock_available(id):
			name_text = "%s 해금!" % name_text
		elif GameState.is_tier_unlocked(id):
			name_text = "%s  %dG" % [name_text, GameState.tier_place_cost(id)]  # 배치 비용
	_tooltip_label.text = name_text
	var text_w: float = PANEL_FONT.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, TOOLTIP_FONT).x
	var pill_w: float = text_w + TOOLTIP_PAD * 2.0
	var pill_h: float = float(TOOLTIP_FONT) + TOOLTIP_PAD * 1.6
	_tooltip.position = Vector2(float(item["right_x"]) + TOOLTIP_GAP, float(item["center_y"]))
	_tooltip_pill.position = Vector2(TOOLTIP_TAIL_W - 0.5, -pill_h * 0.5)
	_tooltip_pill.size = Vector2(pill_w, pill_h)
	_tooltip_label.position = Vector2(TOOLTIP_PAD, (pill_h - float(TOOLTIP_FONT)) * 0.5 - 1.0)
	_tooltip.visible = true


# ─── Click — grass starts the world; enemy click PLACES one (claim first) ──
func _on_item_input(event: InputEvent, kind: StringName, id: StringName) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if kind == &"grass":
		GameState.start_world()  # opening: lay the first grass → hero moves, enemies appear
	elif kind == &"rescue":
		GameState.place_rescue_slime()  # free slime → field_enemy appears → deadlock clears
	elif kind == &"enemy":
		if GameState.is_tier_unlocked(id):
			GameState.place_enemy(id)   # click-to-place: -place_cost gold → 1 spawns
		else:
			GameState.unlock_tier(id)   # claim the milestone-reached tier first
	elif kind == &"tile" and id == &"campfire":
		if GameState.campfire_placed:
			GameState.upgrade_campfire()
		else:
			GameState.place_campfire()


# ─── Refresh (state visuals + tooltips) ────────────────────────────────
func _refresh() -> void:
	# Name-entry (empty → grass tile) and world-start (grass → enemy roster) both
	# flip the whole layout; a tier crossing its milestone changes enemy slots.
	if _built_name_entered != GameState.name_entered or _built_world_started != GameState.world_started:
		_rebuild()
		return
	var desired: Array[StringName] = []
	for tier: Dictionary in _visible_enemy_tiers():
		desired.append(tier["id"])
	if desired != _built_enemy_ids:
		_rebuild()
		return
	for item: Dictionary in _items:
		if item["kind"] == &"enemy":
			_refresh_enemy(item)
		else:
			_refresh_tile(item)


func _refresh_enemy(item: Dictionary) -> void:
	# Visual state only — name/price live in the custom tooltip (_show_tooltip).
	# States: claimable(해금 가능, gold pulse) / placeable(밝게) / 못 사면(어둡게).
	var id: StringName = item["id"]
	var icon: Control = item["icon"]
	var dot: Control = item["dot"]
	var claimable: bool = GameState.is_tier_unlock_available(id)
	item["claimable"] = claimable
	if claimable:
		# "해금!" — bright gold, gold pip; _process pulses it to draw the eye.
		icon.modulate = Color(1.0, 0.92, 0.5, 1.0)
		dot.add_theme_stylebox_override("panel", _dot_style(Color(1.0, 0.85, 0.3, 1.0)))
		dot.visible = true
		return
	# Unlocked → click-to-place: bright when you can afford it, dim when too poor.
	dot.visible = false
	if GameState.can_place_enemy(id):
		icon.modulate = Color(1, 1, 1, 1)
	else:
		icon.modulate = Color(0.45, 0.45, 0.5, 0.7)  # can't afford the place cost


func _refresh_tile(item: Dictionary) -> void:
	var id: StringName = item["id"]
	var icon: Control = item["icon"]
	var dot: Panel = item["dot"]
	var price: Label = item.get("price", null)
	if id != &"campfire":
		return
	var placed: bool = GameState.campfire_placed
	dot.visible = placed
	dot.add_theme_stylebox_override("panel", _dot_style(Color(1.0, 0.7, 0.35, 1.0)))  # warm fire pip
	# Price + affordability: placed → upgrade cost, else → place cost. Bright when
	# you can afford it, dim when you can't (so you see why it won't drop yet).
	var cost: int = GameState.campfire_upgrade_cost() if placed else GameState.campfire_place_cost()
	var affordable: bool = GameState.gold >= cost
	if price != null:
		price.text = "%dG" % cost
		price.add_theme_color_override("font_color",
			Color(1.0, 0.92, 0.55, 1.0) if affordable else Color(0.6, 0.55, 0.45, 0.85))
	if placed:
		icon.modulate = Color(1, 1, 1, 1)
	elif affordable:
		icon.modulate = Color(1, 1, 1, 1)
	else:
		icon.modulate = Color(0.5, 0.48, 0.45, 0.7)  # can't afford: dimmed


# ─── Helpers / styles ──────────────────────────────────────────────────
func _tier_texture(tier: Dictionary) -> Texture2D:
	var path: String = str(tier.get("enemy_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var ed := load(path) as EnemyData
	return ed.sprite if ed != null else null


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


## Bold COLORED floating tray — vivid green, fully OPAQUE, no shadow (matches the
## right-panel cards' punchy fill). Sprite icons read on top.
func _dock_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.62, 0.34, 1.0)
	style.set_corner_radius_all(11)
	style.set_border_width_all(1)
	style.border_color = Color(0.75, 1.0, 0.82, 0.55)
	return style


## Round running-indicator pip.
func _dot_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(3)  # ≥ half of the 4px dot → circle
	return style


## Bright translucent "frosted" pill (rounded, soft border + shadow). Real
## gaussian blur would need a backbuffer shader; the bright translucency over the
## dark field reads as frosted glass and stays smooth at native resolution.
func _pill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.96, 0.99, 0.86)
	style.set_corner_radius_all(7)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.55)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 4
	return style
