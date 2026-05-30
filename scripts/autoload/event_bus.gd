extends Node

## Global signal bus.
## Game-wide events go here. Local communication should use plain signals.
## Connect with: EventBus.signal_name.connect(_on_signal_name)

# ─── Field / Encounter ────────────────────────────────────────────────
## Player collided with an enemy on the field. Triggers a battle_window spawn.
signal enemy_encountered(enemy: Node)

## A party combo attack should damage the battle windows opened by that combo.
signal combo_attack_damage_requested(damage_ratio: float, combo_batch_id: int)

## Player stepped onto the home-base field tile. Main handles the scene transition.
signal town_entered(tile: Node)

# ─── Party Composition ────────────────────────────────────────────────
## Party roster changed (run start, swap, revival). Listeners should re-read
## GameState.party / party_hp from scratch.
signal party_changed()

# ─── Battle Window Lifecycle ──────────────────────────────────────────
signal battle_window_opened(window: Node)
signal battle_window_closed(window: Node)
## Fight is over but the window is still on screen as a closed chest waiting
## for the player to claim its reward. BattleManager releases modal pause and
## stops counting the window toward the multi-window cap from this point on.
signal battle_window_resolved(window: Node)
## All battle windows have finished — there is no active combat anywhere.
## Used to gate field-loop settlement so it doesn't fire while combat is running.
signal all_battles_resolved()

# ─── Combat ───────────────────────────────────────────────────────────
## Damage dealt to *any* combatant. Used by floating numbers, juice, etc.
signal damage_dealt(target: Node, amount: int, world_position: Vector2)

## Enemy died. Used by reward popups, combat log, modifier triggers.
signal enemy_defeated(enemy: Node, gold: int, world_position: Vector2)

## Party HP changed for a specific member. Used by HUD.
signal party_member_hp_changed(index: int, new_hp: int, max_hp: int)

## Party EXP/level changed for a specific member. Used by HUD.
signal party_member_xp_changed(index: int, xp: int, xp_to_next: int, level: int)
signal party_member_leveled_up(index: int, new_level: int)

## Party equipment changed for a specific member. Used by HUD.
signal party_equipment_changed(index: int)
signal inventory_changed()

## Field should spawn an item pickup at this world position.
signal field_item_drop_requested(item: ItemData, world_position: Vector2)
signal field_gold_drop_requested(amount: int, world_position: Vector2)

## At least one party member changed HP. Used for "any-change" listeners.
signal party_hp_changed()

## All party members are dead. Game over. (Unused under the downed/auto-recovery
## model — kept for compatibility; combat no longer ends the run.)
signal party_wiped()

## A party member hit 0 HP and is now DOWNED — out of combat, refilling in place.
signal party_member_downed(index: int)
## A downed party member finished refilling and stood back up (rejoined combat).
signal party_member_revived(index: int)

# ─── Field buildings (structure system) ────────────────────────────────
## A field building was purchased + placed. The Field spawns its structure.
signal building_built(id: StringName)
## The Sanctuary instantly revived a member (instead of the slow downed cycle).
## The structure plays a pulse; the member is back to full immediately.
signal sanctuary_revived(index: int)

# ─── Companions (condition → 등장, gold → 영입) ─────────────────────────
## A companion met its appearance condition and is now recruitable (등장).
signal companion_appeared(id: StringName)
## A companion was recruited into the party (영입). Party also emits party_changed.
signal companion_recruited(id: StringName)

# ─── Field tiles ───────────────────────────────────────────────────────
## The campfire tile was just placed (paid for). The Field spawns it at a random
## spot, records its position, and runs the one-time mage-arrival event.
signal campfire_placed()

## Actual HP removed from a party member after clamping overkill.
signal party_damage_taken(member_index: int, amount: int)

# ─── Field Loop / Progression ─────────────────────────────────────────
signal field_loop_started(loop_num: int)
signal field_loop_settled(loop_num: int)
signal run_cleared()
signal field_loop_timer_changed(remaining_seconds: int)
signal field_loop_finish_requested()

# ─── Economy / Modifiers ──────────────────────────────────────────────
signal gold_changed(new_gold: int)
signal modifier_offered(modifiers: Array)  ## Array[ModifierData]
signal modifier_purchase_requested(modifier: ModifierData, source: Node)
signal modifier_purchase_succeeded(modifier: ModifierData, source: Node)
signal modifier_purchase_failed(modifier: ModifierData, source: Node)
signal modifier_purchased(modifier: ModifierData)
signal card_purchased(modifier: ModifierData, cost: int)
signal modifier_picked(modifier: ModifierData)

# ─── Skill Tree ───────────────────────────────────────────────────────
signal skill_node_purchase_succeeded(node)
signal skill_node_purchase_failed(node)

# ─── Incremental combat (SPEED / LUCK / SCALE / TIER) ──────────────────
## A combat upgrade axis changed. `axis` is one of &"speed", &"luck",
## &"scale", &"tier", &"open_speed". UI refreshes + combat re-read off this.
signal combat_upgrade_changed(axis: StringName)
## Hero auto-equipped a newly unlocked weapon (SPEED skin). Battle windows show
## "○○ 장착!" and bump their hit-effect size.
signal weapon_equipped(weapon_name: String)
## Hero auto-equipped a newly unlocked armor (survival skin). Same "○○ 장착!"
## feedback; party defense rises.
signal armor_equipped(armor_name: String)
## A combat-upgrade purchase was attempted but refused (not enough gold, maxed,
## tier already owned, …). UI can flash the relevant control.
signal combat_upgrade_failed(axis: StringName)

## An enemy tier was just unlocked (cumulative-gold milestone reached + claimed).
## HUD shows a big "○○ 해금!" popup with the enemy sprite.
signal tier_unlocked(tier_id: StringName)

# ─── Per-enemy level (System 1) ────────────────────────────────────────
## An enemy tier's kill-progress changed (fires every kill). Left bar updates
## that tier's Lv number + progress gauge.
signal enemy_progress_changed(tier_id: StringName)
## An enemy tier leveled up. Used for extra juice (icon pop, etc.).
signal enemy_leveled_up(tier_id: StringName, level: int)

# ─── Treasure-chest buffer (System 2) ──────────────────────────────────
## The unopened-chest buffer crossed full/not-full. When full, new fights are
## refused until the player opens a chest. HUD shows a "상자 가득! 열어주세요" banner.
signal chest_buffer_full_changed(is_full: bool)
