class_name TopMenuBar
extends Control

## Top menu bar — the "OS" of the desktop metaphor. A thin macOS-style strip across
## the top: logo + app menus on the left, hero level on the right (like the clock).
##
## LOOK = scenes/ui/menu_bar.tscn (bar background, fonts, colors, menu buttons,
## layout — all editable in the editor). This script is LOGIC ONLY: it wires the
## launcher buttons to toggle their windows and keeps the level readout live.
## The menu buttons' target windows are bound in the scene's signal connections
## (pressed → _toggle_group with the window's group name).

@onready var _level_label: Label = %Level


func _ready() -> void:
	EventBus.party_member_xp_changed.connect(_on_any_change.unbind(4))
	EventBus.party_changed.connect(_on_any_change)
	_refresh_status()


## Toggle (or open) the app window registered under `group`. Wired from the scene:
## each launcher button's `pressed` is bound to its window group.
func _toggle_group(group: String) -> void:
	var w: Node = get_tree().get_first_node_in_group(group)
	if w == null:
		return
	if w.has_method("toggle"):
		w.call("toggle")
	elif w.has_method("open"):
		w.call("open")


func _on_any_change() -> void:
	_refresh_status()


# ─── Debug (moved off the field HUD into the menu bar) ──────────────────
func _on_debug_gold() -> void:
	GameState.add_gold(1000)


func _on_debug_finish() -> void:
	EventBus.field_loop_finish_requested.emit()


func _refresh_status() -> void:
	if _level_label != null and GameState.party_size() > 0:
		_level_label.text = "Lv %d" % GameState.party_level(0)
