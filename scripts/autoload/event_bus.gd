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

## The player wants the camera snapped back onto the hero (it had been panned away
## into free-look). Emitted by the party panel boxes on click; the Player listens
## and re-attaches its follow-camera. Clicking the field hero does the same locally.
signal camera_focus_hero_requested()

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

## A party member (by index) just took its attack turn. Used by the battle-formation
## avatars to play an attack-lunge. Fires once per attack, in any battle window.
signal party_member_attacked(index: int)

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
signal field_item_drop_requested(item: ItemData, world_position: Vector2, level: int)
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

## The WHOLE party just went down at once (collapse). Under the auto-recovery model
## the run doesn't end — but the death penalty fires: every floating (un-flipped)
## reward battle window is wiped. Stacking is now a gamble.
signal party_collapsed()

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

## The player clicked an enemy in the dock (paid place_cost). The Field spawns ONE
## of that tier at a random spot. (Direct click-to-place — the toggle/auto-spawn
## path is preserved separately for future automation.)
signal enemy_place_requested(tier_id: StringName)

## A generic field structure (TILES entry, e.g. village) was paid for + placed.
## The Field spawns its sprite at pending_placement_position.
signal structure_placed(tile_id: StringName)
## A placed field object (e.g. campfire) was clicked → the small [간다][닫기]
## bubble opens above it (ObjectActionPanel).
signal structure_clicked(structure: Node)
## [간다] pressed on a structure's bubble → the hero walks over; the 방문 창
## (ObjectWindow) opens on arrival.
signal structure_visit_requested(structure: Node)
## The hero ARRIVED at a structure → open the big centered 방문 창 for it.
## `structure` implements get_inspector_data() -> Dictionary.
signal object_window_requested(structure: Node)
## A story beat wants the 이벤트 창 (cutscene window). The field holds still while
## it plays. Known ids: &"campfire_mage" (모닥불 → 메이지 합류).
signal event_window_requested(event_id: StringName)
## 따로 다니기 (party split) was learned at the campfire.
signal party_split_learned()
## A party member moved between split groups (0 = hero's chain, 1+ = roaming squads).
signal member_group_changed(index: int, group: int)
## The split-group cap grew (모닥불 분할 확장 upgrade).
signal party_group_limit_changed(new_limit: int)
## A field target (ally / enemy / objet) was clicked → show it in the right property
## inspector. `target` implements get_inspector_data() -> Dictionary. null = deselect.
signal inspector_target_selected(target: Node)
## The "쉰다" button on the campfire panel was pressed.
signal rest_requested()

## The opening "lay the grass" step was taken — the world begins: the hero starts
## moving and the dock swaps the grass tile for the enemy roster.
signal world_started()

## The player named the hero in the opening. The hero's display name updates
## everywhere (party panel, battle log, tooltips) and the grass tile appears.
signal player_named(hero_name: String)

## Gold hit 0 with nothing in progress (no enemies/fights/loot) → a free "rescue
## slime" is offered in the dock so the run can't deadlock. The Field flashes a
## short "[저런..]" overlord-intervention line.
signal rescue_offered()

## A narration / story line for the always-on bottom text window (the "OS desktop"
## persistent log). The Field also mirrors its transient field messages here.
signal narration(text: String)

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

## ─── Objets (item-like collectibles dropped from battle, shelved on the left) ──
## An objet (village, …) was just claimed from a reward card. Free + immediate;
## the left panel shelves it as an owned tile. Most objets are one-time.
signal objet_acquired(id: StringName)

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
## feedback; party MAX HP rises.
signal armor_equipped(armor_name: String)
## A combat-upgrade purchase was attempted but refused (not enough gold, maxed,
## tier already owned, …). UI can flash the relevant control.
signal combat_upgrade_failed(axis: StringName)

## An enemy tier was just unlocked (cumulative-gold milestone reached + claimed).
## Used for combat-upgrade/panel refresh (NOT the big popup anymore).
signal tier_unlocked(tier_id: StringName)

## An enemy tier just became AVAILABLE in the dock (its cumulative-gold milestone
## was crossed) — fires once, the moment the new tile appears. HUD shows the big
## "○○ 해금!" popup here now (not on click).
signal tier_available(tier_id: StringName)

# ─── Per-enemy level (System 1) ────────────────────────────────────────
## An enemy tier's kill-progress changed (fires every kill). Left bar updates
## that tier's Lv number + progress gauge.
signal enemy_progress_changed(tier_id: StringName)
## An enemy tier leveled up. Used for extra juice (icon pop, etc.).
signal enemy_leveled_up(tier_id: StringName, level: int)
