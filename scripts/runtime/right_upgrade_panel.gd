class_name RightUpgradePanel
extends PanelContainer

## Right zone — the 강화 (spend-gold upgrades) list only. The 장비 shop moved to the
## village's on-field panel (everything-happens-on-the-field redesign); this panel
## will go away too eventually. LOGIC ONLY; look = scene + master theme.

const TEMPORARILY_HIDDEN: bool = true
const UPGRADE_SHOP_SCRIPT = preload("res://scripts/runtime/upgrade_shop.gd")

@onready var _content: VBoxContainer = %Content

var _rows: Array[Dictionary] = []   ## {button, cost} — for live affordability re-tint


func _ready() -> void:
	# 강화 패널은 우측 프로퍼티 인스펙터와 분리될 때까지 완전히 숨긴다.
	visible = false
	if TEMPORARILY_HIDDEN:
		return
	add_to_group("upgrade_window")
	_rebuild()
	# Gold ticks only re-tint affordability (no rebuild → no flicker); a purchase
	# (combat_upgrade_changed) rebuilds so prices/levels refresh.
	EventBus.gold_changed.connect(_refresh_afford.unbind(1))
	EventBus.combat_upgrade_changed.connect(_on_changed.unbind(1))


# ─── Window open/close (menu bar 강화 toggle) ───────────────────────────
func open() -> void:
	if TEMPORARILY_HIDDEN:
		visible = false
		return
	visible = true
	_rebuild()


func close() -> void:
	visible = false


func toggle() -> void:
	if TEMPORARILY_HIDDEN:
		visible = false
		return
	visible = not visible


func _on_changed() -> void:
	if visible:
		_rebuild()


## Gold tick → re-tint affordability of the existing rows (no rebuild).
func _refresh_afford() -> void:
	if not visible:
		return
	for r: Dictionary in _rows:
		var b: Button = r["button"]
		if not is_instance_valid(b):
			continue
		var cost: int = r["cost"]
		var afford: bool = GameState.gold >= cost
		b.modulate = Color(1, 1, 1, 1) if afford else Color(0.62, 0.64, 0.68, 1.0)
		if cost > 0:
			b.disabled = not afford


# ─── 강화 list ─────────────────────────────────────────────────────────
func _rebuild() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	_rows.clear()
	for item: Dictionary in UPGRADE_SHOP_SCRIPT.upgrade_items():
		var row := UPGRADE_SHOP_SCRIPT.make_upgrade_row(item)
		_content.add_child(row)
		_rows.append({"button": row, "cost": 99999999 if bool(item.get("maxed", false)) else int(item.get("price", 0))})
