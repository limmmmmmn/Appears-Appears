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
	_register(_node(&"root", "Auto Battle", "AUTO", "The party fights battle windows automatically.", Vector2i(0, 0), 0))

	# North: enemy supply.
	_register(_node(&"more_slimes", "More Slimes", "SLIME", "Start fields with more enemies.", Vector2i(0, -2), 3, [&"root"], "", {"field_enemy_count_bonus": 1}))
	_register(_node(&"more_slimes_2", "Slime Pack", "PACK", "Add even more field enemies.", Vector2i(1, -2), 80, [&"more_slimes"], "", {"field_enemy_count_bonus": 2}))
	_register(_node(&"enemies_per_window", "Crowded Windows", "2/WIN", "Battle windows contain one more enemy.", Vector2i(0, -3), 12, [&"more_slimes"], "", {"enemies_per_window_bonus": 1}))
	_register(_node(&"monster_chase", "Monster Chase", "CHASE", "Chaser enemies can begin appearing.", Vector2i(0, -4), 30, [&"enemies_per_window"], "", {"chaser_enemies_enabled": true}))
	_register(_node(&"spawner", "Spawner", "SPAWN", "Enemy waves begin refilling.", Vector2i(0, -5), 130, [&"monster_chase"], "", {"field_spawn_interval_mult": 0.82}))
	_register(_node(&"spawner_fast", "Fast Spawner", "FAST", "Enemy waves refill much faster.", Vector2i(-1, -5), 300, [&"spawner"], "", {"field_spawn_interval_mult": 0.72}))
	_register(_node(&"spawner_burst", "Burst Spawner", "BURST", "Each wave spawns one extra enemy.", Vector2i(1, -5), 400, [&"spawner"], "", {"field_spawn_batch_bonus": 1}))
	_register(_node(&"max_enemies", "More Room", "MAX8", "Raise field enemy pressure.", Vector2i(0, -6), 150, [&"spawner"], "", {"field_enemy_count_bonus": 3, "field_crowd_cap_bonus": 2}))
	_register(_node(&"max_enemies_2", "Swarm Room", "MAX16", "Raise field enemy pressure again.", Vector2i(0, -7), 600, [&"max_enemies"], "", {"field_enemy_count_bonus": 6, "field_crowd_cap_bonus": 4}))

	# West: resources and party growth.
	_register(_node(&"gold", "Gold", "GOLD", "Enemies drop 1 gold pickup each.", Vector2i(-2, 0), 1, [&"root"]))
	_register(_node(&"item", "Equipment", "ITEM", "Battle windows drop 1 equipment item.", Vector2i(-3, 0), 4, [&"gold"]))
	_register(_node(&"magic", "Magic", "MAGIC", "Recruit a mage with Fireburst.", Vector2i(-4, 0), 70, [&"item"], "res://data/modifiers/prototype/recruit_mage.tres"))
	_register(_node(&"companion", "Companion", "ALLY", "Recruit a priest companion.", Vector2i(-5, 0), 140, [&"magic"], "res://data/modifiers/prototype/recruit_priest.tres"))
	_register(_node(&"drop_uncommon", "Better Drops", "DROP1", "Drop tuning placeholder.", Vector2i(-3, -1), 100, [&"item"]))
	_register(_node(&"drop_rare", "Rare Drops", "DROP2", "Drop tuning placeholder.", Vector2i(-3, -2), 350, [&"drop_uncommon"]))
	_register(_node(&"drop_epic", "Epic Drops", "DROP3", "Drop tuning placeholder.", Vector2i(-3, -3), 1200, [&"drop_rare"]))
	_register(_node(&"drop_legendary", "Legend Drops", "DROP4", "Drop tuning placeholder.", Vector2i(-3, -4), 4000, [&"drop_epic"]))

	# South: automation.
	_register(_node(&"atb", "ATB", "ATB", "Battle windows tick faster.", Vector2i(1, 2), 70, [&"root"], "", {"battle_turn_interval_mult": 0.82}))
	_register(_node(&"battle_movement", "Battle Movement", "MOVE", "Move while battle windows run on the field.", Vector2i(0, 3), 96, [&"atb"], "res://data/modifiers/prototype/swift_boots.tres", {"battle_movement_enabled": true}))
	_register(_node(&"pickup_range", "Pickup Range", "PICK", "Pickups have a wider collection range.", Vector2i(1, 3), 110, [&"battle_movement"], "", {"pickup_range_mult": 1.7}))
	_register(_node(&"multi_battle", "Multi Battle", "MULTI", "Every encounter opens one extra battle window.", Vector2i(0, 4), 192, [&"battle_movement"], "", {"extra_windows_flat": 1}))

	# East: window manipulation and economy.
	_register(_node(&"window_push", "Window Push", "PUSH", "Battle windows push each other around.", Vector2i(2, 0), 60, [&"root"], "", {"window_push_enabled": true}))
	_register(_node(&"window_bash", "Window Bash", "BASH", "Bump into battle windows to push them and damage enemies.", Vector2i(3, 0), 90, [&"window_push"], "res://data/modifiers/prototype/window_crash.tres"))
	_register(_node(&"map_expand", "Map Expand", "MAP", "Fields become larger and hold more enemies.", Vector2i(4, 0), 250, [&"window_bash"], "", {"field_size_mult": 1.5, "field_enemy_count_bonus": 2}))
	_register(_node(&"shop_haggle", "Haggle", "ECO1", "Economy tuning placeholder.", Vector2i(2, 1), 50, [&"window_push"]))
	_register(_node(&"shop_merchant", "Merchant", "ECO2", "Economy tuning placeholder.", Vector2i(3, 1), 200, [&"shop_haggle"]))
	_register(_node(&"shop_baron", "Baron", "ECO3", "Economy tuning placeholder.", Vector2i(4, 1), 800, [&"shop_merchant"]))


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
	description: String,
	grid_position: Vector2i,
	cost: int,
	prerequisite_ids: Array[StringName] = [],
	modifier_path: String = "",
	effect_data: Dictionary = {}
) -> Resource:
	var node: Resource = SKILL_NODE_DATA_SCRIPT.new()
	node.id = id
	node.display_name = display_name
	node.short_label = short_label
	node.description = description
	node.grid_position = grid_position
	node.cost = cost
	node.prerequisite_ids = prerequisite_ids.duplicate()
	node.effect_data = effect_data.duplicate()
	if not modifier_path.is_empty() and ResourceLoader.exists(modifier_path):
		node.linked_modifier = load(modifier_path) as ModifierData
	return node
