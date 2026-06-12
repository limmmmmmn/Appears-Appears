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
## Armor = per-member MAX HP gear, bought ONE MEMBER AT A TIME in the 마을 shop
## (no more party-wide auto-equip). Parallel to `party`: index → level, level 1 =
## "맨몸" (no bonus). Lazily padded to party size — a missing/new index reads as Lv1,
## so every party-append path stays correct without extra bookkeeping (the party only
## grows within a run, never shrinks, so indices are stable).
var member_armor_levels: Array[int] = []
## 마을 레벨 — gates which gear TIER the shop sells. Lv1 → 1단계 장비(검 Lv2, 천 갑옷…)
## 까지만; 마을을 강화할수록 다음 단계 무기/방어구가 해금된다. Re-placeable, so it resets
## with the run (see reset_run).
var village_level: int = 1
## LOOT LEVELS — the 무기/방어구 upgrade now raises drop QUALITY (gear that falls
## in battle = this level), NOT direct stats. Power comes from manually equipping
## the dropped gear. weapon_level / member armor stay at base (no direct effect).
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
## 지금은 처음부터 자동 상태로 시작(true). 수동 전투를 다시 켜고 싶으면 false로,
## 강화 창 행도 다시 보이게(right_upgrade_panel) 되돌리면 됨.
var auto_battle_unlocked: bool = true
## 자동 이동 — 용사가 알아서 가까운 적을 사냥. 처음부터 ON (클릭 이동은 영 별로라).
## 적 클릭은 여전히 그 적으로 유도 가능(engage 우선).
var auto_move_unlocked: bool = true
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
		"intro": "",  # 시작 시 왼쪽 로그를 비워둠 (슬라임 풀어놓기 전엔 아무것도 안 뜨게). 나중에 손볼 것.
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
	# 밤에 전멸하면 즉시 마을로 (낮 전멸은 기존 페널티 흐름 유지).
	EventBus.party_collapsed.connect(func() -> void:
		if is_night and wave_active:
			end_cycle())


func _on_enemy_defeated(_enemy: Node, gold: int, _world_position: Vector2) -> void:
	enemies_killed += 1
	# Kill gold is paid IMMEDIATELY now — the floating "Ng" on the dead enemy IS
	# real money. The reward CARD on the window is a BONUS on top (🟧 = extra gold,
	# 🟥/🟩/🟦 = weapon/heal/xp). See battle_window._grant_reward.
	# 금빛 비석 (tile) + 노드트리 "황금 감각": every kill pays % more.
	if gold > 0:
		var paid: int = int(round(float(gold) * gold_idol_multiplier() * _draft_gold_mult))
		add_gold(paid)
		wave_gold_earned += paid  # settlement readout: what THIS wave was worth
	# 장비 발견은 이제 전투창이 떨어뜨리는 "보물 상자"를 주워야 생긴다(add_gear_ticket).
	# 처치당 자동 티켓은 제거 — 줍는 행위가 보상의 핵심.
	# "모래시계" node: kills can buy back wave time (+1s, chance per level).
	if wave_active and _tree_kill_time_chance > 0.0 and randf() < _tree_kill_time_chance:
		wave_time_left += 1.0


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
	member_armor_levels.clear()  # per-member armor resets with a fresh party
	_downed_recovery_accum.clear()
	_party_collapsed = false
	inventory.clear()
	for m: CharacterData in party:
		party_levels.append(1)
		party_xp.append(0)
		party_equipment.append(_empty_equipment_slots())
		member_armor_levels.append(1)
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
		total_gold_earned += amount  # still tracked (프레스티지 별조각 등)
	# 누적 골드 자동 해금/팝업 제거 — 모든 적 해금은 이제 노드트리 "새로운 마물"이 담당.
	EventBus.gold_changed.emit(gold)


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
	member_armor_levels.append(1)
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
	member_armor_levels.append(1)
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
	# 드래프트 "북적이는 들판" stacks on top of any skill-tree bonus.
	return skill_effect_int_sum("field_crowd_cap_bonus") + draft_crowd_bonus()


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
	return skill_effect_int_sum("enemies_per_window_bonus") + _tree_window_size_bonus  # 노드트리 "전투창 적 +N"


func battle_turn_interval_multiplier() -> float:
	# 노드트리 "전투 가속" stacks multiplicatively with any skill effects.
	return skill_effect_float_product("battle_turn_interval_mult") * _tree_battle_speed_mult


func pickup_range_multiplier() -> float:
	# 노드트리 "넓은 손" stacks on any skill effect.
	return maxf(1.0, skill_effect_float_product("pickup_range_mult")) * _tree_pickup_mult


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
	# 멀티 전투창 노드를 사면 전투가 더 이상 파티를 멈추지 않는다(한 창이 싸우는
	# 동안 용사는 다음 적을 사냥) — 이게 멀티 전투창의 핵심 가치.
	return _tree_window_bonus > 0 or scale_purchases > 0 or has_skill_node(&"battle_movement") or skill_effect_bool("battle_movement_enabled")


## Max number of battle windows allowed on screen at once = the SCALE axis.
## 0 SCALE purchases → 1 (one-at-a-time); each purchase adds +1 (no cap).
func battle_window_cap() -> int:
	return scale_window_count() + _tree_window_bonus  # 노드트리 "멀티 전투창"


# ─── 강타 (Smite — the player's active MULTIPLIER on a battle window) ────
## Auto-battle is the slow passive baseline; the player taps a charged window to
## SMITE — an AoE burst hitting EVERY enemy in it. That's the missing "곱하기"
## lever: more enemies fed in = more hit at once. Scales off the party's best
## attacker so it stays relevant; cooldown + power are future node axes.
const SMITE_ATK_MULT: float = 3.2     ## smite = best member's combat attack × this
const SMITE_BASE_COOLDOWN: float = 3.0
const SMITE_COMBO_GOLD: int = 8       ## bonus gold per EXTRA enemy killed in one smite


## Smite is a NODE-TREE unlock (cheap first buy). Until bought, no gauge appears.
var smite_unlocked: bool = false


func smite_cooldown() -> float:
	# 전투 가속 + "빠른 강타" both shorten the charge.
	return SMITE_BASE_COOLDOWN * _tree_battle_speed_mult * _tree_smite_cd_mult


func smite_damage() -> int:
	var best: int = 0
	for i in party_size():
		if is_combat_ready(i):
			best = maxi(best, int(round(float(effective_attack(i)) * member_weapon_multiplier(i))))
	return maxi(1, int(round(float(best) * SMITE_ATK_MULT * _tree_smite_mult)))  # "강타 강화"


## A multi-kill smite pays a combo bonus on top of each kill's own gold.
func grant_smite_combo(kills: int) -> void:
	if kills >= 2:
		add_gold(SMITE_COMBO_GOLD * (kills - 1))


## True when BattleManager still has room under the SIMULTANEOUS-FIGHT cap (a perf
## guard on concurrent active windows — NOT chests). When false, new field-enemy
## encounters are silently refused until a fight resolves.
## 따로 다니기: the cap is PER SPLIT GROUP — each party may run battle_window_cap()
## fights at once (멀티 전투창 2 × two parties → up to 4 windows total). This
## legacy any-group form stays for generic "is anything able to fight" checks.
func can_accept_new_battle_window() -> bool:
	for group in active_party_groups():
		if can_group_accept_battle_window(group):
			return true
	return false


## Does THIS split group still have window room? (group 0 = the hero's chain)
func can_group_accept_battle_window(group: int) -> bool:
	var tree := get_tree()
	if tree == null:
		return true
	var bm: Node = tree.get_first_node_in_group("battle_manager")
	if bm == null or not bm.has_method("active_window_count_for_group"):
		return true
	return int(bm.active_window_count_for_group(group)) < battle_window_cap()


## Groups currently in play: the hero's chain (0) + every squad someone is in.
func active_party_groups() -> Array[int]:
	var groups: Array[int] = [0]
	for index in _member_groups.keys():
		var g: int = int(_member_groups[index])
		if g > 0 and int(index) < party_size() and not groups.has(g):
			groups.append(g)
	return groups


func combo_attack_unlocked() -> bool:
	return _draft_combo_unlocked or has_skill_node(&"combo_attack") or skill_effect_bool("combo_attack_enabled")


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
	# Gated by the 마을 레벨: the next weapon TIER must be unlocked first.
	return village_allows_gear_level(weapon_level(type_id) + 1) and gold >= weapon_upgrade_cost(type_id)


## Property-inspector payload for a party member (hero = index 0). Shared by Player /
## Companion so the right inspector renders allies identically: ① header icon + name,
## ② role + 공격력 line, ③ a single 공격력(무기) 강화 action (gold-gated).
func member_inspector_data(index: int, data: CharacterData) -> Dictionary:
	var member_name: String = data.display_name if data else "아군"
	var role: StringName = Balance.character_trait(data.id) if data else Balance.HERO_TRAIT
	var role_name: String = str(Balance.TRAIT_NAMES.get(role, role))
	var atk: int = effective_attack(index) if index >= 0 and index < party_size() else 0
	return {
		"name": member_name,
		"info": "%s · 공격력 %d" % [role_name, atk],
		"sprite": data.inspector_icon() if data else null,
		"actions": [],
		# JRPG equipment sheet: 6 slots, each with [구매]/[변경] (see the builder).
		"equip_rows": member_equipment_rows(index),
	}


## ─── 장비 6칸 (JRPG sheet in the 속성창) ────────────────────────────────
## Slots: 무기 / 방패(쌍수 클래스는 보조 무기) / 투구 / 갑옷 / 악세 ×2.
## [구매] = the gold ladder (무기/갑옷만; the village must STAND on the field —
## early game is loot-only). [변경] = rotate matching gear from the bag.
const EQUIP_SLOT_NAMES_KR: Array[String] = ["무기", "방패", "투구", "갑옷", "악세 1", "악세 2"]


## 장비 구매는 마을이 필드에 서 있어야 열린다 — 초반은 루팅 경제.
func gear_buying_unlocked() -> bool:
	return is_tile_placed(&"village")


func member_equipment_rows(index: int) -> Array:
	var rows: Array = []
	if index < 0 or index >= party_size():
		return rows
	var equipment: Array = equipment_for_member(index)
	var wtype: StringName = Balance.character_weapon_type(party[index].id)
	for slot in EQUIPMENT_SLOT_COUNT:
		var slot_name: String = EQUIP_SLOT_NAMES_KR[slot]
		if slot == 1 and member_dual_wields(index):
			slot_name = "쌍수"
		# Contents: looted entry first; the bought ladders show through 무기/갑옷
		# when nothing looted sits there (same rule as the party-box slots).
		var entry = equipment[slot] if slot < equipment.size() else null
		var item: ItemData = item_entry_data(entry)
		var item_name: String = "—"
		if item != null:
			item_name = entry_display_name(entry)  # "[등급] 이름 +N"
		elif slot == 0 and weapon_level(wtype) > 1:
			item_name = current_weapon_name(wtype)
		elif slot == 3 and member_armor_level(index) > 1:
			item_name = Balance.armor_name_for_level(member_armor_level(index))
		var buy_cost: int = 0
		var can_buy: bool = false
		var on_buy: Callable = Callable()
		var has_buy: bool = slot == 0 or slot == 3
		match slot:
			0:
				var ladder: Array = Balance.WEAPON_NAMES_BY_TYPE.get(wtype, [])
				var maxed: bool = weapon_level(wtype) >= ladder.size()
				buy_cost = 0 if maxed else weapon_upgrade_cost(wtype)
				can_buy = gear_buying_unlocked() and not maxed and can_upgrade_weapon(wtype)
				on_buy = upgrade_weapon.bind(wtype)
			3:
				buy_cost = member_armor_upgrade_cost(index)
				can_buy = gear_buying_unlocked() and can_upgrade_member_armor(index)
				on_buy = upgrade_member_armor.bind(index)
		rows.append({
			"slot": slot,
			"slot_name": slot_name,
			"item_name": item_name,
			"has_buy": has_buy,
			"buy_cost": buy_cost,
			"can_buy": can_buy,
			"on_buy": on_buy,
			"can_change": not _inventory_matches_for_slot(index, slot).is_empty(),
			"on_change": cycle_equip.bind(index, slot),
		})
	return rows


func _inventory_matches_for_slot(member_index: int, slot: int) -> Array[int]:
	var matches: Array[int] = []
	for i in inventory.size():
		var item: ItemData = item_entry_data(inventory[i])
		if item != null and can_equip_to_slot(item, member_index, slot):
			matches.append(i)
	return matches


## [변경]: equip the FIRST matching bag item — repeated clicks rotate naturally
## because the swapped-out piece returns to the END of the bag.
func cycle_equip(index: int, slot: int) -> void:
	var matches: Array[int] = _inventory_matches_for_slot(index, slot)
	if matches.is_empty():
		return
	equip_inventory_item_to(matches[0], index, slot)


## Buying a weapon type auto-equips the matching companion (그 타입 사용자) —
## visible via the "○○ 장착!" feedback + a bigger hit effect.
func upgrade_weapon(type_id: StringName) -> bool:
	# Hard gate (defense in depth): never sell past the 마을 레벨's unlocked tier.
	if not village_allows_gear_level(weapon_level(type_id) + 1):
		EventBus.combat_upgrade_failed.emit(&"weapon")
		return false
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


# ─── 마을 레벨 (gates which gear tier the shop sells) ──────────────────
## Highest gear LEVEL the 마을 currently unlocks for purchase. Level 1 = 맨손/맨몸
## (always owned), so Lv1 마을 → gear level 2 = "1단계 장비" (청동검 / 천 갑옷).
func village_unlocked_gear_level() -> int:
	return village_level + 1


## True when the shop may sell gear up to `target_level` at the current 마을 레벨.
func village_allows_gear_level(target_level: int) -> bool:
	return target_level <= village_unlocked_gear_level()


func village_upgrade_cost() -> int:
	return Balance.village_upgrade_cost(village_level)


func can_upgrade_village() -> bool:
	return is_structure_placed(&"village") and gold >= village_upgrade_cost()


## 마을 강화: raises the tier ceiling so the next 무기/방어구 단계 appears in the shop.
func upgrade_village() -> bool:
	if not is_structure_placed(&"village") or not spend_gold(village_upgrade_cost()):
		EventBus.combat_upgrade_failed.emit(&"village")
		return false
	village_level += 1
	EventBus.combat_upgrade_changed.emit(&"village")
	return true


# ─── Survival: armor axis (PER-MEMBER MAX HP / 마을 방어구 상점) ─────────
## Pad `member_armor_levels` to the current party size (new members → Lv1). The party
## only grows mid-run, so this never has to shift existing indices.
func _ensure_member_armor_sized() -> void:
	while member_armor_levels.size() < party.size():
		member_armor_levels.append(1)
	if member_armor_levels.size() > party.size():
		member_armor_levels.resize(party.size())


func member_armor_level(index: int) -> int:
	if index < 0 or index >= member_armor_levels.size():
		return 1  # unpadded / out of range → 맨몸 (correct default for a new member)
	return member_armor_levels[index]


func member_armor_name(index: int) -> String:
	return Balance.armor_name_for_level(member_armor_level(index))


func member_next_armor_name(index: int) -> String:
	return Balance.armor_name_for_level(member_armor_level(index) + 1)


## Flat MAX HP this member gains from THEIR own armor (level 1 = 0).
func member_armor_hp_bonus(index: int) -> int:
	return Balance.armor_hp_for_level(member_armor_level(index))


func member_armor_upgrade_cost(index: int) -> int:
	return Balance.armor_cost(member_armor_level(index))


func can_upgrade_member_armor(index: int) -> bool:
	return village_allows_gear_level(member_armor_level(index) + 1) \
		and gold >= member_armor_upgrade_cost(index)


## Buy the next armor for ONE member (no longer the whole party). Gated by the 마을
## 레벨's tier ceiling, then by gold. Bumps that member's MAX HP only.
func upgrade_member_armor(index: int) -> bool:
	_ensure_member_armor_sized()
	if index < 0 or index >= member_armor_levels.size():
		return false
	if not village_allows_gear_level(member_armor_level(index) + 1):
		EventBus.combat_upgrade_failed.emit(&"armor")
		return false
	if not spend_gold(member_armor_upgrade_cost(index)):
		EventBus.combat_upgrade_failed.emit(&"armor")
		return false
	member_armor_levels[index] += 1
	EventBus.combat_upgrade_changed.emit(&"armor")
	EventBus.armor_equipped.emit(member_armor_name(index))
	# Member's MAX HP just rose — refresh their bar without changing current HP.
	if index < party_hp.size():
		EventBus.party_member_hp_changed.emit(index, party_hp[index], effective_max_hp(index))
	register_upgrade_purchase(&"armor")
	return true


## Leftmost party member who can still take the next armor at the current 마을 레벨
## (their armor level is below the tier ceiling). -1 when everyone is maxed for this
## village level. Drives the single 무기-style armor row: one click → this member.
func next_armor_buyer() -> int:
	_ensure_member_armor_sized()
	for i in party.size():
		if village_allows_gear_level(member_armor_level(i) + 1):
			return i
	return -1


## Buy the next armor for the leftmost eligible member (the single-row shop path).
func upgrade_next_member_armor() -> bool:
	var i: int = next_armor_buyer()
	if i < 0:
		EventBus.combat_upgrade_failed.emit(&"armor")
		return false
	return upgrade_member_armor(i)


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


## Build a DIRECT building. Its owner companion only APPEARS here (등장) — the
## actual join happens RPG-style in the 이벤트 창 when the hero walks up to the
## placed building (e.g. 성소 도착 → 사제 만남, see Field._arrival_event_for).
func purchase_building(id: StringName) -> bool:
	if not can_purchase_building(id) or not spend_gold(building_cost(id)):
		return false
	_raise_building(id)
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
	member_armor_levels.append(1)
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
## The NEAREST still-locked milestone (tier OR tile) — drives the HUD "next
## carrot" gauge (incremental rule: the next thing is ALWAYS visible).
## {} when everything is already open.
func next_tier_unlock_progress() -> Dictionary:
	var best_need: int = -1
	for i in Balance.tier_count():
		var id: StringName = Balance.tier_at(i)["id"]
		if is_tier_unlocked(id):
			continue
		var need: int = tier_unlock_threshold(id)
		if need > 0 and (best_need < 0 or need < best_need):
			best_need = need
	for t: Dictionary in Balance.TILES:
		var tid: StringName = StringName(t.get("id", &""))
		if tid == &"" or is_tile_unlocked(tid):
			continue
		var need: int = int(t.get("unlock_at", 0))
		if need > 0 and (best_need < 0 or need < best_need):
			best_need = need
	if best_need <= 0:
		return {}
	return {"current": total_gold_earned, "need": best_need}


func can_place_enemy(id: StringName) -> bool:
	return is_tier_unlocked(id) and gold >= tier_place_cost(id)


## Highest tier the player has DELIBERATELY placed this run — the ceiling for
## every mixed/automatic spawn. The dragon never crashes a slime party until
## the player has personally introduced it to the world.
var _max_placed_tier_index: int = 0


## Spend the place cost and ask the Field to spawn one. Returns false (and flashes
## the dock) when too poor.
func place_enemy(id: StringName) -> bool:
	if not can_place_enemy(id) or not spend_gold(tier_place_cost(id)):
		EventBus.combat_upgrade_failed.emit(&"tier")
		return false
	_max_placed_tier_index = maxi(_max_placed_tier_index, Balance.tier_index(id))
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


## Direct-buy tile gates: a tile OPENS at its lifetime-gold milestone (before
## that the dock shows its silhouette + the milestone — plannable, no RNG).
func is_tile_unlocked(id: StringName) -> bool:
	return total_gold_earned >= int(Balance.tile_by_id(id).get("unlock_at", 0))


## Placed check that also covers the campfire's dedicated flag.
func is_tile_placed(id: StringName) -> bool:
	return is_objet_placed(id)


# ─── 방생 장치 (auto-spawner — the automation rung) ─────────────────────
## The incremental ladder: the player graduates from CLICKING enemies in to
## DESIGNING a machine that does it. Placed like the village (generic TILES
## path); upgraded in the 속성창; spawns random UNLOCKED tiers for free.
var spawner_level: int = 1


func spawner_unlocked() -> bool:
	return is_tile_unlocked(&"spawner")


func is_spawner_placed() -> bool:
	return is_structure_placed(&"spawner")


func spawner_interval() -> float:
	return maxf(
		Balance.SPAWNER_MIN_INTERVAL,
		Balance.SPAWNER_BASE_INTERVAL \
			* pow(Balance.SPAWNER_INTERVAL_MULT_PER_LEVEL, float(spawner_level - 1)) \
			* prestige_spawner_multiplier()
	)


func spawner_upgrade_cost() -> int:
	return int(round(Balance.SPAWNER_UPGRADE_BASE_COST * pow(Balance.SPAWNER_UPGRADE_COST_MULT, float(spawner_level - 1))))


func can_upgrade_spawner() -> bool:
	return is_spawner_placed() and gold >= spawner_upgrade_cost()


func upgrade_spawner() -> void:
	if not can_upgrade_spawner() or not spend_gold(spawner_upgrade_cost()):
		return
	spawner_level += 1
	EventBus.combat_upgrade_changed.emit(&"spawner")


## What the machine releases: drawn from the UNLOCKED roster but capped at the
## strongest tier the player has personally placed, weak-biased — the device
## keeps pace with the player without ever springing a surprise dragon.
func spawner_random_enemy_data() -> EnemyData:
	return _weighted_weak_enemy_pick(unlocked_tier_ids)


# ─── 웨이브 (the dopamine cadence) ───────────────────────────────────────
## fight wave_duration() seconds → wave_ended → 3-card draft → next wave.
## Enemies pour in FREE during a wave (no placement needed — placement stays as
## an optional accelerator). Draft picks are the run's build: 적(danger) /
## 아군(power) / 보상(greed) / 필살기(hooks).
var wave_number: int = 0
var wave_active: bool = false
var wave_time_left: float = 0.0
## True between the timer hitting 0 and the 정산 opening: blocks NEW battle windows
## so the open turn-based fights can FINISH (no abort) before settlement.
var wave_winding_down: bool = false
## 밤: the second half of a cycle. Day timeout → night (hunters chase); night
## timeout OR party collapse → 마을 (정산). One full cycle = day + night.
var is_night: bool = false
var night_time_left: float = 0.0
## Draft-granted run effects (cleared by reset_run).
var _draft_attack_mult: float = 1.0
var _draft_hp_mult: float = 1.0
var _draft_gold_mult: float = 1.0
var _draft_spawn_rate_mult: float = 1.0
var _draft_crowd_bonus: int = 0
var _draft_combo_unlocked: bool = false
var _draft_window_collision_ratio: float = 0.0
var _drafted_once_ids: Array[StringName] = []


## Wave length no longer auto-grows per wave — it's bought: "오래 머물기" node.
func wave_duration(_n: int) -> float:
	return minf(Balance.WAVE_DURATION_MAX, Balance.WAVE_BASE_DURATION + _tree_wave_time_bonus)


## Per-wave HARVEST (shown + spent at settlement).
var wave_gold_earned: int = 0     ## kill gold banked THIS wave (multipliers included)
var wave_item_tickets: int = 0    ## gear finds — each one = a 4-choice pick round


func start_next_wave() -> void:
	wave_number += 1
	wave_active = true
	wave_winding_down = false
	is_night = false  # 아침이 밝았다
	wave_time_left = wave_duration(wave_number)
	wave_gold_earned = 0
	wave_item_tickets = 0
	EventBus.wave_started.emit(wave_number)


## Field drives this each frame (only while the field actually runs).
## 낮 타임아웃 → 밤 시작; 밤 타임아웃 → 마을(정산). 한 사이클 = 낮 + 밤.
func tick_wave(delta: float) -> void:
	if not wave_active:
		return
	if is_night:
		night_time_left = maxf(0.0, night_time_left - delta)
		if night_time_left <= 0.0:
			end_cycle()
	else:
		wave_time_left = maxf(0.0, wave_time_left - delta)
		if wave_time_left <= 0.0:
			# 밤 보류: 낮이 끝나면 바로 정산 → 마을. (밤 사이클은 _begin_night으로
			# 다시 이어붙일 수 있게 코드는 그대로 둔다.)
			end_cycle()


func _begin_night() -> void:
	is_night = true
	night_time_left = Balance.NIGHT_DURATION
	EventBus.night_started.emit(wave_number)


## 밤 종료(버팀) 또는 전멸 → 무조건 마을로 (기존 정산 체인이 받아서 처리).
func end_cycle() -> void:
	if not wave_active:
		return
	wave_active = false
	EventBus.wave_ended.emit(wave_number)


## 밤의 박쥐 — the night hunter's data (one tier up, NIGHT_ENEMY_TIER).
func night_enemy_data() -> EnemyData:
	var path: String = str(Balance.tier_by_id(Balance.NIGHT_ENEMY_TIER).get("enemy_res", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return wave_enemy_data()
	return load(path) as EnemyData


func wave_spawn_interval() -> float:
	return maxf(Balance.WAVE_SPAWN_INTERVAL_MIN, Balance.WAVE_SPAWN_INTERVAL * _draft_spawn_rate_mult)


func wave_enemy_data() -> EnemyData:
	return _weighted_weak_enemy_pick(unlocked_tier_ids)


func draft_crowd_bonus() -> int:
	return _draft_crowd_bonus


## A collected 보물 상자 → one settlement pick (3지선다) at the next 정산.
func add_gear_ticket() -> void:
	wave_item_tickets += 1


## Bank gold that ALSO counts toward this wave's 스테이지 골드 readout (field coin
## pickups route through here so the 정산 total matches the balance).
func bank_wave_gold(amount: int) -> void:
	if amount <= 0:
		return
	add_gold(amount)
	wave_gold_earned += amount


## Settlement pick with NO eligible wearer → straight into the bag (전설템은
## 일단 갖고 싶으니까). Returns true.
func gain_gear_to_bag(item: ItemData, level: int, rarity: StringName = &"common") -> bool:
	if item == null:
		return false
	inventory.append(_make_item_entry(item, level, rarity))
	EventBus.inventory_changed.emit()
	return true


## 정산 "가방 전부 판매" — sells every bag entry at once, returns the total gold.
func sell_all_inventory() -> int:
	var total: int = 0
	var i: int = 0
	while i < inventory.size():
		var v: int = sell_inventory_entry_at(i)
		if v <= 0:
			i += 1  # unsellable entry (worthless/null) — skip, don't loop forever
		else:
			total += v  # sold → next entry slid into slot i
	return total


## Extra chance a battle window drops a 보물 상자 ("보물 감각" node). Read by the
## window's drop roll on top of its base ITEM_DROP_CHANCE.
func gear_box_chance_bonus() -> float:
	return _tree_ticket_bonus


## Pull WAVE_DRAFT_CHOICES distinct cards, skipping spent "once" picks and the
## new-tier card when no stronger tier exists to introduce.
func draft_options() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for card: Dictionary in Balance.WAVE_DRAFT_CARDS:
		var id: StringName = StringName(card.get("id", &""))
		if bool(card.get("once", false)) and _drafted_once_ids.has(id):
			continue
		if id == &"enemy_new_tier" and _next_tier_above_ceiling() == &"":
			continue
		pool.append(card)
	pool.shuffle()
	var picks: Array[Dictionary] = []
	for card: Dictionary in pool:
		if picks.size() >= Balance.WAVE_DRAFT_CHOICES:
			break
		picks.append(card)
	return picks


## The weakest tier strictly above the current mixed-spawn ceiling, or &"".
func _next_tier_above_ceiling() -> StringName:
	for i in Balance.tier_count():
		if i > _max_placed_tier_index:
			return StringName(Balance.tier_at(i).get("id", &""))
	return &""


# ─── 마을 노드트리 (JRPG spine — settlement gold goes HERE) ──────────────
## 태초마을부터 마왕 마을까지 외길 스파인; 각 마을이 열리면 그 마을의 파생
## 노드(적/아군/보상/전투창)가 구매 가능해지고, 마을 등급이 정산 픽의 장비
## 레벨 천장을 올린다. 프레스티지에 전부 리셋 — 요즘 인크리멘탈의 룰대로.
var town_index: int = 0                 ## highest unlocked spine town (0 = 태초마을)
var tree_levels: Dictionary = {}        ## node id -> level
var map_hero_hex: Vector2i = Vector2i.ZERO  ## the hero's avatar position ON the world map
var _tree_window_bonus: int = 0         ## "멀티 전투창" node → battle window cap
var _tree_battle_speed_mult: float = 1.0  ## "전투 가속" — turn interval shrinks (<1)
var _tree_move_speed_mult: float = 1.0    ## "신속" — party move speed grows (>1)
var _tree_window_size_bonus: int = 0      ## "전투창 적 +N" — bodies per window
## Per-class 단련 nodes (아군 axis): character id → multiplier.
var _tree_member_atk_mult: Dictionary = {}
var _tree_member_hp_mult: Dictionary = {}
var _tree_crit_bonus: float = 0.0         ## "도적 단련" — flat crit chance for everyone
var _tree_sell_mult: float = 1.0          ## "비싸게 팔기" — gear sell value
var _tree_ticket_bonus: float = 0.0       ## "보물 감각" — gear-find chance per kill
var _tree_wave_time_bonus: float = 0.0    ## "오래 머물기" — +초 per wave
var _tree_kill_time_chance: float = 0.0   ## "모래시계" — kill → chance of +1s
var _tree_auto_collect_chance: float = 0.0  ## "자동 줍기" — per-drop auto-pickup at wave end
var _tree_smite_mult: float = 1.0         ## "강타 강화/폭주" — smite damage
var _tree_smite_cd_mult: float = 1.0      ## "빠른 강타" — smite charge time (<1)
var _tree_pickup_mult: float = 1.0        ## "넓은 손" — hover/magnet pickup reach
var _tree_interest: float = 0.0           ## "이자" — % of held gold paid at 정산


## 0 by default — drops must be picked up by HAND (100%). The "자동 줍기" node
## buys a per-drop chance the wave-end sweep grabs leftovers for you.
func auto_collect_chance() -> float:
	return _tree_auto_collect_chance


func town_gear_level() -> int:
	return int(Balance.town_by_index(town_index).get("gear_level", 1))


func next_town() -> Dictionary:
	return Balance.town_by_index(town_index + 1)


func can_unlock_next_town() -> bool:
	var town: Dictionary = next_town()
	return not town.is_empty() and gold >= int(town.get("cost", 0))


func unlock_next_town() -> void:
	if not can_unlock_next_town() or not spend_gold(int(next_town().get("cost", 0))):
		return
	town_index += 1
	EventBus.combat_upgrade_changed.emit(&"town")


func tree_node_level(id: StringName) -> int:
	return int(tree_levels.get(id, 0))


func tree_node_cost(id: StringName) -> int:
	var node: Dictionary = Balance.tree_node_by_id(id)
	return int(round(int(node.get("cost", 50)) * pow(float(node.get("cost_mult", 1.5)), float(tree_node_level(id)))))


## A node is visible/buyable only once its town stands on the spine.
func is_tree_node_open(id: StringName) -> bool:
	var node: Dictionary = Balance.tree_node_by_id(id)
	var town_id: StringName = StringName(node.get("town", &""))
	for i in town_index + 1:
		if StringName(Balance.town_by_index(i).get("id", &"")) == town_id:
			return true
	return false


func can_buy_tree_node(id: StringName) -> bool:
	var node: Dictionary = Balance.tree_node_by_id(id)
	if node.is_empty() or not is_tree_node_open(id):
		return false
	if tree_node_level(id) >= int(node.get("max_level", 1)):
		return false
	if StringName(node.get("effect", "")) == &"tier" and _next_tier_above_ceiling() == &"":
		return false
	# 영입 노드: already in the party (or party full) → not buyable.
	var char_id: StringName = StringName(node.get("char_id", &""))
	if char_id != &"" and (has_party_member(char_id) or party.size() >= Balance.MAX_PARTY_SIZE):
		return false
	# 체인 순서: an ADJACENT hex must already be owned (도르프식 성장).
	if not is_tree_node_reachable(id):
		return false
	return gold >= tree_node_cost(id)


## Chain-order gate: a node opens only when it touches something already built
## (a town, a road, or a bought node) — the tree grows outward, no skipping.
func is_tree_node_reachable(id: StringName) -> bool:
	var node: Dictionary = Balance.tree_node_by_id(id)
	var hex: Vector2i = node.get("hex", Vector2i.ZERO)
	for n: Vector2i in Balance.hex_neighbors(hex):
		if _is_hex_owned(n):
			return true
	return false


func _is_hex_owned(h: Vector2i) -> bool:
	# Unlocked towns.
	for i in town_index + 1:
		if Vector2i(Balance.town_by_index(i).get("hex", Vector2i(99, 99))) == h:
			return true
	# Roads between unlocked towns (odd x on the spine row).
	if h.y == 0 and posmod(h.x, 2) == 1 and h.x >= 1 and h.x <= town_index * 2 - 1:
		return true
	# Bought nodes.
	for node: Dictionary in Balance.TREE_NODES:
		if Vector2i(node.get("hex", Vector2i(99, 99))) == h \
				and tree_node_level(StringName(node.get("id", &""))) > 0:
			return true
	return false


## "이자" node: pays % of held gold at 정산 (called once by the tally). 0 = none.
func collect_wave_interest() -> int:
	if _tree_interest <= 0.0:
		return 0
	var amount: int = int(floor(float(gold) * _tree_interest))
	if amount > 0:
		add_gold(amount)
	return amount


func buy_tree_node(id: StringName) -> void:
	if not can_buy_tree_node(id) or not spend_gold(tree_node_cost(id)):
		return
	tree_levels[id] = tree_node_level(id) + 1
	var node: Dictionary = Balance.tree_node_by_id(id)
	_apply_tree_effect(str(node.get("effect", "")), float(node.get("mag", 0.0)))
	EventBus.combat_upgrade_changed.emit(&"tree")


## Generic, magnitude-driven effect table: the node's "mag" field IS the number
## ("atk" mag 0.05 = +5%, "wave_time" mag 3.0 = +3s …) so tier-II/royal versions
## of an effect are pure data, no new code.
func _apply_tree_effect(effect: String, mag: float = 0.0) -> void:
	match effect:
		# ⚔️ 공격
		"atk": _draft_attack_mult *= 1.0 + mag
		"atk_hero": _bump_tree_member_atk(&"hero", 1.0 + mag)
		"atk_mage": _bump_tree_member_atk(&"mage", 1.0 + mag)
		"atk_priest": _bump_tree_member_atk(&"priest", 1.0 + mag)
		"crit": _tree_crit_bonus += mag
		"battle_speed": _tree_battle_speed_mult *= 1.0 - mag
		# 🛡 생존/이동
		"hp":
			_draft_hp_mult *= 1.0 + mag
			EventBus.party_hp_changed.emit()
		"hp_knight":
			_tree_member_hp_mult[&"knight"] = float(_tree_member_hp_mult.get(&"knight", 1.0)) * (1.0 + mag)
			EventBus.party_hp_changed.emit()
		"move_speed": _tree_move_speed_mult *= 1.0 + mag
		# 💰 보상
		"gold": _draft_gold_mult *= 1.0 + mag
		"sell": _tree_sell_mult *= 1.0 + mag
		"interest": _tree_interest += mag
		"wave_time": _tree_wave_time_bonus += mag
		"kill_time": _tree_kill_time_chance += mag
		# 🧲 획득
		"pickup_range": _tree_pickup_mult *= 1.0 + mag
		"auto_collect": _tree_auto_collect_chance = minf(1.0, _tree_auto_collect_chance + mag)
		"ticket": _tree_ticket_bonus += mag
		# 🔴 적 (위험 = 수입 다이얼)
		"horde": _draft_spawn_rate_mult *= 1.0 - mag
		"crowd": _draft_crowd_bonus += int(mag)
		"window_size": _tree_window_size_bonus += int(mag)
		"tier": _raise_tier_ceiling()
		# 🟣 전투창 훅
		"windows": _tree_window_bonus += 1
		"smite": smite_unlocked = true
		"smite_power": _tree_smite_mult *= 1.0 + mag
		"smite_cd": _tree_smite_cd_mult *= 1.0 - mag
		"combo": _draft_combo_unlocked = true
		"billiards": _draft_window_collision_ratio = maxf(_draft_window_collision_ratio, 0.2)
		"collision": _draft_window_collision_ratio += mag
		# 👥 동료
		"recruit_mage": _recruit_by_node(&"mage")
		"recruit_priest": _recruit_by_node(&"priest")
		"recruit_knight": _recruit_by_node(&"knight")
		"recruit_thief": _recruit_by_node(&"thief")


func _bump_tree_member_atk(char_id: StringName, mult: float) -> void:
	_tree_member_atk_mult[char_id] = float(_tree_member_atk_mult.get(char_id, 1.0)) * mult
	EventBus.combat_upgrade_changed.emit(&"speed")


## 동료 영입 노드: the companion joins the party on the spot (이벤트 없이 즉시).
func _recruit_by_node(char_id: StringName) -> void:
	if has_party_member(char_id):
		return
	var path: String = "res://data/characters/%s.tres" % char_id
	if not ResourceLoader.exists(path):
		return
	var data: CharacterData = load(path) as CharacterData
	if data == null:
		return
	_add_party_member(data)
	EventBus.companion_recruited.emit(char_id)


## The next tier debuts: force-unlock + raise the mixed-spawn ceiling.
func _raise_tier_ceiling() -> void:
	var next_id: StringName = _next_tier_above_ceiling()
	if next_id == &"":
		return
	if not is_tier_unlocked(next_id):
		unlocked_tier_ids.append(next_id)
		EventBus.tier_unlocked.emit(next_id)
	_max_placed_tier_index = Balance.tier_index(next_id)
	EventBus.combat_upgrade_changed.emit(&"tier")


# ─── 정산 장비 픽 (Brotato-style 4지선다) ────────────────────────────────
## Each wave's gear find = one round of: 3 rolled items + the gold option.
## Items roll up to the TOWN's gear level — better towns, better loot.
func roll_gear_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for i in Balance.SETTLE_GEAR_CHOICES:
		var item: ItemData = ItemDB.random_drop()
		if item == null:
			continue
		var cap: int = town_gear_level()
		var level: int = randi_range(maxi(1, cap - 1), cap)
		var rarity: StringName = StringName(Balance.roll_gear_rarity().get("id", &"common"))
		options.append({"item": item, "level": level, "rarity": rarity})
	return options


func settle_gold_option_value() -> int:
	return Balance.SETTLE_GOLD_OPTION_BASE + Balance.SETTLE_GOLD_OPTION_PER_WAVE * wave_number


func gear_gold_value(level: int) -> int:
	return Balance.GEAR_GOLD_VALUE_PER_LEVEL * maxi(1, level)


## Party indices that can wear this item (drives the pick-card portraits).
func eligible_members_for_item(item: ItemData) -> Array[int]:
	var out: Array[int] = []
	var slot: int = slot_index_for_item(item)
	for i in party_size():
		if can_equip_to_slot(item, i, slot):
			out.append(i)
	return out


## The slot this item should drop into for `member`. Accessories prefer an EMPTY
## accessory slot (악세1 then 악세2) so both get used; only replace 악세1 when both
## are full. Everything else uses its fixed slot.
func best_slot_for_item(item: ItemData, member_index: int) -> int:
	if item == null or member_index < 0 or member_index >= party_equipment.size():
		return slot_index_for_item(item)
	if item.slot == ItemData.Slot.ACCESSORY:
		if item_entry_data(party_equipment[member_index][EQUIPMENT_ACCESSORY_SLOT_A]) == null:
			return EQUIPMENT_ACCESSORY_SLOT_A
		if item_entry_data(party_equipment[member_index][EQUIPMENT_ACCESSORY_SLOT_B]) == null:
			return EQUIPMENT_ACCESSORY_SLOT_B
		return EQUIPMENT_ACCESSORY_SLOT_A  # both full → replace 악세1
	return slot_index_for_item(item)


## Which (member, slot) a settlement pick would land in: prefer an eligible member
## who has an EMPTY destination slot; else the first eligible (a replace).
func settlement_target_for(item: ItemData) -> Dictionary:
	var eligible: Array[int] = eligible_members_for_item(item)
	if eligible.is_empty():
		return {}
	for i in eligible:
		var slot: int = best_slot_for_item(item, i)
		if item_entry_data(party_equipment[i][slot]) == null:
			return {"member": i, "slot": slot}
	var first: int = eligible[0]
	return {"member": first, "slot": best_slot_for_item(item, first)}


## Equip a settlement pick. The replaced piece (if any) goes BACK TO THE BAG —
## never auto-sold (the player decides). Returns the equipped member index (or -1).
func equip_settlement_gear(item: ItemData, level: int, rarity: StringName = &"common") -> int:
	var target: Dictionary = settlement_target_for(item)
	if target.is_empty():
		return -1
	var member: int = int(target["member"])
	var slot: int = int(target["slot"])
	var previous = party_equipment[member][slot]
	if item_entry_data(previous) != null:
		inventory.append(previous)  # 교체된 장비는 판매 대신 가방으로
		EventBus.inventory_changed.emit()
	party_equipment[member][slot] = _make_item_entry(item, level, rarity)
	party_hp[member] = mini(party_hp[member], effective_max_hp(member))
	EventBus.party_member_hp_changed.emit(member, party_hp[member], effective_max_hp(member))
	EventBus.party_equipment_changed.emit(member)
	return member


func apply_draft_card(card_id: StringName) -> void:
	var card: Dictionary = {}
	for c: Dictionary in Balance.WAVE_DRAFT_CARDS:
		if StringName(c.get("id", &"")) == card_id:
			card = c
			break
	if card.is_empty():
		return
	if bool(card.get("once", false)):
		_drafted_once_ids.append(card_id)
	match card_id:
		&"enemy_new_tier":
			_raise_tier_ceiling()
		&"enemy_horde":
			_draft_spawn_rate_mult *= 0.8
		&"enemy_crowd":
			_draft_crowd_bonus += 2
		&"ally_sharpen":
			_draft_attack_mult *= 1.05
		&"ally_vitality":
			_draft_hp_mult *= 1.08
			EventBus.party_hp_changed.emit()
		&"ally_mend":
			restore_party_full()
		&"loot_gold":
			_draft_gold_mult *= 1.15
		&"loot_cache":
			add_gold(Balance.WAVE_CACHE_GOLD_BASE + Balance.WAVE_CACHE_GOLD_PER_WAVE * wave_number)
		&"hook_combo":
			_draft_combo_unlocked = true
		&"hook_billiards":
			_draft_window_collision_ratio = maxf(_draft_window_collision_ratio, 0.2)
	EventBus.draft_card_picked.emit(card_id, str(card.get("name", "")))


# ─── 패시브 타일 (Loop-Hero style world auras) ───────────────────────────
## A PLACED passive tile blesses the whole party — no radius, no babysitting.
## Click the tile → 속성창 → 강화 raises its level. Effects are read through
## the helpers below so combat code never touches tile bookkeeping.
var tile_levels: Dictionary = {}  ## tile id -> level (1 when first placed)


func tile_level(id: StringName) -> int:
	return int(tile_levels.get(id, 1))


func tile_upgrade_cost(id: StringName) -> int:
	var up: Dictionary = Balance.TILE_UPGRADES.get(id, {})
	return int(round(int(up.get("base_cost", 100)) * pow(float(up.get("cost_mult", 1.6)), float(tile_level(id) - 1))))


func can_upgrade_tile(id: StringName) -> bool:
	var up: Dictionary = Balance.TILE_UPGRADES.get(id, {})
	if up.is_empty() or not is_structure_placed(id):
		return false
	return tile_level(id) < int(up.get("max_level", 1)) and gold >= tile_upgrade_cost(id)


func upgrade_tile(id: StringName) -> void:
	if not can_upgrade_tile(id) or not spend_gold(tile_upgrade_cost(id)):
		return
	tile_levels[id] = tile_level(id) + 1
	EventBus.tile_upgraded.emit(id, tile_level(id))
	EventBus.combat_upgrade_changed.emit(&"tile")


## Tile effect %, already multiplied by level (0 when not placed).
func tile_effect_percent(id: StringName) -> int:
	if not is_structure_placed(id):
		return 0
	return int(Balance.TILE_UPGRADES.get(id, {}).get("value", 0)) * tile_level(id)


func whetstone_attack_multiplier() -> float:
	return 1.0 + float(tile_effect_percent(&"whetstone")) / 100.0


func gold_idol_multiplier() -> float:
	return 1.0 + float(tile_effect_percent(&"gold_idol")) / 100.0


# ─── 프레스티지 (세계 다시 쓰기) ─────────────────────────────────────────
## The hour-two layer: fold the world, convert lifetime gold into 별조각, buy
## PERMANENT perks, wake the world again stronger. Everything here deliberately
## survives reset_run() — it IS the thing that persists.
var star_shards: int = 0
var prestige_count: int = 0
var prestige_perk_levels: Dictionary = {}  ## perk id -> level (permanent)


## Shards this fold would pay right now.
func prestige_shards_on_reset() -> int:
	return int(floor(sqrt(float(total_gold_earned) / Balance.PRESTIGE_SHARD_DIVISOR)))


func can_prestige() -> bool:
	return world_started and prestige_shards_on_reset() >= 1


## Fold the world: bank the shards, reset the run. The caller (prestige window)
## reloads the scene afterwards so every node starts from the fresh state.
func do_prestige() -> void:
	if not can_prestige():
		return
	var earned: int = prestige_shards_on_reset()
	star_shards += earned
	prestige_count += 1
	reset_run()
	EventBus.prestige_completed.emit(earned, star_shards)


func perk_level(id: StringName) -> int:
	return int(prestige_perk_levels.get(id, 0))


func perk_cost(id: StringName) -> int:
	var perk: Dictionary = Balance.prestige_perk_by_id(id)
	return int(perk.get("base_cost", 1)) * (perk_level(id) + 1)


func can_buy_perk(id: StringName) -> bool:
	var perk: Dictionary = Balance.prestige_perk_by_id(id)
	if perk.is_empty() or perk_level(id) >= int(perk.get("max_level", 1)):
		return false
	return star_shards >= perk_cost(id)


func buy_perk(id: StringName) -> void:
	if not can_buy_perk(id):
		return
	star_shards -= perk_cost(id)
	prestige_perk_levels[id] = perk_level(id) + 1
	EventBus.prestige_changed.emit()


## ── Perk effects (hooked into the run systems) ──
func prestige_starting_gold() -> int:
	return STARTING_GOLD + perk_level(&"start_gold") * int(Balance.prestige_perk_by_id(&"start_gold").get("value", 100))


func prestige_attack_multiplier() -> float:
	return 1.0 + 0.1 * float(perk_level(&"hero_might"))


func prestige_spawner_multiplier() -> float:
	return pow(0.9, float(perk_level(&"swift_spawner")))


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


## DEBUG (gold-chip click): surface EVERY placement tile in the dock at once —
## all enemy tiers unlock, both objets (모닥불/마을) land in hand, and the direct
## buildings' gate counters (성소's downs, …) jump to their thresholds. Placement
## costs still apply — the +1000G from the same click bankrolls the testing.
func debug_unlock_all_tiles() -> void:
	for i in Balance.tier_count():
		var tier_id: StringName = StringName(Balance.tier_at(i)["id"])
		if not is_tier_unlocked(tier_id):
			unlocked_tier_ids.append(tier_id)
			EventBus.tier_unlocked.emit(tier_id)
	for tile: Dictionary in Balance.TILES:
		total_gold_earned = maxi(total_gold_earned, int(tile.get("unlock_at", 0)))
	for building_id: StringName in [&"sanctuary"]:
		var cond: Dictionary = Balance.building_by_id(building_id).get("unlock", {})
		var need: int = int(cond.get("value", 0))
		match StringName(cond.get("type", &"")):
			&"kills": total_enemy_kills = maxi(total_enemy_kills, need)
			&"downs": total_party_downs = maxi(total_party_downs, need)
			&"gold_earned": total_gold_earned = maxi(total_gold_earned, need)
	# One catch-all refresh so the dock/tooltips rebuild immediately.
	EventBus.combat_upgrade_changed.emit(&"tier")


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
## Capped + weak-biased — see _weighted_weak_enemy_pick.
func random_active_tier_enemy_data() -> EnemyData:
	return _weighted_weak_enemy_pick(active_tier_ids)


## Shared mixed-spawn picker (field refill + 방생 장치):
##   ① CEILING — only tiers at/below the strongest one the player has placed
##      ("슬라임 눌렀는데 용" never happens; you introduce each tier yourself).
##   ② WEAK BIAS — weight halves per strength rank, so stronger tiers stay
##      accents inside the mix instead of taking it over.
func _weighted_weak_enemy_pick(ids: Array[StringName]) -> EnemyData:
	var paths: Array[String] = []
	var weights: Array[float] = []
	var total: float = 0.0
	for id: StringName in ids:
		if not is_tier_unlocked(id):
			continue
		var rank: int = Balance.tier_index(id)
		if rank > _max_placed_tier_index:
			continue
		var path: String = str(Balance.tier_by_id(id).get("enemy_res", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var weight: float = pow(0.5, float(rank))
		paths.append(path)
		weights.append(weight)
		total += weight
	if paths.is_empty():
		return null
	var roll: float = randf() * total
	for i in paths.size():
		roll -= weights[i]
		if roll <= 0.0:
			return load(paths[i]) as EnemyData
	return load(paths.back()) as EnemyData


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


## Base enemies per window = 1. 적 레벨에 따른 증가 제거 — 전투창 적 수는 이제
## 오직 노드트리 "전투창 적 +1"(enemies_per_window_bonus)이 키운다.
func enemy_spawn_count(_tier_id: StringName) -> int:
	return 1


## Uncapped per-level kill-gold multiplier for this tier.
func enemy_kill_gold_multiplier(tier_id: StringName) -> float:
	return Balance.kill_gold_mult_for_level(enemy_level(tier_id))


## Called when one enemy of `tier_id` dies. 적 레벨 시스템 제거 — 더 이상 누적
## 처치로 레벨이 오르지 않는다(노드트리와 중복). 총 처치 수만 집계.
func record_enemy_kill(_tier_id: StringName) -> void:
	total_enemy_kills += 1


## 방문 창 (ObjectWindow) open state — the hero holds still while "inside" the
## visited object. WITHOUT detached members the whole field pauses (movement,
## spawning, encounters) via the battle-pause counter. WITH 따로 다니기 in effect
## only the hero's chain is held (is_movement_frozen) — the detached members keep
## roaming and fighting while the hero shops.
var object_window_open: bool = false
var _object_window_paused_field: bool = false


func open_object_window() -> void:
	if object_window_open:
		return
	object_window_open = true
	_object_window_paused_field = not has_detached_members()
	if _object_window_paused_field:
		begin_field_battle_pause()


func close_object_window() -> void:
	if not object_window_open:
		return
	object_window_open = false
	if _object_window_paused_field:
		end_field_battle_pause()
	_object_window_paused_field = false


# ─── 따로 다니기 (party split — BG-style chain break into squads) ────────
## Learned once at the campfire (needs a companion) → 2 groups. 분할 확장
## upgrades raise the cap toward Balance.PARTY_GROUP_MAX. Group 0 = the hero's
## chain; groups 1+ are independent SQUADS: members of the same group travel
## together (lowest index leads, hunting field enemies; the rest wedge behind).
## Drag a party-bar chip right/left to push it a group out / pull it back in.
var party_group_limit: int = 1
var _member_groups: Dictionary = {}  ## party index -> group id (0 = hero chain)


func is_party_split_unlocked() -> bool:
	return party_group_limit >= 2


func party_split_learn_cost() -> int:
	return Balance.PARTY_SPLIT_LEARN_COST


func can_learn_party_split() -> bool:
	return party_group_limit < 2 and party_size() >= 2 and gold >= party_split_learn_cost()


func learn_party_split() -> void:
	if not can_learn_party_split() or not spend_gold(party_split_learn_cost()):
		return
	party_group_limit = 2
	EventBus.party_split_learned.emit()


## 분할 확장: each step allows one more simultaneous squad (cap PARTY_GROUP_MAX).
func party_split_expand_cost() -> int:
	return Balance.PARTY_SPLIT_EXPAND_BASE_COST * maxi(1, party_group_limit - 1)


func can_expand_party_split() -> bool:
	return is_party_split_unlocked() and party_group_limit < Balance.PARTY_GROUP_MAX \
		and gold >= party_split_expand_cost()


func expand_party_split() -> void:
	if not can_expand_party_split() or not spend_gold(party_split_expand_cost()):
		return
	party_group_limit += 1
	EventBus.party_group_limit_changed.emit(party_group_limit)


func member_group(index: int) -> int:
	return int(_member_groups.get(index, 0))


func is_member_detached(index: int) -> bool:
	return member_group(index) != 0


func has_detached_members() -> bool:
	for index in _member_groups.keys():
		if int(_member_groups[index]) != 0:
			return true
	return false


## Move a member to `group` (clamped to the unlocked cap). The hero (index 0)
## never leaves group 0. Returns true when the assignment actually changed.
func set_member_group(index: int, group: int) -> bool:
	if not is_party_split_unlocked() or index <= 0 or index >= party_size():
		return false
	var clamped: int = clampi(group, 0, party_group_limit - 1)
	if clamped == member_group(index):
		return false
	_member_groups[index] = clamped
	EventBus.member_group_changed.emit(index, clamped)
	return true


## 이벤트 창 (EventWindow cutscenes) — same freeze contract as the 방문 창, with
## its own flag so the two window types can't release each other's hold.
var event_window_open: bool = false


func open_event_window() -> void:
	if event_window_open:
		return
	event_window_open = true
	begin_field_battle_pause()


func close_event_window() -> void:
	if not event_window_open:
		return
	event_window_open = false
	end_field_battle_pause()


func begin_field_battle_pause() -> void:
	_field_battle_pause_count += 1


func end_field_battle_pause() -> void:
	_field_battle_pause_count = maxi(0, _field_battle_pause_count - 1)


## Per-party battle pause — used by pre-멀티전투창 MODAL fights so only the party
## that's actually fighting holds still; the other split squads keep roaming and
## fighting. (Global window/cutscene freezes keep using the counter above.)
var _group_battle_pause_counts: Dictionary = {}  ## group id -> pause count


func begin_group_battle_pause(group: int) -> void:
	_group_battle_pause_counts[group] = int(_group_battle_pause_counts.get(group, 0)) + 1


func end_group_battle_pause(group: int) -> void:
	_group_battle_pause_counts[group] = maxi(0, int(_group_battle_pause_counts.get(group, 0)) - 1)


func is_group_battle_paused(group: int) -> bool:
	return int(_group_battle_pause_counts.get(group, 0)) > 0


func is_field_battle_paused() -> bool:
	return _field_battle_pause_count > 0


## True while the WHOLE field should hold still: a global pause is held, OR every
## active split group is individually frozen (modal-paused or window-capped).
## With one un-split party this is the classic behavior; with 따로 다니기 the
## field keeps living as long as ANY party can still roam.
func is_field_frozen_for_battle() -> bool:
	if is_field_battle_paused():
		return true
	for group in active_party_groups():
		if not is_group_frozen_for_battle(group):
			return false
	return true


## Per-party freeze: THIS group holds still while its own modal fight runs or its
## own windows are capped — the other parties keep moving/fighting.
func is_group_frozen_for_battle(group: int) -> bool:
	return is_field_battle_paused() or is_group_battle_paused(group) \
		or not can_group_accept_battle_window(group)


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
	member_armor_levels.append(1)
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
	var hp: float = avg_hit * base_kill_time * Balance.PARTY_HITS_PER_SECOND
	if is_night:
		hp *= Balance.NIGHT_ENEMY_HP_MULT  # 밤엔 끈질기게 버틴다 — 강타로도 한방에 안 죽음
	return maxi(1, int(round(hp)))


func scaled_enemy_attack(data: EnemyData) -> int:
	if data == null:
		return 1
	# Per-tier attack ramp (Balance TIERS.atk_mult) so orc+ hit hard enough to
	# actually threaten a wipe — the source of mid/late "위기".
	var atk_mult: float = float(tier_for_enemy_data(data).get("atk_mult", 1.0))
	var atk: float = float(data.attack) * atk_mult
	if is_night:
		atk *= Balance.NIGHT_ENEMY_ATK_MULT  # 밤의 공격은 묵직하다 — 초반엔 버티다 전멸
	return maxi(1, int(round(atk)))


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


## Field movement is frozen while the whole party recovers from a full collapse,
## or while a 방문 창 / 이벤트 창 holds the field still.
func is_movement_frozen() -> bool:
	return _party_collapsed or not world_started or party_resting \
		or object_window_open or event_window_open


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
		# 쌍수: dual-wield classes take a second WEAPON in the off-hand (slot 1).
		if not (slot_index == 1 and item.slot == ItemData.Slot.WEAPON and member_dual_wields(member_index)):
			return false
	if item.allowed_character_id != &"" and party[member_index].id != item.allowed_character_id:
		return false
	return true


## 쌍수 class check — the off-hand slot doubles as a weapon hand (단검 계열).
func member_dual_wields(index: int) -> bool:
	if index < 0 or index >= party.size():
		return false
	return Balance.character_weapon_type(party[index].id) == &"dagger"


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
	# Half the gear's worth, scaled by the "비싸게 팔기" node.
	return maxi(1, int(round(float(gear_entry_value(entry)) * 0.5 * _tree_sell_mult)))


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
	if member_armor_level(index) > 1:
		lines.append("  └ 방어구 %s  HP +%d" % [member_armor_name(index), member_armor_hp_bonus(index)])
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


func _make_item_entry(item: ItemData, level: int = 1, rarity: StringName = &"common") -> Dictionary:
	return {
		"item": item,
		"level": maxi(1, level),
		"rarity": rarity,
	}


# ─── 장비 등급 (rarity) helpers ───────────────────────────────────────────
func item_entry_rarity(entry) -> StringName:
	if entry is Dictionary:
		return StringName((entry as Dictionary).get("rarity", &"common"))
	return &"common"


func entry_rarity_mult(entry) -> float:
	return float(Balance.gear_rarity_by_id(item_entry_rarity(entry)).get("mult", 1.0))


func entry_rarity_color(entry) -> Color:
	return Balance.gear_rarity_by_id(item_entry_rarity(entry)).get("color", Color.WHITE)


## "[고급] 강철검 +1" — the full colored-name string for lists/cards.
func entry_display_name(entry) -> String:
	var item: ItemData = item_entry_data(entry)
	if item == null:
		return "—"
	var level: int = item_entry_level(entry)
	var rarity: Dictionary = Balance.gear_rarity_by_id(item_entry_rarity(entry))
	var prefix: String = "" if StringName(rarity.get("id", &"common")) == &"common" else "[%s] " % str(rarity.get("name", ""))
	return prefix + item.display_name + (" +%d" % (level - 1) if level > 1 else "")


## A gear entry's base gold worth: per-level value × rarity multiplier.
func gear_entry_value(entry) -> int:
	var item: ItemData = item_entry_data(entry)
	if item == null:
		return 0
	return maxi(1, int(round(float(Balance.GEAR_GOLD_VALUE_PER_LEVEL * item_entry_level(entry)) * entry_rarity_mult(entry))))


## 장비 상자: buy ONE random piece of the current town's stage straight into the
## bag. Rarity is rolled — the shop is a little slot machine.
func gear_box_cost() -> int:
	return town_gear_level() * Balance.GEAR_SHOP_COST_PER_LEVEL


func can_buy_gear_box() -> bool:
	return gold >= gear_box_cost()


func buy_gear_box() -> bool:
	if not can_buy_gear_box() or not spend_gold(gear_box_cost()):
		return false
	var item: ItemData = ItemDB.random_drop()
	if item == null:
		return false
	var cap: int = town_gear_level()
	var level: int = randi_range(maxi(1, cap - 1), cap)
	var rarity: StringName = StringName(Balance.roll_gear_rarity().get("id", &"common"))
	inventory.append(_make_item_entry(item, level, rarity))
	EventBus.inventory_changed.emit()
	return true


## [해제]: take the piece OFF into the bag (the equip/unequip half of the tab).
func unequip_to_bag(member_index: int, slot: int) -> void:
	if member_index < 0 or member_index >= party_equipment.size():
		return
	if slot < 0 or slot >= party_equipment[member_index].size():
		return
	var entry = party_equipment[member_index][slot]
	if item_entry_data(entry) == null:
		return
	party_equipment[member_index][slot] = null
	inventory.append(entry)
	party_hp[member_index] = mini(party_hp[member_index], effective_max_hp(member_index))
	EventBus.party_member_hp_changed.emit(member_index, party_hp[member_index], effective_max_hp(member_index))
	EventBus.party_equipment_changed.emit(member_index)
	EventBus.inventory_changed.emit()


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
	var base: int = party[index].attack + _level_bonus(index, "atk") + _equipment_bonus(index, "attack_bonus") + _stacked_int_effect_for_character(character_id, "atk_flat") + skill_effect_int_sum("atk_flat")
	# 숫돌 (tile) + 노드트리 (전체 + per-class 단련) + 프레스티지: % multipliers.
	var class_mult: float = float(_tree_member_atk_mult.get(party[index].id, 1.0))
	return int(round(float(base) * whetstone_attack_multiplier() * _draft_attack_mult * class_mult * prestige_attack_multiplier()))


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
	return (base_speed + flat_bonus) * (1.0 + mult_bonus) * _tree_move_speed_mult \
		* _active_move_speed_drag_multiplier() * _active_move_speed_boost_multiplier()


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
	# 방어구(방어력→HP 전환): 이제 멤버 개인의 armor 레벨만큼 맷집이 붙는다(파티 공통 아님).
	var base: int = party[index].max_hp + _level_bonus(index, "hp") + _equipment_bonus(index, "max_hp_bonus") + _stacked_int_effect_for_character(character_id, "hp_flat") + skill_effect_int_sum("hp_flat") + member_armor_hp_bonus(index)
	# 노드트리 "강골"(전체) + per-class 단련 (기사): % multipliers.
	var class_hp_mult: float = float(_tree_member_hp_mult.get(character_id, 1.0))
	return int(round(float(base) * _draft_hp_mult * class_hp_mult))


func _equipment_bonus(index: int, property_name: StringName) -> int:
	if index < 0 or index >= party_equipment.size():
		return 0
	var total: int = 0
	for entry in party_equipment[index]:
		var item: ItemData = item_entry_data(entry)
		if item:
			# 단계(level) × 등급(rarity) — the two dials of the gear half.
			total += int(round(float(int(item.get(property_name)) * item_entry_level(entry)) * entry_rarity_mult(entry)))
	return total


## Roll a crit. Returns { is_crit: bool, mult: float }.
## Multiple crit modifiers stack their chances (capped at 1.0); the largest
## multiplier wins.
func roll_crit() -> Dictionary:
	var total_chance: float = _tree_crit_bonus  # 노드트리 "도적 단련"
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
	var ratio: float = _draft_window_collision_ratio  # 드래프트 "전투창 당구"
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
	member_armor_levels.clear()        # per-member armor resets with the run
	village_level = 1                  # 마을 re-placeable → tier ceiling back to 1단계
	inventory.clear()
	gold = prestige_starting_gold()    # 프레스티지 종잣돈 perk applies here
	spawner_level = 1                  # 방생 장치 re-levels with the run
	tile_levels.clear()                # 패시브 타일도 새 세계에서 다시 깐다
	purchased_skill_nodes.clear()
	_ensure_default_skill_nodes()
	total_gold_earned = 0
	_tier_available_announced.clear()  # re-announce tiers next run
	placed_structures.clear()          # village etc. re-placeable next run
	acquired_objets.clear()            # objets drop fresh again next run
	party_group_limit = 1              # 따로 다니기 re-learns at the campfire
	_member_groups.clear()             # everyone back on the hero's chain
	enemies_killed = 0
	biggest_hit = 0
	unlocked_tier_ids = [&"slime"]   # only slime from the start; rest re-lock
	active_tier_ids = []             # toggle/auto-spawn dormant (click-place default)
	_max_placed_tier_index = 0       # mixed-spawn ceiling resets to slime-only
	wave_number = 0                  # waves restart with the world
	wave_active = false
	wave_time_left = 0.0
	is_night = false
	night_time_left = 0.0
	wave_gold_earned = 0
	wave_item_tickets = 0
	town_index = 0                   # 노드트리: back to 태초마을 (프레스티지 룰)
	tree_levels.clear()
	smite_unlocked = false           # 강타도 다시 노드로 사야 함
	auto_move_unlocked = true        # 자동 이동은 기본 ON 유지 (프레스티지 후에도)
	map_hero_hex = Vector2i.ZERO     # 지도 위 용사도 태초마을로
	_tree_window_bonus = 0
	_tree_battle_speed_mult = 1.0
	_tree_move_speed_mult = 1.0
	_tree_window_size_bonus = 0
	_tree_member_atk_mult.clear()
	_tree_member_hp_mult.clear()
	_tree_crit_bonus = 0.0
	_tree_sell_mult = 1.0
	_tree_ticket_bonus = 0.0
	_tree_wave_time_bonus = 0.0
	_tree_kill_time_chance = 0.0
	_tree_auto_collect_chance = 0.0
	_tree_smite_mult = 1.0
	_tree_smite_cd_mult = 1.0
	_tree_pickup_mult = 1.0
	_tree_interest = 0.0
	_draft_attack_mult = 1.0
	_draft_hp_mult = 1.0
	_draft_gold_mult = 1.0
	_draft_spawn_rate_mult = 1.0
	_draft_crowd_bonus = 0
	_draft_combo_unlocked = false
	_draft_window_collision_ratio = 0.0
	_drafted_once_ids.clear()
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
	_group_battle_pause_counts.clear()
	field_loop_count = 0
	current_field_region_id = FIELD_REGION_GRASS
	story_companion_joined = false
	story_gold_goal_announced = false
	story_movement_battle_line_shown = false
	story_mage_joined = false
	run_started_at_ms = Time.get_ticks_msec()
	# Make sure UI listeners flush stale numbers (HUD gold, etc.).
	EventBus.gold_changed.emit(gold)
