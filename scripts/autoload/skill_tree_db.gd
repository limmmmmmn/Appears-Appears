extends Node

## Catalog of meta skill-tree nodes (permanent unlocks bought with gold).
## Nodes are built in code for now — once the set stabilizes we can move
## them to .tres files like the modifier pool, but inline definitions keep
## the iteration loop short during the incremental pivot.
##
## Query nodes by id, list all nodes for UI, or call try_purchase() to
## spend meta gold and persist the unlock through GameState.

signal node_unlocked(node: NodeData)
signal node_purchase_failed(node: NodeData, reason: String)

const REASON_ALREADY_UNLOCKED: String = "already_unlocked"
const REASON_MISSING_PREREQ: String = "missing_prereq"
const REASON_INSUFFICIENT_GOLD: String = "insufficient_gold"

var _all: Array[NodeData] = []
var _by_id: Dictionary = {}  # StringName -> NodeData


func _ready() -> void:
	_build_catalog()
	print("[SkillTreeDB] loaded %d nodes" % _all.size())


# ─── Catalog ──────────────────────────────────────────────────────────
func _build_catalog() -> void:
	_register(_make_node(
		&"recruit_mage",
		"마법사 영입",
		"출동 시 마법사가 파티에 합류합니다.",
		40,
		[],
		Vector2i(0, 0),
		{"recruit_character_id": &"mage"},
	))
	_register(_make_node(
		&"recruit_priest",
		"사제 영입",
		"출동 시 사제가 파티에 합류합니다.",
		80,
		[&"recruit_mage"],
		Vector2i(1, 0),
		{"recruit_character_id": &"priest"},
	))


func _make_node(
	id: StringName,
	display_name: String,
	description: String,
	cost: int,
	prereq_ids: Array,
	grid_position: Vector2i,
	effect_data: Dictionary,
) -> NodeData:
	var node: NodeData = NodeData.new()
	node.id = id
	node.display_name = display_name
	node.description = description
	node.cost = cost
	var typed_prereqs: Array[StringName] = []
	for prereq in prereq_ids:
		typed_prereqs.append(prereq)
	node.prereq_ids = typed_prereqs
	node.grid_position = grid_position
	node.effect_data = effect_data
	return node


func _register(node: NodeData) -> void:
	if node.id == &"":
		push_warning("[SkillTreeDB] node has empty id")
		return
	if _by_id.has(node.id):
		push_warning("[SkillTreeDB] duplicate id: %s" % node.id)
		return
	_all.append(node)
	_by_id[node.id] = node


# ─── Queries ──────────────────────────────────────────────────────────
func get_by_id(id: StringName) -> NodeData:
	return _by_id.get(id, null)


func get_all() -> Array[NodeData]:
	return _all.duplicate()


func is_unlocked(id: StringName) -> bool:
	return GameState.unlocked_node_ids.has(id)


## Returns true when every prereq has been unlocked. Root nodes (no
## prereqs) always pass.
func prereqs_satisfied(node: NodeData) -> bool:
	if node == null:
		return false
	for prereq_id: StringName in node.prereq_ids:
		if not is_unlocked(prereq_id):
			return false
	return true


func can_purchase(node: NodeData) -> bool:
	if node == null or is_unlocked(node.id):
		return false
	if not prereqs_satisfied(node):
		return false
	return GameState.gold >= node.cost


# ─── Purchase ─────────────────────────────────────────────────────────
func try_purchase(node: NodeData) -> bool:
	if node == null:
		return false
	if is_unlocked(node.id):
		node_purchase_failed.emit(node, REASON_ALREADY_UNLOCKED)
		return false
	if not prereqs_satisfied(node):
		node_purchase_failed.emit(node, REASON_MISSING_PREREQ)
		return false
	if not GameState.spend_gold(node.cost):
		node_purchase_failed.emit(node, REASON_INSUFFICIENT_GOLD)
		return false
	GameState.unlock_node(node.id)
	node_unlocked.emit(node)
	return true
