extends Node

## ═══════════════════════════════════════════════════════════════════════
## CENTRAL BALANCE / TUNING — incremental combat system (v1)
##
## CORE PRINCIPLES (keep these true forever):
##   • 모든 업그레이드는 화면에 보이는 변화를 동반한다 — 숫자만 바뀌는 건 금지.
##   • 자동화(자동 개봉 등)는 늦게·약하게 등장하고, 키울 수 있게 한다.
##   • 모든 튜닝 상수는 이 파일 한 곳에 모은다. 즉시 수정 가능.
##
## The on-screen combat stays turn-based and is the *staging*; the formulas
## below are the *summary* of that combat. Tune enemy HP / party damage so the
## emergent gold-per-second matches:
##
##     창당 초당골드 = 티어골드 ÷ (티어처치시간 ÷ SPEED공격배수)
##     총 초당골드   = 창당 초당골드 × 활성 창 수(SCALE)
##
## Axes — SPEED (kill faster), LUCK (jackpot 빈도↑, NOT a gold multiplier),
## SCALE (more windows). Gold is no longer multiplied by an upgrade.
## ═══════════════════════════════════════════════════════════════════════

# ─── 1. Tuning constants (★ edit freely) ───────────────────────────────
const SLIME_BASE_GOLD: int = 1
const SLIME_BASE_TIME: float = 2.0       ## seconds to kill one base slime at SPEED Lv1
const UPGRADE_BASE_COST: int = 10
const COST_MULT: float = 1.6             ## SPEED, GREED cost growth — kept ABOVE effect (1.4) so gold can't pile up
const EFFECT_MULT: float = 1.4           ## SPEED, GREED shared effect growth
## SCALE = the simultaneous battle-window count. Now monsters auto-spawn (toggle),
## so the WINDOW COUNT is the main incremental growth pillar: start at 1, buy +1 at
## a time. Cost ramps geometrically (no cap) — the first few are cheap (fast growth
## dopamine), then it naturally limits itself as it gets expensive.
##   cost(n) = SCALE_BASE_COST × SCALE_COST_MULT^n   (n = purchases already made)
##   → 10, 16, 26, 41, 66, 105, 168, 269 … (after _round_cost tidy-up)
const SCALE_BASE_COST: int = 10          ## first upgrade (1→2 windows) is cheap
const SCALE_COST_MULT: float = 1.6       ## ramp — first couple easy, then steepens

## Enemy-HP calibration. HP(tier) = avg_party_hit × base_kill_time ×
## PARTY_HITS_PER_SECOND, so at SPEED Lv1 / full HP a tier dies in ~its base
## kill time. (turn_interval is ~0.5s → ~2 party hits/sec.)
const PARTY_HITS_PER_SECOND: float = 2.0

## Downed / auto-recovery cycle (death = time loss, never permanent).
## In combat HP only DROPS — no passive regen. At 0 HP a member is DOWNED:
## removed from the fight (party DPS ↓ → slower kills), HP refills fast in place
## ("쫘라락"), and at full HP they auto-stand and rejoin. No revive button.
## Expressed as a DURATION so a future "성소" building can shorten it per member.
const DOWNED_RECOVERY_SECONDS: float = 2.5  ## time to refill 0 → full while downed

# ─── System 1: per-enemy level (auto-growth from kills) ────────────────
## Each enemy TYPE (tier) levels up purely from being killed — no gold cost.
## Kills needed to go level L → L+1 = LEVEL_UP_BASE_KILLS × MULT^(L-1).
## (10 → 15 → 23 → 34 …)
const LEVEL_UP_BASE_KILLS: int = 10
const LEVEL_UP_KILLS_MULT: float = 1.5
## Effect 1 — per-window spawn count grows 1→2→3→4→5 with level, HARD-CAPPED
## at 5 (screen/perf guard; later merge/copy mechanics push beyond this).
const ENEMY_SPAWN_PER_WINDOW_MAX: int = 5
## Effect 2 — kill-gold multiplier per level, UNCAPPED (the infinite-growth
## lever). Gold ×KILL_GOLD_PER_LEVEL_MULT^(level-1).
const KILL_GOLD_PER_LEVEL_MULT: float = 1.1

# ─── Kill-gold variance (each kill = a mini "상자 개봉") ─────────────────
## Per-kill gold = tier average × a RANDOM multiplier. Mean is ≈1.0 so TOTAL
## income is unchanged — most kills wobble inside [MIN,MAX] (avg <1), rare
## JACKPOTs pull the average back up. The amount is floored at 1 gold so a kill
## is never a total 꽝 (the "꽝" feeling is just a small roll). Tuned mean:
##   0.03×5 + 0.97×(0.4+1.35)/2 ≈ 1.00
const KILL_GOLD_MIN_MULT: float = 0.4
const KILL_GOLD_MAX_MULT: float = 1.35
const KILL_GOLD_JACKPOT_CHANCE: float = 0.03   ## ~1 in 33 kills
const KILL_GOLD_JACKPOT_MULT: float = 5.0
## Rolls below this multiplier read as "적게 나옴" (작고 시무룩한 피드백).
const KILL_GOLD_LOW_MULT_THRESHOLD: float = 0.8

# ─── 운(Luck): raises the kill-gold JACKPOT CHANCE (frequency, not size) ──
## Luck NEVER multiplies gold (that's what exploded). It only makes the 팡팡팡
## jackpot fire more OFTEN — the jackpot MULTIPLIER stays fixed (KILL_GOLD_
## JACKPOT_MULT). Chance grows ADDITIVELY (+per-level) while the upgrade cost
## grows exponentially, so income rises gently — no multiplicative blow-up.
## Lv1 = the base rate, each level adds a flat % up to a hard cap.
const LUCK_JACKPOT_CHANCE_PER_LEVEL: float = 0.02   ## +2%p per level
const LUCK_JACKPOT_CHANCE_MAX: float = 0.45         ## cap so it never trivializes

## Chest open-speed upgrade (lives under the GREED axis). Each level shortens the
## hover-to-open gauge time: BASE × MULT^level, floored. (1.0 → 0.8 → 0.64 …)
const CHEST_OPEN_BASE_DURATION: float = 1.0
const CHEST_OPEN_DURATION_MULT: float = 0.8
const CHEST_OPEN_DURATION_MIN: float = 0.15
const CHEST_OPEN_SPEED_BASE_COST: int = 25
const CHEST_OPEN_SPEED_COST_MULT: float = 1.6

## 자동 줍기: one-time unlock — the hero walks to / sweeps up dropped loot instead
## of the player hover-collecting by hand. The manual→auto convenience staircase.
const AUTO_PICKUP_COST: int = 200

## 자동 전투: one-time unlock — battles run themselves (the turn timer drives every
## party member). Before it, the player drives each turn by hand (Fight → 대상 선택).
const AUTO_BATTLE_COST: int = 150

## 자동 이동: one-time unlock — the hero auto-walks to the nearest enemy/drop. Before
## it, the player drives the hero with WASD / arrow keys.
const AUTO_MOVE_COST: int = 120

# ─── 4. Enemy tiers ─────────────────────────────────────────────────────
## Tiers unlock by CUMULATIVE EARNED GOLD (`unlock_at` = lifetime total_gold_earned,
## unaffected by spending). Below the threshold a tier is HIDDEN from the dock.
## Once reached it becomes claimable; the player clicks to unlock it (free — the
## milestone IS the cost), then TOGGLES it ON/OFF. Several can be active at once;
## the field spawns a random mix of whatever's toggled on. Thresholds climb hard
## (tune later). `enemy_res` supplies the sprite; mage/dragon reuse placeholders.
## `unlock_at` climbs geometrically with an ESCALATING ratio (×10→×12→×10) so the
## late tiers (mage/dragon) stay far off. `base_kill_time` = tier toughness (HP);
## `atk_mult` scales the enemy's base attack per tier so orc+ actually threaten a
## party-wipe. Both ramp hard from orc onward — that's the "강화해야 넘는 벽".
## ECONOMY — keep the loop solvent: every tier's KILL reward MUST beat its PLACE
## cost so placing enemies is net-profit (else production stalls). `unlock_at` =
## the ONE-TIME milestone to unlock the tier (NOT per-spawn); `place_cost` = the
## per-spawn cost (≈ ⅓ of kill_gold so even a low luck-roll stays profitable);
## `kill_gold` = base reward (× luck roll, mean ~1) PLUS a chance of gear on top.
## Stronger tier → bigger place_cost, bigger kill_gold, bigger NET. Tune freely.
##   tier   place  kill   net(avg)
##   slime    1     2      +1     (박리다매: 싸고 작고 안전)
##   bat      3     8      +5
##   orc     10    30     +20
##   mage    90   300    +210
##   dragon 700  2500   +1800     (고위험 고수익)
const TIERS: Array[Dictionary] = [
	{"id": &"slime",  "name": "슬라임", "short": "슬", "unlock_at": 0,      "place_cost": 1,   "kill_gold": 2,    "base_kill_time": 1.5,  "atk_mult": 1.0, "enemy_res": "res://data/enemies/slime.tres"},
	{"id": &"bat",    "name": "박쥐",   "short": "박", "unlock_at": 60,     "place_cost": 3,   "kill_gold": 8,    "base_kill_time": 4.5,  "atk_mult": 1.2, "enemy_res": "res://data/enemies/bat.tres"},
	{"id": &"orc",    "name": "오크",   "short": "오", "unlock_at": 600,    "place_cost": 10,  "kill_gold": 30,   "base_kill_time": 10.0, "atk_mult": 1.8, "enemy_res": "res://data/enemies/orc.tres"},
	{"id": &"mage",   "name": "마도사", "short": "마", "unlock_at": 7000,   "place_cost": 90,  "kill_gold": 300,  "base_kill_time": 18.0, "atk_mult": 2.8, "enemy_res": "res://data/enemies/blade_bug.tres"},
	{"id": &"dragon", "name": "드래곤", "short": "용", "unlock_at": 70000,  "place_cost": 700, "kill_gold": 2500, "base_kill_time": 32.0, "atk_mult": 4.5, "enemy_res": "res://data/enemies/slime_chaser.tres"},
]

# ─── 5. Weapon shop = SPEED axis skin (text-based, no sprites) ──────────
## Buying the next weapon IS the SPEED upgrade. The equipped weapon's attack
## multiplier = speed_mult(speed_level). Index by speed_level (1-based); past
## the list we synthesize "명검 +N".
const WEAPON_NAMES: Array[String] = [
	"맨주먹", "낡은 단검", "청동검", "강철검", "기사검",
	"은빛 장검", "용살검", "오리하르콘 검", "여명의 성검", "심판의 대검",
]
## Hero auto-buys the unlocked weapon for this fraction of its unlock cost.
const WEAPON_AUTOBUY_COST_RATIO: float = 1.0 / 50.0

# ─── Armor shop = survival skin (MAX HP, symmetric to the weapon shop) ─
## Buying the next armor IS the survival upgrade. Equipped armor adds flat MAX HP
## to the BUYING MEMBER (each member outfits their own armor in the 마을 상점). 방어력은
## 폐지됨 — 맷집(HP)이 유일한 생존 축. Index by armor level (1-based); level 1 =
## "맨몸" (no bonus HP). Text-based, no sprites.
const ARMOR_NAMES: Array[String] = [
	"맨몸", "천 갑옷", "가죽 갑옷", "사슬 갑옷", "판금 갑옷",
	"기사 갑옷", "미스릴 갑옷", "용비늘 갑옷", "수호의 성갑", "불멸의 판금",
]
const ARMOR_HP_PER_LEVEL: int = 8   ## flat MAX HP added per armor level
const ARMOR_BASE_COST: int = 15
const ARMOR_COST_MULT: float = 1.55

# ─── Party level-up (accumulating survival growth, auto from kills) ────
## Per-member XP/level (shared by ALL party members, not hero-only). Levels
## grant MAX HP only — attack stays with SPEED/weapon, survival(HP) with armor.
const PARTY_LEVEL_BASE_XP: int = 12        ## XP to reach Lv2
const PARTY_LEVEL_XP_MULT: float = 1.5     ## ×each level (exponential)
const HP_PER_LEVEL: int = 6                ## max HP gained per level
const AGILITY_PER_LEVEL: int = 1           ## agility gained per level (ambush/turn order)

# ─── Party / companions ────────────────────────────────────────────────
## Active party cap. hero + 4 owners (기사/도둑/마법사/사제) = 5. '분대' 확장 여지.
const MAX_PARTY_SIZE: int = 5
## Upgrade purchases of a category needed to recruit its count-owner companion.
const COMPANION_RECRUIT_UPGRADE_COUNT: int = 5

## Companions are pure DATA so a Suikoden-style roster drops in later. They join
## as a RESULT of their building (no gold recruit): count-owners (기사/도둑) join
## after N purchases of the building's trigger upgrade; build-owners (마법사/사제)
## join the instant their building is constructed. `building_link` = the owner's
## building. `appear_text` is shown when the companion appears (등장).
const COMPANIONS: Array[Dictionary] = [
	{
		"id": &"knight", "name": "기사", "role": &"knight", "short": "기",
		"char_res": "res://data/characters/knight.tres",
		"weapon_type": &"sword", "trait": &"single",
		"appear_text": "방패를 든 기사가 합류를 청한다!",
		"combo_group": &"", "building_link": &"armory",
	},
	{
		"id": &"thief", "name": "도적", "role": &"thief", "short": "도",
		"char_res": "res://data/characters/thief.tres",
		"weapon_type": &"dagger", "trait": &"gold",
		"appear_text": "금화 냄새를 맡고 도적이 나타났다!",
		"combo_group": &"", "building_link": &"thieves_guild",
	},
	{
		"id": &"mage", "name": "마법사", "role": &"mage", "short": "마",
		"char_res": "res://data/characters/mage.tres",
		"weapon_type": &"staff", "trait": &"aoe",
		"appear_text": "모닥불 곁으로 마법사가 다가온다!",
		"combo_group": &"", "building_link": &"campfire",
	},
	{
		"id": &"priest", "name": "사제", "role": &"priest", "short": "사",
		"char_res": "res://data/characters/priest.tres",
		"weapon_type": &"blunt", "trait": &"support",
		"appear_text": "성소에 사제가 머물기 시작한다!",
		"combo_group": &"", "building_link": &"sanctuary",
	},
]

# ─── Field tiles (placed physically on the map; left panel "타일 탭") ────
## Tiles are the LEFT panel's domain: things put down on the field + their
## upgrades (vs the right panel's abstract stat buildings). Pricey by design.
## Campfire = a proximity HP-regen outpost; placing it the first time recruits
## the mage. Data-driven so more tiles/outposts drop in later.
## PLANNABLE purchases (no random drops): each tile shows as a silhouette in the
## dock with its `unlock_at` lifetime-gold milestone, opens at that milestone,
## and costs `place_cost` to put down. Ordered by unlock — the visible roadmap.
const TILES: Array[Dictionary] = [
	{
		"id": &"village", "name": "마을", "short": "촌", "color": Color(0.85, 0.78, 0.55, 1.0),
		"sprite": "res://assets/sprites/objects/village.png",
		"place_cost": 50, "unlock_at": 60,
		"desc": "첫 마을. 클릭해 여관(휴식)·상점(장비 구매)을 연다.",
	},
	{
		"id": &"campfire", "name": "모닥불", "short": "불", "color": Color(1.0, 0.6, 0.3, 1.0),
		"sprite": "res://assets/sprites/objects/bonfire.png",
		"place_cost": 300, "unlock_at": 150, "owner": &"mage",
		"desc": "세계의 모닥불. 모든 아군의 HP가 어디서든 차오른다.",
	},
	{
		"id": &"whetstone", "name": "숫돌", "short": "숫", "color": Color(0.77, 0.35, 0.27, 1.0),
		"sprite": "res://assets/sprites/objects/whetstone.png",
		"place_cost": 150, "unlock_at": 350,
		"desc": "세계에 깔린 숫돌. 모든 아군의 무기가 은근히 날카로워진다.",
	},
	{
		"id": &"spawner", "name": "방생 장치", "short": "방", "color": Color(0.54, 0.44, 0.82, 1.0),
		"sprite": "res://assets/sprites/objects/spawner.png",
		"place_cost": 250, "unlock_at": 600,
		"desc": "주변에 해금된 적을 스스로 풀어놓는 장치. 클릭은 이제 설계의 영역.",
	},
	{
		"id": &"gold_idol", "name": "금빛 비석", "short": "金", "color": Color(0.9, 0.71, 0.24, 1.0),
		"sprite": "res://assets/sprites/objects/gold_idol.png",
		"place_cost": 220, "unlock_at": 900,
		"desc": "세계에 깔린 비석. 쓰러진 적이 더 많은 골드를 흘린다.",
	},
]
## ─── 패시브 타일 강화 (Loop-Hero style world auras) ─────────────────────
## A placed passive tile applies PARTY-WIDE, level-scaled. `value` = % per level;
## `effect_fmt` renders the 속성창 readout. Costs scale per level.
const TILE_UPGRADES: Dictionary = {
	&"whetstone": {
		"base_cost": 120, "cost_mult": 1.6, "max_level": 25,
		"value": 6, "effect_fmt": "모든 아군 공격 +%d%%",
	},
	&"gold_idol": {
		"base_cost": 150, "cost_mult": 1.65, "max_level": 25,
		"value": 10, "effect_fmt": "처치 골드 +%d%%",
	},
}
## ─── 방생 장치 (auto-spawner — the automation rung) ────────────────────
## Unlock milestone lives in its TILES entry ("unlock_at"). Spawns a random
## UNLOCKED tier near itself for free every interval; upgrades shorten the
## interval (multiplicative, floored).
const SPAWNER_BASE_INTERVAL: float = 6.0
const SPAWNER_INTERVAL_MULT_PER_LEVEL: float = 0.85
const SPAWNER_MIN_INTERVAL: float = 1.2
const SPAWNER_UPGRADE_BASE_COST: int = 200
const SPAWNER_UPGRADE_COST_MULT: float = 1.7

## ─── 웨이브 (the dopamine cadence: fight N seconds → pick 1 of 3 → repeat) ─
const WAVE_BASE_DURATION: float = 15.0      ## wave 1 length (낮 길이)
const WAVE_DURATION_PER_WAVE: float = 1.5   ## +seconds per wave
const WAVE_DURATION_MAX: float = 35.0
const WAVE_SPAWN_INTERVAL: float = 1.7      ## free auto-spawn cadence during a wave
const WAVE_SPAWN_INTERVAL_MIN: float = 0.55
const WAVE_OPENING_BURST: int = 3           ## enemies dropped the moment a wave starts
const WAVE_DRAFT_CHOICES: int = 3

## ─── 밤 (the JRPG dread half of the cycle) ──────────────────────────────
## Day timer runs out → NIGHT: day enemies vanish, the field darkens, and far
## stronger hunters (박쥐) pour in and CHASE. Survive (or die) → 마을 (정산).
const NIGHT_DURATION: float = 12.0          ## seconds of night per cycle
const NIGHT_ENEMY_TIER: StringName = &"bat" ## what hunts at night (one tier up)
const NIGHT_SPAWN_INTERVAL: float = 1.4     ## night hunters spawn this often
const NIGHT_CHASE_SPEED_MULT: float = 1.25  ## hunters run this much faster
const NIGHT_TINT: Color = Color(0.45, 0.5, 0.72, 1.0)  ## the field's night shade
## 밤 버프: night enemies are far tankier AND hit much harder — so early on the
## party FIGHTS AND DIES (퇴각/공포), not easy farming even with 강타.
const NIGHT_ENEMY_HP_MULT: float = 3.0
const NIGHT_ENEMY_ATK_MULT: float = 2.5

## ─── 장비 어픽스 (등급 보너스 스탯) ─────────────────────────────────────
## 일반 초과 장비의 덤: 무기 = 치명 확률, 그 외 = 회피 확률. 등급 배수에 비례.
const GEAR_AFFIX_CRIT_PER_MULT: float = 0.025   ## 전설(×3.0) 무기 ≈ 치명 +7.5%
const GEAR_AFFIX_EVADE_PER_MULT: float = 0.02   ## 전설 방어구 ≈ 회피 +6%

## ─── 필드 랜덤 이벤트 (하루 한 번, 예고 없이 — 도파민의 불시 배달) ────────
const FIELD_EVENT_CHANCE: float = 0.7       ## per-wave chance the day's event fires
const GOLD_RUSH_DURATION: float = 8.0       ## 골드 러시 지속 시간
const GOLD_RUSH_MULT: float = 2.0           ## 골드 러시 동안 처치 골드 ×
const METEOR_COIN_COUNT: int = 3            ## 보물 유성이 흩뿌리는 코인 수
const GOLD_BAR_MULT: int = 5                ## "금괴" 노드: 금괴 = 코인 ×5

## Draft card pool — 4 axes: 적(danger dial) / 아군(power) / 보상(greed) /
## 필살기(hooks). Repeatable unless "once". Effects live in
## GameState.apply_draft_card; this is data only.
const WAVE_DRAFT_CARDS: Array[Dictionary] = [
	{"id": &"enemy_new_tier", "axis": &"enemy", "name": "새로운 마물", "desc": "다음 단계 마물이 세계에 나타난다"},
	{"id": &"enemy_horde", "axis": &"enemy", "name": "마물 쇄도", "desc": "웨이브 스폰 속도 +20%"},
	{"id": &"enemy_crowd", "axis": &"enemy", "name": "북적이는 들판", "desc": "필드 최대 마물 +2"},
	{"id": &"ally_sharpen", "axis": &"ally", "name": "무기 단련", "desc": "모든 아군 공격 +5%"},
	{"id": &"ally_vitality", "axis": &"ally", "name": "강골", "desc": "모든 아군 최대 HP +8%"},
	{"id": &"ally_mend", "axis": &"ally", "name": "재정비", "desc": "전원 즉시 완전 회복"},
	{"id": &"loot_gold", "axis": &"loot", "name": "황금 감각", "desc": "처치 골드 +15%"},
	{"id": &"loot_cache", "axis": &"loot", "name": "전리품 상자", "desc": "즉시 골드 보따리"},
	{"id": &"hook_combo", "axis": &"hook", "name": "합체 공격", "desc": "5킬마다 거대 해골이 전장을 쓸어버린다", "once": true},
	{"id": &"hook_billiards", "axis": &"hook", "name": "전투창 당구", "desc": "전투창끼리 부딪히면 적이 다친다", "once": true},
]
const WAVE_CACHE_GOLD_BASE: int = 60        ## 전리품 상자 = base + per_wave × wave
const WAVE_CACHE_GOLD_PER_WAVE: int = 15

## ─── 정산 (settlement: harvest → Brotato picks) ─────────────────────────
const SETTLE_TICKET_CHANCE: float = 0.12    ## per-kill chance to FIND gear (a pick round)
const SETTLE_GEAR_CHOICES: int = 3          ## gear options per ticket (+1 gold option)
const SETTLE_GOLD_OPTION_BASE: int = 40     ## the "그냥 골드" option = base + per_wave × wave
const SETTLE_GOLD_OPTION_PER_WAVE: int = 10
const GEAR_GOLD_VALUE_PER_LEVEL: int = 14   ## replaced gear melts into this much per level

## ─── 장비 등급 (단계 × 등급 — the gear half of the power split) ───────────
## Every dropped/bought piece rolls a rarity: stat multiplier + sell value +
## name color. 단계(level) comes from the town spine; 등급(rarity) from luck.
const GEAR_RARITIES: Array[Dictionary] = [
	{"id": &"common", "name": "일반", "mult": 1.0, "weight": 58.0, "color": Color(0.45, 0.42, 0.38, 1.0)},
	{"id": &"fine", "name": "고급", "mult": 1.3, "weight": 26.0, "color": Color(0.3, 0.62, 0.32, 1.0)},
	{"id": &"rare", "name": "희귀", "mult": 1.7, "weight": 11.0, "color": Color(0.25, 0.5, 0.85, 1.0)},
	{"id": &"epic", "name": "영웅", "mult": 2.2, "weight": 4.0, "color": Color(0.6, 0.4, 0.85, 1.0)},
	{"id": &"legend", "name": "전설", "mult": 3.0, "weight": 1.0, "color": Color(0.9, 0.62, 0.15, 1.0)},
]
const GEAR_SHOP_COST_PER_LEVEL: int = 45    ## 장비 상자 (random piece) = town gear level × this


static func roll_gear_rarity() -> Dictionary:
	var total: float = 0.0
	for r: Dictionary in GEAR_RARITIES:
		total += float(r.get("weight", 0.0))
	var pick: float = randf() * total
	for r: Dictionary in GEAR_RARITIES:
		pick -= float(r.get("weight", 0.0))
		if pick <= 0.0:
			return r
	return GEAR_RARITIES[0]


static func gear_rarity_by_id(id: StringName) -> Dictionary:
	for r: Dictionary in GEAR_RARITIES:
		if StringName(r.get("id", &"")) == id:
			return r
	return GEAR_RARITIES[0]

## ─── 마을 노드트리 (JRPG spine: 마을이 자랄수록 세계가 깊어진다) ─────────
## Unlock order is strict (a road, not a web). gear_level gates the LEVEL of
## items the settlement picks can roll — better towns, better loot.
## `hex` = axial coordinate on the world-map canvas (pointy-top); towns sit two
## columns apart so a ROAD hex auto-fills between them and each town keeps six
## free neighbors for its branch nodes. `biome` paints the tile's ground.
const TOWN_SPINE: Array[Dictionary] = [
	{"id": &"town1", "name": "태초마을", "cost": 0, "gear_level": 1, "hex": Vector2i(0, 0), "biome": Color(0.42, 0.69, 0.36, 1.0), "icon": "res://assets/sprites/objects/village.png"},
	{"id": &"town2", "name": "조금 큰 마을", "cost": 150, "gear_level": 2, "hex": Vector2i(2, 0), "biome": Color(0.36, 0.62, 0.34, 1.0), "icon": "res://assets/sprites/objects/town.png"},
	{"id": &"town3", "name": "시가지", "cost": 420, "gear_level": 3, "hex": Vector2i(4, 0), "biome": Color(0.63, 0.61, 0.58, 1.0), "icon": "res://assets/sprites/objects/tower.png"},
	{"id": &"town4", "name": "엘프 마을", "cost": 950, "gear_level": 4, "hex": Vector2i(6, 0), "biome": Color(0.2, 0.46, 0.28, 1.0), "icon": "res://assets/sprites/objects/forest.png"},
	{"id": &"town5", "name": "드워프 마을", "cost": 2000, "gear_level": 5, "hex": Vector2i(8, 0), "biome": Color(0.56, 0.42, 0.3, 1.0), "icon": "res://assets/sprites/objects/cave.png"},
	{"id": &"town6", "name": "왕성", "cost": 3800, "gear_level": 6, "hex": Vector2i(10, 0), "biome": Color(0.86, 0.75, 0.46, 1.0), "icon": "res://assets/sprites/objects/castle.png"},
	{"id": &"town7", "name": "마왕 마을", "cost": 7000, "gear_level": 7, "hex": Vector2i(12, 0), "biome": Color(0.4, 0.28, 0.48, 1.0), "icon": "res://assets/sprites/objects/shrine.png"},
]

## Branch nodes sprout from an unlocked town. FOUR axes — 아군(per-class 단련) /
## 적(danger dial) / 보상(greed) / 전투창(the hooks) — plus gear (정산 픽 + 장비
## 탭) carrying the other half of the power curve.
## effect ids are applied in GameState._apply_tree_effect.
const TREE_NODES: Array[Dictionary] = [
	# ════ 태초마을 (0,0) — 3대 기둥의 뿌리. 모든 체인은 인접 순서대로 열린다. ════
	# ⚔️ 공격 체인 (북쪽)
	{"id": &"n_atk1", "town": &"town1", "axis": &"ally", "name": "무기 단련", "desc": "아군 전체 공격 +5%/Lv", "cost": 15, "cost_mult": 1.5, "max_level": 8, "effect": "atk", "mag": 0.05, "hex": Vector2i(0, -1), "icon": "res://assets/sprites/icons/hero_sword.png"},
	{"id": &"n_hero", "town": &"town1", "axis": &"ally", "name": "용사 단련", "desc": "용사 공격 +10%/Lv", "cost": 40, "cost_mult": 1.5, "max_level": 10, "effect": "atk_hero", "mag": 0.10, "hex": Vector2i(0, -2), "icon": "res://assets/sprites/icons/hero_sword.png"},
	{"id": &"n_crit", "town": &"town1", "axis": &"ally", "name": "급소 노리기", "desc": "전체 크리티컬 확률 +2%p/Lv", "cost": 90, "cost_mult": 1.6, "max_level": 5, "effect": "crit", "mag": 0.02, "hex": Vector2i(0, -3), "icon": "res://assets/sprites/icons/thief_sword.png"},
	# ⚡ 강타 체인 (북동)
	{"id": &"n_smite", "town": &"town1", "axis": &"hook", "name": "강타", "desc": "전투창을 탭하면 안의 모든 적을 광역 타격", "cost": 10, "cost_mult": 1.0, "max_level": 1, "effect": "smite", "hex": Vector2i(1, -1), "icon": "res://assets/sprites/icons/hero_sword.png"},
	{"id": &"n_smite_pow", "town": &"town1", "axis": &"hook", "name": "강타 강화", "desc": "강타 데미지 +15%/Lv", "cost": 50, "cost_mult": 1.55, "max_level": 5, "effect": "smite_power", "mag": 0.15, "hex": Vector2i(1, -2), "icon": "res://assets/sprites/icons/hero_sword.png"},
	{"id": &"n_smite_cd", "town": &"town1", "axis": &"hook", "name": "빠른 강타", "desc": "강타 충전 속도 +12%/Lv", "cost": 120, "cost_mult": 1.6, "max_level": 4, "effect": "smite_cd", "mag": 0.12, "hex": Vector2i(1, -3), "icon": "res://assets/sprites/objects/bonfire.png"},
	# 🪟 전투창 체인 (북서)
	{"id": &"n_windows", "town": &"town1", "axis": &"hook", "name": "멀티 전투창", "desc": "동시에 열 수 있는 전투창 +1/Lv", "cost": 60, "cost_mult": 2.0, "max_level": 4, "effect": "windows", "mag": 1.0, "hex": Vector2i(-1, -1), "icon": "res://assets/sprites/objects/tower.png"},
	{"id": &"n_winsize", "town": &"town1", "axis": &"enemy", "name": "전투창 적 +1", "desc": "한 전투창에 나오는 적 수 +1/Lv", "cost": 45, "cost_mult": 1.7, "max_level": 5, "effect": "window_size", "mag": 1.0, "hex": Vector2i(-1, -2), "icon": "res://assets/sprites/objects/spawner.png"},
	{"id": &"n_battle_speed", "town": &"town1", "axis": &"hook", "name": "전투 가속", "desc": "전투·강타 속도 +13%/Lv", "cost": 110, "cost_mult": 1.6, "max_level": 6, "effect": "battle_speed", "mag": 0.13, "hex": Vector2i(-1, -3), "icon": "res://assets/sprites/objects/bonfire.png"},
	# 💰 보상 체인 (남쪽)
	{"id": &"n_gold1", "town": &"town1", "axis": &"loot", "name": "황금 감각", "desc": "처치 골드 +10%/Lv", "cost": 15, "cost_mult": 1.55, "max_level": 8, "effect": "gold", "mag": 0.10, "hex": Vector2i(0, 1), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_lucky_coin", "town": &"town1", "axis": &"loot", "name": "행운의 동전", "desc": "처치 골드가 2배로 나올 확률 +10%p/Lv", "cost": 25, "cost_mult": 1.55, "max_level": 5, "effect": "double_gold", "mag": 0.10, "hex": Vector2i(0, 2), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_time", "town": &"town1", "axis": &"loot", "name": "오래 머물기", "desc": "웨이브 시간 +3초/Lv", "cost": 45, "cost_mult": 1.6, "max_level": 8, "effect": "wave_time", "mag": 3.0, "hex": Vector2i(0, 3), "icon": "res://assets/sprites/objects/save_point.png"},
	{"id": &"n_gold_bar", "town": &"town1", "axis": &"loot", "name": "금괴", "desc": "코인이 금괴(5배)로 떨어질 확률 +5%p/Lv", "cost": 80, "cost_mult": 1.65, "max_level": 4, "effect": "gold_bar", "mag": 0.05, "hex": Vector2i(0, 4), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_hourglass", "town": &"town1", "axis": &"loot", "name": "모래시계", "desc": "처치 시 10%/Lv 확률로 웨이브 +1초", "cost": 115, "cost_mult": 1.7, "max_level": 3, "effect": "kill_time", "mag": 0.10, "hex": Vector2i(0, 5), "icon": "res://assets/sprites/objects/save_point.png"},
	# 🧲 획득 체인 (서쪽)
	{"id": &"n_pickup", "town": &"town1", "axis": &"loot", "name": "넓은 손", "desc": "줍기 범위 +25%/Lv", "cost": 20, "cost_mult": 1.55, "max_level": 5, "effect": "pickup_range", "mag": 0.25, "hex": Vector2i(-1, 0), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_autocollect", "town": &"town1", "axis": &"loot", "name": "자동 줍기", "desc": "웨이브 종료 시 남은 전리품 +30%p/Lv 확률 자동 수거", "cost": 45, "cost_mult": 1.7, "max_level": 4, "effect": "auto_collect", "mag": 0.30, "hex": Vector2i(-1, 1), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_ticket", "town": &"town1", "axis": &"loot", "name": "보물 감각", "desc": "전투 승리 시 보물 상자 확률 +5%p/Lv", "cost": 110, "cost_mult": 1.7, "max_level": 5, "effect": "ticket", "mag": 0.05, "hex": Vector2i(-1, 2), "icon": "res://assets/sprites/icons/necklace.png"},
	# ════ 조금 큰 마을 (2,0) — 첫 동료 + 위험 다이얼 + 생존 ════
	{"id": &"n_rec_mage", "town": &"town2", "axis": &"ally", "name": "메이지 영입", "desc": "광역 마법사가 파티에 합류한다", "cost": 120, "cost_mult": 1.0, "max_level": 1, "effect": "recruit_mage", "hex": Vector2i(2, -1), "char_id": &"mage"},
	{"id": &"n_mage", "town": &"town2", "axis": &"ally", "name": "메이지 단련", "desc": "메이지 공격(광역) +10%/Lv", "cost": 60, "cost_mult": 1.5, "max_level": 10, "effect": "atk_mage", "mag": 0.10, "hex": Vector2i(2, -2), "icon": "res://assets/sprites/icons/mage_staff.png"},
	{"id": &"n_hp", "town": &"town2", "axis": &"ally", "name": "강골", "desc": "아군 전체 최대 HP +8%/Lv", "cost": 50, "cost_mult": 1.55, "max_level": 8, "effect": "hp", "mag": 0.08, "hex": Vector2i(2, 1), "icon": "res://assets/sprites/icons/armor.png"},
	{"id": &"n_move", "town": &"town2", "axis": &"ally", "name": "신속", "desc": "이동 속도 +10%/Lv", "cost": 40, "cost_mult": 1.5, "max_level": 6, "effect": "move_speed", "mag": 0.10, "hex": Vector2i(2, 2), "icon": "res://assets/sprites/icons/thief_sword.png"},
	{"id": &"n_tier", "town": &"town2", "axis": &"enemy", "name": "새로운 마물", "desc": "다음 단계 마물이 나타난다 (더 큰 골드)", "cost": 150, "cost_mult": 1.9, "max_level": 4, "effect": "tier", "hex": Vector2i(3, 1), "icon": "res://assets/sprites/objects/spawner.png"},
	{"id": &"n_sell", "town": &"town2", "axis": &"loot", "name": "비싸게 팔기", "desc": "장비 판매가 +20%/Lv", "cost": 130, "cost_mult": 1.6, "max_level": 5, "effect": "sell", "mag": 0.20, "hex": Vector2i(3, 2), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_horde", "town": &"town2", "axis": &"enemy", "name": "마물 쇄도", "desc": "웨이브 스폰 속도 +20%/Lv", "cost": 80, "cost_mult": 1.7, "max_level": 5, "effect": "horde", "mag": 0.20, "hex": Vector2i(3, -1), "icon": "res://assets/sprites/objects/spawner.png"},
	{"id": &"n_crowd", "town": &"town2", "axis": &"enemy", "name": "북적이는 들판", "desc": "필드 최대 마물 +2/Lv", "cost": 100, "cost_mult": 1.6, "max_level": 5, "effect": "crowd", "mag": 2.0, "hex": Vector2i(3, -2), "icon": "res://assets/sprites/objects/spawner.png"},
	# ════ 시가지 (4,0) — 사제 + 전투창 훅들 ════
	{"id": &"n_rec_priest", "town": &"town3", "axis": &"ally", "name": "사제 영입", "desc": "치유 사제가 파티에 합류한다", "cost": 250, "cost_mult": 1.0, "max_level": 1, "effect": "recruit_priest", "hex": Vector2i(4, -1), "char_id": &"priest"},
	{"id": &"n_priest", "town": &"town3", "axis": &"ally", "name": "사제 단련", "desc": "사제 공격·치유 +10%/Lv", "cost": 90, "cost_mult": 1.5, "max_level": 10, "effect": "atk_priest", "mag": 0.10, "hex": Vector2i(4, -2), "icon": "res://assets/sprites/icons/priest_staff.png"},
	{"id": &"n_combo", "town": &"town3", "axis": &"hook", "name": "합체 공격", "desc": "5킬마다 거대 해골이 전장을 쓸어버린다", "cost": 220, "cost_mult": 1.0, "max_level": 1, "effect": "combo", "hex": Vector2i(5, -1), "icon": "res://assets/sprites/icons/mage_staff.png"},
	{"id": &"n_winsize2", "town": &"town3", "axis": &"enemy", "name": "전투창 적 +1 II", "desc": "한 전투창에 나오는 적 수 +1/Lv", "cost": 300, "cost_mult": 1.7, "max_level": 4, "effect": "window_size", "mag": 1.0, "hex": Vector2i(5, -2), "icon": "res://assets/sprites/objects/spawner.png"},
	{"id": &"n_billiards", "town": &"town3", "axis": &"hook", "name": "전투창 당구", "desc": "전투창 충돌 시 적 피해", "cost": 260, "cost_mult": 1.0, "max_level": 1, "effect": "billiards", "hex": Vector2i(4, 1), "icon": "res://assets/sprites/objects/whetstone.png"},
	{"id": &"n_bash", "town": &"town3", "axis": &"hook", "name": "강한 충돌", "desc": "전투창 충돌 피해 +8%p/Lv", "cost": 200, "cost_mult": 1.6, "max_level": 4, "effect": "collision", "mag": 0.08, "hex": Vector2i(4, 2), "icon": "res://assets/sprites/objects/whetstone.png"},
	# ════ 엘프 마을 (6,0) — 기사 + 경제 II ════
	{"id": &"n_rec_knight", "town": &"town4", "axis": &"ally", "name": "기사 영입", "desc": "방패의 기사가 파티에 합류한다", "cost": 450, "cost_mult": 1.0, "max_level": 1, "effect": "recruit_knight", "hex": Vector2i(6, -1), "char_id": &"knight"},
	{"id": &"n_knight", "town": &"town4", "axis": &"ally", "name": "기사 단련", "desc": "기사 최대 HP +15%/Lv", "cost": 150, "cost_mult": 1.5, "max_level": 10, "effect": "hp_knight", "mag": 0.15, "hex": Vector2i(6, -2), "icon": "res://assets/sprites/icons/shield.png"},
	{"id": &"n_gold2", "town": &"town4", "axis": &"loot", "name": "황금 감각 II", "desc": "처치 골드 +15%/Lv", "cost": 350, "cost_mult": 1.55, "max_level": 6, "effect": "gold", "mag": 0.15, "hex": Vector2i(6, 1), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_interest", "town": &"town4", "axis": &"loot", "name": "이자", "desc": "정산 시 보유 골드의 +2%/Lv 추가 지급", "cost": 500, "cost_mult": 1.6, "max_level": 5, "effect": "interest", "mag": 0.02, "hex": Vector2i(6, 2), "icon": "res://assets/sprites/icons/gold.png"},
	{"id": &"n_atk2", "town": &"town4", "axis": &"ally", "name": "무기 단련 II", "desc": "아군 전체 공격 +10%/Lv", "cost": 400, "cost_mult": 1.5, "max_level": 8, "effect": "atk", "mag": 0.10, "hex": Vector2i(7, -1), "icon": "res://assets/sprites/icons/hero_sword.png"},
	# ════ 드워프 마을 (8,0) — 도적 + 시간/강타 II ════
	{"id": &"n_rec_thief", "town": &"town5", "axis": &"ally", "name": "도적 영입", "desc": "재빠른 도적이 파티에 합류한다", "cost": 800, "cost_mult": 1.0, "max_level": 1, "effect": "recruit_thief", "hex": Vector2i(8, -1), "char_id": &"thief"},
	{"id": &"n_thief", "town": &"town5", "axis": &"ally", "name": "도적 단련", "desc": "전체 크리티컬 확률 +2%p/Lv", "cost": 200, "cost_mult": 1.6, "max_level": 10, "effect": "crit", "mag": 0.02, "hex": Vector2i(8, -2), "icon": "res://assets/sprites/icons/thief_sword.png"},
	{"id": &"n_smite2", "town": &"town5", "axis": &"hook", "name": "강타 폭주", "desc": "강타 데미지 +20%/Lv", "cost": 600, "cost_mult": 1.55, "max_level": 5, "effect": "smite_power", "mag": 0.20, "hex": Vector2i(8, 1), "icon": "res://assets/sprites/icons/hero_sword.png"},
	{"id": &"n_time2", "town": &"town5", "axis": &"loot", "name": "오래 머물기 II", "desc": "웨이브 시간 +4초/Lv", "cost": 650, "cost_mult": 1.6, "max_level": 6, "effect": "wave_time", "mag": 4.0, "hex": Vector2i(9, -1), "icon": "res://assets/sprites/objects/save_point.png"},
	# ════ 왕성 (10,0) — 왕가의 곱연산 ════
	{"id": &"n_royal_atk", "town": &"town6", "axis": &"ally", "name": "왕의 권위", "desc": "아군 전체 공격 +25%/Lv", "cost": 1500, "cost_mult": 1.7, "max_level": 3, "effect": "atk", "mag": 0.25, "hex": Vector2i(10, -1), "icon": "res://assets/sprites/objects/castle.png"},
	{"id": &"n_royal_gold", "town": &"town6", "axis": &"loot", "name": "왕실 금고", "desc": "처치 골드 +25%/Lv", "cost": 1500, "cost_mult": 1.7, "max_level": 3, "effect": "gold", "mag": 0.25, "hex": Vector2i(10, 1), "icon": "res://assets/sprites/objects/castle.png"},
	{"id": &"n_windows2", "town": &"town6", "axis": &"hook", "name": "멀티 전투창 II", "desc": "동시에 열 수 있는 전투창 +1/Lv", "cost": 1200, "cost_mult": 1.8, "max_level": 2, "effect": "windows", "mag": 1.0, "hex": Vector2i(11, -1), "icon": "res://assets/sprites/objects/tower.png"},
	# ════ 마왕 마을 (12,0) — 끝의 끝 ════
	{"id": &"n_demon_atk", "town": &"town7", "axis": &"ally", "name": "마왕의 힘", "desc": "아군 전체 공격 +100%", "cost": 4000, "cost_mult": 1.0, "max_level": 1, "effect": "atk", "mag": 1.0, "hex": Vector2i(12, -1), "icon": "res://assets/sprites/objects/shrine.png"},
	{"id": &"n_demon_loot", "town": &"town7", "axis": &"loot", "name": "혼돈의 보고", "desc": "보물 상자 확률 +10%p/Lv", "cost": 3500, "cost_mult": 1.6, "max_level": 3, "effect": "ticket", "mag": 0.10, "hex": Vector2i(12, 1), "icon": "res://assets/sprites/objects/shrine.png"},
]



## Flat-top odd-q offset neighbors (odd columns sit half a row DOWN — matches
## node_tree_window._hex_center). Drives chain unlock: a node is buyable only
## when an ADJACENT hex is already owned.
static func hex_neighbors(c: Vector2i) -> Array:
	if posmod(c.x, 2) == 0:
		return [c + Vector2i(0, -1), c + Vector2i(0, 1), c + Vector2i(1, -1),
			c + Vector2i(1, 0), c + Vector2i(-1, -1), c + Vector2i(-1, 0)]
	return [c + Vector2i(0, -1), c + Vector2i(0, 1), c + Vector2i(1, 0),
		c + Vector2i(1, 1), c + Vector2i(-1, 0), c + Vector2i(-1, 1)]


func town_by_index(index: int) -> Dictionary:
	if index >= 0 and index < TOWN_SPINE.size():
		return TOWN_SPINE[index]
	return {}


func tree_node_by_id(id: StringName) -> Dictionary:
	for node: Dictionary in TREE_NODES:
		if StringName(node.get("id", &"")) == id:
			return node
	return {}


## ─── 프레스티지 (세계 다시 쓰기) ────────────────────────────────────────
## Folding the world converts LIFETIME gold into 별조각 (star shards), spent on
## PERMANENT perks that survive every reset. Shards = floor(sqrt(earned/400)):
## first fold worth taking around ~400G, ~5★ at 10k, ~16★ at 100k.
const PRESTIGE_SHARD_DIVISOR: float = 400.0
## Perk cost = base_cost × (level + 1) shards. `value` is the per-level effect.
const PRESTIGE_PERKS: Array[Dictionary] = [
	{
		"id": &"start_gold", "name": "세계의 종잣돈", "base_cost": 1, "max_level": 12,
		"value": 100, "desc": "다시 쓴 세계가 시작 골드 +100을 품는다",
	},
	{
		"id": &"hero_might", "name": "착취 강화", "base_cost": 2, "max_level": 10,
		"value": 10, "desc": "용사 일행의 공격력 +10%",
	},
	{
		"id": &"swift_spawner", "name": "방생 가속", "base_cost": 2, "max_level": 8,
		"value": 10, "desc": "방생 장치가 10% 빠르게 돈다",
	},
]


## A tier's strength rank = its position in the TIERS list (0 = weakest).
func tier_index(id: StringName) -> int:
	for i in tier_count():
		if StringName(tier_at(i).get("id", &"")) == id:
			return i
	return 0


static func prestige_perk_by_id(id: StringName) -> Dictionary:
	for perk: Dictionary in PRESTIGE_PERKS:
		if StringName(perk.get("id", &"")) == id:
			return perk
	return {}
const CAMPFIRE_REGEN_RADIUS: float = 72.0       ## only party within this regen
const CAMPFIRE_REGEN_BASE_RATE: float = 0.6     ## HP/sec at level 1 (very weak)
const CAMPFIRE_REGEN_PER_LEVEL: float = 0.7     ## +HP/sec per upgrade
const CAMPFIRE_UPGRADE_BASE_COST: int = 120
const CAMPFIRE_UPGRADE_COST_MULT: float = 1.6
## 따로 다니기 (party split) — learned once at the campfire; needs a companion.
## Further 분할 확장 upgrades raise the squad cap toward PARTY_GROUP_MAX.
const PARTY_SPLIT_LEARN_COST: int = 150
const PARTY_SPLIT_EXPAND_BASE_COST: int = 300  ## ×(current cap - 1) per step
const PARTY_GROUP_MAX: int = 4                 ## hero chain + up to 3 squads
## 마을 강화 — each level raises the gear TIER the shop will sell (무기/방어구 1단계씩).
const VILLAGE_UPGRADE_BASE_COST: int = 80
const VILLAGE_UPGRADE_COST_MULT: float = 1.7

# ─── Weapon types (얕게 — identity + shop categories; effect = attack↑ only) ─
## Unlocking a type's weapon auto-equips the matching companion (그 타입 사용자).
## No type-specific effects — character TRAITS carry the role identity.
const WEAPON_TYPES: Array[Dictionary] = [
	{"id": &"sword",  "name": "검",      "short": "검"},
	{"id": &"staff",  "name": "지팡이",  "short": "장"},
	{"id": &"blunt",  "name": "둔기",    "short": "둔"},
	{"id": &"dagger", "name": "단검",    "short": "비"},
]
const WEAPON_NAMES_BY_TYPE: Dictionary = {
	&"sword":  ["맨손", "청동검", "강철검", "기사검", "용살검"],
	&"staff":  ["나무 막대", "견습 지팡이", "수정 지팡이", "현자의 지팡이", "용골 지팡이"],
	&"blunt":  ["나무 몽둥이", "철퇴", "축성 메이스", "성스러운 망치", "심판의 철퇴"],
	&"dagger": ["녹슨 단검", "강철 단검", "비수", "그림자 단검", "월광 단검"],
}

## Innate per-character profile: weapon TYPE (auto-equip routing) + TRAIT (role
## variant — fixed to the character, never changed by gear). Future collectible
## variants (e.g. 버스트 마법사 with trait &"burst") just add rows; the structure
## already supports same-class trait splits. Traits: &"single" (단일/균형),
## &"aoe" (광역딜), &"support" (힐/부활), &"gold" (골드+).
const HERO_WEAPON_TYPE: StringName = &"sword"
const HERO_TRAIT: StringName = &"single"
const TRAIT_NAMES: Dictionary = {
	&"single": "단일딜/균형", &"aoe": "광역딜", &"support": "힐/부활", &"gold": "골드+",
}

# ─── Role scaling (grows with the member's LEVEL — no skills) ───────────
## Mage: AoE width + power. Priest: heal + downed-recovery speed. Thief: gold ×.
const MAGE_BASE_EXTRA_TARGETS: int = 1      ## extra enemies hit at Lv1 (so 2 total)
const MAGE_LEVELS_PER_EXTRA_TARGET: int = 3 ## +1 target every N levels
const MAGE_SPLASH_DMG_BASE: float = 0.6     ## splash damage mult at Lv1
const MAGE_SPLASH_DMG_PER_LEVEL: float = 0.04
const MAGE_SPLASH_DMG_MAX: float = 1.2
const PRIEST_HEAL_BASE: int = 5             ## heal on the priest's turn at Lv1
const PRIEST_HEAL_PER_LEVEL: int = 2
const PRIEST_ATTACK_MULT: float = 0.5       ## priest is a weak attacker
## Downed-recovery time is multiplied by this when a priest is present (faster
## revive = the "human 성소"). Shrinks with priest level, floored.
const PRIEST_RECOVERY_FACTOR_BASE: float = 0.6
const PRIEST_RECOVERY_FACTOR_PER_LEVEL: float = 0.04
const PRIEST_RECOVERY_FACTOR_MIN: float = 0.2
const THIEF_GOLD_MULT_BASE: float = 1.15    ## party-wide gold × at Lv1 (GREED-style)
const THIEF_GOLD_MULT_PER_LEVEL: float = 0.05

# ─── DQ1-style ambush / initiative (per battle window) ─────────────────
## At each fight's start: 선공(party acts first) / 피습(enemies first) / 보통.
## Higher party agility vs enemy agility tilts toward 선공. Order only — no
## bonus damage or instakill; the order itself creates the swing.
const AMBUSH_PREEMPT_BASE: float = 0.25     ## base 선공 chance at equal agility
const AMBUSH_SURPRISE_BASE: float = 0.15    ## base 피습 chance at equal agility
const AMBUSH_AGILITY_WEIGHT: float = 0.015  ## per point of (party - enemy) agility
const AMBUSH_CHANCE_MIN: float = 0.02
const AMBUSH_CHANCE_MAX: float = 0.85

# ─── Field buildings (reusable structure system; 성소 is the first) ────
## Player-bought structures placed on the field. Generic table so 대장간 / 상점
## etc. drop in later with no new plumbing — add a row + handle its effect.
## Sanctuary cost is tuned to be skippable early but tempting after the down/
## recovery slowdown bites a few times.
## Buildings live only in the right-panel village grid (NOT on the field). They
## are the RESULT of upgrades, not a purchase target:
##   • mode &"auto"   — pops into the grid the first time its `trigger` upgrade is
##                      bought. Owner (if any) appears then, and joins after
##                      COMPANION_RECRUIT_UPGRADE_COUNT purchases of `trigger`.
##   • mode &"direct" — the exception: built by clicking the tile (gold) once its
##                      `unlock` condition is met. Owner joins on construction.
## upgrade kinds (the list cards): &"weapons" / &"armor" / &"luck" / &"scale" /
## &"open_speed". Tiles also act as filter tabs for the lower list.
const BUILDINGS: Array[Dictionary] = [
	{
		"id": &"weapon_shop", "name": "무기점", "short": "무", "color": Color(0.95, 0.42, 0.38, 1.0),
		"mode": &"auto", "trigger": &"weapons", "owner": &"", "recruit_at": 0,
		"upgrades": [{"kind": &"weapons"}],
		"desc": "무기를 강화하면 세워진다. 내 손으로 세운 첫 마을.",
	},
	{
		"id": &"armory", "name": "방어구점", "short": "방", "color": Color(0.62, 0.82, 0.86, 1.0),
		"mode": &"auto", "trigger": &"armor", "owner": &"knight", "recruit_at": 5,
		"upgrades": [{"kind": &"armor"}],
		"desc": "방어구를 강화하면 세워진다. 기사가 모인다.",
	},
	{
		"id": &"thieves_guild", "name": "도둑길드", "short": "도", "color": Color(0.92, 0.82, 0.55, 1.0),
		"mode": &"auto", "trigger": &"luck", "owner": &"thief", "recruit_at": 5,
		"upgrades": [{"kind": &"luck"}],
		"desc": "운을 끌어올리면 세워진다. 도둑이 모인다.",
	},
	{
		"id": &"war_council", "name": "작전회의소", "short": "작", "color": Color(0.46, 0.68, 1.0, 1.0),
		"mode": &"auto", "trigger": &"scale", "owner": &"", "recruit_at": 0,
		"upgrades": [{"kind": &"scale"}],
		"desc": "전투창 수를 늘리면 세워진다.",
	},
	{
		"id": &"sanctuary", "name": "성소", "short": "성", "color": Color(0.55, 0.85, 1.0, 1.0),
		"sprite": "res://assets/sprites/objects/shrine.png",
		"mode": &"direct", "build_cost": 150, "unlock": {"type": &"downs", "value": 3},
		"owner": &"priest", "recruit_at": 0,
		"upgrades": [],
		"desc": "직접 세운다. 쓰러진 동료를 즉시 부활 — 사제 합류.",
	},
]


# ─── SPEED / GREED formulas (shared cost + effect curves) ──────────────
## Cost to go from `current_level` → `current_level + 1`.
## level 1 → 2 costs UPGRADE_BASE_COST (×COST_MULT each further level).
func upgrade_cost(current_level: int) -> int:
	var raw: float = float(UPGRADE_BASE_COST) * pow(COST_MULT, float(maxi(1, current_level) - 1))
	return _round_cost(raw)


## Effect multiplier at a given level. Level 1 = 1.0 (base).
func effect_multiplier(level: int) -> float:
	return pow(EFFECT_MULT, float(maxi(1, level) - 1))


# ─── SCALE formulas (window count + cost) ──────────────────────────────
## Cost of the next SCALE purchase given how many were already bought.
func scale_cost(purchases_done: int) -> int:
	var raw: float = float(SCALE_BASE_COST) * pow(SCALE_COST_MULT, float(maxi(0, purchases_done)))
	return _round_cost(raw)


## Simultaneous battle-window count: 1 + one per SCALE purchase (start at 1).
func scale_window_count(purchases_done: int) -> int:
	return 1 + maxi(0, purchases_done)


## No real cap — the cost curve is the limiter. Huge value so scale_is_maxed()
## never trips (kept for API compatibility).
func scale_max_purchases() -> int:
	return 1000000


# ─── Per-enemy level curves (System 1) ─────────────────────────────────
## Kills required to advance from `level` to `level + 1`.
func kills_for_level(level: int) -> int:
	return maxi(1, int(round(float(LEVEL_UP_BASE_KILLS) * pow(LEVEL_UP_KILLS_MULT, float(maxi(1, level) - 1)))))


## How many of this enemy spawn in one window at the given level (1→5, capped).
func spawn_count_for_level(level: int) -> int:
	return clampi(level, 1, ENEMY_SPAWN_PER_WINDOW_MAX)


## Uncapped kill-gold multiplier for the given level.
func kill_gold_mult_for_level(level: int) -> float:
	return pow(KILL_GOLD_PER_LEVEL_MULT, float(maxi(1, level) - 1))


# ─── Chest open-speed (GREED axis upgrade) ─────────────────────────────
## Hover-to-open gauge duration at a given open-speed level (level 0 = base).
func chest_open_duration(level: int) -> float:
	return maxf(CHEST_OPEN_DURATION_MIN, CHEST_OPEN_BASE_DURATION * pow(CHEST_OPEN_DURATION_MULT, float(maxi(0, level))))


## Cost to buy the next open-speed level (from `level` → `level + 1`).
func chest_open_speed_cost(level: int) -> int:
	return _round_cost(float(CHEST_OPEN_SPEED_BASE_COST) * pow(CHEST_OPEN_SPEED_COST_MULT, float(maxi(0, level))))


# ─── Tier lookups ───────────────────────────────────────────────────────
func tier_count() -> int:
	return TIERS.size()


func tier_at(index: int) -> Dictionary:
	if index < 0 or index >= TIERS.size():
		return {}
	return TIERS[index]


func tier_by_id(id: StringName) -> Dictionary:
	for tier: Dictionary in TIERS:
		if tier["id"] == id:
			return tier
	return {}


func tier_index_of(id: StringName) -> int:
	for i in TIERS.size():
		if TIERS[i]["id"] == id:
			return i
	return -1


## Reverse lookup: which tier owns a given enemy resource path. Used to resolve
## per-enemy HP/gold when several tiers are active at once. {} if no match.
func tier_by_enemy_res(path: String) -> Dictionary:
	for tier: Dictionary in TIERS:
		if str(tier["enemy_res"]) == path:
			return tier
	return {}


# ─── Building lookups (structure system) ───────────────────────────────
func building_count() -> int:
	return BUILDINGS.size()


func building_at(index: int) -> Dictionary:
	if index < 0 or index >= BUILDINGS.size():
		return {}
	return BUILDINGS[index]


func building_by_id(id: StringName) -> Dictionary:
	for b: Dictionary in BUILDINGS:
		if b["id"] == id:
			return b
	return {}


## The auto-appear building whose trigger matches this upgrade category (or "").
func building_for_trigger(category: StringName) -> StringName:
	for b: Dictionary in BUILDINGS:
		if StringName(b.get("mode", &"")) == &"auto" and StringName(b.get("trigger", &"")) == category:
			return b["id"]
	return &""


## The building that hosts a given upgrade kind (for the list filter mapping).
func building_for_upgrade_kind(kind: StringName) -> StringName:
	for b: Dictionary in BUILDINGS:
		for desc: Dictionary in b.get("upgrades", []):
			if StringName(desc.get("kind", &"")) == kind:
				return b["id"]
	return &""


# ─── Field tiles (left panel) ──────────────────────────────────────────
func tile_count() -> int:
	return TILES.size()


func tile_at(index: int) -> Dictionary:
	if index < 0 or index >= TILES.size():
		return {}
	return TILES[index]


func tile_by_id(id: StringName) -> Dictionary:
	for t: Dictionary in TILES:
		if t["id"] == id:
			return t
	return {}


func campfire_regen_rate(level: int) -> float:
	return CAMPFIRE_REGEN_BASE_RATE + CAMPFIRE_REGEN_PER_LEVEL * float(maxi(1, level) - 1)


func campfire_upgrade_cost(level: int) -> int:
	return _round_cost(float(CAMPFIRE_UPGRADE_BASE_COST) * pow(CAMPFIRE_UPGRADE_COST_MULT, float(maxi(1, level) - 1)))


func village_upgrade_cost(level: int) -> int:
	return _round_cost(float(VILLAGE_UPGRADE_BASE_COST) * pow(VILLAGE_UPGRADE_COST_MULT, float(maxi(1, level) - 1)))


# ─── Companion lookups ─────────────────────────────────────────────────
func companion_count() -> int:
	return COMPANIONS.size()


func companion_at(index: int) -> Dictionary:
	if index < 0 or index >= COMPANIONS.size():
		return {}
	return COMPANIONS[index]


func companion_by_id(id: StringName) -> Dictionary:
	for c: Dictionary in COMPANIONS:
		if c["id"] == id:
			return c
	return {}


# ─── Weapon types + per-character profile ──────────────────────────────
func weapon_type_count() -> int:
	return WEAPON_TYPES.size()


func weapon_type_at(index: int) -> Dictionary:
	if index < 0 or index >= WEAPON_TYPES.size():
		return {}
	return WEAPON_TYPES[index]


func weapon_type_by_id(id: StringName) -> Dictionary:
	for t: Dictionary in WEAPON_TYPES:
		if t["id"] == id:
			return t
	return {}


func weapon_name_for(type_id: StringName, level: int) -> String:
	var names: Array = WEAPON_NAMES_BY_TYPE.get(type_id, [])
	var idx: int = maxi(1, level) - 1
	if idx < names.size():
		return str(names[idx])
	var type_name: String = str(weapon_type_by_id(type_id).get("name", "무기"))
	return "%s +%d" % [type_name, idx - names.size() + 1]


## The weapon TYPE a character wields (auto-equip routing).
func character_weapon_type(id: StringName) -> StringName:
	if id == &"hero":
		return HERO_WEAPON_TYPE
	return StringName(companion_by_id(id).get("weapon_type", HERO_WEAPON_TYPE))


## The character's innate TRAIT (role variant; never changed by gear).
func character_trait(id: StringName) -> StringName:
	if id == &"hero":
		return HERO_TRAIT
	return StringName(companion_by_id(id).get("trait", HERO_TRAIT))


# ─── Role scaling curves (by member level) ─────────────────────────────
func mage_extra_targets(level: int) -> int:
	return MAGE_BASE_EXTRA_TARGETS + int(float(maxi(1, level) - 1) / float(maxi(1, MAGE_LEVELS_PER_EXTRA_TARGET)))


func mage_splash_damage(level: int) -> float:
	return minf(MAGE_SPLASH_DMG_MAX, MAGE_SPLASH_DMG_BASE + MAGE_SPLASH_DMG_PER_LEVEL * float(maxi(1, level) - 1))


func priest_heal(level: int) -> int:
	return PRIEST_HEAL_BASE + PRIEST_HEAL_PER_LEVEL * (maxi(1, level) - 1)


func priest_recovery_factor(level: int) -> float:
	return maxf(PRIEST_RECOVERY_FACTOR_MIN, PRIEST_RECOVERY_FACTOR_BASE - PRIEST_RECOVERY_FACTOR_PER_LEVEL * float(maxi(1, level) - 1))


func thief_gold_mult(level: int) -> float:
	return THIEF_GOLD_MULT_BASE + THIEF_GOLD_MULT_PER_LEVEL * float(maxi(1, level) - 1)


# ─── Weapon naming (SPEED skin) ────────────────────────────────────────
func weapon_name_for_level(level: int) -> String:
	var idx: int = maxi(1, level) - 1
	if idx < WEAPON_NAMES.size():
		return WEAPON_NAMES[idx]
	return "명검 +%d" % (idx - WEAPON_NAMES.size() + 1)


# ─── Armor (survival skin) ─────────────────────────────────────────────
func armor_name_for_level(level: int) -> String:
	var idx: int = maxi(1, level) - 1
	if idx < ARMOR_NAMES.size():
		return ARMOR_NAMES[idx]
	return "성갑 +%d" % (idx - ARMOR_NAMES.size() + 1)


## Flat party MAX HP from the equipped armor (level 1 = 0).
func armor_hp_for_level(level: int) -> int:
	return ARMOR_HP_PER_LEVEL * (maxi(1, level) - 1)


## Cost to buy the next armor (from `current_level` → `current_level + 1`).
func armor_cost(current_level: int) -> int:
	return _round_cost(float(ARMOR_BASE_COST) * pow(ARMOR_COST_MULT, float(maxi(1, current_level) - 1)))


# ─── Party level-up curve ──────────────────────────────────────────────
## XP required to advance a party member from `level` to `level + 1`.
func party_xp_for_level(level: int) -> int:
	return maxi(1, int(round(float(PARTY_LEVEL_BASE_XP) * pow(PARTY_LEVEL_XP_MULT, float(maxi(1, level) - 1)))))


# ─── Internal ───────────────────────────────────────────────────────────
## Round costs up to a tidy step so the shop reads cleanly.
func _round_cost(raw: float) -> int:
	if raw < 100.0:
		return maxi(1, int(ceil(raw / 5.0)) * 5)
	return maxi(1, int(ceil(raw / 10.0)) * 10)
