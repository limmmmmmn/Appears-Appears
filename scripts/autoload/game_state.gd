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
## Per-member downed flag (HP hit 0). Downed members are out of combat and
## refill in place until they auto-stand. Parallel to `party`.
var party_downed: Array[bool] = []
## Fractional HP-refill carry per downed member index (heals < 1 HP/frame).
var _downed_recovery_accum: Dictionary = {}
## Set when the WHOLE party is downed at once; movement freezes until every
## member has fully refilled, then they resume together. (Individual members
## still stand/rejoin combat as they fill — this only gates field movement.)
var _party_collapsed: bool = false
var party_equipment: Array[Array] = []
var inventory: Array = []
var _move_speed_drag_multiplier: float = 1.0
var _move_speed_drag_until_msec: int = 0
var _move_speed_boost_multiplier: float = 1.0
var _move_speed_boost_until_msec: int = 0
var _field_battle_pause_count: int = 0

const FIELD_REGION_GRASS: StringName = &"grass"
const FIELD_REGION_FOREST: StringName = &"forest"

# ─── Economy ──────────────────────────────────────────────────────────
const STARTING_GOLD: int = 1  # enough to click-place the first slime (place_cost 1)

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

# ─── Incremental combat axes (WEAPONS / LUCK / SCALE) ──────────────────
## See Balance.gd for the formulas these levels feed. The combat stays
## turn-based; these multipliers shape its emergent gold-per-second.
## Weapons replace the old single SPEED track: one level per weapon TYPE
## (검/지팡이/둔기/단검). A member's damage uses their weapon type's multiplier,
## so unlocking a 지팡이 only boosts the mage, etc. type id → level (default 1).
var weapon_levels: Dictionary = {}
## Armor = flat party MAX HP (the armor shop is its UI skin). Survival axis.
## Level 1 = "맨몸" (no bonus). Shared by the whole party, like the weapon.
var armor_level: int = 1
## LOOT LEVELS — the 무기/방어구 upgrade now raises drop QUALITY (gear that falls
## in battle = this level), NOT direct stats. Power comes from manually equipping
## the dropped gear. weapon_level/armor_level stay at base (no direct effect).
var weapon_loot_level: int = 1
var armor_loot_level: int = 1
## LUCK = kill-gold JACKPOT CHANCE (frequency only — never a gold multiplier).
## Replaces the old GREED ×gold track, which compounded into a money explosion.
var luck_level: int = 1
## Chest open-speed level. 0 = base hover duration.
var open_speed_level: int = 0
## 자동 줍기 해금 — false = 수동 호버 줍기, true = 용사가 전리품을 자동으로 주움.
var auto_pickup_unlocked: bool = false
## 자동 전투 해금 — false = 수동 전투(Fight→대상 선택), true = 턴 타이머가 자동 진행.
var auto_battle_unlocked: bool = false
## 자동 이동 해금 — false = WASD/방향키 수동 이동, true = 용사가 적으로 자동 이동.
var auto_move_unlocked: bool = false
## SCALE = how many SCALE purchases were made; simultaneous window count =
## Balance.scale_window_count(scale_purchases). 0 purchases → 1 window.
var scale_purchases: int = 0
## Enemy tiers the player has unlocked. Slime is free from the start (its dock
## icon is click-PLACEABLE once the world has started).
var unlocked_tier_ids: Array[StringName] = [&"slime"]
## Tiers toggled ON for AUTO-SPAWN. Empty by default — click-to-place is the
## default; the toggle/auto-spawn path is dormant (future automation lever).
var active_tier_ids: Array[StringName] = []
## Opening gate: the world hasn't begun until the player lays the first grass.
## Until then the hero stands frozen and the dock shows only the grass tile.
var world_started: bool = false
## Opening step 0 — the player names the hero before anything else appears.
var player_name: String = ""
var name_entered: bool = false
## Random-name pool for the "랜덤" button in the name prompt.
const RANDOM_HERO_NAMES: PackedStringArray = [
	"아서", "레온", "카이", "유노", "리나", "도윤", "세라", "타이로", "미르", "하늘",
]
## Per-enemy-tier level (System 1) — grows automatically from kills, never
## bought. tier_id → int level (default 1).
var enemy_levels: Dictionary = {}
## tier_id → int kills accumulated toward the next level (resets each level-up).
var enemy_kill_progress: Dictionary = {}
## Field buildings the player has purchased + placed (reusable structure system).
## Persistent — a standing investment, not cleared per field loop.
var built_buildings: Array[StringName] = []
## Companions that met their appearance condition (등장) and can be recruited.
var companions_appeared: Array[StringName] = []
## How many times each upgrade category was bought (drives auto-building spawn +
## count-based companion recruit). category → count.
var upgrade_counts: Dictionary = {}
## Campfire field tile (left panel): a placed HP-regen outpost.
var campfire_placed: bool = false
var campfire_level: int = 1
var campfire_position: Vector2 = Vector2.ZERO
var _campfire_regen_accum: Dictionary = {}
## Lifetime counters that drive companion appearance conditions.
var total_enemy_kills: int = 0
var total_party_downs: int = 0

# ─── Progression ──────────────────────────────────────────────────────
var field_loop_count: int = 0
## Mouse-wheel camera zoom on the field. 1.0 = default; >1 zoom in, <1 zoom out.
## Persisted here so it survives the per-loop player rebuild.
var field_camera_zoom: float = 1.0
## True while the party is RESTING at the campfire (held still, healing to full).
## Freezes field movement so they stay put until everyone's topped off.
var party_resting: bool = false
## Drag-and-drop placement target: the world spot where the NEXT placed thing
## (enemy / campfire) should appear. Vector2.INF = none (fall back to near-player
## random). The Field consumes + clears it when it spawns the placement.
var pending_placement_position: Vector2 = Vector2.INF
var current_field_region_id: StringName = FIELD_REGION_GRASS
var story_companion_joined: bool = false
var story_gold_goal_announced: bool = false
var story_movement_battle_line_shown: bool = false
var story_mage_joined: bool = false

const FIELD_REGION_MILESTONES: Array[Dictionary] = [
	{"name": "초원", "gold": 0, "nodes": 0},
	{"name": "깊은 숲", "gold": 75, "nodes": 2},
	{"name": "오래된 폐허", "gold": 250, "nodes": 5},
	{"name": "검은 늪", "gold": 700, "nodes": 8},
	{"name": "마왕성 외곽", "gold": 1800, "nodes": 12},
	{"name": "마왕성", "gold": 4200, "nodes": 16},
]

const STORY_MODE_ENABLED: bool = true
const OPENING_SEQUENCE_ENABLED: bool = false
const STORY_GOLD_GOAL: int = 1000
const STORY_OPENING_LINES: PackedStringArray = [
	"마왕이 점령한 세계.",
	"용사는 너무 늦게 움직인다.",
]
const STORY_FIRST_CAMP_HERO_LINES: PackedStringArray = [
	"아직 너무 느려.",
	"이미 마왕은 세계를 정복했어.",
	"더 빠르게 가자.",
]
const STORY_FIRST_CAMP_SKILL_NODE_ID: StringName = &"battle_movement"
const STORY_MOVEMENT_BATTLE_LINE: String = "좋아 계속 움직이자."
const STORY_MAGE_COMPANION: CharacterData = preload("res://data/characters/mage.tres")
const STORY_FIELD_CONFIGS: Dictionary = {
	1: {
		"enemy_count": 3,
		"campfire_unlock_kills": 3,
		"intro": "필드 1 - 초원. 슬라임이 나타났습니다.",
	},
	2: {
		"enemy_count": 8,
		"campfire_unlock_kills": 3,
		"intro": "필드 2 - 싸우는 소리를 듣고 누군가 다가옵니다.",
		"recruit_first_companion": true,
		"companion_join_message": "동료가 나타났습니다. 함께 싸웁니다.",
	},
}
const STORY_FIRST_COMPANION: CharacterData = preload("res://data/characters/elf.tres")
const MAX_CHARACTER_LEVEL: int = 20
const PARTY_LEVELING_ENABLED: bool = true
const ITEM_MERGING_ENABLED: bool = false
const EQUIPMENT_SLOT_COUNT: int = 6
const EQUIPMENT_ACCESSORY_SLOT_A: int = 4
const EQUIPMENT_ACCESSORY_SLOT_B: int = 5
const EQUIPMENT_SLOT_LABELS: Array[String] = ["Weapon", "Shield", "Helmet", "Armor", "Accessory"]
const XP_CURVE_BASE: int = 10
const XP_CURVE_LEVEL_STEP: int = 5
const XP_CURVE_QUADRATIC: int = 3
# 방어력 폐지: 옛 "def" 성장치는 생존 축인 "hp"로 흡수(1:1). 두 축(공격/HP)만 유지.
const DEFAULT_LEVEL_GROWTH: Dictionary = {
	"hp": 5,
	"atk": 2,
	"agi": 1,
}
const LEVEL_GROWTH_BY_CHARACTER_ID: Dictionary = {
	&"hero": {"hp": 6, "atk": 2, "agi": 1},
	&"elf": {"hp": 5, "atk": 2, "agi": 2},
	&"mage": {"hp": 3, "atk": 3, "agi": 1},
	&"knight": {"hp": 8, "atk": 2, "agi": 0},
	&"priest": {"hp": 6, "atk": 1, "agi": 1},
	&"thief": {"hp": 3, "atk": 2, "agi": 2},
}

const PRICE_LEVEL_MULTIPLIERS = [1.0, 1.45, 2.05, 2.8, 3.7]
const EFFECT_STACK_MULTIPLIERS = [1.0, 0.75, 0.55, 0.4, 0.3]
const DAMAGE_BONUS_STACK_MULTIPLIERS = [1.0, 0.5, 0.3, 0.2, 0.16]
# ─── Run statistics (for the game-over summary) ───────────────────────
var enemies_killed: int = 0
var total_gold_earned: int = 0  ## lifetime, not affected by spending
## Tiers whose "available" popup already fired (so it shows once when the tile
## appears, not every gold tick). Reset per run.
var _tier_available_announced: Array[StringName] = []
var biggest_hit: int = 0
var run_started_at_ms: int = 0

func _ready() -> void:
	_ensure_default_skill_nodes()
	# Listen to bus events to keep counters fresh without coupling combat code.
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.modifier_purchase_requested.connect(_on_modifier_purchase_requested)


func _on_enemy_defeated(_enemy: Node, gold: int, _world_position: Vector2) -> void:
	enemies_killed += 1
	# Kill gold is paid IMMEDIATELY now — the floating "Ng" on the dead enemy IS
	# real money. The reward CARD on the window is a BONUS on top (🟧 = extra gold,
	# 🟥/🟩/🟦 = weapon/heal/xp). See battle_window._grant_reward.
	if gold > 0:
		add_gold(gold)


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
	party_downed.clear()
	_downed_recovery_accum.clear()
	_party_collapsed = false
	inventory.clear()
	for m: CharacterData in party:
		party_levels.append(1)
		party_xp.append(0)
		party_equipment.append(_empty_equipment_slots())
		party_hp.append(effective_max_hp(party_hp.size()))
		party_mp.append(m.max_mp)
		party_downed.append(false)
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
	if party_downed[index]:
		return  # already down and refilling — can't be hit further
	var before_hp: int = party_hp[index]
	party_hp[index] = max(0, party_hp[index] - amount)
	var actual_damage: int = before_hp - party_hp[index]
	if actual_damage > 0:
		EventBus.party_damage_taken.emit(index, actual_damage)
	EventBus.party_member_hp_changed.emit(index, party_hp[index], effective_max_hp(index))
	EventBus.party_hp_changed.emit()
	# Death = time loss, not game over.
	if party_hp[index] == 0:
		if sanctuary_active():
			# 성소 intervenes: full revive on the spot, never enters the downed
			# state — so no slowdown and the fight doesn't collapse.
			party_hp[index] = effective_max_hp(index)
			party_downed[index] = false
			_downed_recovery_accum[index] = 0.0
			EventBus.party_member_hp_changed.emit(index, party_hp[index], effective_max_hp(index))
			EventBus.party_hp_changed.emit()
			EventBus.sanctuary_revived.emit(index)
		else:
			# No sanctuary: drop into the downed/auto-recovery cycle.
			party_downed[index] = true
			_downed_recovery_accum[index] = 0.0
			total_party_downs += 1  # gates the 성소(sanctuary) build unlock
			EventBus.party_member_downed.emit(index)
			# Full collapse → freeze field movement until everyone recovers, AND fire
			# the death penalty (floating reward windows are wiped).
			if is_party_all_downed() and not _party_collapsed:
				_party_collapsed = true
				EventBus.party_collapsed.emit()


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
	if not PARTY_LEVELING_ENABLED:
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
	return Balance.party_xp_for_level(level)


## Level-up grants MAX HP only (kept generic for every party member, not just
## the hero). Attack is the SPEED/weapon axis and HP(survival) is the armor axis,
## so leveling only nudges HP/agility — keeps the stat space tiny (방어력 폐지).
func _level_bonus(index: int, key: String) -> int:
	if index < 0 or index >= party.size():
		return 0
	var level: int = party_level(index)
	if level <= 1:
		return 0
	# Level grants MAX HP (survival) + a little agility (ambush/turn order).
	# Attack stays SPEED/weapon; survival(HP) is the armor axis — no stat creep.
	match key:
		"hp":
			return Balance.HP_PER_LEVEL * (level - 1)
		"agi":
			return Balance.AGILITY_PER_LEVEL * (level - 1)
	return 0


func _level_growth_value(character_id: StringName, key: String) -> int:
	var growth: Dictionary = LEVEL_GROWTH_BY_CHARACTER_ID.get(character_id, DEFAULT_LEVEL_GROWTH)
	return int(growth.get(key, DEFAULT_LEVEL_GROWTH.get(key, 0)))


# ─── Economy ──────────────────────────────────────────────────────────
func add_gold(amount: int) -> void:
	gold += amount
	if amount > 0:
		total_gold_earned += amount  # gates gold-based building unlocks
		_announce_new_tiers()        # popup fires when a new tier becomes available
	EventBus.gold_changed.emit(gold)


## Fire the "○○ 해금!" popup the moment a tier's cumulative-gold milestone is
## crossed (the new tile appears in the dock) — once per tier, not on click.
func _announce_new_tiers() -> void:
	for i in Balance.tier_count():
		var id: StringName = Balance.tier_at(i)["id"]
		if is_tier_unlocked(id) or _tier_available_announced.has(id):
			continue
		if tier_threshold_reached(id):
			_tier_available_announced.append(id)
			EventBus.tier_available.emit(id)  # "○○ 해금!" popup
			unlock_tier(id)                   # auto-claim → tile is placeable right away


func story_field_index() -> int:
	return maxi(1, field_loop_count)


func story_opening_lines() -> PackedStringArray:
	return STORY_OPENING_LINES


func story_field_config() -> Dictionary:
	return STORY_FIELD_CONFIGS.get(story_field_index(), {})


func story_field_enemy_count() -> int:
	return int(story_field_config().get("enemy_count", 10 + story_field_index() * 2))


func story_campfire_unlock_kills() -> int:
	return int(story_field_config().get("campfire_unlock_kills", 3))


func story_field_intro() -> String:
	return str(story_field_config().get("intro", "필드 %d - 더 멀리 나아갑니다." % story_field_index()))


func story_should_recruit_first_companion() -> bool:
	# Disabled: companions now join via the condition→gold recruit system
	# (Balance.COMPANIONS), not story auto-recruit. Kept so callers don't break.
	return false


func story_first_companion_join_message() -> String:
	return str(story_field_config().get("companion_join_message", "동료가 나타났습니다. 함께 싸웁니다."))


func story_is_first_camp() -> bool:
	return STORY_MODE_ENABLED and story_field_index() == 1


func story_first_camp_hero_lines() -> PackedStringArray:
	return STORY_FIRST_CAMP_HERO_LINES


func story_first_camp_skill_node():
	return SkillTreeDB.get_by_id(STORY_FIRST_CAMP_SKILL_NODE_ID)


func story_claim_first_camp_skill_node():
	if not story_is_first_camp():
		return null
	var node = story_first_camp_skill_node()
	if node == null or has_skill_node(node.id):
		return null
	purchased_skill_nodes[node.id] = 1
	if node.linked_modifier:
		add_modifier(node.linked_modifier)
		EventBus.modifier_purchased.emit(node.linked_modifier)
	EventBus.skill_node_purchase_succeeded.emit(node)
	return node


func story_should_show_movement_battle_line() -> bool:
	return STORY_MODE_ENABLED \
		and not story_movement_battle_line_shown \
		and story_field_index() == 2 \
		and battle_movement_unlocked()


func story_claim_movement_battle_line() -> String:
	if not story_should_show_movement_battle_line():
		return ""
	story_movement_battle_line_shown = true
	return STORY_MOVEMENT_BATTLE_LINE


func story_should_play_mage_event() -> bool:
	return STORY_MODE_ENABLED \
		and story_field_index() == 3 \
		and not story_mage_joined \
		and STORY_MAGE_COMPANION != null \
		and not has_party_member(STORY_MAGE_COMPANION.id)


func story_recruit_mage_companion() -> bool:
	if story_mage_joined or STORY_MAGE_COMPANION == null:
		return false
	if has_party_member(STORY_MAGE_COMPANION.id):
		story_mage_joined = true
		return false
	party.append(STORY_MAGE_COMPANION)
	party_levels.append(1)
	party_xp.append(0)
	party_equipment.append(_empty_equipment_slots())
	party_hp.append(effective_max_hp(party_hp.size()))
	party_mp.append(STORY_MAGE_COMPANION.max_mp)
	party_downed.append(false)
	story_mage_joined = true
	EventBus.party_changed.emit()
	return true


func story_camp_line() -> String:
	if story_field_index() <= 1:
		return "불빛 말고는 아무것도 없습니다."
	if gold < STORY_GOLD_GOAL:
		return "돈 좀 모아서 잠자리좀 만들어보자. %d골드가 필요합니다." % STORY_GOLD_GOAL
	return "1000골드가 모였습니다. 이제 잠자리를 만들 수 있습니다."


func story_should_announce_gold_goal(new_gold: int) -> bool:
	return STORY_MODE_ENABLED \
		and not story_gold_goal_announced \
		and story_field_index() >= 2 \
		and new_gold >= STORY_GOLD_GOAL


func story_recruit_first_companion() -> bool:
	if story_companion_joined or STORY_FIRST_COMPANION == null:
		return false
	if _party_has_character(STORY_FIRST_COMPANION.id):
		story_companion_joined = true
		return false
	party.append(STORY_FIRST_COMPANION)
	party_levels.append(1)
	party_xp.append(0)
	party_equipment.append(_empty_equipment_slots())
	party_hp.append(effective_max_hp(party_hp.size()))
	party_mp.append(STORY_FIRST_COMPANION.max_mp)
	party_downed.append(false)
	story_companion_joined = true
	EventBus.party_changed.emit()
	return true


func _party_has_character(character_id: StringName) -> bool:
	for member: CharacterData in party:
		if member.id == character_id:
			return true
	return false


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
	if gold < skill_node_purchase_cost(node.id):
		return false
	if node.linked_modifier and not can_add_modifier(node.linked_modifier):
		return false
	return true


func skill_node_purchase_cost(node_id: StringName) -> int:
	var node = SkillTreeDB.get_by_id(node_id)
	if node == null:
		return 0
	if node.max_level <= 1:
		return node.cost
	var level: int = clampi(skill_node_level(node.id), 0, node.max_level - 1)
	if level == 0:
		return node.cost
	var raw_cost: float = float(node.cost) * _price_multiplier_for_level(level)
	return maxi(node.cost, ceili(raw_cost / 5.0) * 5)


func purchase_skill_node(node_id: StringName) -> bool:
	var node = SkillTreeDB.get_by_id(node_id)
	if node == null:
		EventBus.skill_node_purchase_failed.emit(null)
		return false
	if not can_purchase_skill_node(node.id):
		EventBus.skill_node_purchase_failed.emit(node)
		return false
	if not spend_gold(skill_node_purchase_cost(node.id)):
		EventBus.skill_node_purchase_failed.emit(node)
		return false
	purchased_skill_nodes[node.id] = skill_node_level(node.id) + 1
	if node.linked_modifier:
		add_modifier(node.linked_modifier)
		EventBus.modifier_purchased.emit(node.linked_modifier)
	EventBus.skill_node_purchase_succeeded.emit(node)
	return true


func skill_effect_bool(key: String) -> bool:
	for id in purchased_skill_nodes.keys():
		var node = SkillTreeDB.get_by_id(id)
		if node and skill_node_level(id) > 0 and bool(node.effect_data.get(key, false)):
			return true
	return false


func skill_effect_int_sum(key: String) -> int:
	var total: int = 0
	for id in purchased_skill_nodes.keys():
		var node = SkillTreeDB.get_by_id(id)
		if node:
			total += int(node.effect_data.get(key, 0)) * skill_node_level(id)
	return total


func skill_effect_float_sum(key: String) -> float:
	var total: float = 0.0
	for id in purchased_skill_nodes.keys():
		var node = SkillTreeDB.get_by_id(id)
		if node:
			total += float(node.effect_data.get(key, 0.0)) * float(skill_node_level(id))
	return total


func skill_effect_float_product(key: String, default_value: float = 1.0) -> float:
	var value: float = default_value
	for id in purchased_skill_nodes.keys():
		var node = SkillTreeDB.get_by_id(id)
		if node and node.effect_data.has(key):
			for i in skill_node_level(id):
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


func forest_region_unlocked() -> bool:
	return skill_effect_bool("forest_region_unlocked") or has_skill_node(&"forest_region")


func current_field_region_display_name() -> String:
	if current_field_region_id == FIELD_REGION_FOREST:
		return "숲"
	return "초원"


func gold_drops_enabled() -> bool:
	return has_skill_node(&"gold")


func item_drops_enabled() -> bool:
	return true  # gear drops are core now (loot-level system) — no skill gate


func chaser_enemies_enabled() -> bool:
	return skill_effect_bool("chaser_enemies_enabled")


func enemies_per_window_bonus() -> int:
	return skill_effect_int_sum("enemies_per_window_bonus")


func battle_turn_interval_multiplier() -> float:
	return skill_effect_float_product("battle_turn_interval_mult")


func pickup_range_multiplier() -> float:
	return maxf(1.0, skill_effect_float_product("pickup_range_mult"))


# ─── 자동 줍기 (manual hover → hero auto-collects) ──────────────────────
## Before unlock: loot is hover-collected by the cursor. After: the hero walks to
## drops and grabs them on the way (the preserved auto path turns back on).
func auto_pickup_cost() -> int:
	return Balance.AUTO_PICKUP_COST


func can_unlock_auto_pickup() -> bool:
	return not auto_pickup_unlocked and gold >= auto_pickup_cost()


func unlock_auto_pickup() -> bool:
	if auto_pickup_unlocked or not spend_gold(auto_pickup_cost()):
		EventBus.combat_upgrade_failed.emit(&"auto_pickup")
		return false
	auto_pickup_unlocked = true
	EventBus.combat_upgrade_changed.emit(&"auto_pickup")
	return true


# ─── 자동 전투 (manual turn input → auto turn timer) ────────────────────
## Before unlock: the player drives each party member's turn by hand (Fight → pick a
## target). After: every battle window ticks its turns automatically.
func auto_battle_cost() -> int:
	return Balance.AUTO_BATTLE_COST


func can_unlock_auto_battle() -> bool:
	return not auto_battle_unlocked and gold >= auto_battle_cost()


func unlock_auto_battle() -> bool:
	if auto_battle_unlocked or not spend_gold(auto_battle_cost()):
		EventBus.combat_upgrade_failed.emit(&"auto_battle")
		return false
	auto_battle_unlocked = true
	EventBus.combat_upgrade_changed.emit(&"auto_battle")
	return true


# ─── 자동 이동 (manual WASD → hero auto-walks to enemies) ───────────────
## Before unlock: the player drives the hero with WASD / arrows. After: the hero
## auto-walks toward the nearest enemy/drop (manual input still overrides).
func auto_move_cost() -> int:
	return Balance.AUTO_MOVE_COST


func can_unlock_auto_move() -> bool:
	return not auto_move_unlocked and gold >= auto_move_cost()


func unlock_auto_move() -> bool:
	if auto_move_unlocked or not spend_gold(auto_move_cost()):
		EventBus.combat_upgrade_failed.emit(&"auto_move")
		return false
	auto_move_unlocked = true
	EventBus.combat_upgrade_changed.emit(&"auto_move")
	return true


## Multi-window drift unlocks with the first SCALE purchase. (Legacy skill
## flags kept as an OR so any older nodes still work.)
func battle_movement_unlocked() -> bool:
	return scale_purchases > 0 or has_skill_node(&"battle_movement") or skill_effect_bool("battle_movement_enabled")


## Max number of battle windows allowed on screen at once = the SCALE axis.
## 0 SCALE purchases → 1 (one-at-a-time); each purchase adds +1 (no cap).
func battle_window_cap() -> int:
	return scale_window_count()


## True when BattleManager still has room under the SIMULTANEOUS-FIGHT cap (a perf
## guard on concurrent active windows — NOT chests). When false, new field-enemy
## encounters are silently refused until a fight resolves.
## (The old chest-buffer cap was removed: click-to-place + multi-window already
## pace the player, so stacking unopened chests no longer blocks new fights.)
func can_accept_new_battle_window() -> bool:
	var tree := get_tree()
	if tree == null:
		return true
	var bm: Node = tree.get_first_node_in_group("battle_manager")
	if bm == null or not bm.has_method("active_window_count"):
		return true
	return int(bm.active_window_count()) < battle_window_cap()


func combo_attack_unlocked() -> bool:
	return has_skill_node(&"combo_attack") or skill_effect_bool("combo_attack_enabled")


# ─── Weapons: per-type tracks (damage axis / weapon shop) ──────────────
func weapon_level(type_id: StringName) -> int:
	return int(weapon_levels.get(type_id, 1))


func weapon_attack_multiplier(type_id: StringName) -> float:
	return Balance.effect_multiplier(weapon_level(type_id))


## Damage multiplier for the member at `index`, from THEIR weapon type's level.
## This is the per-member SPEED component of the gold/sec formula.
func member_weapon_multiplier(index: int) -> float:
	if index < 0 or index >= party.size():
		return 1.0
	return weapon_attack_multiplier(Balance.character_weapon_type(party[index].id))


## Highest weapon level across types — drives the hit-effect size bump.
func max_weapon_level() -> int:
	var best: int = 1
	for t: Dictionary in Balance.WEAPON_TYPES:
		best = maxi(best, weapon_level(t["id"]))
	return best


func weapon_upgrade_cost(type_id: StringName) -> int:
	return Balance.upgrade_cost(weapon_level(type_id))


func can_upgrade_weapon(type_id: StringName) -> bool:
	return gold >= weapon_upgrade_cost(type_id)


## Buying a weapon type auto-equips the matching companion (그 타입 사용자) —
## visible via the "○○ 장착!" feedback + a bigger hit effect.
func upgrade_weapon(type_id: StringName) -> bool:
	if not spend_gold(weapon_upgrade_cost(type_id)):
		EventBus.combat_upgrade_failed.emit(&"weapon")
		return false
	weapon_levels[type_id] = weapon_level(type_id) + 1
	EventBus.combat_upgrade_changed.emit(&"weapon")
	EventBus.weapon_equipped.emit(current_weapon_name(type_id))
	register_upgrade_purchase(&"weapons")
	return true


func current_weapon_name(type_id: StringName) -> String:
	return Balance.weapon_name_for(type_id, weapon_level(type_id))


func next_weapon_name(type_id: StringName) -> String:
	return Balance.weapon_name_for(type_id, weapon_level(type_id) + 1)


## Weapon types in use by the current party (for the shop to show only relevant
## categories). Hero's 검 is always present.
func owned_weapon_types() -> Array[StringName]:
	var out: Array[StringName] = []
	for member: CharacterData in party:
		var t: StringName = Balance.character_weapon_type(member.id)
		if not out.has(t):
			out.append(t)
	return out


# ─── Survival: armor axis (party MAX HP / armor shop) ─────────────────
## Flat MAX HP added to EVERY party member by the equipped armor.
func armor_hp_bonus() -> int:
	return Balance.armor_hp_for_level(armor_level)


func current_armor_name() -> String:
	return Balance.armor_name_for_level(armor_level)


func next_armor_name() -> String:
	return Balance.armor_name_for_level(armor_level + 1)


func armor_upgrade_cost() -> int:
	return Balance.armor_cost(armor_level)


func can_upgrade_armor() -> bool:
	return gold >= armor_upgrade_cost()


## Armor shop = survival skin: each level unlocks + auto-equips the next armor,
## visibly bumping party MAX HP (fewer downs → less slowdown).
func upgrade_armor() -> bool:
	if not spend_gold(armor_upgrade_cost()):
		EventBus.combat_upgrade_failed.emit(&"armor")
		return false
	armor_level += 1
	EventBus.combat_upgrade_changed.emit(&"armor")
	EventBus.armor_equipped.emit(current_armor_name())
	register_upgrade_purchase(&"armor")
	return true


# ─── Loot levels (강화 = 드롭 장비 등급↑, NOT direct stats / auto-equip) ──
func weapon_loot_cost() -> int:
	return Balance.upgrade_cost(weapon_loot_level)


func can_upgrade_weapon_loot() -> bool:
	return gold >= weapon_loot_cost()


func upgrade_weapon_loot() -> bool:
	if not spend_gold(weapon_loot_cost()):
		EventBus.combat_upgrade_failed.emit(&"weapons")
		return false
	weapon_loot_level += 1
	EventBus.combat_upgrade_changed.emit(&"weapons")
	register_upgrade_purchase(&"weapons")  # still raises the weapon shop / recruits
	return true


func armor_loot_cost() -> int:
	return Balance.armor_cost(armor_loot_level)


func can_upgrade_armor_loot() -> bool:
	return gold >= armor_loot_cost()


func upgrade_armor_loot() -> bool:
	if not spend_gold(armor_loot_cost()):
		EventBus.combat_upgrade_failed.emit(&"armor")
		return false
	armor_loot_level += 1
	EventBus.combat_upgrade_changed.emit(&"armor")
	register_upgrade_purchase(&"armor")
	return true


## The loot level that scales a dropped item's quality → it drops at THIS entry
## level (so a weapon at loot Lv5 = level-5 gear = 5× its per-level stats).
func loot_level_for_item(item: ItemData) -> int:
	if item == null:
		return 1
	match item.slot:
		ItemData.Slot.WEAPON: return weapon_loot_level
		ItemData.Slot.SHIELD, ItemData.Slot.HELMET, ItemData.Slot.ARMOR: return armor_loot_level
		_: return maxi(weapon_loot_level, armor_loot_level)


# ─── Village buildings (right-panel grid; buildings are a RESULT of upgrades) ─
func is_building_built(id: StringName) -> bool:
	return built_buildings.has(id)


func building_cost(id: StringName) -> int:
	return int(Balance.building_by_id(id).get("build_cost", 0))


## Direct-build (모닥불/성소) locked → buildable gate. Empty `unlock` = always.
func is_building_unlocked(id: StringName) -> bool:
	var cond: Dictionary = Balance.building_by_id(id).get("unlock", {})
	if cond.is_empty():
		return true
	var need: int = int(cond.get("value", 0))
	match StringName(cond.get("type", &"")):
		&"kills":
			return total_enemy_kills >= need
		&"downs":
			return total_party_downs >= need
		&"gold_earned":
			return total_gold_earned >= need
	return true


## Only DIRECT buildings (모닥불/성소) are purchasable by clicking the tile. Auto
## buildings appear as a side effect of buying their upgrade.
func can_purchase_building(id: StringName) -> bool:
	var b: Dictionary = Balance.building_by_id(id)
	if b.is_empty() or StringName(b.get("mode", &"")) != &"direct":
		return false
	if is_building_built(id) or not is_building_unlocked(id):
		return false
	return gold >= building_cost(id)


## Build a DIRECT building. Its owner companion joins immediately (모닥불→마법사,
## 성소→사제).
func purchase_building(id: StringName) -> bool:
	if not can_purchase_building(id) or not spend_gold(building_cost(id)):
		return false
	_raise_building(id)
	_join_building_owner(id)  # direct owners join the moment the building is up
	return true


## Mark a building as present + make its owner companion appear (등장). Shared by
## the direct-build path and the auto-appear-on-upgrade path.
func _raise_building(id: StringName) -> void:
	if is_building_built(id):
		return
	built_buildings.append(id)
	EventBus.building_built.emit(id)
	var owner_id: StringName = StringName(Balance.building_by_id(id).get("owner", &""))
	if owner_id != &"" and not companions_appeared.has(owner_id) and not is_companion_recruited(owner_id):
		companions_appeared.append(owner_id)
		EventBus.companion_appeared.emit(owner_id)


## ★ The inverted causality: every upgrade purchase calls this with its category.
## First purchase of a category raises its auto-building; reaching the building's
## recruit_at count joins the owner companion.
func register_upgrade_purchase(category: StringName) -> void:
	upgrade_counts[category] = int(upgrade_counts.get(category, 0)) + 1
	var bid: StringName = Balance.building_for_trigger(category)
	if bid == &"":
		return
	_raise_building(bid)
	var b: Dictionary = Balance.building_by_id(bid)
	var recruit_at: int = int(b.get("recruit_at", 0))
	if recruit_at > 0 and int(upgrade_counts.get(category, 0)) >= recruit_at:
		_join_building_owner(bid)


func _join_building_owner(building_id: StringName) -> void:
	join_companion(StringName(Balance.building_by_id(building_id).get("owner", &"")))


## Join a companion into the party (no gold). No-op if absent / already in / the
## party is full. Used by building owners and the campfire mage event.
func join_companion(id: StringName) -> void:
	if id == &"" or is_companion_recruited(id):
		return
	if party.size() >= Balance.MAX_PARTY_SIZE:
		return
	var path: String = str(Balance.companion_by_id(id).get("char_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var data: CharacterData = load(path) as CharacterData
	if data == null:
		return
	if not companions_appeared.has(id):
		companions_appeared.append(id)
	_add_party_member(data)
	EventBus.companion_recruited.emit(id)


# ─── Campfire tile (field-placed HP-regen outpost; left panel) ─────────
func campfire_place_cost() -> int:
	return int(Balance.tile_by_id(&"campfire").get("place_cost", 0))


func can_place_campfire() -> bool:
	return not campfire_placed and gold >= campfire_place_cost()


## Pay for the campfire. The Field spawns it + runs the mage event (signal).
func place_campfire() -> bool:
	if not can_place_campfire() or not spend_gold(campfire_place_cost()):
		return false
	campfire_placed = true
	EventBus.campfire_placed.emit()
	return true


func set_campfire_position(pos: Vector2) -> void:
	campfire_position = pos


func campfire_regen_radius() -> float:
	return Balance.CAMPFIRE_REGEN_RADIUS


func campfire_regen_rate() -> float:
	return Balance.campfire_regen_rate(campfire_level)


func campfire_upgrade_cost() -> int:
	return Balance.campfire_upgrade_cost(campfire_level)


func can_upgrade_campfire() -> bool:
	return campfire_placed and gold >= campfire_upgrade_cost()


func upgrade_campfire() -> bool:
	if not campfire_placed or not spend_gold(campfire_upgrade_cost()):
		return false
	campfire_level += 1
	EventBus.combat_upgrade_changed.emit(&"campfire")
	return true


## Heal the given (in-radius, combat-ready) member indices. Field passes who's
## near the campfire each frame; only those regen — never global.
func tick_campfire_regen(indices: Array, delta: float) -> void:
	if not campfire_placed or delta <= 0.0:
		return
	var rate: float = campfire_regen_rate()
	for i in indices:
		if not is_combat_ready(i):
			continue
		var maxv: int = effective_max_hp(i)
		if party_hp[i] >= maxv:
			_campfire_regen_accum[i] = 0.0
			continue
		var carry: float = float(_campfire_regen_accum.get(i, 0.0)) + rate * delta
		var whole: int = int(carry)
		_campfire_regen_accum[i] = carry - float(whole)
		if whole >= 1:
			heal_party_member(i, whole)


## 성소 effect: while built, downed members are revived on the spot instead of
## entering the slow downed/recovery cycle.
func sanctuary_active() -> bool:
	return is_building_built(&"sanctuary")


# ─── Companions: appearance (등장) + recruit (영입) ─────────────────────
func is_companion_appeared(id: StringName) -> bool:
	return companions_appeared.has(id)


func is_companion_recruited(id: StringName) -> bool:
	return has_party_member(id)


func companion_recruit_cost(id: StringName) -> int:
	return int(Balance.companion_by_id(id).get("recruit_cost", 0))


func can_recruit_companion(id: StringName) -> bool:
	if not is_companion_appeared(id) or is_companion_recruited(id):
		return false
	if party.size() >= Balance.MAX_PARTY_SIZE:
		return false
	return gold >= companion_recruit_cost(id)


func recruit_companion(id: StringName) -> bool:
	if not can_recruit_companion(id) or not spend_gold(companion_recruit_cost(id)):
		return false
	var path: String = str(Balance.companion_by_id(id).get("char_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var data: CharacterData = load(path) as CharacterData
	if data == null:
		return false
	_add_party_member(data)
	EventBus.companion_recruited.emit(id)
	return true


## Append a member to the party, keeping every parallel array in sync. Shared by
## all recruit paths so companions never desync from party_hp/downed/etc.
func _add_party_member(data: CharacterData) -> void:
	party.append(data)
	var idx: int = party.size() - 1
	party_levels.append(1)
	party_xp.append(0)
	party_equipment.append(_empty_equipment_slots())
	party_hp.append(effective_max_hp(idx))
	party_mp.append(data.max_mp)
	party_downed.append(false)
	EventBus.party_changed.emit()


# ─── DQ1-style ambush / initiative ─────────────────────────────────────
## Average agility of combat-ready members (used for the ambush roll).
func _avg_combat_ready_agility() -> float:
	var total: int = 0
	var n: int = 0
	for i in party.size():
		if is_combat_ready(i):
			total += effective_agility(i)
			n += 1
	return float(total) / float(n) if n > 0 else 0.0


## Roll initiative for a starting fight against enemies of `enemy_agility_avg`.
## Returns +1 = 선공 (party first), -1 = 피습 (enemies first), 0 = 보통 (by agility).
func roll_battle_initiative(enemy_agility_avg: float) -> int:
	var diff: float = _avg_combat_ready_agility() - enemy_agility_avg
	var preempt: float = clampf(Balance.AMBUSH_PREEMPT_BASE + diff * Balance.AMBUSH_AGILITY_WEIGHT, Balance.AMBUSH_CHANCE_MIN, Balance.AMBUSH_CHANCE_MAX)
	var surprise: float = clampf(Balance.AMBUSH_SURPRISE_BASE - diff * Balance.AMBUSH_AGILITY_WEIGHT, Balance.AMBUSH_CHANCE_MIN, Balance.AMBUSH_CHANCE_MAX)
	var r: float = randf()
	if r < preempt:
		return 1
	if r > 1.0 - surprise:
		return -1
	return 0


# ─── Incremental combat: LUCK axis (kill-gold jackpot CHANCE) ──────────
## Jackpot chance at a given luck level. Lv1 = the base rate; each level adds a
## flat % (additive, capped). Never touches the jackpot MULTIPLIER.
func luck_jackpot_chance_for_level(level: int) -> float:
	var steps: int = maxi(0, level - 1)
	var chance: float = Balance.KILL_GOLD_JACKPOT_CHANCE + float(steps) * Balance.LUCK_JACKPOT_CHANCE_PER_LEVEL
	return minf(chance, Balance.LUCK_JACKPOT_CHANCE_MAX)


## Current kill-gold jackpot chance (used by roll_kill_gold).
func luck_jackpot_chance() -> float:
	return luck_jackpot_chance_for_level(luck_level)


func luck_is_maxed() -> bool:
	return luck_jackpot_chance() >= Balance.LUCK_JACKPOT_CHANCE_MAX - 0.0001


func luck_upgrade_cost() -> int:
	return Balance.upgrade_cost(luck_level)


func can_upgrade_luck() -> bool:
	return not luck_is_maxed() and gold >= luck_upgrade_cost()


func upgrade_luck() -> bool:
	if luck_is_maxed() or not spend_gold(luck_upgrade_cost()):
		EventBus.combat_upgrade_failed.emit(&"luck")
		return false
	luck_level += 1
	EventBus.combat_upgrade_changed.emit(&"luck")
	register_upgrade_purchase(&"luck")
	return true


# ─── Chest open-speed (independent relic upgrade) ──────────────────────
## Hover-to-open gauge duration; shortens as open_speed_level rises (floored).
func chest_hover_duration() -> float:
	return Balance.chest_open_duration(open_speed_level)


func open_speed_upgrade_cost() -> int:
	return Balance.chest_open_speed_cost(open_speed_level)


func open_speed_is_maxed() -> bool:
	return chest_hover_duration() <= Balance.CHEST_OPEN_DURATION_MIN + 0.0001


func can_upgrade_open_speed() -> bool:
	return not open_speed_is_maxed() and gold >= open_speed_upgrade_cost()


func upgrade_open_speed() -> bool:
	if open_speed_is_maxed() or not spend_gold(open_speed_upgrade_cost()):
		EventBus.combat_upgrade_failed.emit(&"open_speed")
		return false
	open_speed_level += 1
	EventBus.combat_upgrade_changed.emit(&"open_speed")
	register_upgrade_purchase(&"open_speed")
	return true


# ─── Incremental combat: SCALE axis (simultaneous windows) ─────────────
func scale_window_count() -> int:
	return Balance.scale_window_count(scale_purchases)


func scale_upgrade_cost() -> int:
	return Balance.scale_cost(scale_purchases)


func scale_is_maxed() -> bool:
	return scale_purchases >= Balance.scale_max_purchases()


func can_upgrade_scale() -> bool:
	return not scale_is_maxed() and gold >= scale_upgrade_cost()


func upgrade_scale() -> bool:
	if scale_is_maxed() or not spend_gold(scale_upgrade_cost()):
		EventBus.combat_upgrade_failed.emit(&"scale")
		return false
	scale_purchases += 1
	EventBus.combat_upgrade_changed.emit(&"scale")
	register_upgrade_purchase(&"scale")
	return true


# ─── Incremental combat: enemy tiers (cumulative-gold unlock + toggle) ──
func is_tier_unlocked(id: StringName) -> bool:
	return unlocked_tier_ids.has(id)


## Lifetime earned-gold milestone this tier unlocks at (spending never lowers it).
func tier_unlock_threshold(id: StringName) -> int:
	return int(Balance.tier_by_id(id).get("unlock_at", 0))


## Has the player earned enough (lifetime) for this tier to be claimable yet?
func tier_threshold_reached(id: StringName) -> bool:
	return total_gold_earned >= tier_unlock_threshold(id)


## Shown in the dock at all? Unlocked tiers always; locked tiers only once their
## cumulative-gold milestone is reached (below that they're hidden = blank).
func is_tier_visible(id: StringName) -> bool:
	return is_tier_unlocked(id) or tier_threshold_reached(id)


## Reached the milestone but not yet claimed → the dock shows a "해금" button.
func is_tier_unlock_available(id: StringName) -> bool:
	return not is_tier_unlocked(id) and tier_threshold_reached(id)


## Claim a tier whose milestone is reached. FREE — the lifetime-earned milestone
## is the gate, so spending gold never costs you an unlock. Fires the popup.
## Unlocking only makes the tier CLICK-PLACEABLE; it does NOT auto-toggle it ON
## (toggle/auto-spawn is the dormant future-automation path).
func unlock_tier(id: StringName) -> bool:
	if not is_tier_unlock_available(id):
		EventBus.combat_upgrade_failed.emit(&"tier")
		return false
	unlocked_tier_ids.append(id)
	EventBus.tier_unlocked.emit(id)
	EventBus.combat_upgrade_changed.emit(&"tier")
	return true


# ─── CLICK-TO-PLACE: the default way enemies appear (click → -gold → 1 spawns) ──
## Gold spent to drop one of this tier on the field.
func tier_place_cost(id: StringName) -> int:
	return int(Balance.tier_by_id(id).get("place_cost", 0))


## Can place one now? (Unlocked + can afford the place cost.)
func can_place_enemy(id: StringName) -> bool:
	return is_tier_unlocked(id) and gold >= tier_place_cost(id)


## Spend the place cost and ask the Field to spawn one. Returns false (and flashes
## the dock) when too poor.
func place_enemy(id: StringName) -> bool:
	if not can_place_enemy(id) or not spend_gold(tier_place_cost(id)):
		EventBus.combat_upgrade_failed.emit(&"tier")
		return false
	EventBus.enemy_place_requested.emit(id)
	return true


# ─── Generic field structures (TILES: village, …) — placed like the campfire ──
var placed_structures: Array[StringName] = []


func is_structure_placed(id: StringName) -> bool:
	return placed_structures.has(id)


## Spend the tile's place_cost and ask the Field to spawn it. Returns false (and
## flashes) when too poor or already placed.
func place_structure(id: StringName) -> bool:
	if is_structure_placed(id):
		return false
	var cost: int = int(Balance.tile_by_id(id).get("place_cost", 0))
	if gold < cost or not spend_gold(cost):
		EventBus.combat_upgrade_failed.emit(&"tier")
		return false
	placed_structures.append(id)
	EventBus.structure_placed.emit(id)
	return true


func can_place_structure(id: StringName) -> bool:
	return not is_structure_placed(id) and gold >= int(Balance.tile_by_id(id).get("place_cost", 0))


# ─── Objets (item-like collectibles: drop from battle → shelved on the left) ──
## Acquired objet ids. Free + immediate (claimed from a reward card, no field
## spawn). Most are one-time — once here, they won't roll as a drop again.
var acquired_objets: Array[StringName] = []


func is_objet_acquired(id: StringName) -> bool:
	return acquired_objets.has(id)


## Claim an objet (from a reward card). Idempotent; emits objet_acquired for the
## left-panel shelf the first time.
func acquire_objet(id: StringName) -> void:
	if id == &"" or acquired_objets.has(id):
		return
	acquired_objets.append(id)
	EventBus.objet_acquired.emit(id)


## Has this owned objet already been dropped onto the field?
func is_objet_placed(id: StringName) -> bool:
	if id == &"campfire":
		return campfire_placed
	return is_structure_placed(id)


## Place an OWNED objet on the field for FREE, reusing the existing spawn paths
## (click tile → carry → drop). Returns false if not owned or already placed.
func place_acquired_objet(id: StringName) -> bool:
	if not is_objet_acquired(id) or is_objet_placed(id):
		return false
	if id == &"campfire":
		campfire_placed = true
		EventBus.campfire_placed.emit()  # Field spawns it + runs the mage event
		return true
	placed_structures.append(id)
	EventBus.structure_placed.emit(id)   # Field spawns the structure at the drop spot
	return true


## 여관(Inn): everyone wakes up topped off — revive any downed members and refill
## all HP to full. The single full-party restore the field offers.
func restore_party_full() -> void:
	for i in party.size():
		var was_downed: bool = party_downed[i]
		party_downed[i] = false
		_downed_recovery_accum[i] = 0.0
		party_hp[i] = effective_max_hp(i)
		EventBus.party_member_hp_changed.emit(i, party_hp[i], party_hp[i])
		if was_downed:
			EventBus.party_member_revived.emit(i)
	_party_collapsed = false
	EventBus.party_hp_changed.emit()


## Deadlock rescue: spent everything, gold 0, nothing left to fight. Spawn ONE
## slime for FREE so the economy can restart. No gold check, no spend — the dock
## only offers this when truly stuck (see _is_deadlocked), so it can't be abused.
func place_rescue_slime() -> void:
	EventBus.enemy_place_requested.emit(&"slime")


## A tier's enemy resource (loaded fresh per spawn). Null if missing.
func tier_enemy_data(id: StringName) -> EnemyData:
	var path: String = str(Balance.tier_by_id(id).get("enemy_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as EnemyData


# ─── Toggle / auto-spawn (DORMANT — preserved for future automation) ───
## Kept intact so a later "automation" purchase can flip a tier to auto-spawn
## (toggle ON → the field's continuous-spawn path picks it up). Not wired to the
## dock click anymore; click now PLACES instead.
func is_tier_active(id: StringName) -> bool:
	return active_tier_ids.has(id)


## Toggle an unlocked tier ON/OFF. OFF only stops NEW spawns of that tier —
## enemies already wandering the field stay until killed. (The field watches
## active_tier_ids for its continuous spawn mix; it never culls on toggle.)
func toggle_tier(id: StringName) -> void:
	if not is_tier_unlocked(id):
		return
	if active_tier_ids.has(id):
		active_tier_ids.erase(id)
	else:
		active_tier_ids.append(id)
	EventBus.combat_upgrade_changed.emit(&"tier")


## The tier dict that owns a spawned enemy (resolved by its resource path), so
## HP/gold are correct even with several tiers active. Falls back to slime.
func tier_for_enemy_data(data: EnemyData) -> Dictionary:
	if data != null:
		var tier: Dictionary = Balance.tier_by_enemy_res(data.resource_path)
		if not tier.is_empty():
			return tier
	return Balance.tier_by_id(&"slime")


## A random toggled-on tier's enemy resource for the field to spawn. Returns
## null when nothing is active (field then spawns nothing new).
func random_active_tier_enemy_data() -> EnemyData:
	var candidates: Array[String] = []
	for id: StringName in active_tier_ids:
		if not is_tier_unlocked(id):
			continue
		var path: String = str(Balance.tier_by_id(id).get("enemy_res", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			candidates.append(path)
	if candidates.is_empty():
		return null
	return load(candidates[randi() % candidates.size()]) as EnemyData


func tier_id_for_enemy_data(data: EnemyData) -> StringName:
	return StringName(tier_for_enemy_data(data).get("id", &"slime"))


# ─── Per-enemy level (System 1: auto-growth from kills) ────────────────
func enemy_level(tier_id: StringName) -> int:
	return int(enemy_levels.get(tier_id, 1))


func enemy_kill_progress_value(tier_id: StringName) -> int:
	return int(enemy_kill_progress.get(tier_id, 0))


func enemy_kills_to_next(tier_id: StringName) -> int:
	return Balance.kills_for_level(enemy_level(tier_id))


func enemy_level_progress_ratio(tier_id: StringName) -> float:
	var req: int = enemy_kills_to_next(tier_id)
	if req <= 0:
		return 0.0
	return clampf(float(enemy_kill_progress_value(tier_id)) / float(req), 0.0, 1.0)


## How many of this tier spawn in one window (1→5, level-capped).
func enemy_spawn_count(tier_id: StringName) -> int:
	return Balance.spawn_count_for_level(enemy_level(tier_id))


## Uncapped per-level kill-gold multiplier for this tier.
func enemy_kill_gold_multiplier(tier_id: StringName) -> float:
	return Balance.kill_gold_mult_for_level(enemy_level(tier_id))


## Called when one enemy of `tier_id` dies. Accumulates kill progress and levels
## the tier up (possibly multiple levels at once). Emits UI signals.
func record_enemy_kill(tier_id: StringName) -> void:
	if tier_id == &"":
		return
	total_enemy_kills += 1  # gates the 모닥불(campfire) build unlock
	var progress: int = enemy_kill_progress_value(tier_id) + 1
	var level: int = enemy_level(tier_id)
	var leveled: bool = false
	while progress >= Balance.kills_for_level(level):
		progress -= Balance.kills_for_level(level)
		level += 1
		leveled = true
	enemy_levels[tier_id] = level
	enemy_kill_progress[tier_id] = progress
	EventBus.enemy_progress_changed.emit(tier_id)
	if leveled:
		EventBus.enemy_leveled_up.emit(tier_id, level)


func begin_field_battle_pause() -> void:
	_field_battle_pause_count += 1


func end_field_battle_pause() -> void:
	_field_battle_pause_count = maxi(0, _field_battle_pause_count - 1)


func is_field_battle_paused() -> bool:
	return _field_battle_pause_count > 0


## True while the field should hold still for a fight: an explicit pause is held, OR
## every battle-window slot is in use (at the SCALE cap). Below the cap the field
## keeps roaming so the hero walks into the next fight; once the cap is full it
## freezes until a window resolves and frees a slot.
func is_field_frozen_for_battle() -> bool:
	return is_field_battle_paused() or not can_accept_new_battle_window()


func _purchased_skill_node_data() -> Array:
	var out: Array = []
	for id in purchased_skill_nodes.keys():
		var node = SkillTreeDB.get_by_id(id)
		if node:
			out.append(node)
	return out


func _ensure_default_skill_nodes() -> void:
	# Skill tree is being rebuilt and currently has no nodes, so there are no
	# default unlocks to seed. Re-add starter node ids here once the new tree
	# defines them.
	pass


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
	party_downed.append(false)
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
func start_next_field_loop(region_id: StringName = FIELD_REGION_GRASS) -> void:
	current_field_region_id = _validated_field_region(region_id)
	field_loop_count += 1
	EventBus.field_loop_started.emit(field_loop_count)


func _validated_field_region(region_id: StringName) -> StringName:
	if region_id == FIELD_REGION_FOREST and forest_region_unlocked():
		return FIELD_REGION_FOREST
	return FIELD_REGION_GRASS


# ─── Enemy scaling ────────────────────────────────────────────────────
func scaled_enemy_max_hp(data: EnemyData) -> int:
	if data == null:
		return 1
	# Calibrated so this enemy's tier dies in ~base_kill_time at SPEED Lv1 / full
	# party HP. SPEED (party damage ×) then shortens kill time; the formula
	#   처치시간 = 적HP ÷ (파티 실효 데미지)
	# falls straight out of this. Tier is resolved per-enemy so a mix of toggled
	# tiers all get the right HP.
	var base_kill_time: float = float(tier_for_enemy_data(data).get("base_kill_time", Balance.SLIME_BASE_TIME))
	var avg_hit: float = _reference_party_hit_damage()
	return maxi(1, int(round(avg_hit * base_kill_time * Balance.PARTY_HITS_PER_SECOND)))


func scaled_enemy_attack(data: EnemyData) -> int:
	if data == null:
		return 1
	# Per-tier attack ramp (Balance TIERS.atk_mult) so orc+ hit hard enough to
	# actually threaten a wipe — the source of mid/late "위기".
	var atk_mult: float = float(tier_for_enemy_data(data).get("atk_mult", 1.0))
	return maxi(1, int(round(float(data.attack) * atk_mult)))


## Each kill is a mini chest-open: the base (average) reward × a random roll.
## Returns {"amount": int, "tier": &"low"/&"normal"/&"jackpot"} so the feedback
## can be sized to the luck. Mean ≈ 1.0 (Balance), so total income is unchanged.
func roll_kill_gold(base_reward: int) -> Dictionary:
	if base_reward <= 0:
		return {"amount": 0, "tier": &"normal"}
	# LUCK raises the jackpot CHANCE (frequency); the MULTIPLIER stays fixed.
	if randf() < luck_jackpot_chance():
		return {"amount": maxi(1, int(round(float(base_reward) * Balance.KILL_GOLD_JACKPOT_MULT))), "tier": &"jackpot"}
	var mult: float = randf_range(Balance.KILL_GOLD_MIN_MULT, Balance.KILL_GOLD_MAX_MULT)
	var tier: StringName = &"low" if mult < Balance.KILL_GOLD_LOW_MULT_THRESHOLD else &"normal"
	return {"amount": maxi(1, int(round(float(base_reward) * mult))), "tier": tier}  # min 1 — never a total 꽝


func scaled_enemy_agility(data: EnemyData) -> int:
	if data == null:
		return 0
	return data.agility


func scaled_enemy_gold_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	# Gold per kill = tier base gold × tier-level × thief (도적) multiplier.
	# (No GREED multiplier — it was removed; LUCK raises jackpot CHANCE instead,
	# applied later in roll_kill_gold, not here.)
	var tier_id: StringName = tier_id_for_enemy_data(data)
	var kill_gold: int = int(tier_for_enemy_data(data).get("kill_gold", Balance.SLIME_BASE_GOLD))
	return maxi(1, int(round(float(kill_gold) * enemy_kill_gold_multiplier(tier_id) * thief_gold_multiplier())))


## Average single party hit at SPEED Lv1 (weapon-free, full HP). Used only to
## calibrate enemy HP — combat applies SPEED/penalty on top of this.
## Enemy-HP calibration uses BASE attack (+ level-up bonus) only — NOT equipped
## gear/modifiers. So equipping dropped gear lifts real damage ABOVE this baseline
## → faster kills = felt progression (gear no longer auto-inflates enemy HP).
func _reference_party_hit_damage() -> float:
	var total: int = 0
	var n: int = 0
	for i in party.size():
		total += party[i].attack + _level_bonus(i, "atk")
		n += 1
	if n == 0:
		return 4.0
	return maxf(1.0, float(total) / float(n))


# ─── Incremental combat: downed cycle ──────────────────────────────────
## True while a member is knocked out (HP hit 0) and refilling in place.
func is_downed(index: int) -> bool:
	return index >= 0 and index < party_downed.size() and party_downed[index]


## A member can act / be targeted only when up with HP. Downed members (even
## mid-refill) are out of the fight — this is what slows kills when the party
## is too weak for the tier.
func is_combat_ready(index: int) -> bool:
	return index >= 0 and index < party_hp.size() and party_hp[index] > 0 and not is_downed(index)


## True when every party member is currently downed (a full collapse).
func is_party_all_downed() -> bool:
	if party.is_empty():
		return false
	for i in party.size():
		if not party_downed[i]:
			return false
	return true


## True when every member is upright and at full HP.
func is_party_fully_recovered() -> bool:
	for i in party.size():
		if party_downed[i] or party_hp[i] < effective_max_hp(i):
			return false
	return true


## Field movement is frozen while the whole party recovers from a full collapse.
func is_movement_frozen() -> bool:
	return _party_collapsed or not world_started or party_resting


## All combat-ready members at full HP? (Downed members refill on their own.)
func is_party_full_hp() -> bool:
	for i in party.size():
		if not is_combat_ready(i):
			continue
		if i < party_hp.size() and party_hp[i] < effective_max_hp(i):
			return false
	return true


# ─── Opening: name the hero → lay the first grass → the world begins ───
## Set the hero's name. We duplicate party[0]'s CharacterData so the new name
## shows EVERYWHERE that reads it (party panel, battle log, tooltips) without
## mutating the shared .tres resource.
func set_player_name(new_name: String) -> void:
	var clean: String = new_name.strip_edges()
	if clean.is_empty():
		clean = random_hero_name()
	player_name = clean
	name_entered = true
	if party.size() > 0 and party[0] != null:
		var hero: CharacterData = party[0].duplicate() as CharacterData
		hero.display_name = clean
		party[0] = hero
		EventBus.party_changed.emit()  # HUD rebuilds boxes with the new name
	EventBus.player_named.emit(clean)
	# Naming IS the start now — no separate "초원 깔기" step. The world begins and
	# the placement list (slime first) is live immediately.
	start_world()


func random_hero_name() -> String:
	if RANDOM_HERO_NAMES.is_empty():
		return "용사"
	return RANDOM_HERO_NAMES[randi() % RANDOM_HERO_NAMES.size()]


func start_world() -> void:
	if world_started:
		return
	world_started = true
	EventBus.world_started.emit()


## Seconds to refill 0 → full while downed. A function so a future "성소"
## building (or per-member gear) can shorten it individually.
func downed_recovery_seconds(_index: int) -> float:
	var secs: float = Balance.DOWNED_RECOVERY_SECONDS
	# Support trait (사제) = the "human 성소": speeds every member's recovery.
	var plvl: int = _trait_level(&"support")
	if plvl > 0:
		secs *= Balance.priest_recovery_factor(plvl)
	return maxf(0.1, secs)


## Drives the downed → refill → auto-stand cycle. Called every frame by the
## BattleManager. Only downed members heal (no passive regen for the upright).
func tick_downed_recovery(delta: float) -> void:
	if delta <= 0.0:
		return
	# Auto-recovery ONLY kicks in on a FULL wipe (everyone down). A partial down —
	# one or two members — stays down (they trail the party) until the whole party
	# collapses (then all revive together) or a 성소 revives on the spot.
	if not _party_collapsed:
		return
	for i in party.size():
		if not party_downed[i]:
			continue
		var maxv: int = effective_max_hp(i)
		var per_sec: float = float(maxv) / downed_recovery_seconds(i)
		var carry: float = float(_downed_recovery_accum.get(i, 0.0)) + per_sec * delta
		var whole: int = int(carry)
		_downed_recovery_accum[i] = carry - float(whole)
		if whole >= 1:
			party_hp[i] = mini(maxv, party_hp[i] + whole)
			EventBus.party_member_hp_changed.emit(i, party_hp[i], maxv)
			EventBus.party_hp_changed.emit()
		if party_hp[i] >= maxv:
			# Fully refilled → stand up and rejoin the fight.
			party_hp[i] = maxv
			party_downed[i] = false
			_downed_recovery_accum[i] = 0.0
			EventBus.party_member_revived.emit(i)
	# After a full-party collapse, hold movement until EVERYONE is back to full,
	# then release so the party resumes together.
	if _party_collapsed and is_party_fully_recovered():
		_party_collapsed = false


func scaled_enemy_xp_reward(data: EnemyData) -> int:
	if data == null:
		return 0
	return maxi(1, data.xp_reward)


# ─── Equipment ────────────────────────────────────────────────────────
func collect_item(item: ItemData, level: int = 1) -> bool:
	if item == null:
		return false
	_absorb_item_entry(_make_item_entry(item, maxi(1, level)))
	return true


func add_item_to_inventory(item: ItemData, level: int = 1) -> void:
	if item == null:
		return
	_absorb_item_entry(_make_item_entry(item, maxi(1, level)))


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


# ─── Manual drag-equip (inventory → a specific party slot) ─────────────
## Does an item of this type belong in equip slot `slot_index`?
## 0=Weapon 1=Shield 2=Helmet 3=Armor 4/5=Accessory.
func equip_slot_accepts(slot_index: int, item: ItemData) -> bool:
	if item == null:
		return false
	match slot_index:
		0: return item.slot == ItemData.Slot.WEAPON
		1: return item.slot == ItemData.Slot.SHIELD
		2: return item.slot == ItemData.Slot.HELMET
		3: return item.slot == ItemData.Slot.ARMOR
		EQUIPMENT_ACCESSORY_SLOT_A, EQUIPMENT_ACCESSORY_SLOT_B:
			return item.slot == ItemData.Slot.ACCESSORY
	return false


## Slot-type + owner check for dropping `item` onto (member, slot).
func can_equip_to_slot(item: ItemData, member_index: int, slot_index: int) -> bool:
	if member_index < 0 or member_index >= party.size():
		return false
	if not equip_slot_accepts(slot_index, item):
		return false
	if item.allowed_character_id != &"" and party[member_index].id != item.allowed_character_id:
		return false
	return true


## Manual equip: move inventory[inv_index] into member's slot, sending whatever was
## there back to the bag. (Auto-equip via `_absorb_item_entry` stays for the future
## auto-place skill — this is the player-driven drag path.)
func equip_inventory_item_to(inv_index: int, member_index: int, slot_index: int) -> bool:
	if inv_index < 0 or inv_index >= inventory.size():
		return false
	var entry = inventory[inv_index]
	var item: ItemData = item_entry_data(entry)
	if not can_equip_to_slot(item, member_index, slot_index):
		return false
	var previous = party_equipment[member_index][slot_index]
	inventory.remove_at(inv_index)
	party_equipment[member_index][slot_index] = entry
	if previous != null:
		inventory.append(previous)  # swapped-out gear returns to the bag
	party_hp[member_index] = mini(party_hp[member_index], effective_max_hp(member_index))
	EventBus.party_member_hp_changed.emit(member_index, party_hp[member_index], effective_max_hp(member_index))
	EventBus.party_equipment_changed.emit(member_index)
	EventBus.inventory_changed.emit()
	return true


## The fixed slot index for an item's type (for comparison lookups).
func slot_index_for_item(item: ItemData) -> int:
	if item == null:
		return -1
	match item.slot:
		ItemData.Slot.WEAPON: return 0
		ItemData.Slot.SHIELD: return 1
		ItemData.Slot.HELMET: return 2
		ItemData.Slot.ARMOR: return 3
		ItemData.Slot.ACCESSORY: return EQUIPMENT_ACCESSORY_SLOT_A
	return -1


## (label, value) of an item's PRIMARY stat: weapon→공격, armor-types→체력,
## accessory→its biggest bonus.
func _item_primary_stat(item: ItemData, level: int) -> Dictionary:
	var lv: int = maxi(1, level)
	match item.slot:
		ItemData.Slot.WEAPON:
			return {"label": "공격", "value": item.attack_bonus * lv}
		ItemData.Slot.SHIELD, ItemData.Slot.HELMET, ItemData.Slot.ARMOR:
			return {"label": "체력", "value": item.max_hp_bonus * lv}
		_:
			var best_label: String = "공격"
			var best: int = item.attack_bonus
			if item.agility_bonus > best: best = item.agility_bonus; best_label = "민첩"
			if item.max_hp_bonus > best: best = item.max_hp_bonus; best_label = "체력"
			return {"label": best_label, "value": best * lv}


## One-line hover comparison vs what's equipped in this item's slot (owner/hero):
## "공격 +8 (현재 +5) ↑더 좋음".
func item_compare_line(item: ItemData, item_level: int) -> String:
	if item == null:
		return ""
	var prim: Dictionary = _item_primary_stat(item, item_level)
	var item_val: int = int(prim["value"])
	var member_index: int = 0
	if item.allowed_character_id != &"":
		var owner: int = _member_index_by_id(item.allowed_character_id)
		if owner >= 0:
			member_index = owner
	var slot_index: int = slot_index_for_item(item)
	var equipped_val: int = 0
	if member_index >= 0 and member_index < party_equipment.size() and slot_index >= 0:
		var eq_item: ItemData = item_entry_data(party_equipment[member_index][slot_index])
		if eq_item != null:
			var eq_prim: Dictionary = _item_primary_stat(eq_item, item_entry_level(party_equipment[member_index][slot_index]))
			equipped_val = int(eq_prim["value"])
	var delta: int = item_val - equipped_val
	var verdict: String = "↑더 좋음" if delta > 0 else ("↓더 나쁨" if delta < 0 else "= 같음")
	return "%s +%d (현재 +%d) %s" % [str(prim["label"]), item_val, equipped_val, verdict]


func inventory_items() -> Array:
	return inventory.duplicate()


func inventory_sell_value(entry) -> int:
	if item_entry_data(entry) == null:
		return 0
	return maxi(1, item_entry_level(entry))


func inventory_sell_total() -> int:
	var total: int = 0
	for entry in inventory:
		total += inventory_sell_value(entry)
	return total


func sell_inventory_entry_at(index: int) -> int:
	if index < 0 or index >= inventory.size():
		return 0
	var entry = inventory[index]
	var value: int = inventory_sell_value(entry)
	if value <= 0:
		return 0
	inventory.remove_at(index)
	EventBus.inventory_changed.emit()
	add_gold(value)
	return value


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
	if ITEM_MERGING_ENABLED and level > 0:
		lines.append("Merge: same Lv %d -> Lv %d" % [level, level + 1])
	return "\n".join(lines)


func party_member_stat_tooltip(index: int) -> String:
	if index < 0 or index >= party.size():
		return ""
	var member: CharacterData = party[index]
	var max_hp: int = effective_max_hp(index)
	var hp: int = party_hp[index] if index < party_hp.size() else max_hp
	var mp: int = party_mp[index] if index < party_mp.size() else member.max_mp
	# 공격력은 전투에서 무기 배수(SPEED)가 곱해진다 — 그게 실제 강함이라 여기서 합쳐
	# 보여준다(예전 툴팁은 기본 ATK만 보여줘 무기 강화가 안 보였음).
	var base_atk: int = effective_attack(index)
	var wmult: float = member_weapon_multiplier(index)
	var combat_atk: int = int(round(float(base_atk) * wmult))
	var wtype: StringName = Balance.character_weapon_type(member.id)
	var wname: String = current_weapon_name(wtype)
	var lines: PackedStringArray = []
	lines.append("%s  Lv %d" % [member.display_name, party_level(index)])
	lines.append("HP %d/%d   MP %d/%d" % [hp, max_hp, mp, member.max_mp])
	lines.append("공격 %d   민첩 %d" % [
		combat_atk,
		effective_agility(index),
	])
	# 무기 배수 = 킬 속도 레버. 강화하면 ×배수와 공격 수치가 같이 오른다.
	lines.append("  └ 무기 %s ×%.2f  (기본 공격 %d · 킬속도)" % [wname, wmult, base_atk])
	if armor_level > 1:
		lines.append("  └ 방어구 %s  HP +%d" % [current_armor_name(), armor_hp_bonus()])
	# 운: 파티 공통 — 킬 보상 대박(팡팡팡) 확률.
	lines.append("운  대박 %.0f%%" % (luck_jackpot_chance() * 100.0))
	lines.append("XP %d/%d" % [
		party_xp[index] if index < party_xp.size() else 0,
		party_xp_to_next(index),
	])
	lines.append("장비  %s" % _member_gear_stat_line(index))
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
	lines.append("ATK %d   AGI %d" % [
		scaled_enemy_attack(data),
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
		&"elf": return "Elf"
		&"mage": return "Mage"
		&"knight": return "Knight"
		&"priest": return "Priest"
		&"thief": return "Thief"
	return String(character_id).capitalize()


func _item_stat_line(item: ItemData, level: int) -> String:
	var parts: PackedStringArray = []
	var hp: int = item.max_hp_bonus * level
	var atk: int = item.attack_bonus * level
	var agility: int = item.agility_bonus * level
	if hp != 0:
		parts.append(_signed_stat("HP", hp))
	if atk != 0:
		parts.append(_signed_stat("ATK", atk))
	if agility != 0:
		parts.append(_signed_stat("AGI", agility))
	return "   ".join(parts)


func _member_gear_stat_line(index: int) -> String:
	var parts: PackedStringArray = []
	var hp: int = _equipment_bonus(index, "max_hp_bonus")
	var atk: int = _equipment_bonus(index, "attack_bonus")
	var agility: int = _equipment_bonus(index, "agility_bonus")
	if hp != 0:
		parts.append(_signed_stat("HP", hp))
	if atk != 0:
		parts.append(_signed_stat("ATK", atk))
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
	if ITEM_MERGING_ENABLED and target_index >= 0:
		var equipped_slot: int = _find_equipped_match(target_index, item, level)
		if equipped_slot >= 0:
			_upgrade_equipped_entry(target_index, equipped_slot)
			return
	var inventory_index: int = _find_inventory_match(item, level) if ITEM_MERGING_ENABLED else -1
	if ITEM_MERGING_ENABLED and inventory_index >= 0:
		inventory.remove_at(inventory_index)
		EventBus.inventory_changed.emit()
		_absorb_item_entry(_make_item_entry(item, level + 1))
		return
	if target_index >= 0 and not _has_equipped_item(target_index, item):
		if _equip_item_entry(entry):
			return
	_add_item_entry_to_inventory(entry)


func _upgrade_equipped_entry(member_index: int, slot_index: int) -> void:
	if not ITEM_MERGING_ENABLED:
		return
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
	if not ITEM_MERGING_ENABLED:
		return
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
	return party[index].attack + _level_bonus(index, "atk") + _equipment_bonus(index, "attack_bonus") + _stacked_int_effect_for_character(character_id, "atk_flat") + skill_effect_int_sum("atk_flat")


func effective_agility(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	return party[index].agility + _level_bonus(index, "agi") + _equipment_bonus(index, "agility_bonus") + _stacked_int_effect_for_character(character_id, "agi_flat") + skill_effect_int_sum("agi_flat")


func effective_move_speed(base_speed: float) -> float:
	var flat_bonus: float = float(_stacked_int_effect("move_speed_flat") + skill_effect_int_sum("move_speed_flat"))
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


# ─── Companion roles via TRAITS (intrinsic, scale with level — no skills) ──
## Combat behavior keys off a member's innate TRAIT (Balance.character_trait),
## not their id — so a future variant (e.g. a different mage with trait &"burst")
## just slots in. Action scaling uses the ACTING member's level; passive party
## effects (gold ×, recovery speed) use the first member carrying that trait.

## Party index of a character id, or -1 if absent.
func _member_index_by_id(id: StringName) -> int:
	for i in party.size():
		if party[i].id == id:
			return i
	return -1


## First party index whose innate trait matches, or -1.
func _member_index_by_trait(trait_id: StringName) -> int:
	for i in party.size():
		if Balance.character_trait(party[i].id) == trait_id:
			return i
	return -1


## Level of the first member with this trait (0 if none present).
func _trait_level(trait_id: StringName) -> int:
	var i: int = _member_index_by_trait(trait_id)
	return party_level(i) if i >= 0 else 0


# Action scaling — driven by the ACTING member's level (passed by index).
func member_aoe_extra_targets(index: int) -> int:
	return Balance.mage_extra_targets(party_level(index))


func member_aoe_damage_mult(index: int) -> float:
	return Balance.mage_splash_damage(party_level(index))


func member_heal_amount(index: int) -> int:
	return Balance.priest_heal(party_level(index))


func hero_attack_multiplier() -> float:
	return 1.0 + _stacked_float_effect("hero_damage_bonus_mult", DAMAGE_BONUS_STACK_MULTIPLIERS)


func priest_attack_multiplier() -> float:
	return Balance.PRIEST_ATTACK_MULT


## Passive party-wide gold × from any member with the &"gold" trait (도적).
func thief_gold_multiplier() -> float:
	var lvl: int = _trait_level(&"gold")
	return Balance.thief_gold_mult(lvl) if lvl > 0 else 1.0


## Steal kept inert (no skills) — the gold trait contributes via the multiplier
## above, not per-hit theft.
func thief_steal_chance() -> float:
	return 0.0


func thief_steal_gold_amount() -> int:
	return 0


func effective_max_hp(index: int) -> int:
	if index < 0 or index >= party.size():
		return 0
	var character_id: StringName = party[index].id
	# 방어구(방어력→HP 전환): 파티 공통 armor_hp_bonus() 가 맷집으로 합산된다.
	return party[index].max_hp + _level_bonus(index, "hp") + _equipment_bonus(index, "max_hp_bonus") + _stacked_int_effect_for_character(character_id, "hp_flat") + skill_effect_int_sum("hp_flat") + armor_hp_bonus()


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
	_tier_available_announced.clear()  # re-announce tiers next run
	placed_structures.clear()          # village etc. re-placeable next run
	acquired_objets.clear()            # objets drop fresh again next run
	enemies_killed = 0
	biggest_hit = 0
	unlocked_tier_ids = [&"slime"]   # only slime from the start; rest re-lock
	active_tier_ids = []             # toggle/auto-spawn dormant (click-place default)
	world_started = false            # opening replays: lay grass again to begin
	name_entered = false             # …and re-prompt for the hero's name
	player_name = ""
	enemy_levels.clear()
	enemy_kill_progress.clear()
	active_modifiers.clear()
	recruited_companions.clear()
	_move_speed_drag_multiplier = 1.0
	_move_speed_drag_until_msec = 0
	_move_speed_boost_multiplier = 1.0
	_move_speed_boost_until_msec = 0
	_field_battle_pause_count = 0
	field_loop_count = 0
	current_field_region_id = FIELD_REGION_GRASS
	story_companion_joined = false
	story_gold_goal_announced = false
	story_movement_battle_line_shown = false
	story_mage_joined = false
	run_started_at_ms = Time.get_ticks_msec()
	# Make sure UI listeners flush stale numbers (HUD gold, etc.).
	EventBus.gold_changed.emit(gold)
