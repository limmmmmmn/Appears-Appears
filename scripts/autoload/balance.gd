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
	{"id": &"slime",  "name": "슬라임", "short": "슬", "unlock_at": 0,      "place_cost": 1,   "kill_gold": 2,    "base_kill_time": 2.0,  "atk_mult": 1.0, "enemy_res": "res://data/enemies/slime.tres"},
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
const TILES: Array[Dictionary] = [
	{
		"id": &"campfire", "name": "모닥불", "short": "불", "color": Color(1.0, 0.6, 0.3, 1.0),
		"sprite": "res://assets/sprites/objects/bonfire.png",
		"place_cost": 300, "owner": &"mage",
		"desc": "필드에 놓는 회복 거점. 근처 파티원만 HP가 차오른다.",
	},
	{
		"id": &"village", "name": "마을", "short": "촌", "color": Color(0.85, 0.78, 0.55, 1.0),
		"sprite": "res://assets/sprites/objects/village.png",
		"place_cost": 50,
		"desc": "첫 마을. 클릭해 여관(휴식)·상점(장비 구매)을 연다.",
	},
]
const CAMPFIRE_REGEN_RADIUS: float = 72.0       ## only party within this regen
const CAMPFIRE_REGEN_BASE_RATE: float = 0.6     ## HP/sec at level 1 (very weak)
const CAMPFIRE_REGEN_PER_LEVEL: float = 0.7     ## +HP/sec per upgrade
const CAMPFIRE_UPGRADE_BASE_COST: int = 120
const CAMPFIRE_UPGRADE_COST_MULT: float = 1.6
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
