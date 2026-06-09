@tool
class_name EnemyPlacementShelf
extends Control

## Placement shelf — a compact grid of icon-only tiles.
## This owns the tile list and drag/drop placement only. Tooltip placement is a
## separate scene (EnemyPlacementTooltip) so both pieces can be moved independently.

const BONFIRE_TEX: Texture2D = preload("res://assets/sprites/objects/bonfire.png")
const SHRINE_TEX: Texture2D = preload("res://assets/sprites/objects/shrine.png")
const VILLAGE_TEX: Texture2D = preload("res://assets/sprites/objects/village.png")
const TILE_SCENE: PackedScene = preload("res://scenes/ui/dos_tile.tscn")

const TILE_ON: Color = Color(1, 1, 1, 1)
const TILE_OFF: Color = Color(0.4, 0.42, 0.46, 1.0)

@onready var _grid: GridContainer = %Grid

var _tiles: Array[Dictionary] = []
var _built_signature: String = ""
var _was_deadlocked: bool = false
var _carry: Dictionary = {}
var _ghost: TextureRect = null


func _ready() -> void:
	add_to_group("placement_panel")
	if Engine.is_editor_hint():
		return
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
	EventBus.structure_placed.connect(_on_changed.unbind(1))
	set_process(true)


func _on_changed() -> void:
	_refresh()


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
	if Engine.is_editor_hint():
		return
	if _ghost != null:
		_position_ghost_at_mouse()
	var dl: bool = _is_deadlocked()
	if dl != _was_deadlocked:
		_was_deadlocked = dl
		if dl:
			EventBus.rescue_offered.emit()
		_rebuild()


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

	if not GameState.name_entered:
		return
	if _was_deadlocked:
		_add_tile(&"rescue", &"slime", _tier_sprite(&"slime"), true)
	for i in Balance.tier_count():
		var tier: Dictionary = Balance.tier_at(i)
		var id: StringName = tier["id"]
		if not GameState.is_tier_visible(id):
			continue
		_add_tile(&"enemy", id, _tier_sprite(id), _tile_bright(&"enemy", id))
	for oid in GameState.acquired_objets:
		if not GameState.is_objet_placed(oid):
			_add_tile(&"objet", oid, _objet_tex(oid), _tile_bright(&"objet", oid))
	if GameState.is_building_unlocked(&"sanctuary") and not GameState.is_building_built(&"sanctuary"):
		_add_tile(&"sanctuary", &"sanctuary", SHRINE_TEX, _tile_bright(&"sanctuary", &"sanctuary"))

	if not _carry.is_empty():
		for t: Dictionary in _tiles:
			if t["kind"] == _carry["kind"] and t["id"] == _carry["id"] and is_instance_valid(t["tile"]):
				(t["tile"] as Control).visible = false


func _add_tile(kind: StringName, id: StringName, icon: Texture2D, bright: bool) -> void:
	var tile: Button = TILE_SCENE.instantiate()
	(tile.get_node("Icon") as TextureRect).texture = icon
	tile.modulate = TILE_ON if bright else TILE_OFF
	tile.pressed.connect(_on_tile_pressed.bind(kind, id))
	tile.mouse_entered.connect(_on_tile_hover.bind(kind, id))
	tile.mouse_exited.connect(_hide_tip)
	_grid.add_child(tile)
	_tiles.append({"tile": tile, "kind": kind, "id": id})


func _refresh_brightness() -> void:
	for t: Dictionary in _tiles:
		var tile: Button = t["tile"]
		if not is_instance_valid(tile):
			continue
		tile.modulate = TILE_ON if _tile_bright(t["kind"], t["id"]) else TILE_OFF


func _tile_bright(kind: StringName, id: StringName) -> bool:
	match kind:
		&"rescue": return true
		&"enemy": return GameState.can_place_enemy(id)
		&"campfire":
			var c: int = GameState.campfire_upgrade_cost() if GameState.campfire_placed else GameState.campfire_place_cost()
			return GameState.gold >= c
		&"sanctuary": return GameState.gold >= GameState.building_cost(&"sanctuary")
		&"village": return GameState.can_place_structure(&"village")
		&"objet": return not GameState.is_objet_placed(id)
	return true


func _on_tile_hover(kind: StringName, id: StringName) -> void:
	var tip := _placement_tooltip()
	if tip != null and tip.has_method("show_text"):
		tip.call("show_text", _tooltip_for(kind, id))


func _hide_tip() -> void:
	var tip := _placement_tooltip()
	if tip != null and tip.has_method("hide_tip"):
		tip.call("hide_tip")


func _placement_tooltip() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("placement_tooltip")


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


func _on_tile_pressed(kind: StringName, id: StringName) -> void:
	if not _carry.is_empty():
		return
	match kind:
		&"enemy":
			GameState.place_enemy(id)
		&"rescue":
			GameState.place_rescue_slime()
		&"campfire", &"sanctuary", &"village":
			if _tile_bright(kind, id):
				_begin_carry(kind, id)
		&"objet":
			if not GameState.is_objet_placed(id):
				_begin_carry(kind, id)


func _begin_carry(kind: StringName, id: StringName) -> void:
	_carry = {"kind": kind, "id": id}
	_hide_tip()
	for t: Dictionary in _tiles:
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
	_position_ghost_at_mouse()


func _position_ghost_at_mouse() -> void:
	if _ghost == null:
		return
	# The ghost is a child of this panel, but the cursor is in viewport/global UI
	# coordinates. Set global_position so the panel's own layout offset is not added.
	_ghost.global_position = get_viewport().get_mouse_position() - _ghost.size * 0.5


func _carry_icon(kind: StringName, id: StringName) -> Texture2D:
	match kind:
		&"campfire": return BONFIRE_TEX
		&"sanctuary": return SHRINE_TEX
		&"village": return VILLAGE_TEX
		&"objet": return _objet_tex(id)
	return _tier_sprite(id)


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
			GameState.place_acquired_objet(id)
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
	_rebuild()


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
		return false
	return true


func _signature() -> String:
	var parts: PackedStringArray = []
	parts.append("n%d" % (1 if GameState.name_entered else 0))
	parts.append("d%d" % (1 if _was_deadlocked else 0))
	parts.append("s%d" % (1 if (GameState.is_building_unlocked(&"sanctuary") and not GameState.is_building_built(&"sanctuary")) else 0))
	parts.append("v%d" % (1 if GameState.is_structure_placed(&"village") else 0))
	for oid in GameState.acquired_objets:
		parts.append("%s:%d" % [oid, 1 if GameState.is_objet_placed(oid) else 0])
	for i in Balance.tier_count():
		var id: StringName = Balance.tier_at(i)["id"]
		if GameState.is_tier_visible(id):
			parts.append(str(id))
	return "|".join(parts)


func _tier_sprite(id: StringName) -> Texture2D:
	var data: EnemyData = GameState.tier_enemy_data(id)
	return data.sprite if data != null else null
