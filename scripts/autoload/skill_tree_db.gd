extends Node

## Static catalog for the incremental skill tree.
## Nodes are authored in code for now so iteration stays fast while the tree is
## still being redesigned.

const SKILL_NODE_DATA_SCRIPT: Script = preload("res://scripts/data/skill_node_data.gd")

var _all: Array = []
var _by_id: Dictionary = {}


func _ready() -> void:
	_load_all()
	print("[SkillTreeDB] loaded %d skill nodes" % _all.size())


func get_all() -> Array:
	return _all.duplicate()


func get_by_id(id: StringName):
	return _by_id.get(id, null)


func _load_all() -> void:
	_all.clear()
	_by_id.clear()
	# Skill tree intentionally empty — being rebuilt from scratch.
	# Re-add nodes here with `_register(_node(...))` when the new tree is designed.


func _register(node) -> void:
	if node.id == &"":
		push_warning("[SkillTreeDB] skill node has empty id")
		return
	if _by_id.has(node.id):
		push_warning("[SkillTreeDB] duplicate skill node id: %s" % node.id)
		return
	_all.append(node)
	_by_id[node.id] = node


func _node(
	id: StringName,
	display_name: String,
	short_label: String,
	tier: int,
	description: String,
	grid_position: Vector2i,
	cost: int,
	prerequisite_ids: Array[StringName] = [],
	modifier_path: String = "",
	effect_data: Dictionary = {},
	max_level: int = 1
) -> Resource:
	var node: Resource = SKILL_NODE_DATA_SCRIPT.new()
	node.id = id
	node.display_name = display_name
	node.short_label = short_label
	node.tier = tier
	node.description = description
	node.grid_position = grid_position
	node.cost = cost
	node.max_level = maxi(1, max_level)
	node.prerequisite_ids = prerequisite_ids.duplicate()
	node.effect_data = effect_data.duplicate()
	if not modifier_path.is_empty() and ResourceLoader.exists(modifier_path):
		node.linked_modifier = load(modifier_path) as ModifierData
	return node
