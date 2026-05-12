extends Node

## Run-wide state: party, gold, modifiers, stage.
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
var inventory: Array[ItemData] = []

# ─── Economy ──────────────────────────────────────────────────────────
const STARTING_GOLD: int = 30

var gold: int = STARTING_GOLD
## Stat-affecting modifiers picked this run.
var active_modifiers: Array[ModifierData] = []
## Recruit cards that successfully added a member to `party` this run.
## Kept separate from active_modifiers because companions are *party state*,
## not stat effects — useful for run summaries and avoiding "modifiers: 0"
## logs after recruiting.
var recruited_companions: Array[ModifierData] = []

# ─── Progression ──────────────────────────────────────────────────────
var current_stage: int = 0

const MAX_CHARACTER_LEVEL: int = 20
const EQUIPMENT_SLOT_COUNT: int = 6
const EQUIPMENT_ACCESSORY_SLOT_A: int = 4
const EQUIPMENT_ACCESSORY_SLOT_B: int = 5
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
const ENEMY_GOLD_STAGE_INTERVAL: int = 5
const ENEMY_GOLD_STAGE_BONUS_CAP: int = 4
const ENEMY_HP_STAGE_LINEAR: float = 0.12
const ENEMY_HP_STAGE_QUADRATIC: float = 0.01
const ENEMY_ATTACK_STAGE_LINEAR: float = 0.08
const ENEMY_ATTACK_STAGE_QUADRATIC: float = 0.006


# ─── Run statistics (for the game-over summary) ───────────────────────
var enemies_killed: int = 0
var total_gold_earned: int = 0  ## lifetime, not affected by spending
var biggest_hit: int = 0
var run_started_at_ms: int = 0

func _ready() -> void:
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


## Check whether `mod` can actually be applied right now. Town shops should
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


# ─── Stage ────────────────────────────────────────────────────────────
func advance_stage() -> void:
	current_stage += 1
	EventBus.stage_started.emit(current_stage)


# ─── Enemy scaling ────────────────────────────────────────────────────
func scaled_enemy_max_hp(data: EnemyData) -> int:
	if data == null:
		return 1
	return maxi(1, int(round(float(data.max_hp) * _enemy_hp_multiplier(data))))


func scaled_enemy_attack(data: EnemyData) -> int:
	if data == null:
		return 1
	return maxi(1, int(round(float(data.attack) * _enemy_attack_multiplier(data))))


func scaled_enemy_defense(data: EnemyData) -> int:
	if data == null:
		return 0
	var bonus: int = 0
	if data.id == &"orc":
		bonus = int(floor(float(_enemy_stage_index()) / 5.0))
	return maxi(0, data.defense + bonus)


func scaled_enemy_agility(data: EnemyData) -> int:
	if data == null:
		return 0
	var bonus: int = 0
	if data.id == &"bat":
		bonus = int(floor(float(_enemy_stage_index()) / 3.0))
	return maxi(0, data.agility + bonus)


func scaled_enemy_gold_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	var bonus: int = mini(
		ENEMY_GOLD_STAGE_BONUS_CAP,
		int(floor(float(_enemy_stage_index()) / float(ENEMY_GOLD_STAGE_INTERVAL)))
	)
	return maxi(1, data.gold_reward + bonus)


func scaled_enemy_xp_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	var stage_bonus: int = int(floor(float(_enemy_stage_index()) / 3.0))
	return maxi(1, data.xp_reward + stage_bonus)


# ─── Equipment ────────────────────────────────────────────────────────
func collect_item(item: ItemData) -> bool:
	if item == null:
		return false
	if equip_item(item):
		return true
	add_item_to_inventory(item)
	return true


func add_item_to_inventory(item: ItemData) -> void:
	if item == null:
		return
	inventory.append(item)
	EventBus.inventory_changed.emit()


func equip_item(item: ItemData) -> bool:
	if item == null:
		return false
	var target_index: int = _equipment_target_index(item)
	if target_index < 0:
		return false
	var slot_index: int = _equipment_slot_index(target_index, item)
	if slot_index < 0:
		return false
	party_equipment[target_index][slot_index] = item
	party_hp[target_index] = mini(party_hp[target_index], effective_max_hp(target_index))
	EventBus.party_member_hp_changed.emit(target_index, party_hp[target_index], effective_max_hp(target_index))
	EventBus.party_equipment_changed.emit(target_index)
	return true


func can_equip_item(item: ItemData) -> bool:
	return item != null and _equipment_target_index(item) >= 0


func inventory_items() -> Array[ItemData]:
	return inventory.duplicate()


func equipment_for_member(index: int) -> Array:
	if index < 0 or index >= party_equipment.size():
		return _empty_equipment_slots()
	return party_equipment[index].duplicate()


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


func _enemy_stage_index() -> int:
	return maxi(0, current_stage - 1)


func _enemy_hp_multiplier(data: EnemyData) -> float:
	var s: float = float(_enemy_stage_index())
	var base_mult: float = 1.0 + s * ENEMY_HP_STAGE_LINEAR + s * s * ENEMY_HP_STAGE_QUADRATIC
	return _enemy_species_multiplier(data, base_mult, 0.8, 0.85, 1.2)


func _enemy_attack_multiplier(data: EnemyData) -> float:
	var s: float = float(_enemy_stage_index())
	var base_mult: float = 1.0 + s * ENEMY_ATTACK_STAGE_LINEAR + s * s * ENEMY_ATTACK_STAGE_QUADRATIC
	return _enemy_species_multiplier(data, base_mult, 0.6, 0.85, 1.15)


func _enemy_species_multiplier(
	data: EnemyData,
	base_mult: float,
	slime_growth: float,
	bat_growth: float,
	orc_growth: float
) -> float:
	var growth: float = 1.0
	if data.id == &"slime":
		growth = slime_growth
	elif data.id == &"bat":
		growth = bat_growth
	elif data.id == &"orc":
		growth = orc_growth
	return 1.0 + (base_mult - 1.0) * growth


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
	return (base_speed + flat_bonus) * (1.0 + mult_bonus)


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
	for item in party_equipment[index]:
		if item is ItemData:
			total += int((item as ItemData).get(property_name))
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
	var extras: int = 0
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
	return window_collision_damage_ratio() > 0.0


func party_window_push_enabled() -> bool:
	return party_bump_damage_ratio() > 0.0 or window_collision_heal_amount() > 0


## Apply gold modifiers to a base reward. Multiplicative then additive.
func modify_gold_reward(base: int) -> int:
	var mult: float = 1.0
	var flat: int = 0
	for mod: ModifierData in active_modifiers:
		mult *= float(mod.effect_data.get("gold_mult", 1.0))
		flat += int(mod.effect_data.get("gold_flat", 0))
	return int(round(base * mult)) + flat


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
	total_gold_earned = 0
	enemies_killed = 0
	biggest_hit = 0
	active_modifiers.clear()
	recruited_companions.clear()
	current_stage = 0
	run_started_at_ms = Time.get_ticks_msec()
	# Make sure UI listeners flush stale numbers (HUD gold, etc.).
	EventBus.gold_changed.emit(gold)
