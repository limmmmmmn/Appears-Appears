class_name Town2Slot
extends Panel

## Bottom-zone feed row: a single horizontal line per party slot showing
## "[NAME] [stats] [• upgrade • upgrade ...]". The PARTY row hides stats and
## lets upgrades fill the width. Empty hero rows hide entirely so the feed
## only shows recruited members — that's the breathing room the layout needs.

enum SlotMode { PARTY, HERO_PRESENT, HERO_EMPTY }

@export var expected_id: StringName = &""
@export var fallback_title: String = ""

@onready var _header_label: Label = %HeaderLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _upgrades_label: Label = %UpgradesLabel

var _mode: SlotMode = SlotMode.HERO_EMPTY
var _party_index: int = -1
## modifier_id -> ModifierData. Used to rebuild the upgrades line when one
## entry's level changes, so we don't have to re-walk active_modifiers.
var _entries: Dictionary = {}
## Insertion order so earlier-bought upgrades show up first in the feed,
## matching how a Trello board reads top-to-bottom (here: left-to-right).
var _entry_order: Array[StringName] = []


func _ready() -> void:
	if expected_id == &"":
		_mode = SlotMode.PARTY
	else:
		_resolve_party_index()
	_apply_mode()
	_rebuild_upgrades_label()


## Re-pull from GameState — call after recruits, purchases, or rests.
func refresh() -> void:
	if expected_id != &"":
		_resolve_party_index()
		_mode = SlotMode.HERO_PRESENT if _party_index >= 0 else SlotMode.HERO_EMPTY
	_apply_mode()


func add_upgrade(mod: ModifierData) -> void:
	if mod == null:
		return
	if not _entries.has(mod.id):
		_entry_order.append(mod.id)
	_entries[mod.id] = mod
	_rebuild_upgrades_label()


func clear_upgrades() -> void:
	_entries.clear()
	_entry_order.clear()
	_rebuild_upgrades_label()


# ─── Internal ─────────────────────────────────────────────────────────
func _resolve_party_index() -> void:
	_party_index = -1
	for i in GameState.party.size():
		if GameState.party[i].id == expected_id:
			_party_index = i
			return


func _apply_mode() -> void:
	match _mode:
		SlotMode.PARTY:
			visible = true
			_header_label.text = "PARTY"
			_stats_label.visible = false
			modulate = Color.WHITE
		SlotMode.HERO_PRESENT:
			visible = true
			_header_label.text = GameState.party[_party_index].display_name.to_upper()
			_stats_label.visible = true
			modulate = Color.WHITE
			_refresh_stats_text()
		SlotMode.HERO_EMPTY:
			visible = false


func _refresh_stats_text() -> void:
	if _party_index < 0:
		return
	var hp: int = GameState.party_hp[_party_index]
	var max_hp: int = GameState.effective_max_hp(_party_index)
	_stats_label.text = "LV %d   HP %d/%d   ATK %d   DEF %d   AGI %d" % [
		GameState.party_level(_party_index),
		hp, max_hp,
		GameState.effective_attack(_party_index),
		GameState.effective_defense(_party_index),
		GameState.effective_agility(_party_index),
	]


func _rebuild_upgrades_label() -> void:
	if _entry_order.is_empty():
		_upgrades_label.text = ""
		return
	var parts: Array[String] = []
	for id: StringName in _entry_order:
		parts.append(_format_upgrade_line(_entries[id]))
	_upgrades_label.text = "   ".join(parts)


func _format_upgrade_line(mod: ModifierData) -> String:
	var lvl: int = GameState.modifier_level(mod.id)
	if mod.max_level > 1 and lvl >= 2:
		return "• %s ×%d" % [mod.display_name, lvl]
	return "• %s" % mod.display_name
