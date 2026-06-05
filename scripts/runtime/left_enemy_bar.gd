class_name LeftEnemyBar
extends Control

## Left placement panel — a compact GRID of ICON-ONLY tiles (enemies + events).
## Click an enemy tile to SPEND GOLD and drop ONE of it on the map (random spot).
## A tile is bright when affordable and DIMMED when too poor.
## Hovering a tile pops a tooltip beside the panel with the name / level / cost.
##
## LOOK = scenes/ui/left_enemy_bar.tscn (the Box panel, grid spacing, tooltip box)
## + scenes/ui/dos_tile.tscn (one icon tile) — editable in the editor. This script
## is LOGIC ONLY: which tiles exist, their ON/OFF brightness, the tooltip text, and
## what clicking does.

const BONFIRE_TEX: Texture2D = preload("res://assets/sprites/objects/bonfire.png")
const SHRINE_TEX: Texture2D = preload("res://assets/sprites/objects/shrine.png")
const VILLAGE_TEX: Texture2D = preload("res://assets/sprites/objects/village.png")
const TILE_SCENE: PackedScene = preload("res://scenes/ui/dos_tile.tscn")

## Brightness for a tile that is ON / affordable vs OFF / unaffordable.
const TILE_ON: Color = Color(1, 1, 1, 1)
const TILE_OFF: Color = Color(0.4, 0.42, 0.46, 1.0)

@onready var _box: PanelContainer = %Box
@onready var _grid: GridContainer = %Grid
@onready var _tooltip: PanelContainer = %Tooltip
@onready var _tip_label: Label = %TipLabel

var _tiles: Array[Dictionary] = []          ## {tile, kind, id}
var _built_signature: String = ""
var _was_deadlocked: bool = false
## Drag-and-drop placement (iOS/macOS icon style): clicking a tile picks it up
## (a ghost follows the cursor, the panel tile hides); clicking the MAP drops it
## there. Empty = not carrying.
var _carry: Dictionary = {}
var _ghost: TextureRect = null


func _ready() -> void:
	add_to_group("placement_panel")
	_hide_tip()
	_rebuild()
	EventBus.gold_changed.connect(_on_changed.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))
	EventBus.tier_unlocked.connect(_on_changed.unbind(1))
	EventBus.campfire_placed.connect(_on_changed)
	EventBus.building_built.connect(_on_changed.unbind(1))
	EventBus.world_started.connect(_on_changed)
	EventBus.player_named.connect(_on_changed.unbind(1))
	EventBus.objet_acquired.connect(_on_objet_acquired)
	EventBus.structure_placed.connect(_on_changed.unbind(1))  # placed objet → dim its tile
	set_process(true)


func _on_changed() -> void:
	_refresh()


## A battle reward dropped an objet → rebuild so the new owned tile appears, then
## pop it in (it just "flew" here from the reward card).
func _on_objet_acquired(_id: StringName) -> void:
	_rebuild()
	for t in _tiles:
		if t["kind"] == &"objet" and is_instance_valid(t["tile"]):
			var tile: Control = t["tile"]
			tile.scale = Vector2(0.3, 0.3)
			var tw := create_tween()
			tw.tween_property(tile, "scale", Vector2(1.2, 1.2), 0.2)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(tile, "scale", Vector2.ONE, 0.12)


func _process(_delta: float) -> void:
	# Carried tile ghost trails the cursor (screen space).
	if _ghost != null:
		_ghost.position = get_viewport().get_mouse_position() - _ghost.size * 0.5
	# Cheap deadlock poll (queries the field for live enemies / fights / loot).
	var dl: bool = _is_deadlocked()
	if dl != _was_deadlocked:
		_was_deadlocked = dl
		if dl:
			EventBus.rescue_offered.emit()
		_rebuild()


# ─── Build ─────────────────────────────────────────────────────────────
func _refresh() -> void:
	if _signature() != _built_signature:
		_rebuild()
	else:
		_refresh_brightness()


func _rebuild() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_tiles.clear()
	_built_signature = _signature()
	_hide_tip()

	# Wait only for the name overlay; naming auto-starts the world.
	if not GameState.name_entered:
		return

	if _was_deadlocked:
		_add_tile(&"rescue", &"slime", _tier_sprite(&"slime"), true)

	# Enemies (toggle auto-spawn). Unlock-available tiers read as bright (claimable).
	for i in Balance.tier_count():
		var tier: Dictionary = Balance.tier_at(i)
		var id: StringName = tier["id"]
		if not GameState.is_tier_visible(id):
			continue
		_add_tile(&"enemy", id, _tier_sprite(id), _tile_bright(&"enemy", id))

	# Owned OBJETS (village, campfire, … dropped from battle) sit on the shelf as
	# tiles. Click one to place it on the field for free (existing carry/drop). It
	# dims once placed. They are NOT bought here anymore.
	for oid in GameState.acquired_objets:
		_add_tile(&"objet", oid, _objet_tex(oid), _tile_bright(&"objet", oid))
	# Events / structures. Once placed, a tile vanishes from the panel (it lives on
	# the map now).
	if GameState.is_building_unlocked(&"sanctuary") and not GameState.is_building_built(&"sanctuary"):
		_add_tile(&"sanctuary", &"sanctuary", SHRINE_TEX, _tile_bright(&"sanctuary", &"sanctuary"))

	# Keep the carried tile hidden if a rebuild happened mid-drag.
	if not _carry.is_empty():
		for t: Dictionary in _tiles:
			if t["kind"] == _carry["kind"] and t["id"] == _carry["id"] and is_instance_valid(t["tile"]):
				(t["tile"] as Control).visible = false


## One icon tile from the dos_tile template. `bright` lights it (ON/affordable);
## otherwise it's dimmed (OFF/unaffordable).
func _add_tile(kind: StringName, id: StringName, icon: Texture2D, bright: bool) -> void:
	var tile: Button = TILE_SCENE.instantiate()
	(tile.get_node("Icon") as TextureRect).texture = icon
	tile.modulate = TILE_ON if bright else TILE_OFF
	tile.pressed.connect(_on_tile_pressed.bind(kind, id))
	tile.mouse_entered.connect(_on_tile_hover.bind(kind, id, tile))
	tile.mouse_exited.connect(_hide_tip)
	_grid.add_child(tile)
	_tiles.append({"tile": tile, "kind": kind, "id": id})


func _refresh_brightness() -> void:
	for t: Dictionary in _tiles:
		var tile: Button = t["tile"]
		if not is_instance_valid(tile):
			continue
		tile.modulate = TILE_ON if _tile_bright(t["kind"], t["id"]) else TILE_OFF


## Bright = ON (enemy toggled on / unlockable) or affordable (event).
func _tile_bright(kind: StringName, id: StringName) -> bool:
	match kind:
		&"rescue": return true
		&"enemy":
			return GameState.can_place_enemy(id)   # tier auto-unlocks on reveal → just affordability
		&"campfire":
			var c: int = GameState.campfire_upgrade_cost() if GameState.campfire_placed else GameState.campfire_place_cost()
			return GameState.gold >= c
		&"sanctuary": return GameState.gold >= GameState.building_cost(&"sanctuary")
		&"village": return GameState.can_place_structure(&"village")
		&"objet": return not GameState.is_objet_placed(id)  # lit until placed
	return true


# ─── Tooltip (pops beside the panel, aligned with the hovered tile) ─────
func _on_tile_hover(kind: StringName, id: StringName, tile: Button) -> void:
	_tip_label.text = _tooltip_for(kind, id)
	_tooltip.visible = true
	# Right of the box, top-aligned with the hovered tile. (Root sits at the
	# screen origin, so the tile's global y maps straight to our local y.)
	var box_right: float = _box.position.x + _box.size.x
	_tooltip.position = Vector2(box_right + 6.0, tile.global_position.y)


func _hide_tip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


func _tooltip_for(kind: StringName, id: StringName) -> String:
	match kind:
		&"rescue":
			return "구제 슬라임\n무료"
		&"enemy":
			var name_text: String = str(Balance.tier_by_id(id).get("name", "?"))
			var lvl: int = GameState.enemy_level(id)
			var cost: int = GameState.tier_place_cost(id)
			return "%s\nLv %d\n배치 %dG" % [name_text, lvl, cost]
		&"campfire":
			var cost: int = GameState.campfire_upgrade_cost() if GameState.campfire_placed else GameState.campfire_place_cost()
			return "%s\n%dG" % ["모닥불 강화" if GameState.campfire_placed else "모닥불", cost]
		&"sanctuary":
			return "성소\n%dG" % GameState.building_cost(&"sanctuary")
		&"village":
			return "마을\n배치 %dG" % int(Balance.tile_by_id(&"village").get("place_cost", 0))
		&"objet":
			return "%s\n%s" % [_objet_name(id), "배치됨" if GameState.is_objet_placed(id) else "클릭해 배치"]
	return ""


## Objet display helpers (sprite + Korean name by id).
func _objet_tex(id: StringName) -> Texture2D:
	match id:
		&"campfire": return BONFIRE_TEX
		&"sanctuary": return SHRINE_TEX
	return VILLAGE_TEX


func _objet_name(id: StringName) -> String:
	match id:
		&"campfire": return "모닥불"
		&"sanctuary": return "성소"
	return "마을"


# ─── Click handlers — pick up the tile (drag-and-drop placement) ────────
func _on_tile_pressed(kind: StringName, id: StringName) -> void:
	if not _carry.is_empty():
		return  # already carrying a tile
	match kind:
		&"enemy":
			# Tiers auto-unlock the moment they appear, so a click always BUYS +
			# spawns ONE at a random spot near the party (no claim step).
			GameState.place_enemy(id)
		&"rescue":
			GameState.place_rescue_slime()
		&"campfire", &"sanctuary", &"village":
			# Drag-and-drop tiles: pick up → drop on the map at the clicked spot.
			if _tile_bright(kind, id):
				_begin_carry(kind, id)
		&"objet":
			# Owned objet → pick up and drop on the field for free (until placed).
			if not GameState.is_objet_placed(id):
				_begin_carry(kind, id)


## Pick up: a ghost icon follows the cursor and the panel tile hides until the
## player drops it on the map (or cancels with right-click).
func _begin_carry(kind: StringName, id: StringName) -> void:
	_carry = {"kind": kind, "id": id}
	_hide_tip()
	for t: Dictionary in _tiles:  # the panel tile vanishes while carried
		if t["kind"] == kind and t["id"] == id and is_instance_valid(t["tile"]):
			(t["tile"] as Control).visible = false
	_ghost = TextureRect.new()
	_ghost.texture = _carry_icon(kind, id)
	_ghost.custom_minimum_size = Vector2(20, 20)
	_ghost.size = Vector2(20, 20)
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost.modulate = Color(1, 1, 1, 0.85)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.z_index = 100
	add_child(_ghost)


func _carry_icon(kind: StringName, id: StringName) -> Texture2D:
	match kind:
		&"campfire": return BONFIRE_TEX
		&"sanctuary": return SHRINE_TEX
		&"village": return VILLAGE_TEX
		&"objet": return _objet_tex(id)
	return _tier_sprite(id)  # enemy / rescue


## While carrying: left-click drops the tile at the cursor's world spot, right-click
## cancels. Uses _input (runs BEFORE GUI/background controls) so the click is always
## caught — and consumes it so nothing else reacts. The pick-up click itself is safe:
## at that moment _carry is still empty (it's set later in the tile button's press).
func _input(event: InputEvent) -> void:
	if _carry.is_empty():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drop_carry_at_mouse()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_carry()
			get_viewport().set_input_as_handled()


func _drop_carry_at_mouse() -> void:
	var kind: StringName = _carry["kind"]
	var id: StringName = _carry["id"]
	var camera: Camera2D = get_viewport().get_camera_2d()
	var world: Vector2 = camera.get_global_mouse_position() if camera != null else Vector2.ZERO
	# Tell the Field WHERE to drop it, then trigger the existing placement. Only
	# passive tiles (campfire / sanctuary) are drag-placed — no party reaction.
	GameState.pending_placement_position = world
	match kind:
		&"campfire":
			if GameState.campfire_placed:
				GameState.upgrade_campfire()
			else:
				GameState.place_campfire()
		&"sanctuary":
			if GameState.can_purchase_building(&"sanctuary"):
				GameState.purchase_building(&"sanctuary")
		&"village":
			GameState.place_structure(&"village")
		&"objet":
			GameState.place_acquired_objet(id)   # free placement of an owned objet
	_end_carry()


func _cancel_carry() -> void:
	GameState.pending_placement_position = Vector2.INF
	_end_carry()


func _end_carry() -> void:
	_carry = {}
	GameState.pending_placement_position = Vector2.INF
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_rebuild()  # restores the hidden tile


# ─── Deadlock detection (gold 0, nothing in progress) ──────────────────
func _is_deadlocked() -> bool:
	if not GameState.world_started:
		return false
	if GameState.gold >= GameState.tier_place_cost(&"slime"):
		return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	if not tree.get_nodes_in_group("field_enemy").is_empty():
		return false
	if not tree.get_nodes_in_group("field_pickup").is_empty():
		return false
	var bm: Node = tree.get_first_node_in_group("battle_manager")
	if bm != null and bm.has_method("pending_window_count") and int(bm.pending_window_count()) > 0:
		return false  # a live fight OR an unflipped reward card → not stuck
	return true


# ─── Helpers ───────────────────────────────────────────────────────────
## A signature of everything that changes the TILE SET (which tiles exist) — NOT
## their ON/OFF brightness. So a toggle / gold tick just re-tints (no rebuild → the
## tooltip doesn't flicker); only an appearing/disappearing tile forces a rebuild.
func _signature() -> String:
	var parts: PackedStringArray = []
	parts.append("n%d" % (1 if GameState.name_entered else 0))
	parts.append("d%d" % (1 if _was_deadlocked else 0))
	parts.append("s%d" % (1 if (GameState.is_building_unlocked(&"sanctuary") and not GameState.is_building_built(&"sanctuary")) else 0))
	parts.append("v%d" % (1 if GameState.is_structure_placed(&"village") else 0))
	for i in Balance.tier_count():
		var id: StringName = Balance.tier_at(i)["id"]
		if GameState.is_tier_visible(id):
			parts.append(str(id))
	return "|".join(parts)


func _tier_sprite(id: StringName) -> Texture2D:
	var data: EnemyData = GameState.tier_enemy_data(id)
	return data.sprite if data != null else null
