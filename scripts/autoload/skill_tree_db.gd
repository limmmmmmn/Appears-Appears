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
	_register(_node(&"root", "Auto Battle", "AUTO", "적과 부딪히면 전투창이 열리고 파티가 자동으로 싸웁니다.", Vector2i(0, 0), 0))

	# North: enemies and field scale.
	_register(_node(&"more_slimes", "More Slimes", "SLIME", "필드 시작 시 적이 1마리 더 등장합니다.", Vector2i(0, -2), 3, [&"root"], "", {"field_enemy_count_bonus": 1}))
	_register(_node(&"more_slimes_2", "Slime Pack", "PACK", "필드 시작 시 적 무리가 더 커집니다.", Vector2i(1, -2), 80, [&"more_slimes"], "", {"field_enemy_count_bonus": 2}))
	_register(_node(&"enemies_per_window", "Crowded Windows", "2/WIN", "전투창 하나에 적이 1마리 더 들어옵니다.", Vector2i(0, -3), 12, [&"more_slimes"], "", {"enemies_per_window_bonus": 1}))
	_register(_node(&"monster_chase", "Monster Chase", "CHASE", "플레이어를 따라오는 추격형 적이 등장합니다.", Vector2i(0, -4), 30, [&"enemies_per_window"], "", {"chaser_enemies_enabled": true}))
	_register(_node(&"spawner", "Spawner", "SPAWN", "시간이 지나면 필드에 적이 다시 채워집니다.", Vector2i(0, -5), 130, [&"monster_chase"], "", {"field_spawn_interval_mult": 0.82}))
	_register(_node(&"spawner_fast", "Fast Spawner", "FAST", "적이 다시 채워지는 속도가 빨라집니다.", Vector2i(-1, -5), 300, [&"spawner"], "", {"field_spawn_interval_mult": 0.72}))
	_register(_node(&"spawner_burst", "Burst Spawner", "BURST", "적이 재등장할 때 1마리가 더 추가됩니다.", Vector2i(1, -5), 400, [&"spawner"], "", {"field_spawn_batch_bonus": 1}))
	_register(_node(&"map_expand", "Map Expand", "MAP", "필드가 넓어지고 더 많은 적을 담습니다.", Vector2i(1, -6), 250, [&"spawner"], "", {"field_size_mult": 1.5, "field_enemy_count_bonus": 2}))
	_register(_node(&"max_enemies", "More Room", "MAX8", "필드에 쌓일 수 있는 적 압박이 증가합니다.", Vector2i(0, -6), 150, [&"spawner"], "", {"field_enemy_count_bonus": 3, "field_crowd_cap_bonus": 2}))
	_register(_node(&"max_enemies_2", "Swarm Room", "MAX16", "필드의 최대 적 압박이 한 번 더 증가합니다.", Vector2i(0, -7), 600, [&"max_enemies"], "", {"field_enemy_count_bonus": 6, "field_crowd_cap_bonus": 4}))

	# West: party growth.
	_register(_node(&"magic", "Magic", "MAGIC", "동료와 특수 전투 능력으로 이어지는 길을 엽니다.", Vector2i(-2, 0), 70, [&"root"]))
	_register(_node(&"companion", "Companion", "ALLY", "빠른 엘프 동료가 파티에 합류합니다.", Vector2i(-3, 0), 140, [&"magic"], "res://data/modifiers/prototype/recruit_elf.tres"))

	# South: window mechanics.
	_register(_node(&"battle_movement", "Battle Movement", "MOVE", "전투창이 열려 있어도 필드에서 움직일 수 있습니다.", Vector2i(0, 2), 10, [&"root"], "res://data/modifiers/prototype/swift_boots.tres", {"battle_movement_enabled": true}))
	_register(_node(&"multi_battle", "Multi Battle", "MULTI", "적과 조우할 때 전투창이 1개 더 열립니다.", Vector2i(0, 3), 60, [&"battle_movement"], "", {"extra_windows_flat": 1}))
	_register(_node(&"window_bash", "Window Bash", "BASH", "전투창을 몸으로 밀면 안의 적에게 피해를 줍니다.", Vector2i(0, 4), 90, [&"multi_battle"], "res://data/modifiers/prototype/bump_attack.tres"))
	_register(_node(&"window_push", "Window Push", "PUSH", "전투창끼리 충돌하면 안의 적들이 피해를 받습니다.", Vector2i(0, 5), 140, [&"window_bash"], "res://data/modifiers/prototype/window_crash.tres", {"window_push_enabled": true}))

	# East: rewards and home base.
	_register(_node(&"gold", "Gold", "GOLD", "적을 처치하면 골드 픽업이 떨어집니다.", Vector2i(2, 0), 1, [&"root"]))
	_register(_node(&"item", "Equipment", "ITEM", "전투창을 끝내면 장비가 떨어질 수 있습니다.", Vector2i(3, 0), 4, [&"gold"]))
	_register(_node(&"pickup_range", "Pickup Range", "PICK", "골드와 장비를 줍는 범위가 넓어집니다.", Vector2i(2, 1), 110, [&"item"], "", {"pickup_range_mult": 1.7}))
	_register(_node(&"drop_uncommon", "Better Drops", "DROP1", "더 좋은 보상 단계로 이어지는 길을 엽니다.", Vector2i(3, 1), 100, [&"item"]))
	_register(_node(&"drop_rare", "Rare Drops", "DROP2", "희귀 보상 단계로 이어지는 길을 엽니다.", Vector2i(4, 1), 350, [&"drop_uncommon"]))
	_register(_node(&"drop_epic", "Epic Drops", "DROP3", "상급 보상 단계로 이어지는 길을 엽니다.", Vector2i(5, 1), 1200, [&"drop_rare"]))
	_register(_node(&"drop_legendary", "Legend Drops", "DROP4", "전설 보상 단계로 이어지는 길을 엽니다.", Vector2i(6, 1), 4000, [&"drop_epic"]))
	_register(_node(&"shop_haggle", "Base Stores", "BASE1", "본거지 보급 기능으로 이어지는 길을 엽니다.", Vector2i(3, 2), 50, [&"item"]))
	_register(_node(&"shop_merchant", "Quartermaster", "BASE2", "본거지 보급관 기능으로 이어지는 길을 엽니다.", Vector2i(4, 2), 200, [&"shop_haggle"]))
	_register(_node(&"shop_baron", "Command Room", "BASE3", "본거지 지휘실 기능으로 이어지는 길을 엽니다.", Vector2i(5, 2), 800, [&"shop_merchant"]))


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
