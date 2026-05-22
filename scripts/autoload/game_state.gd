extends Node

## Run-wide state: party, gold, modifiers, and field loop progress.
## Read freely. Mutate through helper methods so signals fire correctly.
##
## Use the effective_* helpers when you need stat values during combat —
## they fold in active_modifiers. Raw fields on CharacterData are base only.

const STARTER_SKILL_BY_CHARACTER_ID: Dictionary = {
	&"mage": preload("res://data/modifiers/prototype/fireburst.tres"),
	&"priest": preload("res://data/modifiers/prototype/battle_prayer.tres"),
	&"thief": preload("res://data/modifiers/prototype/pilfer.tres"),
}

# ─── Party ────────────────────────────────────────────────────────────
## The 4 party members chosen for this run.
var party: Array[CharacterData] = []

## Current HP/MP per party member. Index matches `party`.
var party_hp: Array[int] = []
var party_mp: Array[int] = []
var party_levels: Array[int] = []
var party_xp: Array[int] = []
var party_equipment: Array[Array] = []
var inventory: Array = []
var _move_speed_drag_multiplier: float = 1.0
var _move_speed_drag_until_msec: int = 0
var _move_speed_boost_multiplier: float = 1.0
var _move_speed_boost_until_msec: int = 0
var _field_battle_pause_count: int = 0

# ─── Economy ──────────────────────────────────────────────────────────
const STARTING_GOLD: int = 0

var gold: int = STARTING_GOLD
## Stat-affecting modifiers picked this run.
var active_modifiers: Array[ModifierData] = []
## Permanent incremental-tree purchases. Value = node level.
var purchased_skill_nodes: Dictionary = {}
## Recruit cards that successfully added a member to `party` this run.
## Kept separate from active_modifiers because companions are *party state*,
## not stat effects — useful for run summaries and avoiding "modifiers: 0"
## logs after recruiting.
var recruited_companions: Array[ModifierData] = []

# ─── Progression ──────────────────────────────────────────────────────
var field_loop_count: int = 0

const FIELD_REGION_MILESTONES: Array[Dictionary] = [
	{"name": "초원", "gold": 0, "nodes": 0},
	{"name": "깊은 숲", "gold": 75, "nodes": 2},
	{"name": "오래된 폐허", "gold": 250, "nodes": 5},
	{"name": "검은 늪", "gold": 700, "nodes": 8},
	{"name": "마왕성 외곽", "gold": 1800, "nodes": 12},
	{"name": "마왕성", "gold": 4200, "nodes": 16},
]

const MAX_CHARACTER_LEVEL: int = 20
const EQUIPMENT_SLOT_COUNT: int = 6
const EQUIPMENT_ACCESSORY_SLOT_A: int = 4
const EQUIPMENT_ACCESSORY_SLOT_B: int = 5
const EQUIPMENT_SLOT_LABELS: Array[String] = ["Weapon", "Shield", "Helmet", "Armor", "Accessory"]
const XP_CURVE_BASE: int = 10
const XP_CURVE_LEVEL_STEP: int = 5
const XP_CURVE_QUADRATIC: int = 3
const DEFAULT_LEVEL_GROWTH: Dictionary = {
	"hp": 4,
	"atk": 2,
	"def": 1,
	"agi": 1,
}
const LEVEL_GROWTH_BY_CHARACTER_ID: Dictionary = {
	&"hero": {"hp": 5, "atk": 2, "def": 1, "agi": 1},
	&"mage": {"hp": 3, "atk": 3, "def": 0, "agi": 1},
	&"priest": {"hp": 5, "atk": 1, "def": 1, "agi": 1},
	&"thief": {"hp": 3, "atk": 2, "def": 0, "agi": 2},
}

const PRICE_LEVEL_MULTIPLIERS = [1.0, 1.45, 2.05, 2.8, 3.7]
const EFFECT_STACK_MULTIPLIERS = [1.0, 0.75, 0.55, 0.4, 0.3]
const DAMAGE_BONUS_STACK_MULTIPLIERS = [1.0, 0.5, 0.3, 0.2, 0.16]
# ─── Run statistics (for the game-over summary) ───────────────────────
var enemies_killed: int = 0
var total_gold_earned: int = 0  ## lifetime, not affected by spending
var biggest_hit: int = 0
var run_started_at_ms: int = 0

func _ready() -> void:
	_ensure_default_skill_nodes()
	# Listen to bus events to keep counters fresh without coupling combat code.
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.modifier_purchase_requested.connect(_on_modifier_purchase_requested)


func _on_enemy_defeated(_enemy: Node, _gold: int, _world_position: Vector2) -> void:
	enemies_killed += 1


func _on_damage_dealt(_target: Node, amount: int, _world_position: Vector2) -> void:
	if amount > biggest_hit:
		biggest_hit = amount


func get_run_elapsed_seconds() -> float:
	if run_started_at_ms <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - run_started_at_ms) / 1000.0


# ─── Party setup ──────────────────────────────────────────────────────
## Initialize the party from a list of CharacterData. Resets HP/MP to max.
## Emits party_changed so listeners (HUD, etc.) can re-populate from scratch
## regardless of node-init order.
func set_party(members: Array[CharacterData]) -> void:
	party = members.duplicate()
	party_hp.clear()
	party_mp.clear()
	party_levels.clear()
	party_xp.clear()
	party_equipment.clear()
	inventory.clear()
	for m: CharacterData in party:
		party_levels.append(1)
		party_xp.append(0)
		party_equipment.append(_empty_equipment_slots())
		party_hp.append(effective_max_hp(party_hp.size()))
		party_mp.append(m.max_mp)
	# A fresh party means a fresh run timer.
	run_started_at_ms = Time.get_ticks_msec()
	EventBus.party_changed.emit()


func party_size() -> int:
	return party.size()


func is_alive(index: int) -> bool:
	return index >= 0 and index < party_hp.size() and party_hp[index] > 0


func is_party_wiped() -> bool:
	for hp in party_hp:
		if hp > 0:
			return false
	return true


# ─── Combat hooks ─────────────────────────────────────────────────────
func damage_party_member(index: int, amount: int) -> void:
	if index < 0 or index >= party_hp.size():
		return
	var was_alive: bool = party_hp[index] > 0
	var before_hp: int = party_hp[index]
	party_hp[index] = max(0, party_hp[index] - amount)
	var actual_damage: int = before_hp - party_hp[index]
	if actual_damage > 0:
		EventBus.party_damage_taken.emit(index, actual_damage)
	EventBus.party_member_hp_changed.emit(index, party_hp[index], effective_max_hp(index))
	EventBus.party_hp_changed.emit()
	if was_alive and party_hp[index] == 0 and is_party_wiped():
		EventBus.party_wiped.emit()


func heal_party_member(index: int, amount: int) -> void:
	if index < 0 or index >= party_hp.size():
		return
	party_hp[index] = min(effective_max_hp(index), party_hp[index] + amount)
	EventBus.party_member_hp_changed.emit(index, party_hp[index], effective_max_hp(index))
	EventBus.party_hp_changed.emit()


# ─── Experience / Levels ──────────────────────────────────────────────
func add_party_xp(amount: int) -> void:
	if amount <= 0:
		return
	for i in party.size():
		_add_xp_to_member(i, amount)


func party_level(index: int) -> int:
	if index < 0 or index >= party_levels.size():
		return 1
	return party_levels[index]


func party_xp_to_next(index: int) -> int:
	return _xp_required_for_level(party_level(index))


func party_xp_ratio(index: int) -> float:
	if index < 0 or index >= party_xp.size():
		return 0.0
	if party_level(index) >= MAX_CHARACTER_LEVEL:
		return 1.0
	return clampf(float(party_xp[index]) / float(party_xp_to_next(index)), 0.0, 1.0)


func _add_xp_to_member(index: int, amount: int) -> void:
	if index < 0 or index >= party.size():
		return
	if index >= party_levels.size() or index >= party_xp.size():
		return
	if party_levels[index] >= MAX_CHARACTER_LEVEL:
		party_xp[index] = 0
		_emit_member_xp_changed(index)
		return
	party_xp[index] += amount
	var leveled: bool = false
	var was_alive: bool = is_alive(index)
	while party_levels[index] < MAX_CHARACTER_LEVEL and party_xp[index] >= _xp_required_for_level(party_levels[index]):
		party_xp[index] -= _xp_required_for_level(party_levels[index])
		_level_up_member(index, was_alive)
		leveled = true
	if party_levels[index] >= MAX_CHARACTER_LEVEL:
		party_xp[index] = 0
	_emit_member_xp_changed(index)
	if leveled:
		EventBus.party_hp_changed.emit()


func _level_up_member(index: int, heal_if_alive: bool) -> void:
	var old_max_hp: int = effective_max_hp(index)
	party_levels[index] += 1
	var new_max_hp: int = effective_max_hp(index)
	if heal_if_alive and index < party_hp.size():
		party_hp[index] = min(new_max_hp, party_hp[index] + maxi(0, new_max_hp - old_max_hp))
	EventBus.party_member_leveled_up.emit(index, party_levels[index])
	EventBus.party_member_hp_changed.emit(index, party_hp[index], new_max_hp)


func _emit_member_xp_changed(index: int) -> void:
	EventBus.party_member_xp_changed.emit(index, party_xp[index], party_xp_to_next(index), party_levels[index])


func _xp_required_for_level(level: int) -> int:
	var l: int = maxi(1, level)
	var t: int = l - 1
	return XP_CURVE_BASE + t * XP_CURVE_LEVEL_STEP + t * t * XP_CURVE_QUADRATIC


func _level_bonus(index: int, key: String) -> int:
	if index < 0 or index >= party.size():
		return 0
	var level: int = party_level(index)
	if level <= 1:
		return 0
	return _level_growth_value(party[index].id, key) * (level - 1)


func _level_growth_value(character_id: StringName, key: String) -> int:
	var growth: Dictionary = LEVEL_GROWTH_BY_CHARACTER_ID.get(character_id, DEFAULT_LEVEL_GROWTH)
	return int(growth.get(key, DEFAULT_LEVEL_GROWTH.get(key, 0)))


# ─── Economy ──────────────────────────────────────────────────────────
func add_gold(amount: int) -> void:
	gold += amount
	if amount > 0:
		total_gold_earned += amount
	EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true


# ─── Skill Tree ───────────────────────────────────────────────────────
func purchased_skill_node_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in purchased_skill_nodes.keys():
		out.append(id)
	return out


func unlocked_field_node_count() -> int:
	var count: int = 0
	for id in purchased_skill_nodes.keys():
		if id == &"root":
			continue
		count += 1
	return count


func field_region_name() -> String:
	var unlocked_nodes: int = unlocked_field_node_count()
	var best_name: String = str(FIELD_REGION_MILESTONES.front()["name"])
	for milestone: Dictionary in FIELD_REGION_MILESTONES:
		if total_gold_earned >= int(milestone["gold"]) and unlocked_nodes >= int(milestone["nodes"]):
			best_name = str(milestone["name"])
	return best_name


func field_region_summary() -> String:
	return "%s  |  %dG earned  |  %d nodes" % [
		field_region_name(),
		total_gold_earned,
		unlocked_field_node_count(),
	]


func skill_node_level(node_id: StringName) -> int:
	return int(purchased_skill_nodes.get(node_id, 0))


func has_skill_node(node_id: StringName) -> bool:
	return skill_node_level(node_id) > 0


func can_unlock_skill_node(node_id: StringName) -> bool:
	var node = SkillTreeDB.get_by_id(node_id)
	if node == null:
		return false
	if skill_node_level(node.id) >= node.max_level:
		return false
	for prereq_id: StringName in node.prerequisite_ids:
		if not has_skill_node(prereq_id):
			return false
	return true


func can_purchase_skill_node(node_id: StringName) -> bool:
	var node = SkillTreeDB.get_by_id(node_id)
	if node == null or not can_unlock_skill_node(node.id):
		return false
	if gold < node.cost:
		return false
	if node.linked_modifier and not can_add_modifier(node.linked_modifier):
		return false
	return true


func purchase_skill_node(node_id: StringName) -> bool:
	var node = SkillTreeDB.get_by_id(node_id)
	if node == null:
		EventBus.skill_node_purchase_failed.emit(null)
		return false
	if not can_purchase_skill_node(node.id):
		EventBus.skill_node_purchase_failed.emit(node)
		return false
	if not spend_gold(node.cost):
		EventBus.skill_node_purchase_failed.emit(node)
		return false
	purchased_skill_nodes[node.id] = skill_node_level(node.id) + 1
	if node.linked_modifier:
		add_modifier(node.linked_modifier)
		EventBus.modifier_purchased.emit(node.linked_modifier)
	EventBus.skill_node_purchase_succeeded.emit(node)
	return true


func skill_effect_bool(key: String) -> bool:
	for node in _purchased_skill_node_data():
		if bool(node.effect_data.get(key, false)):
			return true
	return false


func skill_effect_int_sum(key: String) -> int:
	var total: int = 0
	for node in _purchased_skill_node_data():
		total += int(node.effect_data.get(key, 0))
	return total


func skill_effect_float_sum(key: String) -> float:
	var total: float = 0.0
	for node in _purchased_skill_node_data():
		total += float(node.effect_data.get(key, 0.0))
	return total


func skill_effect_float_product(key: String, default_value: float = 1.0) -> float:
	var value: float = default_value
	for node in _purchased_skill_node_data():
		if node.effect_data.has(key):
			value *= float(node.effect_data[key])
	return value


func field_enemy_count_bonus() -> int:
	return skill_effect_int_sum("field_enemy_count_bonus")


func field_crowd_cap_bonus() -> int:
	return skill_effect_int_sum("field_crowd_cap_bonus")


func field_spawn_batch_bonus() -> int:
	return skill_effect_int_sum("field_spawn_batch_bonus")


func field_spawner_enabled() -> bool:
	return has_skill_node(&"spawner")


func field_spawn_interval_multiplier() -> float:
	return skill_effect_float_product("field_spawn_interval_mult")


func field_size_multiplier() -> float:
	return maxf(1.0, skill_effect_float_product("field_size_mult"))


func gold_drops_enabled() -> bool:
	return has_skill_node(&"gold")


func item_drops_enabled() -> bool:
	return has_skill_node(&"item")


func chaser_enemies_enabled() -> bool:
	return skill_effect_bool("chaser_enemies_enabled")


func enemies_per_window_bonus() -> int:
	return skill_effect_int_sum("enemies_per_window_bonus")


func battle_turn_interval_multiplier() -> float:
	return skill_effect_float_product("battle_turn_interval_mult")


func pickup_range_multiplier() -> float:
	return maxf(1.0, skill_effect_float_product("pickup_range_mult"))


func battle_movement_unlocked() -> bool:
	return has_skill_node(&"battle_movement") or skill_effect_bool("battle_movement_enabled")


func begin_field_battle_pause() -> void:
	_field_battle_pause_count += 1


func end_field_battle_pause() -> void:
	_field_battle_pause_count = maxi(0, _field_battle_pause_count - 1)


func is_field_battle_paused() -> bool:
	return _field_battle_pause_count > 0


func _purchased_skill_node_data() -> Array:
	var out: Array = []
	for id in purchased_skill_nodes.keys():
		var node = SkillTreeDB.get_by_id(id)
		if node:
			out.append(node)
	return out


func _ensure_default_skill_nodes() -> void:
	for node_id: StringName in [&"root", &"gold", &"item"]:
		if not purchased_skill_nodes.has(node_id):
			purchased_skill_nodes[node_id] = 1


func modifier_purchase_cost(mod: ModifierData) -> int:
	if mod == null:
		return 0
	if mod.category == ModifierData.Category.COMPANION or mod.max_level <= 1:
		return mod.cost
	var level: int = clampi(modifier_level(mod.id), 0, mod.max_level - 1)
	if level == 0:
		return mod.cost
	var raw_cost: float = float(mod.cost) * _price_multiplier_for_level(level)
	return maxi(mod.cost, ceili(raw_cost / 5.0) * 5)


func modifier_next_int_effect(mod: ModifierData, key: String) -> int:
	if mod == null:
		return 0
	return _int_effect_value_for_stack(mod, key, modifier_level(mod.id))


func modifier_last_int_effect(mod: ModifierData, key: String) -> int:
	if mod == null:
		return 0
	return _int_effect_value_for_stack(mod, key, maxi(0, modifier_level(mod.id) - 1))


func modifier_next_float_effect(mod: ModifierData, key: String) -> float:
	if mod == null:
		return 0.0
	return _float_effect_value_for_stack(mod, key, modifier_level(mod.id), _multipliers_for_float_key(key))


func modifier_last_float_effect(mod: ModifierData, key: String) -> float:
	if mod == null:
		return 0.0
	return _float_effect_value_for_stack(mod, key, maxi(0, modifier_level(mod.id) - 1), _multipliers_for_float_key(key))


## Check whether `mod` can actually be applied right now. Settlement shops should
## call this *before* spending gold so a stale/invalid card doesn't silently
## eat the player's coin.
func can_add_modifier(mod: ModifierData) -> bool:
	if mod == null:
		return false
	if mod.required_party_member_id != &"" and not has_party_member(mod.required_party_member_id):
		return false
	if mod.category == ModifierData.Category.COMPANION:
		if _available_recruits(mod).is_empty():
			return false
	elif modifier_level(mod.id) >= mod.max_level:
		return false
	return true


func _on_modifier_purchase_requested(mod: ModifierData, source: Node) -> void:
	if not can_add_modifier(mod):
		EventBus.modifier_purchase_failed.emit(mod, source)
		return
	var cost: int = modifier_purchase_cost(mod)
	if not spend_gold(cost):
		EventBus.modifier_purchase_failed.emit(mod, source)
		return
	add_modifier(mod)
	EventBus.modifier_purchased.emit(mod)
	EventBus.card_purchased.emit(mod, cost)
	EventBus.modifier_purchase_succeeded.emit(mod, source)


func add_modifier(mod: ModifierData) -> void:
	# Companion cards take a different path: they grow the party instead of
	# stacking onto active_modifiers.
	if mod.category == ModifierData.Category.COMPANION:
		_recruit_companion(mod)
		return
	active_modifiers.append(mod)
	EventBus.modifier_picked.emit(mod)
	# Hearty-style: an HP bonus also heals up so the boost is felt immediately.
	# Per-hero HP cards only heal their owner; party-wide cards heal everyone.
	var hp_bonus: int = _int_effect_value_for_stack(mod, "hp_flat", modifier_level(mod.id) - 1)
	if hp_bonus > 0:
		var owner_id: StringName = mod.required_party_member_id
		for i in party.size():
			if owner_id != &"" and party[i].id != owner_id:
				continue
			party_hp[i] = min(party_hp[i] + hp_bonus, effective_max_hp(i))
			EventBus.party_member_hp_changed.emit(i, party_hp[i], effective_max_hp(i))
		EventBus.party_hp_changed.emit()


## Add the companion to the party. Caller must verify with can_add_modifier()
## first; this method asserts those preconditions and skips on failure to
## stay safe against logic errors.
## New member's starting HP/MP respects existing modifiers (e.g. Hearty bonus).
func _recruit_companion(mod: ModifierData) -> void:
	if not can_add_modifier(mod):
		push_warning("[GameState] _recruit_companion called with invalid mod: %s" % mod.id)
		return
	var recruits: Array[CharacterData] = _available_recruits(mod)
	if recruits.is_empty():
		return
	var recruited: CharacterData = recruits.pick_random()
	party.append(recruited)
	var idx: int = party.size() - 1
	party_levels.append(1)
	party_xp.append(0)
	party_equipment.append(_empty_equipment_slots())
	party_hp.append(effective_max_hp(idx))
	party_mp.append(recruited.max_mp)
	recruited_companions.append(mod)
	_grant_starter_skill(recruited)
	EventBus.modifier_picked.emit(mod)
	EventBus.party_changed.emit()


func _grant_starter_skill(character: CharacterData) -> void:
	var starter := STARTER_SKILL_BY_CHARACTER_ID.get(character.id, null) as ModifierData
	if starter == null or modifier_level(starter.id) > 0:
		return
	active_modifiers.append(starter)
	EventBus.modifier_picked.emit(starter)


func _available_recruits(mod: ModifierData) -> Array[CharacterData]:
	var candidates: Array[CharacterData] = []
	if mod.companion_pool.is_empty():
		if mod.companion_data:
			candidates.append(mod.companion_data)
	else:
		candidates = mod.companion_pool.duplicate()
	var out: Array[CharacterData] = []
	for candidate: CharacterData in candidates:
		if candidate and not has_party_member(candidate.id):
			out.append(candidate)
	return out


func has_party_member(character_id: StringName) -> bool:
	for member: CharacterData in party:
		if member.id == character_id:
			return true
	return false


func modifier_level(modifier_id: StringName) -> int:
	var level: int = 0
	for mod: ModifierData in active_modifiers:
		if mod.id == modifier_id:
			level += 1
	return level


# ─── Field Loop ───────────────────────────────────────────────────────
func start_next_field_loop() -> void:
	field_loop_count += 1
	EventBus.field_loop_started.emit(field_loop_count)


# ─── Enemy scaling ────────────────────────────────────────────────────
func scaled_enemy_max_hp(data: EnemyData) -> int:
	if data == null:
		return 1
	return data.max_hp


func scaled_enemy_attack(data: EnemyData) -> int:
	if data == null:
		return 1
	return data.attack


func scaled_enemy_defense(data: EnemyData) -> int:
	if data == null:
		return 0
	return data.defense


func scaled_enemy_agility(data: EnemyData) -> int:
	if data == null:
		return 0
	return data.agility


func scaled_enemy_gold_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	return 1


func scaled_enemy_xp_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	return maxi(1, data.xp_reward)


# ─── Equipment ────────────────────────────────────────────────────────
func collect_item(item: ItemData) -> bool:
	if item == null:
		return false
	_absorb_item_entry(_make_item_entry(item, 1))
	return true


func add_item_to_inventory(item: ItemData) -> void:
	if item == null:
		return
	_absorb_item_entry(_make_item_entry(item, 1))


func _add_item_entry_to_inventory(entry: Dictionary) -> void:
	if item_entry_data(entry) == null:
		return
	inventory.append(entry)
	EventBus.inventory_changed.emit()


func equip_item(item: ItemData) -> bool:
	if item == null:
		return false
	return _equip_item_entry(_make_item_entry(item, 1))


func _equip_item_entry(entry: Dictionary) -> bool:
	var item: ItemData = item_entry_data(entry)
	if item == null:
		return false
	var target_index: int = _equipment_target_index(item)
	if target_index < 0:
		return false
	var slot_index: int = _equipment_slot_index(target_index, item, false)
	if slot_index < 0:
		return false
	party_equipment[target_index][slot_index] = entry
	party_hp[target_index] = mini(party_hp[target_index], effective_max_hp(target_index))
	EventBus.party_member_hp_changed.emit(target_index, party_hp[target_index], effective_max_hp(target_index))
	EventBus.party_equipment_changed.emit(target_index)
	return true


func can_equip_item(item: ItemData) -> bool:
	return item != null and _equipment_target_index(item) >= 0


func inventory_items() -> Array:
	return inventory.duplicate()


func equipment_for_member(index: int) -> Array:
	if index < 0 or index >= party_equipment.size():
		return _empty_equipment_slots()
	return party_equipment[index].duplicate()


func equipment_slot_name(slot: int) -> String:
	if slot >= 0 and slot < EQUIPMENT_SLOT_LABELS.size():
		return EQUIPMENT_SLOT_LABELS[slot]
	return "Item"


func item_entry_data(entry) -> ItemData:
	if entry is ItemData:
		return entry as ItemData
	if entry is Dictionary:
		return (entry as Dictionary).get("item", null) as ItemData
	return null


func item_entry_level(entry) -> int:
	if entry is Dictionary:
		return maxi(1, int((entry as Dictionary).get("level", 1)))
	return 1 if entry is ItemData else 0


func item_entry_tooltip(entry) -> String:
	var item: ItemData = item_entry_data(entry)
	if item == null:
		return ""
	var level: int = item_entry_level(entry)
	var lines: PackedStringArray = []
	lines.append("%s  Lv %d" % [item.display_name, level])
	lines.append("%s  |  %s" % [equipment_slot_name(int(item.slot)), _item_owner_label(item)])
	var stat_line: String = _item_stat_line(item, level)
	lines.append(stat_line if not stat_line.is_empty() else "No stats")
	if level > 0:
		lines.append("Merge: same Lv %d -> Lv %d" % [level, level + 1])
	return "\n".join(lines)


func party_member_stat_tooltip(index: int) -> String:
	if index < 0 or index >= party.size():
		return ""
	var member: CharacterData = party[index]
	var max_hp: int = effective_max_hp(index)
	var hp: int = party_hp[index] if index < party_hp.size() else max_hp
	var mp: int = party_mp[index] if index < party_mp.size() else member.max_mp
	var lines: PackedStringArray = []
	lines.append("%s  Lv %d" % [member.display_name, party_level(index)])
	lines.append("HP %d/%d   MP %d/%d" % [hp, max_hp, mp, member.max_mp])
	lines.append("ATK %d   DEF %d   AGI %d" % [
		effective_attack(index),
		effective_defense(index),
		effective_agility(index),
	])
	lines.append("XP %d/%d" % [
		party_xp[index] if index < party_xp.size() else 0,
		party_xp_to_next(index),
	])
	lines.append("Gear  %s" % _member_gear_stat_line(index))
	return "\n".join(lines)


func enemy_stat_tooltip(data: EnemyData, current_hp: int = -1, max_hp_override: int = -1) -> String:
	if data == null:
		return ""
	var max_hp_value: int = max_hp_override if max_hp_override > 0 else scaled_enemy_max_hp(data)
	var hp_value: int = current_hp if current_hp >= 0 else max_hp_value
	var gold_reward: int = scaled_enemy_gold_reward(data) if gold_drops_enabled() else 0
	var lines: PackedStringArray = []
	lines.append(data.display_name)
	lines.append("HP %d/%d" % [hp_value, max_hp_value])
	lines.append("ATK %d   DEF %d   AGI %d" % [
		scaled_enemy_attack(data),
		scaled_enemy_defense(data),
		scaled_enemy_agility(data),
	])
	lines.append("XP %d   Gold %d" % [scaled_enemy_xp_reward(data), gold_reward])
	if data.chases_player_on_field:
		lines.append("Field: chase %d  detect %d" % [int(data.field_chase_speed), int(data.field_detect_radius)])
	else:
		lines.append("Field: passive  wander %d" % int(data.field_wander_speed))
	return "\n".join(lines)


func _make_item_entry(item: ItemData, level: int = 1) -> Dictionary:
	return {
		"item": item,
		"level": maxi(1, level),
	}


func _item_owner_label(item: ItemData) -> String:
	if item.allowed_character_id == &"":
		return "Any member"
	return "%s only" % _character_display_name(item.allowed_character_id)


func _character_display_name(character_id: StringName) -> String:
	for member: CharacterData in party:
		if member.id == character_id:
			return member.display_name
	match character_id:
		&"hero": return "Hero"
		&"mage": return "Mage"
		&"priest": return "Priest"
		&"thief": return "Thief"
	return String(character_id).capitalize()


func _item_stat_line(item: ItemData, level: int) -> String:
	var parts: PackedStringArray = []
	var hp: int = item.max_hp_bonus * level
	var atk: int = item.attack_bonus * level
	var defense: int = item.defense_bonus * level
	var agility: int = item.agility_bonus * level
	if hp != 0:
		parts.append(_signed_stat("HP", hp))
	if atk != 0:
		parts.append(_signed_stat("ATK", atk))
	if defense != 0:
		parts.append(_signed_stat("DEF", defense))
	if agility != 0:
		parts.append(_signed_stat("AGI", agility))
	return "   ".join(parts)


func _member_gear_stat_line(index: int) -> String:
	var parts: PackedStringArray = []
	var hp: int = _equipment_bonus(index, "max_hp_bonus")
	var atk: int = _equipment_bonus(index, "attack_bonus")
	var defense: int = _equipment_bonus(index, "defense_bonus")
	var agility: int = _equipment_bonus(index, "agility_bonus")
	if hp != 0:
		parts.append(_signed_stat("HP", hp))
	if atk != 0:
		parts.append(_signed_stat("ATK", atk))
	if defense != 0:
		parts.append(_signed_stat("DEF", defense))
	if agility != 0:
		parts.append(_signed_stat("AGI", agility))
	return "none" if parts.is_empty() else "   ".join(parts)


func _signed_stat(label: String, value: int) -> String:
	var sign: String = "+" if value > 0 else ""
	return "%s %s%d" % [label, sign, value]


func _absorb_item_entry(entry: Dictionary) -> void:
	var item: ItemData = item_entry_data(entry)
	var level: int = item_entry_level(entry)
	if item == null or level <= 0:
		return
	var target_index: int = _equipment_target_index(item)
	if target_index >= 0:
		var equipped_slot: int = _find_equipped_match(target_index, item, level)
		if equipped_slot >= 0:
			_upgrade_equipped_entry(target_index, equipped_slot)
			return
	var inventory_index: int = _find_inventory_match(item, level)
	if inventory_index >= 0:
		inventory.remove_at(inventory_index)
		EventBus.inventory_changed.emit()
		_absorb_item_entry(_make_item_entry(item, level + 1))
		return
	if target_index >= 0 and not _has_equipped_item(target_index, item):
		if _equip_item_entry(entry):
			return
	_add_item_entry_to_inventory(entry)


func _upgrade_equipped_entry(member_index: int, slot_index: int) -> void:
	var entry = party_equipment[member_index][slot_index]
	var item: ItemData = item_entry_data(entry)
	var level: int = item_entry_level(entry)
	if item == null:
		return
	party_equipment[member_index][slot_index] = _make_item_entry(item, level + 1)
	_cascade_equipped_inventory_merge(member_index, slot_index)
	party_hp[member_index] = mini(party_hp[member_index], effective_max_hp(member_index))
	EventBus.party_member_hp_changed.emit(member_index, party_hp[member_index], effective_max_hp(member_index))
	EventBus.party_equipment_changed.emit(member_index)


func _cascade_equipped_inventory_merge(member_index: int, slot_index: int) -> void:
	while true:
		var entry = party_equipment[member_index][slot_index]
		var item: ItemData = item_entry_data(entry)
		var level: int = item_entry_level(entry)
		var inventory_index: int = _find_inventory_match(item, level)
		if inventory_index < 0:
			return
		inventory.remove_at(inventory_index)
		party_equipment[member_index][slot_index] = _make_item_entry(item, level + 1)
		EventBus.inventory_changed.emit()


func _find_equipped_match(member_index: int, item: ItemData, level: int) -> int:
	if member_index < 0 or member_index >= party_equipment.size():
		return -1
	for i in party_equipment[member_index].size():
		var entry = party_equipment[member_index][i]
		if _entry_matches(entry, item, level):
			return i
	return -1


func _find_inventory_match(item: ItemData, level: int) -> int:
	for i in inventory.size():
		if _entry_matches(inventory[i], item, level):
			return i
	return -1


func _has_equipped_item(member_index: int, item: ItemData) -> bool:
	if member_index < 0 or member_index >= party_equipment.size():
		return false
	for entry in party_equipment[member_index]:
		var equipped: ItemData = item_entry_data(entry)
		if equipped != null and equipped.id == item.id:
			return true
	return false


func _entry_matches(entry, item: ItemData, level: int) -> bool:
	var entry_item: ItemData = item_entry_data(entry)
	return entry_item != null and item != null and entry_item.id == item.id and item_entry_level(entry) == level


func _equipment_target_index(item: ItemData) -> int:
	if item.allowed_character_id != &"":
		for i in party.size():
			if party[i].id == item.allowed_character_id:
				return i
		return -1
	for i in party.size():
		var slot_index: int = _equipment_slot_index(i, item, false)
		if slot_index >= 0 and party_equipment[i][slot_index] == null:
			return i
	return 0 if not party.is_empty() else -1


func _equipment_slot_index(member_index: int, item: ItemData, allow_replace: bool = true) -> int:
	if member_index < 0 or member_index >= party_equipment.size():
		return -1
	if item.slot == ItemData.Slot.ACCESSORY:
		if party_equipment[member_index][EQUIPMENT_ACCESSORY_SLOT_A] == null:
			return EQUIPMENT_ACCESSORY_SLOT_A
		if party_equipment[member_index][EQUIPMENT_ACCESSORY_SLOT_B] == null:
			return EQUIPMENT_ACCESSORY_SLOT_B
		return EQUIPMENT_ACCESSORY_SLOT_A if allow_replace else -1
	return int(item.slot)


func _empty_equipment_slots() -> Array:
	var slots: Array = []
	for i in EQUIPMENT_SLOT_COUNT:
		slots.append(null)
	return slots


# ─── Modifier-aware stat helpers ──────────────────────────────────────
## True if `mod` should affect the party member with `character_id`. Modifiers
## with no owner (party-wide) apply to everyone; class-tagged modifiers only
## apply to the matching member. The per-hero stat splits (ATK/HP/dodge) live
## here — that's how Sharper Blades-style cards stay scoped to one hero.
func _modifier_applies_to(mod: ModifierData, character_id: StringName) -> bool:
	return mod.required_party_member_id == &"" or mod.required_party_member_id == character_id


func _price_multiplier_for_level(level: int) -> float:
	return float(PRICE_LEVEL_MULTIPLIERS[mini(level, PRICE_LEVEL_MULTIPLIERS.size() - 1)])


func _effect_multiplier_for_stack(stack_index: int, multipliers: Array) -> float:
	return float(multipliers[mini(stack_index, multipliers.size() - 1)])


func _multipliers_for_float_key(key: String) -> Array:
	if key == "hero_damage_bonus_mult":
		return DAMAGE_BONUS_STACK_MULTIPLIERS
	return EFFECT_STACK_MULTIPLIERS


func _int_effect_value_for_stack(mod: ModifierData, key: String, stack_index: int) -> int:
	var base: int = int(mod.effect_data.get(key, 0))
	if base <= 0:
		return 0
	var scaled: int = int(round(float(base) * _effect_multiplier_for_stack(stack_index, EFFECT_STACK_MULTIPLIERS)))
	return maxi(1, scaled)


func _float_effect_value_for_stack(mod: ModifierData, key: String, stack_index: int, multipliers: Array) -> float:
	var base: float = float(mod.effect_data.get(key, 0.0))
	if base <= 0.0:
		return 0.0
	return base * _effect_multiplier_for_stack(stack_index, multipliers)


func _stacked_int_effect_for_character(character_id: StringName, key: String) -> int:
	var bonus: int = 0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not _modifier_applies_to(mod, character_id):
			continue
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _int_effect_value_for_stack(mod, key, stack_index)
	return bonus


func _stacked_int_effect(key: String) -> int:
	var bonus: int = 0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _int_effect_value_for_stack(mod, key, stack_index)
	return bonus


func _stacked_float_effect(key: String, multipliers: Array) -> float:
	var bonus: float = 0.0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _float_effect_value_for_stack(mod, key, stack_index, multipliers)
	return bonus


func _stacked_float_effect_for_character(character_id: StringName, key: String, multipliers: Array) -> float:
	var bonus: float = 0.0
	var stacks_by_id: Dictionary = {}
	for mod: ModifierData in active_modifiers:
		if not _modifier_applies_to(mod, character_id):
			continue
		if not mod.effect_data.has(key):
			continue
		var stack_index: int = int(stacks_by_id.get(mod.id, 0))
		stacks_by_id[mod.id] = stack_index + 1
		bonus += _float_effect_value_for_stack(mod, key, stack_index, multipliers)
	return bonus


func effective_attack(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].attack + _level_bonus(index, "atk") + _equipment_bonus(index, "attack_bonus") + _stacked_int_effect_for_character(character_id, "atk_flat")


func effective_defense(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].defense + _level_bonus(index, "def") + _equipment_bonus(index, "defense_bonus") + _stacked_int_effect_for_character(character_id, "def_flat")


func effective_agility(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].agility + _level_bonus(index, "agi") + _equipment_bonus(index, "agility_bonus") + _stacked_int_effect_for_character(character_id, "agi_flat")


func effective_move_speed(base_speed: float) -> float:
	var flat_bonus: float = float(_stacked_int_effect("move_speed_flat"))
	var mult_bonus: float = 0.0
	for mod: ModifierData in active_modifiers:
		mult_bonus += float(mod.effect_data.get("move_speed_mult", 0.0))
	return (base_speed + flat_bonus) * (1.0 + mult_bonus) * _active_move_speed_drag_multiplier() * _active_move_speed_boost_multiplier()


func apply_move_speed_drag(multiplier: float, duration: float) -> void:
	_move_speed_drag_multiplier = minf(_active_move_speed_drag_multiplier(), clampf(multiplier, 0.05, 1.0))
	_move_speed_drag_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)


func apply_move_speed_boost(multiplier: float, duration: float) -> void:
	_move_speed_boost_multiplier = maxf(_active_move_speed_boost_multiplier(), maxf(multiplier, 1.0))
	_move_speed_boost_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)


func clear_move_speed_drag() -> void:
	_move_speed_drag_multiplier = 1.0
	_move_speed_drag_until_msec = 0


func _active_move_speed_drag_multiplier() -> float:
	if Time.get_ticks_msec() > _move_speed_drag_until_msec:
		_move_speed_drag_multiplier = 1.0
	return _move_speed_drag_multiplier


func _active_move_speed_boost_multiplier() -> float:
	if Time.get_ticks_msec() > _move_speed_boost_until_msec:
		_move_speed_boost_multiplier = 1.0
	return _move_speed_boost_multiplier


func roll_evade(index: int) -> bool:
	if index < 0 or index >= party.size():
		return false
	var character_id: StringName = party[index].id
	var chance: float = _stacked_float_effect_for_character(character_id, "evade_chance", EFFECT_STACK_MULTIPLIERS)
	chance = clampf(chance, 0.0, 0.75)
	return randf() < chance


func hero_attack_multiplier() -> float:
	return 1.0 + _stacked_float_effect("hero_damage_bonus_mult", DAMAGE_BONUS_STACK_MULTIPLIERS)


func mage_splash_extra_targets() -> int:
	var extra_targets: int = 0
	for mod: ModifierData in active_modifiers:
		extra_targets += int(mod.effect_data.get("mage_splash_extra_targets", 0))
	return extra_targets


func mage_splash_damage_multiplier() -> float:
	var mult: float = 1.0
	for mod: ModifierData in active_modifiers:
		if mod.effect_data.has("mage_splash_damage_mult"):
			mult = minf(mult, float(mod.effect_data["mage_splash_damage_mult"]))
	return mult


func priest_heal_amount() -> int:
	return _stacked_int_effect("priest_heal_flat")


func priest_attack_multiplier() -> float:
	var mult: float = 1.0
	for mod: ModifierData in active_modifiers:
		if mod.effect_data.has("priest_attack_mult"):
			mult = minf(mult, float(mod.effect_data["priest_attack_mult"]))
	return mult


func thief_steal_chance() -> float:
	var chance: float = _stacked_float_effect("thief_steal_chance", EFFECT_STACK_MULTIPLIERS)
	return clampf(chance, 0.0, 0.95)


func thief_steal_gold_amount() -> int:
	var amount: int = 0
	for mod: ModifierData in active_modifiers:
		amount = maxi(amount, int(mod.effect_data.get("thief_steal_gold", 0)))
	return amount


func effective_max_hp(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].max_hp + _level_bonus(index, "hp") + _equipment_bonus(index, "max_hp_bonus") + _stacked_int_effect_for_character(character_id, "hp_flat")


func _equipment_bonus(index: int, property_name: StringName) -> int:
	if index < 0 or index >= party_equipment.size():
		return 0
	var total: int = 0
	for entry in party_equipment[index]:
		var item: ItemData = item_entry_data(entry)
		if item:
			total += int(item.get(property_name)) * item_entry_level(entry)
	return total


## Roll a crit. Returns { is_crit: bool, mult: float }.
## Multiple crit modifiers stack their chances (capped at 1.0); the largest
## multiplier wins.
func roll_crit() -> Dictionary:
	var total_chance: float = 0.0
	var max_mult: float = 1.0
	for mod: ModifierData in active_modifiers:
		total_chance += float(mod.effect_data.get("crit_chance", 0.0))
		var m: float = float(mod.effect_data.get("crit_mult", 1.0))
		if m > max_mult:
			max_mult = m
	total_chance = min(total_chance, 1.0)
	var rolled: bool = randf() < total_chance
	return { "is_crit": rolled, "mult": (max_mult if rolled else 1.0) }


## Roll Echo Strike-style modifiers. Returns the number of *extra* windows
## the encounter should spawn (beyond the original).
func roll_window_duplicates() -> int:
	var extras: int = skill_effect_int_sum("extra_windows_flat")
	for mod: ModifierData in active_modifiers:
		extras += int(mod.effect_data.get("extra_windows_flat", 0))
		var chance: float = float(mod.effect_data.get("duplicate_chance", 0.0))
		var max_dup: int = int(mod.effect_data.get("duplicate_max", 0))
		for j in max_dup:
			if randf() < chance:
				extras += 1
	return extras


func window_collision_damage_ratio() -> float:
	var ratio: float = 0.0
	for mod: ModifierData in active_modifiers:
		ratio = maxf(ratio, float(mod.effect_data.get("window_collision_damage_ratio", 0.0)))
	return ratio


func party_bump_damage_ratio() -> float:
	var ratio: float = 0.0
	for mod: ModifierData in active_modifiers:
		ratio = maxf(ratio, float(mod.effect_data.get("party_bump_damage_ratio", 0.0)))
	return ratio


func window_collision_heal_amount() -> int:
	return _stacked_int_effect("window_collision_heal_flat")


func battle_window_push_enabled() -> bool:
	return skill_effect_bool("window_push_enabled") or window_collision_damage_ratio() > 0.0


func window_bash_enabled() -> bool:
	return has_skill_node(&"window_bash") or window_collision_damage_ratio() > 0.0


func party_window_push_enabled() -> bool:
	return window_bash_enabled() or party_bump_damage_ratio() > 0.0 or window_collision_heal_amount() > 0


# ─── Reset ────────────────────────────────────────────────────────────
func reset_run() -> void:
	party.clear()
	party_hp.clear()
	party_mp.clear()
	party_levels.clear()
	party_xp.clear()
	party_equipment.clear()
	inventory.clear()
	gold = STARTING_GOLD
	purchased_skill_nodes.clear()
	_ensure_default_skill_nodes()
	total_gold_earned = 0
	enemies_killed = 0
	biggest_hit = 0
	active_modifiers.clear()
	recruited_companions.clear()
	_move_speed_drag_multiplier = 1.0
	_move_speed_drag_until_msec = 0
	_move_speed_boost_multiplier = 1.0
	_move_speed_boost_until_msec = 0
	_field_battle_pause_count = 0
	field_loop_count = 0
	run_started_at_ms = Time.get_ticks_msec()
	# Make sure UI listeners flush stale numbers (HUD gold, etc.).
	EventBus.gold_changed.emit(gold)
