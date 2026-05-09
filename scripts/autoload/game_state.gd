extends Node

## Run-wide state: party, gold, modifiers, stage.
## Read freely. Mutate through helper methods so signals fire correctly.
##
## Use the effective_* helpers when you need stat values during combat —
## they fold in active_modifiers. Raw fields on CharacterData are base only.

# ─── Party ────────────────────────────────────────────────────────────
## The 4 party members chosen for this run.
var party: Array[CharacterData] = []

## Current HP/MP per party member. Index matches `party`.
var party_hp: Array[int] = []
var party_mp: Array[int] = []

# ─── Economy ──────────────────────────────────────────────────────────
var gold: int = 0
var active_modifiers: Array[ModifierData] = []

# ─── Progression ──────────────────────────────────────────────────────
var current_stage: int = 0


# ─── Party setup ──────────────────────────────────────────────────────
## Initialize the party from a list of CharacterData. Resets HP/MP to max.
## Emits party_changed so listeners (HUD, etc.) can re-populate from scratch
## regardless of node-init order.
func set_party(members: Array[CharacterData]) -> void:
	party = members.duplicate()
	party_hp.clear()
	party_mp.clear()
	for m: CharacterData in party:
		party_hp.append(m.max_hp)
		party_mp.append(m.max_mp)
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
	party_hp[index] = max(0, party_hp[index] - amount)
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


# ─── Economy ──────────────────────────────────────────────────────────
func add_gold(amount: int) -> void:
	gold += amount
	EventBus.gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	EventBus.gold_changed.emit(gold)
	return true


func add_modifier(mod: ModifierData) -> void:
	active_modifiers.append(mod)
	EventBus.modifier_picked.emit(mod)
	# Hearty-style: an HP bonus also heals up so the boost is felt immediately.
	var hp_bonus: int = int(mod.effect_data.get("hp_flat", 0))
	if hp_bonus > 0:
		for i in party.size():
			party_hp[i] = min(party_hp[i] + hp_bonus, effective_max_hp(i))
			EventBus.party_member_hp_changed.emit(i, party_hp[i], effective_max_hp(i))
		EventBus.party_hp_changed.emit()


# ─── Stage ────────────────────────────────────────────────────────────
func advance_stage() -> void:
	current_stage += 1
	EventBus.stage_started.emit(current_stage)


# ─── Modifier-aware stat helpers ──────────────────────────────────────
func effective_attack(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var bonus: int = 0
	for mod: ModifierData in active_modifiers:
		bonus += int(mod.effect_data.get("atk_flat", 0))
	return party[index].attack + bonus


func effective_defense(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var bonus: int = 0
	for mod: ModifierData in active_modifiers:
		bonus += int(mod.effect_data.get("def_flat", 0))
	return party[index].defense + bonus


func effective_max_hp(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var bonus: int = 0
	for mod: ModifierData in active_modifiers:
		bonus += int(mod.effect_data.get("hp_flat", 0))
	return party[index].max_hp + bonus


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
		var chance: float = float(mod.effect_data.get("duplicate_chance", 0.0))
		var max_dup: int = int(mod.effect_data.get("duplicate_max", 0))
		for j in max_dup:
			if randf() < chance:
				extras += 1
	return extras


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
	gold = 0
	active_modifiers.clear()
	current_stage = 0
