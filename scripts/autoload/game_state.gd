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
## Stat-affecting modifiers picked this run.
var active_modifiers: Array[ModifierData] = []
## Recruit cards that successfully added a member to `party` this run.
## Kept separate from active_modifiers because companions are *party state*,
## not stat effects — useful for run summaries and avoiding "modifiers: 0"
## logs after recruiting.
var recruited_companions: Array[ModifierData] = []

# ─── Progression ──────────────────────────────────────────────────────
var current_stage: int = 0

# ─── Run statistics (for the game-over summary) ───────────────────────
var enemies_killed: int = 0
var total_gold_earned: int = 0  ## lifetime, not affected by spending
var biggest_hit: int = 0
var run_started_at_ms: int = 0

const STAGE_EXTRA_ENEMY_SLOT_CHANCE: float = 0.5


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
	for m: CharacterData in party:
		party_hp.append(m.max_hp)
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
	if not spend_gold(mod.cost):
		EventBus.modifier_purchase_failed.emit(mod, source)
		return
	add_modifier(mod)
	EventBus.card_purchased.emit(mod, mod.cost)
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
	var hp_bonus: int = int(mod.effect_data.get("hp_flat", 0))
	if hp_bonus > 0:
		for i in party.size():
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
	party_hp.append(effective_max_hp(idx))
	party_mp.append(recruited.max_mp)
	recruited_companions.append(mod)
	EventBus.modifier_picked.emit(mod)
	EventBus.party_changed.emit()


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


func effective_agility(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var bonus: int = 0
	for mod: ModifierData in active_modifiers:
		bonus += int(mod.effect_data.get("agi_flat", 0))
	return party[index].agility + bonus


func effective_move_speed(base_speed: float) -> float:
	var flat_bonus: float = 0.0
	var mult_bonus: float = 0.0
	for mod: ModifierData in active_modifiers:
		flat_bonus += float(mod.effect_data.get("move_speed_flat", 0.0))
		mult_bonus += float(mod.effect_data.get("move_speed_mult", 0.0))
	return (base_speed + flat_bonus) * (1.0 + mult_bonus)


func roll_evade(_index: int) -> bool:
	var chance: float = 0.0
	for mod: ModifierData in active_modifiers:
		chance += float(mod.effect_data.get("evade_chance", 0.0))
	chance = clampf(chance, 0.0, 0.75)
	return randf() < chance


func hero_attack_multiplier() -> float:
	var bonus: float = 0.0
	for mod: ModifierData in active_modifiers:
		bonus += float(mod.effect_data.get("hero_damage_bonus_mult", 0.0))
	return 1.0 + bonus


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
	var amount: int = 0
	for mod: ModifierData in active_modifiers:
		amount += int(mod.effect_data.get("priest_heal_flat", 0))
	return amount


func priest_attack_multiplier() -> float:
	var mult: float = 1.0
	for mod: ModifierData in active_modifiers:
		if mod.effect_data.has("priest_attack_mult"):
			mult = minf(mult, float(mod.effect_data["priest_attack_mult"]))
	return mult


func thief_steal_chance() -> float:
	var chance: float = 0.0
	for mod: ModifierData in active_modifiers:
		chance += float(mod.effect_data.get("thief_steal_chance", 0.0))
	return clampf(chance, 0.0, 0.95)


func thief_steal_gold_amount() -> int:
	var amount: int = 0
	for mod: ModifierData in active_modifiers:
		amount = maxi(amount, int(mod.effect_data.get("thief_steal_gold", 0)))
	return amount


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
		extras += int(mod.effect_data.get("extra_windows_flat", 0))
		var chance: float = float(mod.effect_data.get("duplicate_chance", 0.0))
		var max_dup: int = int(mod.effect_data.get("duplicate_max", 0))
		for j in max_dup:
			if randf() < chance:
				extras += 1
	return extras


## Roll extra enemies that may appear inside this battle window.
func roll_extra_enemies_per_window() -> int:
	var extras: int = roll_stage_extra_enemies_per_window()
	for mod: ModifierData in active_modifiers:
		extras += int(mod.effect_data.get("extra_enemies_per_window", 0))
		var slots: int = int(mod.effect_data.get("extra_enemy_slots_per_window", 0))
		var chance: float = clampf(float(mod.effect_data.get("extra_enemy_spawn_chance", 1.0)), 0.0, 1.0)
		for i in slots:
			if randf() < chance:
				extras += 1
	return extras


func roll_stage_extra_enemies_per_window() -> int:
	# Fields 2, 4, 6, and 8 each add one random extra-enemy slot.
	var slots: int = clampi(int(floor(float(current_stage) / 2.0)), 0, 4)
	var extras: int = 0
	for i in slots:
		if randf() < STAGE_EXTRA_ENEMY_SLOT_CHANCE:
			extras += 1
	return extras


func extra_field_enemies() -> int:
	var extras: int = 0
	for mod: ModifierData in active_modifiers:
		extras += int(mod.effect_data.get("field_enemies_flat", 0))
	return extras


func window_collision_damage_ratio() -> float:
	var ratio: float = 0.0
	for mod: ModifierData in active_modifiers:
		ratio = maxf(ratio, float(mod.effect_data.get("window_collision_damage_ratio", 0.0)))
	return ratio


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
	total_gold_earned = 0
	enemies_killed = 0
	biggest_hit = 0
	active_modifiers.clear()
	recruited_companions.clear()
	current_stage = 0
	run_started_at_ms = Time.get_ticks_msec()
	# Make sure UI listeners flush stale numbers (HUD gold, etc.).
	EventBus.gold_changed.emit(gold)
