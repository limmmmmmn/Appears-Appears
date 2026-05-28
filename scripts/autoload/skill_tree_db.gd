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
	_register(_node(&"root", "자동 전투", "자동", 2, "필드 적과 닿으면 전투창이 열리고 파티가 자동으로 공격합니다.", Vector2i(0, 0), 0))

	# Right-panel PARTY: early, readable stat bumps.
	_register(_node(&"party_hp", "체력 훈련", "HP", 1, "파티원의 최대 HP가 오르고 즉시 회복됩니다.", Vector2i(-1, 1), 4, [&"root"], "res://data/modifiers/prototype/hp_up.tres", {}, 5))
	_register(_node(&"party_atk", "무기 연마", "AT", 1, "파티원의 공격력이 오릅니다.", Vector2i(-1, 2), 6, [&"root"], "res://data/modifiers/prototype/atk_up.tres", {}, 5))
	_register(_node(&"party_agi", "발놀림", "AG", 1, "파티원의 행동 속도가 오릅니다.", Vector2i(-1, 3), 8, [&"party_atk"], "res://data/modifiers/prototype/agi_up.tres", {}, 5))
	_register(_node(&"party_defense", "방어 자세", "DF", 1, "파티원의 방어력이 레벨마다 1 오릅니다.", Vector2i(-1, 4), 12, [&"party_agi"], "", {"def_flat": 1}, 5))
	_register(_node(&"hero_heavy_strike", "강타 훈련", "강", 1, "용사의 기본 공격이 더 강해집니다.", Vector2i(-1, 5), 22, [&"party_defense"], "res://data/modifiers/prototype/heavy_strike.tres", {}, 5))

	# North: enemies and field scale.
	_register(_node(&"more_slimes", "슬라임 증가", "슬라임", 1, "필드에 등장하는 기본 적 수가 1마리 늘어납니다.", Vector2i(0, -2), 3, [&"root"], "", {"field_enemy_count_bonus": 1}))
	_register(_node(&"more_slimes_2", "슬라임 무리", "무리", 1, "필드에 등장하는 기본 적 수가 2마리 더 늘어납니다.", Vector2i(1, -2), 80, [&"more_slimes"], "", {"field_enemy_count_bonus": 2}))
	_register(_node(&"enemies_per_window", "전투창 적 수", "적수", 1, "레벨마다 전투창 하나에 들어가는 적 수가 1마리 늘어납니다.", Vector2i(0, -3), 12, [&"more_slimes"], "", {"enemies_per_window_bonus": 1}, 4))
	_register(_node(&"monster_chase", "추격자 출현", "추격자", 2, "필드에 플레이어를 쫓아오는 추격형 슬라임이 섞여 나옵니다.", Vector2i(0, -4), 30, [&"enemies_per_window"], "", {"chaser_enemies_enabled": true}))
	_register(_node(&"spawner", "적 재생성", "재생성", 1, "필드 적이 부족하면 시간이 지나며 다시 보충됩니다.", Vector2i(0, -5), 130, [&"monster_chase"], "", {"field_spawn_interval_mult": 0.82}))
	_register(_node(&"spawner_fast", "빠른 재생성", "가속", 0, "필드 적이 보충되는 주기가 더 짧아집니다.", Vector2i(-1, -5), 300, [&"spawner"], "", {"field_spawn_interval_mult": 0.72}))
	_register(_node(&"spawner_burst", "폭발 재생성", "폭발", 0, "적 보충이 일어날 때마다 추가 적이 1마리 더 나옵니다.", Vector2i(1, -5), 400, [&"spawner"], "", {"field_spawn_batch_bonus": 1}))
	_register(_node(&"map_expand", "필드 확장", "확장", 2, "필드 크기가 1.5배가 되고 기본 적 수가 2마리 늘어납니다.", Vector2i(1, -6), 250, [&"spawner"], "", {"field_size_mult": 1.5, "field_enemy_count_bonus": 2}))
	_register(_node(&"forest_region", "숲 지역", "숲", 2, "본거지에서 숲 필드로 출발할 수 있게 됩니다.", Vector2i(2, -6), 500, [&"map_expand"], "", {"forest_region_unlocked": true}))
	_register(_node(&"max_enemies", "수용량 증가", "수용+", 0, "필드가 유지하려는 적 수와 적 압박 한도가 함께 증가합니다.", Vector2i(0, -6), 150, [&"spawner"], "", {"field_enemy_count_bonus": 3, "field_crowd_cap_bonus": 2}))
	_register(_node(&"max_enemies_2", "군집 수용", "군집", 0, "필드가 더 큰 적 무리를 계속 유지할 수 있게 됩니다.", Vector2i(0, -7), 600, [&"max_enemies"], "", {"field_enemy_count_bonus": 6, "field_crowd_cap_bonus": 4}))

	# West: party growth.
	_register(_node(&"magic", "마법", "마법", 2, "동료 영입과 파티 특수 능력 노드를 해금합니다.", Vector2i(-2, 0), 70, [&"root"]))
	_register(_node(&"companion", "동료", "동료", 2, "엘프가 첫 번째 동료로 합류해 함께 전투합니다.", Vector2i(-3, 0), 140, [&"magic"], "res://data/modifiers/prototype/recruit_elf.tres"))
	_register(_node(&"companion_2", "동료 2", "동료2", 2, "메이지가 두 번째 동료로 합류해 함께 전투합니다.", Vector2i(-4, 0), 260, [&"companion"], "res://data/modifiers/prototype/recruit_mage.tres"))
	_register(_node(&"companion_3", "동료 3", "동료3", 2, "나이트가 세 번째 동료로 합류해 4인 파티가 됩니다.", Vector2i(-5, 0), 420, [&"companion_2"], "res://data/modifiers/prototype/recruit_knight.tres"))
	_register(_node(&"combo_attack", "합체 공격", "합체", 2, "5킬마다 화면 안의 필드 적에게 합체공격을 자동 발동합니다.", Vector2i(-6, 0), 700, [&"companion_3"], "", {"combo_attack_enabled": true}))

	# South: window mechanics.
	_register(_node(&"battle_movement", "이동속도", "이동", 2, "전투창이 떠 있어도 움직일 수 있고 레벨마다 속도가 오릅니다.", Vector2i(0, 2), 10, [&"root"], "", {"battle_movement_enabled": true, "move_speed_flat": 6}, 5))
	_register(_node(&"window_bash", "창 강타", "강타", 1, "파티가 전투창을 밀면 창 안의 적에게 피해를 줍니다.", Vector2i(0, 3), 90, [&"battle_movement"], "res://data/modifiers/prototype/bump_attack.tres"))
	_register(_node(&"window_push", "창 충돌", "충돌", 2, "전투창끼리 부딪히면 양쪽 창 안의 적들이 피해를 받습니다.", Vector2i(0, 4), 140, [&"window_bash"], "res://data/modifiers/prototype/window_crash.tres", {"window_push_enabled": true}))
	_register(_node(&"window_blessing", "창 축복", "회복", 1, "파티가 전투창을 밀 때 가장 다친 동료가 회복됩니다.", Vector2i(0, 5), 180, [&"window_push"], "res://data/modifiers/prototype/bump_blessing.tres"))
	_register(_node(&"window_echo", "메아리 창", "복제", 2, "필드 적과 닿을 때 추가 전투창이 하나 더 생깁니다.", Vector2i(0, 6), 260, [&"window_blessing"], "", {"extra_windows_flat": 1}, 3))

	# East: rewards and home base.
	_register(_node(&"gold", "골드", "골드", 2, "적을 처치하면 필드에 골드 픽업이 떨어집니다.", Vector2i(2, 0), 1, [&"root"]))
	_register(_node(&"item", "장비", "장비", 2, "전투창을 클리어하면 장비 픽업이 떨어질 수 있습니다.", Vector2i(3, 0), 4, [&"gold"]))
	_register(_node(&"pickup_range", "습득 범위", "습득", 0, "레벨마다 골드와 장비를 끌어오는 범위가 넓어집니다.", Vector2i(2, 1), 80, [&"item"], "", {"pickup_range_mult": 1.18}, 5))
	_register(_node(&"drop_uncommon", "고급 전리품", "고급", 1, "고급 보상 단계로 가는 첫 전리품 노드입니다.", Vector2i(3, 1), 100, [&"item"]))
	_register(_node(&"drop_rare", "희귀 전리품", "희귀", 1, "희귀 보상 단계로 가는 전리품 노드입니다.", Vector2i(4, 1), 350, [&"drop_uncommon"]))
	_register(_node(&"drop_epic", "상급 전리품", "상급", 1, "상급 보상 단계로 가는 전리품 노드입니다.", Vector2i(5, 1), 1200, [&"drop_rare"]))
	_register(_node(&"drop_legendary", "전설 전리품", "전설", 2, "전설 보상 단계로 가는 최종 전리품 노드입니다.", Vector2i(6, 1), 4000, [&"drop_epic"]))
	_register(_node(&"shop_haggle", "본거지 보급", "보급", 1, "본거지 보급 계열의 첫 기능 노드입니다.", Vector2i(3, 2), 50, [&"item"]))
	_register(_node(&"shop_merchant", "보급관", "보급관", 1, "본거지 보급관 기능으로 이어지는 중간 노드입니다.", Vector2i(4, 2), 200, [&"shop_haggle"]))
	_register(_node(&"shop_baron", "지휘실", "지휘실", 2, "본거지 지휘실 기능으로 이어지는 최종 노드입니다.", Vector2i(5, 2), 800, [&"shop_merchant"]))


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
