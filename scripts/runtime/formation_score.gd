class_name FormationScore
extends RefCounted

## ─── 전투창 스택 족보(meld) 평가기 ──────────────────────────────────────
## 손으로 겹쳐 만든 스택을 한 "패"로 보고 점수를 낸다. 순수 로직(상태 없음):
##   evaluate([{type, color, count, chips}, …]) → {chips, mult, score, melds}
##
##   점수(골드) = 칩 × 배수
##   • 칩  = Σ(각 창의 chips = 몬스터 골드값 × 마릿수)   ← 성장은 여기로 (덧셈, 통제됨)
##   • 배수 = 성립한 족보 중 **가장 높은 하나만** (겹치지 않음 — 포커처럼 최고 끗발)
##
## 족보: 세 축(색=보상, 종류=적, 수=마릿수)이 각각 "전부 같음" 또는 "전부 다름"이면
## 성립. 같은 축의 두 조건은 상호배타. 3축 모두 성립 = 올스타(최고 등급).
##
## ⚠️ 배수는 전부 플레이스홀더 — 작게(×1.5~3, 올스타만 ×4~6). 성장은 칩으로. 상수만 튠.

## 같은/다른 색·종류 (장수 N별).
const FLUSH_BY_COUNT: Dictionary = {2: 1.5, 3: 2.0, 4: 2.5, 5: 3.0}
const RAINBOW_BY_COUNT: Dictionary = {2: 1.5, 3: 2.0, 4: 2.5, 5: 3.0}
const SET_BY_COUNT: Dictionary = {2: 1.5, 3: 2.0, 4: 2.5, 5: 3.0}
const ZOO_BY_COUNT: Dictionary = {2: 1.5, 3: 2.0, 4: 2.5, 5: 3.0}
## 수: 연속(스트레이트) / 전부 같음(동수).
const STRAIGHT_MULT: float = 2.0
const STRAIGHT_MIN_RUN: int = 3   ## 연속으로 인정할 최소 distinct 길이
const SAME_COUNT_MULT: float = 1.5
## 올스타(색·종류·수 3축 동시) — 항상 단일 멜드보다 높게(=최고 등급). n≥3에서만.
const ALLSTAR_BY_COUNT: Dictionary = {3: 4.0, 4: 5.0, 5: 6.0}


## cards: Array of { "type": StringName, "color": int, "count": int, "chips": int }.
static func evaluate(cards: Array) -> Dictionary:
	var n: int = cards.size()
	if n == 0:
		return {"chips": 0, "mult": 1.0, "score": 0, "melds": []}
	var chips: int = 0
	var color_counts: Dictionary = {}
	var type_counts: Dictionary = {}
	var counts: Array = []
	for c in cards:
		chips += int(c.get("chips", c.get("count", 1)))
		counts.append(int(c.get("count", 1)))
		var col: int = int(c.get("color", -1))
		color_counts[col] = int(color_counts.get(col, 0)) + 1
		var ty: StringName = c.get("type", &"")
		type_counts[ty] = int(type_counts.get(ty, 0)) + 1

	# 성립하는 모든 후보 멜드를 모은 뒤 가장 높은 배수 하나만 채택(겹치지 않음).
	var candidates: Array = []
	var has_color: bool = false
	var has_type: bool = false
	var has_count: bool = false
	if n >= 2:
		# 색
		if color_counts.size() == 1:
			candidates.append({"name": "플러시", "mult": _tier_mult(FLUSH_BY_COUNT, n)})
			has_color = true
		elif color_counts.size() == n:
			candidates.append({"name": "레인보우", "mult": _tier_mult(RAINBOW_BY_COUNT, n)})
			has_color = true
		# 종류
		if type_counts.size() == 1:
			candidates.append({"name": "셋", "mult": _tier_mult(SET_BY_COUNT, n)})
			has_type = true
		elif type_counts.size() == n:
			candidates.append({"name": "동물원", "mult": _tier_mult(ZOO_BY_COUNT, n)})
			has_type = true
		# 수
		if _is_straight(counts):
			candidates.append({"name": "스트레이트", "mult": STRAIGHT_MULT})
			has_count = true
		elif _all_same(counts):
			candidates.append({"name": "동수", "mult": SAME_COUNT_MULT})
			has_count = true
		# 올스타 (3축 동시, 3장+) — 최고 등급
		if has_color and has_type and has_count and n >= 3:
			candidates.append({"name": "올스타", "mult": _tier_mult(ALLSTAR_BY_COUNT, n)})

	# 가장 높은 배수의 멜드 하나만.
	var best: Dictionary = {}
	for c in candidates:
		if best.is_empty() or float(c["mult"]) > float(best["mult"]):
			best = c
	var mult: float = float(best["mult"]) if not best.is_empty() else 1.0
	var melds: Array = [best] if not best.is_empty() else []

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


## True when every count is identical (동수). Caller checks size ≥ 2.
static func _all_same(counts: Array) -> bool:
	if counts.size() < 2:
		return false
	for c in counts:
		if int(c) != int(counts[0]):
			return false
	return true


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
