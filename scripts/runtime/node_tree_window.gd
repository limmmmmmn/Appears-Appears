class_name NodeTreeWindow
extends Control

## 세계 지도 — the node tree IS a pannable world map, 도르프로만틱 갬성 with the
## bottom control bar of "A Game About Feeding A Black Hole":
##   · big EXTRUDED hexes that float (side face + soft shadow), icons not labels
##   · GHOST tiles on the rim hint what's next; hover = the tile LIFTS + a bright
##     card above it + the cost shows in the bottom bar (focused-cost readout)
##   · the hero's avatar lives on the map and WALKS to every tile you unlock
##   · [WASD] pan / [drag] move the map / [click] unlock / [SPACE] next wave
## Settlement gold is spent here; [다음 웨이브] releases the freeze.

const HEX_SIZE: float = 44.0          ## flat-top circumradius (tile width = 2×)
const SQUASH: float = 0.66            ## vertical squash → the pressed 도르프 3D look
const BUILT_RAISE: float = 3.0        ## placed tiles sit THIS slightly above ghosts
const HERO_TRAVEL_SPEED: float = 150.0  ## px/s walking to a newly unlocked tile
const HERO_WANDER_SPEED: float = 26.0   ## px/s idle-strolling inside the tile
const PAN_KEY_SPEED: float = 360.0    ## WASD pan px/sec
const NODE_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
const INK: Color = Color(0.08627451, 0.08235294, 0.09411765, 1.0)
const CREAM: Color = Color(0.96862745, 0.9411765, 0.87058824, 1.0)
const GHOST_FILL: Color = Color(0.95, 0.92, 0.86, 1.0)
const GHOST_BORDER: Color = Color(0.72, 0.66, 0.58, 1.0)
const GHOST_TEXT: Color = Color(0.45, 0.4, 0.34, 1.0)   ## dim label text (slots, empty, …)
const GOLD_TEXT: Color = Color(0.62, 0.45, 0.1, 1.0)
const ROAD_FILL: Color = Color(0.82, 0.72, 0.54, 1.0)
const SHADOW_COLOR: Color = Color(0.3, 0.2, 0.1, 0.2)
const AXIS_COLORS: Dictionary = {
	&"enemy": Color(0.95, 0.55, 0.47, 1.0),
	&"ally": Color(0.55, 0.7, 0.93, 1.0),
	&"loot": Color(0.95, 0.8, 0.42, 1.0),
	&"hook": Color(0.72, 0.62, 0.9, 1.0),
}
const WALK_FRAME_SEQ: Array[int] = [0, 1, 2, 1]

@onready var _map_wrap: Control = %MapWrap
@onready var _gold_label: Label = %GoldLabel
@onready var _map: Control = %Map
@onready var _overlay: Control = %Overlay
@onready var _cost_label: Label = %CostLabel
@onready var _next_button: Button = %NextButton
@onready var _map_tab_button: Button = %MapTabButton
@onready var _gear_tab_button: Button = %GearTabButton
@onready var _gear_panel: ScrollContainer = %GearPanel
@onready var _gear_content: VBoxContainer = %GearContent

var _gear_tab_active: bool = false
var _hex_roots: Dictionary = {}
var _pop_id: StringName = &""
var _walk_target_hex: Vector2i = Vector2i.ZERO
var _walk_pending: bool = false
var _hero_marker: TextureRect
# Hero roam/travel state (all in map-local coords, panned with the tiles)
var _hero_home_hex: Vector2i = Vector2i.ZERO
var _hero_target: Vector2 = Vector2.ZERO
var _hero_wait: float = 0.0
var _hero_traveling: bool = false
var _hero_facing: int = 0
var _hero_anim_time: float = 0.0
# 동료들이 월드맵에서 용사 아바타를 스네이크로 따라다닌다 (party slots 1+).
var _party_markers: Array[TextureRect] = []
var _pending_recruit_hex: Vector2i = Vector2i(99, 99)  ## tile a just-bought companion waits on (99,99 = none)
var _shadow_layer: Control
var _hover_tip: PanelContainer
var _tip_band_style: StyleBoxFlat
var _tip_title_label: Label
var _tip_body_label: Label
var _tip_cost_label: Label
# Pan state
var _pan_offset: Vector2 = Vector2.ZERO
var _content_min: Vector2 = Vector2.ZERO
var _content_max: Vector2 = Vector2.ZERO
var _dragging: bool = false


func _ready() -> void:
	add_to_group("node_tree_window")
	visible = false
	set_process(false)
	_next_button.pressed.connect(_on_next_wave)
	_map_tab_button.pressed.connect(_show_tab.bind(false))
	_gear_tab_button.pressed.connect(_show_tab.bind(true))
	EventBus.gold_changed.connect(_on_state_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_state_changed.unbind(1))
	EventBus.inventory_changed.connect(_on_gear_changed)
	EventBus.party_equipment_changed.connect(_on_gear_changed.unbind(1))


func open() -> void:
	visible = true
	set_process(true)
	_show_tab(false)  # always land on the map first
	await get_tree().process_frame  # flush layout so _map.size is real
	_render()
	_snap_hero_marker()
	_sync_party_markers()
	_center_on_hero()
	# Curtain: the table fades in, the island settles out of it.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.16)


## [세계 지도] ↔ [파티·장비] — same screen, two desks: spend on land, or kit
## the party out (사고/팔고/끼우고/해제).
func _show_tab(gear: bool) -> void:
	_gear_tab_active = gear
	_map_wrap.visible = not gear
	_gear_panel.visible = gear
	_map_tab_button.disabled = not gear   # disabled = the ACTIVE tab (pressed look)
	_gear_tab_button.disabled = gear
	_hide_tip()
	if gear:
		_render_gear()


func _on_state_changed() -> void:
	if not visible:
		return
	_render()
	if _gear_tab_active:
		_render_gear()


func _on_gear_changed() -> void:
	if visible and _gear_tab_active:
		_render_gear()


func _on_next_wave() -> void:
	_hide_tip()
	visible = false
	set_process(false)
	GameState.close_event_window()
	GameState.start_next_wave()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_on_next_wave()
		get_viewport().set_input_as_handled()


# ─── Panning ────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	# WASD/arrows pan the map (the field is frozen, so these keys are free).
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		_pan_offset -= dir * PAN_KEY_SPEED * delta
		_apply_pan()
	_tick_hero(delta)
	_tick_party_followers(delta)


## Drag-pan via _input (runs before GUI): we never CONSUME the press, so tile
## buttons still get their click — but a drag moves the mouse off the button,
## which Godot auto-cancels, so a dragged press never fires a buy. Best of both.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _map_wrap.get_global_rect().has_point(event.position):
			_dragging = true
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_pan_offset += event.relative
		_apply_pan()
		_hide_tip()  # the card would drift while dragging


func _apply_pan() -> void:
	# Keep the island reachable: clamp so its bbox always overlaps the viewport.
	var vw: Vector2 = _map_wrap.size
	var content_w: float = _content_max.x - _content_min.x
	var content_h: float = _content_max.y - _content_min.y
	var margin := 70.0
	if content_w <= vw.x:
		_pan_offset.x = (vw.x - content_w) * 0.5 - _content_min.x  # center
	else:
		_pan_offset.x = clampf(_pan_offset.x,
			vw.x - _content_max.x - margin, margin - _content_min.x)
	if content_h <= vw.y:
		_pan_offset.y = (vw.y - content_h) * 0.5 - _content_min.y
	else:
		_pan_offset.y = clampf(_pan_offset.y,
			vw.y - _content_max.y - margin, margin - _content_min.y)
	_map.position = _pan_offset


func _center_on_hero() -> void:
	var hero_pt: Vector2 = _hex_center(GameState.map_hero_hex)
	_pan_offset = _map_wrap.size * 0.5 - hero_pt
	_apply_pan()


# ─── Hex math (flat-top, odd-q offset, vertically squashed) ─────────────
func _row_height() -> float:
	return sqrt(3.0) * HEX_SIZE * SQUASH  # flat-to-flat distance between rows


func _hex_center(coord: Vector2i) -> Vector2:
	# Flat-top columns step 1.5×radius apart; odd columns drop half a row.
	var x: float = float(coord.x) * 1.5 * HEX_SIZE
	var y: float = (float(coord.y) + 0.5 * float(posmod(coord.x, 2))) * _row_height()
	return Vector2(x, y)


## Flat-top hexagon outline (point on the left/right, flat top/bottom), squashed.
func _hex_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle: float = deg_to_rad(60.0 * float(i))
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius * SQUASH))
	return points


# ─── Render the world ───────────────────────────────────────────────────
func _render() -> void:
	_gold_label.text = "보유 골드  %dG" % GameState.gold
	_hide_tip()
	for c in _map.get_children():
		if c == _hero_marker or _party_markers.has(c):
			continue  # the party avatars persist across renders (keep walk positions)
		c.queue_free()
	_hex_roots.clear()
	_content_min = Vector2(INF, INF)
	_content_max = Vector2(-INF, -INF)
	# All tile shadows live on ONE layer BELOW every tile (z 1: above the beige
	# backdrop at 0, under the tiles at 1000+), so a lower tile's shadow never
	# paints over an upper tile.
	_shadow_layer = Control.new()
	_shadow_layer.z_index = 1
	_shadow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_shadow_layer)

	# Roads under everything: one connector hex per unlocked spine link.
	for i in range(1, GameState.town_index + 1):
		var town_hex: Vector2i = Balance.town_by_index(i).get("hex", Vector2i.ZERO)
		_make_hex(_hex_center(Vector2i(town_hex.x - 1, town_hex.y)),
			ROAD_FILL, INK, "", "", Callable(), null)

	# Spine towns: unlocked = biome tile (+icon); the NEXT one = ghost.
	for i in Balance.TOWN_SPINE.size():
		var town: Dictionary = Balance.town_by_index(i)
		var center: Vector2 = _hex_center(town.get("hex", Vector2i.ZERO))
		var town_name: String = str(town.get("name", ""))
		var gear: String = "정산 장비 Lv%d까지 등장" % int(town.get("gear_level", 1))
		var biome: Color = town.get("biome", Color.GREEN)
		if i <= GameState.town_index:
			var root := _make_hex(center, biome, INK,
				town_name, gear, Callable(), _icon_of(town), biome.lightened(0.18))
			_hex_roots[StringName(town.get("id", &""))] = root
		elif i == GameState.town_index + 1:
			var cost: int = int(town.get("cost", 0))
			var buyable: bool = GameState.can_unlock_next_town()
			# Ghost reveals its BIOME color on hover ("하늘색 타일이면 하늘색이 된다").
			var root := _make_hex(center, GHOST_FILL, GHOST_BORDER,
				town_name, gear,
				_buy_town_callable(town) if buyable else Callable(), _icon_of(town), biome, cost)
			_dim_ghost(root, buyable)
			_hex_roots[StringName(town.get("id", &""))] = root

	# Branch nodes of every unlocked town — but only the FRONTIER shows as ghosts:
	# a locked node hides until an adjacent hex is owned (체인 순서가 지도에 보임).
	for node: Dictionary in Balance.TREE_NODES:
		var id: StringName = StringName(node.get("id", &""))
		if not GameState.is_tree_node_open(id):
			continue
		if GameState.tree_node_level(id) <= 0 and not GameState.is_tree_node_reachable(id):
			continue
		var center: Vector2 = _hex_center(node.get("hex", Vector2i.ZERO))
		var axis: StringName = StringName(node.get("axis", &"ally"))
		var level: int = GameState.tree_node_level(id)
		var max_level: int = int(node.get("max_level", 1))
		var node_name: String = str(node.get("name", ""))
		var desc: String = str(node.get("desc", ""))
		var axis_color: Color = AXIS_COLORS.get(axis, Color.WHITE)
		var char_id: StringName = StringName(node.get("char_id", &""))
		var root: Control
		# 영입 완료: the companion left this tile to join the hero — no sprite, just
		# a quiet "합류!" plaque.
		if char_id != &"" and level >= 1:
			root = _make_hex(center, axis_color.lightened(0.35), INK,
				node_name, "파티에 합류했다!", Callable(), null, axis_color, 0)
			_hex_roots[id] = root
			continue
		if level <= 0:
			var buyable: bool = GameState.can_buy_tree_node(id)
			# Ghost reveals its AXIS color on hover (적=빨강, 아군=하늘색 …).
			root = _make_hex(center, GHOST_FILL, GHOST_BORDER,
				node_name, desc,
				_buy_node_callable(node) if buyable else Callable(), _icon_of(node),
				axis_color, GameState.tree_node_cost(id))
			_dim_ghost(root, buyable)
		elif level < max_level:
			var can_up: bool = GameState.can_buy_tree_node(id)
			root = _make_hex(center, axis_color, INK,
				"%s  Lv%d" % [node_name, level], desc,
				_buy_node_callable(node) if can_up else Callable(),
				_icon_of(node), axis_color.lightened(0.18), GameState.tree_node_cost(id), level)
			# Already bought but UPGRADEABLE & affordable → breathe so the player
			# notices "오 더 올릴 수 있네!".
			if can_up:
				_pulse_tile_icon(root)
		else:
			# Multi-level nodes show their MAX badge; 1-level unlocks (강타 등) don't.
			root = _make_hex(center, axis_color, INK,
				"%s  Lv%d (최대)" % [node_name, max_level], desc, Callable(), _icon_of(node),
				axis_color.lightened(0.12), 0, max_level if max_level > 1 else 0)
		_hex_roots[id] = root

	# 팍!! — the freshly bought tile slams in, then the hero sets off to it.
	if _pop_id != &"" and _hex_roots.has(_pop_id):
		var fresh: Control = _hex_roots[_pop_id]
		fresh.scale = Vector2(0.2, 0.2)
		var t := create_tween()
		t.tween_property(fresh, "scale", Vector2(1.2, 1.2), 0.13)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(fresh, "scale", Vector2.ONE, 0.09)
	_pop_id = &""
	# A recruit may have grown the party → make sure every companion has a marker.
	_sync_party_markers()
	if _walk_pending:
		_walk_pending = false
		_walk_hero_to(_walk_target_hex)


func _icon_of(entry: Dictionary) -> Texture2D:
	# 영입 노드: the companion's actual SPRITE stands on the tile (front idle
	# frame cut from their walk sheet) — "업글하고 싶게" 생긴 그 얼굴.
	var char_id: StringName = StringName(entry.get("char_id", &""))
	if char_id != &"":
		var res_path: String = "res://data/characters/%s.tres" % char_id
		if ResourceLoader.exists(res_path):
			var data: CharacterData = load(res_path) as CharacterData
			if data != null and data.sprite_sheet != null:
				var atlas := AtlasTexture.new()
				atlas.atlas = data.sprite_sheet
				atlas.region = Rect2(Vector2(float(data.frame_size.x), 0.0), data.frame_size_vec())
				return atlas
	var path: String = str(entry.get("icon", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		return load(path)
	return null


func _buy_town_callable(town: Dictionary) -> Callable:
	return func() -> void:
		_pop_id = StringName(town.get("id", &""))
		_walk_target_hex = town.get("hex", Vector2i.ZERO)
		_walk_pending = true
		GameState.unlock_next_town()


func _buy_node_callable(node: Dictionary) -> Callable:
	return func() -> void:
		_pop_id = StringName(node.get("id", &""))
		_walk_target_hex = node.get("hex", Vector2i.ZERO)
		_walk_pending = true
		# 영입 노드: the new companion waits AT this tile until the hero (walking
		# here) arrives, then falls in — no jarring instant snap.
		if StringName(node.get("char_id", &"")) != &"":
			_pending_recruit_hex = node.get("hex", Vector2i.ZERO)
		GameState.buy_tree_node(StringName(node.get("id", &"")))


func _dim_ghost(root: Control, buyable: bool) -> void:
	if not buyable:
		root.modulate = Color(1.0, 1.0, 1.0, 0.6)
		return
	# Affordable ghost → the icon BREATHES so you see what you can buy now.
	_pulse_tile_icon(root, Color(0.55, 0.5, 0.42, 1.0))


## 우웅우웅: loop the tile's icon alpha to signal "이거 살/올릴 수 있어!".
## Used for affordable ghosts AND already-bought nodes that can still level up.
func _pulse_tile_icon(root: Control, base_modulate: Color = Color.WHITE) -> void:
	if not root.has_meta("tile_icon"):
		return
	var icon: TextureRect = root.get_meta("tile_icon")
	if icon == null or not is_instance_valid(icon):
		return
	icon.modulate = base_modulate
	var t := icon.create_tween().set_loops()
	t.tween_property(icon, "modulate:a", 0.25, 0.7).set_trans(Tween.TRANS_SINE)
	t.tween_property(icon, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)


# ─── The hero ON the map: native sprite that ROAMS its tile, walks to new ones ─
## A little 월드맵 RPG: the avatar wanders inside its home hex (short strolls +
## pauses), and unlocking a tile sends him TRAVELING there, after which he roams
## the new tile. All _process-driven so it pans with the map cleanly.
func _hero_data() -> CharacterData:
	return GameState.party[0] if GameState.party_size() > 0 \
		else preload("res://data/characters/hero.tres")


func _ensure_hero_marker() -> void:
	if _hero_marker != null and is_instance_valid(_hero_marker):
		return
	var data: CharacterData = _hero_data()
	var atlas := AtlasTexture.new()
	atlas.atlas = data.sprite_sheet
	atlas.region = Rect2(Vector2(float(data.frame_size.x), 0.0), data.frame_size_vec())
	_hero_marker = TextureRect.new()
	_hero_marker.texture = atlas
	_hero_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero_marker.stretch_mode = TextureRect.STRETCH_KEEP  # NATIVE 1× — art stays art
	_hero_marker.size = data.frame_size_vec()
	_hero_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_marker.z_index = 1500  # always above the tiles (which z-sort by y)
	_map.add_child(_hero_marker)


## Foot point (where the hero "stands") ↔ marker top-left.
func _marker_pos_for_foot(foot: Vector2) -> Vector2:
	return foot - Vector2(_hero_marker.size.x * 0.5, _hero_marker.size.y - 2.0)


func _set_hero_frame(dir: int, col: int) -> void:
	var data: CharacterData = _hero_data()
	var atlas := _hero_marker.texture as AtlasTexture
	if atlas != null:
		atlas.region = Rect2(
			Vector2(float(col * data.frame_size.x), float(dir * data.frame_size.y)),
			data.frame_size_vec()
		)


func _snap_hero_marker() -> void:
	_ensure_hero_marker()
	_hero_home_hex = GameState.map_hero_hex
	_hero_marker.position = _marker_pos_for_foot(_hex_center(_hero_home_hex))
	_hero_traveling = false
	_hero_wait = 0.0
	_pick_wander_target()
	_set_hero_frame(CharacterData.Direction.DOWN, 1)


## Unlock walked here → travel to the tile's center, then roam it.
func _walk_hero_to(target_hex: Vector2i) -> void:
	_ensure_hero_marker()
	_hero_home_hex = target_hex
	_hero_traveling = true
	_hero_target = _marker_pos_for_foot(_hex_center(target_hex))
	_hero_wait = 0.0


## Random foot point inside the home hex — squashed vertically to match the
## flattened tile, nudged slightly toward the front (below the building).
func _pick_wander_target() -> void:
	var c: Vector2 = _hex_center(_hero_home_hex)
	var angle: float = randf() * TAU
	var radius: float = randf_range(6.0, HEX_SIZE * 0.6)
	var off := Vector2(cos(angle) * radius, sin(angle) * radius * SQUASH)
	_hero_target = _marker_pos_for_foot(c + off + Vector2(0.0, 6.0))


## Per-frame hero movement (travel or wander) — called from _process.
func _tick_hero(delta: float) -> void:
	if _hero_marker == null or not is_instance_valid(_hero_marker):
		return
	if _hero_wait > 0.0:
		_hero_wait -= delta
		_set_hero_frame(_hero_facing, 1)  # idle pose during a pause
		return
	var to: Vector2 = _hero_target - _hero_marker.position
	if to.length() <= 1.5:
		if _hero_traveling:
			_hero_traveling = false
			GameState.map_hero_hex = _hero_home_hex
			_hero_wait = 0.3
		else:
			_hero_wait = randf_range(0.6, 2.2)  # rest between strolls
		_pick_wander_target()
		return
	_hero_facing = CharacterData.Direction.RIGHT if to.x >= 0.0 else CharacterData.Direction.LEFT
	var speed: float = HERO_TRAVEL_SPEED if _hero_traveling else HERO_WANDER_SPEED
	_hero_marker.position = _hero_marker.position.move_toward(_hero_target, speed * delta)
	_hero_anim_time += delta
	var step: int = int(_hero_anim_time * _hero_data().walk_fps) % WALK_FRAME_SEQ.size()
	_set_hero_frame(_hero_facing, WALK_FRAME_SEQ[step])


# ─── 동료 followers on the map (snake trail behind the hero) ─────────────
func _hero_foot_pos() -> Vector2:
	return _hero_marker.position + Vector2(_hero_marker.size.x * 0.5, _hero_marker.size.y - 2.0)


## One marker per recruited companion (party slots 1+). A freshly-bought companion
## spawns standing ON ITS TILE and only joins (starts following) once the hero
## walks over to it — no instant snap. Existing companions follow immediately.
func _sync_party_markers() -> void:
	if _hero_marker == null:
		return
	var want: int = maxi(0, GameState.party_size() - 1)
	while _party_markers.size() > want:
		var m: TextureRect = _party_markers.pop_back()
		if is_instance_valid(m):
			m.queue_free()
	while _party_markers.size() < want:
		var idx: int = _party_markers.size() + 1
		# A new marker that matches the pending recruit waits on its tile; otherwise
		# (window opened with the party already formed) it's already following.
		if _pending_recruit_hex != Vector2i(99, 99):
			_party_markers.append(_make_member_marker(idx, _hex_center(_pending_recruit_hex), false))
			_pending_recruit_hex = Vector2i(99, 99)
		else:
			_party_markers.append(_make_member_marker(idx, _hero_foot_pos(), true))


func _make_member_marker(party_index: int, foot_pos: Vector2, following: bool) -> TextureRect:
	var data: CharacterData = GameState.party[party_index]
	var atlas := AtlasTexture.new()
	atlas.atlas = data.sprite_sheet
	atlas.region = Rect2(Vector2(float(data.frame_size.x), 0.0), data.frame_size_vec())
	var marker := TextureRect.new()
	marker.texture = atlas
	marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	marker.stretch_mode = TextureRect.STRETCH_KEEP
	marker.size = data.frame_size_vec()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.z_index = 1500 - party_index  # trail behind the hero, layered back-to-front
	marker.set_meta("anim", 0.0)
	marker.set_meta("party_index", party_index)
	marker.set_meta("following", following)
	marker.position = foot_pos - Vector2(marker.size.x * 0.5, marker.size.y - 2.0)
	_map.add_child(marker)
	return marker


## Smooth CHAIN follow: each member trails the one ahead at a fixed gap, easing in
## (no trail-snapping). A not-yet-joined companion idles on its tile until the
## hero comes within reach, then falls in. Calmer than the old position-trail.
const FOLLOW_GAP: float = 13.0
const FOLLOW_SPEED: float = 95.0
const JOIN_REACH: float = 22.0


func _tick_party_followers(delta: float) -> void:
	if _party_markers.is_empty() or _hero_marker == null:
		return
	var ahead_foot: Vector2 = _hero_foot_pos()
	for i in _party_markers.size():
		var marker: TextureRect = _party_markers[i]
		if not is_instance_valid(marker):
			continue
		var member_index: int = int(marker.get_meta("party_index", i + 1))
		if member_index >= GameState.party_size():
			continue
		var data: CharacterData = GameState.party[member_index]
		var my_foot: Vector2 = marker.position + Vector2(marker.size.x * 0.5, marker.size.y - 2.0)
		var following: bool = bool(marker.get_meta("following", true))
		var moving: bool = false
		var dir: int = CharacterData.Direction.DOWN
		if not following:
			# Waiting on its tile — join the moment the hero arrives nearby.
			if _hero_foot_pos().distance_to(my_foot) <= JOIN_REACH * 2.0:
				marker.set_meta("following", true)
		else:
			# Maintain FOLLOW_GAP behind whoever's ahead (hero or prev member).
			var to: Vector2 = ahead_foot - my_foot
			var dist: float = to.length()
			if dist > FOLLOW_GAP:
				var move: float = minf(dist - FOLLOW_GAP, FOLLOW_SPEED * delta)
				my_foot += to.normalized() * move
				marker.position = my_foot - Vector2(marker.size.x * 0.5, marker.size.y - 2.0)
				moving = move > 0.05
				dir = CharacterData.Direction.RIGHT if to.x >= 0.0 else CharacterData.Direction.LEFT
		# Animate.
		var anim: float = float(marker.get_meta("anim", 0.0))
		var col: int = 1  # idle frame
		if moving:
			anim += delta
			col = WALK_FRAME_SEQ[int(anim * data.walk_fps) % WALK_FRAME_SEQ.size()]
		marker.set_meta("anim", anim)
		var atlas := marker.texture as AtlasTexture
		if atlas != null:
			atlas.region = Rect2(
				Vector2(float(col * data.frame_size.x), float(dir * data.frame_size.y)),
				data.frame_size_vec())
		# The NEXT member trails THIS one (chain).
		ahead_foot = marker.position + Vector2(marker.size.x * 0.5, marker.size.y - 2.0)


# ─── Hover card with HIERARCHY (밴드 제목 → 효과 → 큰 골드) ──────────────
## The Black-Hole-game card grammar: a COLORED title band names the thing, the
## body says what it does, and the cost is the loudest line on the card.
func _ensure_tip() -> void:
	if _hover_tip != null and is_instance_valid(_hover_tip):
		return
	_hover_tip = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.border_color = INK
	style.set_border_width_all(1)
	style.set_content_margin_all(0.0)
	style.shadow_color = INK
	style.shadow_size = 1
	style.shadow_offset = Vector2(2, 2)
	style.anti_aliasing = false
	_hover_tip.add_theme_stylebox_override("panel", style)
	_hover_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tip.z_index = 2000  # above the hero (1500) and every tile
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_tip.add_child(col)
	# ① Title band: accent-colored strip, cream text.
	var band := PanelContainer.new()
	_tip_band_style = StyleBoxFlat.new()
	_tip_band_style.bg_color = INK
	_tip_band_style.border_width_bottom = 1
	_tip_band_style.border_color = INK
	_tip_band_style.content_margin_left = 10.0
	_tip_band_style.content_margin_right = 10.0
	_tip_band_style.content_margin_top = 2.0
	_tip_band_style.content_margin_bottom = 2.0
	_tip_band_style.anti_aliasing = false
	band.add_theme_stylebox_override("panel", _tip_band_style)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(band)
	_tip_title_label = Label.new()
	_tip_title_label.add_theme_font_override("font", NODE_FONT)
	_tip_title_label.add_theme_font_size_override("font_size", 9)
	_tip_title_label.add_theme_color_override("font_color", CREAM)
	_tip_title_label.add_theme_color_override("font_shadow_color", INK)
	_tip_title_label.add_theme_constant_override("shadow_offset_x", 1)
	_tip_title_label.add_theme_constant_override("shadow_offset_y", 1)
	_tip_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(_tip_title_label)
	# ② Effect line.
	_tip_body_label = Label.new()
	_tip_body_label.add_theme_font_override("font", NODE_FONT)
	_tip_body_label.add_theme_font_size_override("font_size", 8)
	_tip_body_label.add_theme_color_override("font_color", INK)
	_tip_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tip_body_label)
	# ③ THE GOLD — biggest thing on the card.
	_tip_cost_label = Label.new()
	_tip_cost_label.add_theme_font_override("font", NODE_FONT)
	_tip_cost_label.add_theme_font_size_override("font_size", 14)
	_tip_cost_label.add_theme_color_override("font_color", GOLD_TEXT)
	_tip_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tip_cost_label)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0.0, 2.0)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pad)
	_overlay.add_child(_hover_tip)
	_hover_tip.visible = false


func _show_tip(root: Control, title: String, body: String, cost: int, accent: Color) -> void:
	if title.is_empty():
		return
	_ensure_tip()
	_tip_band_style.bg_color = accent.darkened(0.12)
	_tip_title_label.text = title
	_tip_body_label.text = body
	_tip_body_label.visible = not body.is_empty()
	_tip_cost_label.text = ("%dG" % cost) if cost > 0 else "MAX"
	_tip_cost_label.visible = cost > 0
	_hover_tip.visible = true
	# Size the card EXPLICITLY from measured text — Container.reset_size() reads a
	# stale min-size the very first time a label's text changes, which clipped the
	# body line before any upgrade. Measuring the font is frame-independent.
	var w: float = 56.0
	w = maxf(w, NODE_FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 24.0)
	if not body.is_empty():
		w = maxf(w, NODE_FONT.get_string_size(body, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 16.0)
	if cost > 0:
		w = maxf(w, NODE_FONT.get_string_size(_tip_cost_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0)
	var h: float = 22.0  # title band (incl. separation)
	if not body.is_empty():
		h += 15.0
	if cost > 0:
		h += 23.0
	h += 5.0
	_hover_tip.custom_minimum_size = Vector2(w, h)
	_hover_tip.size = Vector2(w, h)
	# root lives in _map (panned); overlay isn't — fold the pan offset in.
	var screen_pos: Vector2 = root.position + _map.position
	var x: float = clampf(screen_pos.x + root.size.x * 0.5 - _hover_tip.size.x * 0.5,
		2.0, _map_wrap.size.x - _hover_tip.size.x - 2.0)
	var y: float = maxf(2.0, screen_pos.y - _hover_tip.size.y - 6.0)
	_hover_tip.position = Vector2(x, y)
	_cost_label.text = "%dG" % cost if cost > 0 else ""


func _hide_tip() -> void:
	if _hover_tip != null and is_instance_valid(_hover_tip):
		_hover_tip.visible = false
	if _cost_label != null:
		_cost_label.text = ""


# ─── One flat-top, vertically-squashed hex tile ─────────────────────────
## Built tiles sit a touch (BUILT_RAISE) above the table — a thin lip + faint
## shadow. Ghost tiles lie FLAT. Hover doesn't lift; it tints the top face to
## `reveal_color` and opens the hierarchy card (밴드 제목/효과/큰 골드).
## The tile itself shows ONLY the icon — every word lives in the card.
func _make_hex(center: Vector2, fill: Color, border: Color,
		tip_title: String, tip_body: String, on_click: Callable, icon_tex: Texture2D,
		reveal_color: Color = Color.WHITE, cost: int = 0, badge_level: int = 0) -> Control:
	var hex_w: float = 2.0 * HEX_SIZE
	var hex_h: float = _row_height()
	var is_ghost: bool = fill == GHOST_FILL
	var raise: float = 0.0 if is_ghost else BUILT_RAISE
	var root := Control.new()
	root.position = center - Vector2(HEX_SIZE, hex_h * 0.5 + BUILT_RAISE)
	root.size = Vector2(hex_w, hex_h + BUILT_RAISE + 5.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Painter order: lower tiles (bigger y) draw on top of upper ones — so the
	# tile in FRONT covers the one behind. +1000 base keeps z POSITIVE so upper
	# (negative-y) tiles never sink behind the beige backdrop (z 0).
	root.z_index = 1000 + int(round(center.y))
	_map.add_child(root)
	_content_min = _content_min.min(root.position)
	_content_max = _content_max.max(root.position + root.size)

	var ground := Vector2(HEX_SIZE, hex_h * 0.5 + BUILT_RAISE)  # table-plane center
	var top_c: Vector2 = ground - Vector2(0.0, raise)           # top-face center
	var pts: PackedVector2Array = _hex_points(HEX_SIZE - 0.5)
	if not is_ghost:
		# Shadow goes on the shared BELOW-everything layer (map space), so it can't
		# paint over a neighbouring tile's top.
		var shadow := Polygon2D.new()
		shadow.polygon = pts
		shadow.color = SHADOW_COLOR
		shadow.position = center + Vector2(1.5, 2.5)
		_shadow_layer.add_child(shadow)
		# Base hex (the side/thickness) — the top sits BUILT_RAISE above it, so the
		# darker base peeks out below as a slim lip.
		var base := Polygon2D.new()
		base.polygon = pts
		base.color = fill.darkened(0.32)
		base.position = ground
		root.add_child(base)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = fill
	poly.position = top_c
	root.add_child(poly)
	var rim := Line2D.new()
	rim.points = pts
	rim.add_point(pts[0])
	rim.width = 1.5
	rim.default_color = border
	rim.position = top_c
	root.add_child(rim)

	if icon_tex != null:
		var tsize: Vector2 = icon_tex.get_size()
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP  # NATIVE 1×
		icon.size = tsize
		icon.position = top_c - Vector2(tsize.x * 0.5, tsize.y * 0.5 + 3.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.set_meta("tile_icon", icon)  # pulsable (ghost-affordable OR upgradeable)
		if is_ghost:
			icon.modulate = Color(0.45, 0.42, 0.38, 0.85)
			root.set_meta("ghost_icon", icon)  # _dim_ghost may pulse it
		root.add_child(icon)

	# 노드 레벨을 타일 위에 큼직하게 — 호버 안 해도 몇 렙인지 보인다 ("Lv3").
	if badge_level > 0:
		var lv := Label.new()
		lv.text = "Lv%d" % badge_level
		lv.add_theme_font_override("font", NODE_FONT)
		lv.add_theme_font_size_override("font_size", 9)
		lv.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		lv.add_theme_color_override("font_outline_color", INK)
		lv.add_theme_constant_override("outline_size", 3)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.position = Vector2(top_c.x - 24.0, top_c.y + hex_h * 0.5 - 13.0)
		lv.size = Vector2(48.0, 11.0)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(lv)

	if tip_title != "" or on_click.is_valid():
		var catcher := Button.new()
		catcher.flat = true
		catcher.focus_mode = Control.FOCUS_NONE
		catcher.position = Vector2(0.0, 0.0)
		catcher.size = Vector2(root.size.x, hex_h + BUILT_RAISE)
		for style_name in ["normal", "hover", "pressed", "disabled", "focus"]:
			catcher.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
		# Card accent = the tile's true color (ghosts use what they'll become).
		var accent: Color = reveal_color if is_ghost else fill
		# Hover = COLOR REVEAL (no lift): the top face takes on what it would be.
		catcher.mouse_entered.connect(func() -> void:
			_show_tip(root, tip_title, tip_body, cost, accent)
			poly.color = reveal_color)
		catcher.mouse_exited.connect(func() -> void:
			_hide_tip()
			poly.color = fill)
		if on_click.is_valid():
			catcher.pressed.connect(on_click)
		else:
			catcher.disabled = true
		root.add_child(catcher)
	return root


# ─── 파티·장비 탭 (사고 / 팔고 / 끼우고 / 해제) ───────────────────────────
## The gear half of the power split: every member's six slots + the bag + a
## one-button shop (장비 상자 — rarity is the slot machine).
func _render_gear() -> void:
	for c in _gear_content.get_children():
		c.queue_free()
	# ── 상점: one random piece of the CURRENT town stage, rarity rolled.
	var shop := HBoxContainer.new()
	shop.add_theme_constant_override("separation", 6)
	_gear_content.add_child(shop)
	shop.add_child(_gear_label("장비 상자 — 무작위 장비 (단계 Lv%d · 등급은 운)" % GameState.town_gear_level(), 8, INK, true))
	var buy := _gear_button("%dG 구매" % GameState.gear_box_cost(), func() -> void:
		GameState.buy_gear_box())
	buy.disabled = not GameState.can_buy_gear_box()
	shop.add_child(buy)

	# ── 파티: each member's six slots.
	for i in GameState.party_size():
		_gear_content.add_child(_gear_label("— %s —" % GameState.party[i].display_name, 9, INK))
		var equipment: Array = GameState.party_equipment[i] if i < GameState.party_equipment.size() else []
		for row_data in GameState.member_equipment_rows(i):
			var slot: int = int(row_data.get("slot", 0))
			var entry = equipment[slot] if slot < equipment.size() else null
			var has_item: bool = GameState.item_entry_data(entry) != null
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 5)
			_gear_content.add_child(row)
			var slot_label := _gear_label(str(row_data.get("slot_name", "")), 7, GHOST_TEXT)
			slot_label.custom_minimum_size = Vector2(36.0, 0.0)
			row.add_child(slot_label)
			var name_color: Color = GameState.entry_rarity_color(entry) if has_item else GHOST_TEXT
			row.add_child(_gear_label(str(row_data.get("item_name", "—")), 8, name_color, true))
			if bool(row_data.get("can_change", false)):
				row.add_child(_gear_button("변경", row_data.get("on_change", Callable())))
			if has_item:
				row.add_child(_gear_button("해제", GameState.unequip_to_bag.bind(i, slot)))

	# ── 가방: equip out / sell off.
	_gear_content.add_child(_gear_label("— 가방 (%d) —" % GameState.inventory.size(), 9, INK))
	if GameState.inventory.is_empty():
		_gear_content.add_child(_gear_label("비어 있다", 7, GHOST_TEXT))
	for idx in GameState.inventory.size():
		var entry = GameState.inventory[idx]
		var item: ItemData = GameState.item_entry_data(entry)
		if item == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		_gear_content.add_child(row)
		row.add_child(_gear_label(GameState.entry_display_name(entry), 8, GameState.entry_rarity_color(entry), true))
		var slot: int = GameState.slot_index_for_item(item)
		var wearer: int = -1
		for m in GameState.party_size():
			if GameState.can_equip_to_slot(item, m, slot):
				wearer = m
				break
		if wearer >= 0:
			var inv_index: int = idx
			var target: int = wearer
			# 악세는 비어있는 악세 슬롯(악세1→악세2)에 들어가도록 best_slot 사용.
			var dest_slot: int = GameState.best_slot_for_item(item, wearer)
			row.add_child(_gear_button("장착", func() -> void:
				GameState.equip_inventory_item_to(inv_index, target, dest_slot)))
		var sell_index: int = idx
		row.add_child(_gear_button("판매 %dG" % GameState.inventory_sell_value(entry), func() -> void:
			GameState.sell_inventory_entry_at(sell_index)))


func _gear_label(text: String, size: int, color: Color, expand: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", NODE_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _gear_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0.0, 15.0)
	b.add_theme_font_size_override("font_size", 7)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b
