extends Node2D

## Main entry point.
## Sets up the party, drives stage progression, hosts the settlement screen
## between stages. Battle window spawning lives in BattleManager.

const SETTLEMENT_SCENE: PackedScene = preload("res://scenes/settlement.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")

const DEBUG_LEGENDARY_PATHS: PackedStringArray = [
	"res://data/modifiers/legendary/echo_strike.tres",
	"res://data/modifiers/legendary/mega_crit.tres",
]

const DEFAULT_PARTY_PATHS: PackedStringArray = [
	"res://data/characters/hero.tres",
	"res://data/characters/mage.tres",
	"res://data/characters/priest.tres",
	"res://data/characters/thief.tres",
]

var _settlement: Settlement


func _ready() -> void:
	print("Hyper Quest booted on Godot 4.6 | %dx%d" % [
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	])
	_setup_default_party()
	EventBus.party_wiped.connect(_on_party_wiped)
	EventBus.stage_cleared.connect(_on_stage_cleared)
	# Kick off the first stage. Field listens to stage_started and spawns enemies.
	GameState.advance_stage()


func _setup_default_party() -> void:
	var members: Array[CharacterData] = []
	for path in DEFAULT_PARTY_PATHS:
		var data: CharacterData = load(path)
		if data:
			members.append(data)
	GameState.set_party(members)
	print("[main] party loaded: %d members" % GameState.party_size())


# ─── Stage flow ───────────────────────────────────────────────────────
func _on_stage_cleared(stage_num: int) -> void:
	print("[main] stage cleared: %d (gold=%d)" % [stage_num, GameState.gold])
	_show_settlement()


func _show_settlement() -> void:
	if _settlement and is_instance_valid(_settlement):
		return
	_settlement = SETTLEMENT_SCENE.instantiate()
	_settlement.closed.connect(_on_settlement_closed)
	add_child(_settlement)


func _on_settlement_closed() -> void:
	_settlement = null
	GameState.advance_stage()


func _on_party_wiped() -> void:
	print("[main] PARTY WIPED — gold this run: %d, modifiers: %d" % [
		GameState.gold,
		GameState.active_modifiers.size(),
	])


# ─── Debug ────────────────────────────────────────────────────────────
## F1 = instant stage clear (skip combat to test settlement)
## F2 = stress spawn 20 battle windows
## F3 = stress spawn 100 battle windows (TRAILER CUT)
## F4 = grant both legendary modifiers
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_F1:
				print("[main] DEBUG: forcing stage_cleared")
				EventBus.stage_cleared.emit(GameState.current_stage)
			KEY_F2:
				_debug_stress_spawn(20)
			KEY_F3:
				_debug_stress_spawn(100)
			KEY_F4:
				_debug_grant_legendaries()


func _debug_stress_spawn(count: int) -> void:
	var mgr: BattleManager = get_node_or_null("BattleManager")
	if mgr == null:
		return
	for i in count:
		mgr.spawn_battle(SLIME_DATA)
	print("[main] DEBUG: spawned %d battle windows (active=%d)" % [count, mgr.active_window_count()])


func _debug_grant_legendaries() -> void:
	for path in DEBUG_LEGENDARY_PATHS:
		var mod: ModifierData = load(path)
		if mod:
			GameState.add_modifier(mod)
	print("[main] DEBUG: granted %d modifiers (total=%d)" % [
		DEBUG_LEGENDARY_PATHS.size(),
		GameState.active_modifiers.size(),
	])
