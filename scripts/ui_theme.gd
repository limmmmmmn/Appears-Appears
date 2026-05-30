class_name UITheme
extends RefCounted

## Central UI SIZING — the one place to tune panel widths, font sizes, paddings,
## tile sizes. Sizes only (colors/styles stay in the individual UI scripts).
## Access anywhere via the class name, e.g. `UITheme.FONT_CARD_NAME`.

# ─── Right panel (강화 상점 / 마을 격자) ───────────────────────────────
## Tuned to match the left dock's small, neat feel. HIERARCHY: name = base,
## numbers (value/cost) are SMALLER (secondary info), section labels smallest.
const RIGHT_PANEL_WIDTH: float = 88.0      ## ~2× the left dock — balanced, wider field
const PANEL_CONTENT_MARGIN: int = 4
const LIST_SEPARATION: int = 3
const FONT_GOLD: int = 10                 ## "Gold N" header
const FONT_SECTION: int = 7               ## "마을" / "강화" — smallest + dim
const FONT_CARD_NAME: int = 9             ## the upgrade's NAME — the base size
const FONT_CARD_VALUE: int = 7            ## current value (×1.40) — smaller
const FONT_CARD_BUTTON: int = 7           ## next + cost on the buy button — smaller
const FONT_TILE_GLYPH: int = 11           ## grid tile letter
const FONT_TILE_TAG: int = 6              ## grid tile cost/"필터" tag
## Card geometry — compact so more cards fit on screen.
const CARD_BUTTON_HEIGHT: float = 13.0
const CARD_MARGIN_H: int = 4
const CARD_MARGIN_V: int = 1
const GRID_TILE_SIZE: Vector2 = Vector2(22.0, 20.0)  ## 3 cols fit inside the floating group

# ─── HUD top bar ───────────────────────────────────────────────────────
const FONT_HUD: int = 9                   ## "Gold N", field/loop labels

# ─── Battle window ─────────────────────────────────────────────────────
const FONT_BATTLE_LOG: int = 6            ## combat log text


## The right panel's left screen edge (it docks to the right side).
static func right_panel_left() -> float:
	return 640.0 - RIGHT_PANEL_WIDTH
