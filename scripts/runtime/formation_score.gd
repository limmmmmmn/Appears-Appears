class_name FormationScore
extends RefCounted

## ─── 전투창 족보(meld) 평가기 ──────────────────────────────────────────
## 포메이션에 모인 전투창들을 한 "패"로 보고 점수를 낸다. 순수 로직(상태 없음):
##   evaluate([{type, color, count}, …]) → {chips, mult, score, melds}
##
##   • 칩(chips) = 모든 창의 적 수 합 (기본 점수)
##   • 배수(mult) = 성립한 멜드들의 배수 전부 곱
##   • 점수(score) = chips × mult   ← 이게 골드 뻥튀기의 양
##
## 멜드 = 세 축(색=보상, 종류=적, 수=적 수)의 조합. 값은 전부 아래 표에서 튜닝.
## 색은 정수(BattleWindow.Reward enum), 종류는 적 id(StringName).

## 같은 색 N장 → 플러시. 5장+ 는 표의 최댓값으로 캡.
const FLUSH_BY_COUNT: Dictionary = {3: 2.0, 4: 3.0, 5: 4.0}
## 같은 적 종류 N장 → 셋.
const SET_BY_COUNT: Dictionary = {3: 2.0, 4: 3.0}
## 전부 다른 색(K장, K≥3) → 레인보우. (플러시와 상호배타)
const RAINBOW_BY_COUNT: Dictionary = {3: 2.0, 4: 3.0, 5: 4.0}
## 적 수가 연속(예 1·2·3) → 스트레이트.
const STRAIGHT_MULT: float = 2.0
## 스트레이트로 인정할 최소 연속 길이.
const STRAIGHT_MIN_RUN: int = 3


## cards: Array of Dictionaries { "type": StringName, "color": int, "count": int }.
static func evaluate(cards: Array) -> Dictionary:
	var n: int = cards.size()
	if n == 0:
		return {"chips": 0, "mult": 1.0, "score": 0, "melds": []}
	var chips: int = 0
	var color_counts: Dictionary = {}
	var type_counts: Dictionary = {}
	var counts: Array = []
	for c in cards:
		var cnt: int = int(c.get("count", 1))
		chips += cnt
		counts.append(cnt)
		var col: int = int(c.get("color", -1))
		color_counts[col] = int(color_counts.get(col, 0)) + 1
		var ty: StringName = c.get("type", &"")
		type_counts[ty] = int(type_counts.get(ty, 0)) + 1

	var melds: Array = []
	var mult: float = 1.0

	# ── 색: 플러시(같은 색) vs 레인보우(전부 다른 색) — 상호배타 ──
	var max_color: int = _max_value(color_counts)
	if max_color >= 3:
		var fm: float = _tier_mult(FLUSH_BY_COUNT, max_color)
		mult *= fm
		melds.append({"name": "플러시", "mult": fm, "count": max_color})
	elif color_counts.size() == n and n >= 3:
		var rm: float = _tier_mult(RAINBOW_BY_COUNT, n)
		mult *= rm
		melds.append({"name": "레인보우", "mult": rm, "count": n})

	# ── 종류: 셋(같은 적) ──
	var max_type: int = _max_value(type_counts)
	if max_type >= 3:
		var sm: float = _tier_mult(SET_BY_COUNT, max_type)
		mult *= sm
		melds.append({"name": "셋", "mult": sm, "count": max_type})

	# ── 수: 스트레이트(연속 적 수) ──
	if _is_straight(counts):
		mult *= STRAIGHT_MULT
		melds.append({"name": "스트레이트", "mult": STRAIGHT_MULT, "count": counts.size()})

	return {
		"chips": chips,
		"mult": mult,
		"score": int(round(float(chips) * mult)),
		"melds": melds,
	}


## Highest tier whose threshold (key) is ≤ count. Caps at the largest key.
static func _tier_mult(table: Dictionary, count: int) -> float:
	var best: float = 1.0
	for k in table:
		if count >= int(k):
			best = maxf(best, float(table[k]))
	return best


static func _max_value(d: Dictionary) -> int:
	var best: int = 0
	for k in d:
		best = maxi(best, int(d[k]))
	return best


## True when the DISTINCT counts form one gap-free run of length ≥ STRAIGHT_MIN_RUN.
static func _is_straight(counts: Array) -> bool:
	var uniq: Dictionary = {}
	for c in counts:
		uniq[int(c)] = true
	var keys: Array = uniq.keys()
	keys.sort()
	if keys.size() < STRAIGHT_MIN_RUN:
		return false
	for i in range(1, keys.size()):
		if int(keys[i]) != int(keys[i - 1]) + 1:
			return false
	return true
