extends Node

## Global signal bus.
## Game-wide events go here. Local communication should use plain signals.
## Connect with: EventBus.signal_name.connect(_on_signal_name)

# ─── Field / Encounter ────────────────────────────────────────────────
## Player collided with an enemy on the field. Triggers a battle_window spawn.
signal enemy_encountered(enemy: Node)

## Player stepped onto the town field tile. Main handles the scene transition.
signal town_entered(tile: Node)

# ─── Party Composition ────────────────────────────────────────────────
## Party roster changed (run start, swap, revival). Listeners should re-read
## GameState.party / party_hp from scratch.
signal party_changed()

# ─── Battle Window Lifecycle ──────────────────────────────────────────
signal battle_window_opened(window: Node)
signal battle_window_closed(window: Node)
## All battle windows have finished — there is no active combat anywhere.
## Used to gate stage_cleared so it doesn't fire while combat is still running.
signal all_battles_resolved()

# ─── Combat ───────────────────────────────────────────────────────────
## Damage dealt to *any* combatant. Used by floating numbers, juice, etc.
signal damage_dealt(target: Node, amount: int, world_position: Vector2)

## Enemy died. Used by reward popups, combat log, modifier triggers.
signal enemy_defeated(enemy: Node, gold: int, world_position: Vector2)

## Party HP changed for a specific member. Used by HUD.
signal party_member_hp_changed(index: int, new_hp: int, max_hp: int)

## At least one party member changed HP. Used for "any-change" listeners.
signal party_hp_changed()

## All party members are dead. Game over.
signal party_wiped()

## Actual HP removed from a party member after clamping overkill.
signal party_damage_taken(member_index: int, amount: int)

# ─── Stage / Progression ──────────────────────────────────────────────
signal stage_started(stage_num: int)
signal stage_cleared(stage_num: int)
signal run_cleared()

# ─── Economy / Modifiers ──────────────────────────────────────────────
signal gold_changed(new_gold: int)
signal modifier_offered(modifiers: Array)  ## Array[ModifierData]
signal modifier_purchase_requested(modifier: ModifierData, source: Node)
signal modifier_purchase_succeeded(modifier: ModifierData, source: Node)
signal modifier_purchase_failed(modifier: ModifierData, source: Node)
signal modifier_purchased(modifier: ModifierData)
signal card_purchased(modifier: ModifierData, cost: int)
signal modifier_picked(modifier: ModifierData)
