class_name UITheme
extends RefCounted

## Central UI SIZING — the one place to tune panel widths, font sizes, paddings,
## tile sizes. Sizes only (colors/styles stay in the individual UI scripts).
## Access anywhere via the class name, e.g. `UITheme.FONT_CARD_NAME`.

# ─── Floating field panels (overlay the full-bleed field) ──────────────
## The field now fills the whole screen; the dock + shop float ON it as small
## cards in the top corners. These drive both the panels' placement AND the
## battle-window play area (windows avoid the panel footprints).
const LEFT_PANEL_WIDTH: float = 142.0      ## left column: dock + party chips + 기록 window
const PANEL_MARGIN: float = 4.0            ## gap from screen edge / between panel & windows
const PANEL_TOP: float = 30.0              ## below the top-left gold / field-name chips

# ─── Lower-left running log (Dark-Room style) ──────────────────────────
## The left column is split: placement dock on top, accumulating text log below.
## The split is NOT fixed at half — tune LEFT_LOG_TOP (y where the log begins) to
## give the dock more or less room. The log fills from there to the screen bottom.
const LEFT_LOG_LEFT: float = 6.0
const LEFT_LOG_TOP: float = 150.0          ## ← the adjustable dock/log split point
const LEFT_LOG_WIDTH: float = 152.0        ## desired width; clamped so it never crosses the field
const LEFT_LOG_RIGHT_GAP: float = 6.0      ## gap kept between the log and the field's left edge
const LEFT_LOG_BOTTOM_MARGIN: float = 12.0 ## gap above the bottom toolbar
const FONT_LOG: int = 11

# ─── Right panel (강화 상점 / 장비) ─────────────────────────────────────
## Tuned to match the left dock's small, neat feel. HIERARCHY: name = base,
## numbers (value/cost) are SMALLER (secondary info), section labels smallest.
const RIGHT_PANEL_WIDTH: float = 120.0     ## floating 속성 inspector window (right)
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
