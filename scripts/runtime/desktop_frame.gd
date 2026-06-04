class_name DesktopFrame
extends Control

## FULL-BLEED FIELD: the field (a camera world) fills the entire viewport and IS
## the background — no "app window" framing anymore. The dock + shop float on top
## as small cards (see LeftEnemyBar / RightUpgradePanel). This node is kept as a
## harmless no-op so the existing scene wiring (DesktopFrameLayer) stays intact;
## it paints nothing. Battle-window placement now reads UITheme panel insets
## instead of a frame rect (see BattleManager._play_area_screen_rect).

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
