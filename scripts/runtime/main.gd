extends Node2D

## Main entry point.
## Sets up the party and drives Field -> Town -> Field stage progression.
## Battle window spawning lives in BattleManager.

const TOWN_SCENE: PackedScene = preload("res://scenes/town2.tscn")
const GAME_OVER_SCENE: PackedScene = preload("res://scenes/game_over.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")

## The run starts with the leader alone. Companions are recruited via
## town cards from the active prototype modifier pool.
const DEFAULT_PARTY_PATHS: PackedStringArray = [
	"res://data/characters/hero.tres",
]

@onready var _field: Field = $Field
@onready var _battle_manager: BattleManager = $BattleManager
@onready var _hud: HUD = $HUD
@onready var _pause_overlay: CanvasLayer = $PauseOverlay

var _town: Town2
var _game_over: GameOver
var _is_manually_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_run_layers_process_mode(Node.PROCESS_MODE_PAUSABLE)
	_pause_overlay.visible = false
	print("Appears! Appears! booted on Godot 4.6 | %dx%d" % [
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"),
	])
	_setup_default_party()
	EventBus.party_wiped.connect(_on_party_wiped)
	EventBus.stage_cleared.connect(_on_stage_cleared)
	EventBus.town_entered.connect(_on_town_entered)
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
	print("[main] field cleared: %d (gold=%d)" % [stage_num, GameState.gold])
	_battle_manager.abort_all_battles()
	_show_town("Field %d Cleared" % stage_num)


func _on_town_entered(_tile: Node) -> void:
	print("[main] town tile entered — aborting active battles with no rewards")
	_battle_manager.abort_all_battles()
	_show_town("Town")


func _show_town(title: String = "") -> void:
	if _town and is_instance_valid(_town):
		return
	_set_manual_pause(false)
	_hud.set_level_up_ui_enabled(false)
	_town = TOWN_SCENE.instantiate()
	_town.setup(title)
	_town.closed.connect(_on_town_closed)
	add_child(_town)
	_set_run_layers_visible(false)
	get_tree().paused = true


func _on_town_closed() -> void:
	_town = null
	get_tree().paused = false
	_set_run_layers_visible(true)
	_hud.set_level_up_ui_enabled(true)
	GameState.advance_stage()


func _set_run_layers_visible(is_visible: bool) -> void:
	_field.visible = is_visible
	_battle_manager.visible = is_visible
	_hud.visible = is_visible


func _set_run_layers_process_mode(mode: ProcessMode) -> void:
	_field.process_mode = mode
	_battle_manager.process_mode = mode
	_hud.process_mode = mode


func _on_party_wiped() -> void:
	print("[main] PARTY WIPED — gold: %d | modifiers: %d | companions: %d | party: %d" % [
		GameState.gold,
		GameState.active_modifiers.size(),
		GameState.recruited_companions.size(),
		GameState.party_size(),
	])
	_show_game_over()


# ─── Game over ────────────────────────────────────────────────────────
func _show_game_over() -> void:
	if _game_over and is_instance_valid(_game_over):
		return
	_set_manual_pause(false)
	# Close town if it happens to be up (defensive — shouldn't be).
	if _town and is_instance_valid(_town):
		_town.queue_free()
		_town = null
		get_tree().paused = false
		_set_run_layers_visible(true)
		_hud.set_level_up_ui_enabled(true)
	_game_over = GAME_OVER_SCENE.instantiate()
	_game_over.try_again_pressed.connect(_on_try_again_pressed)
	add_child(_game_over)


func _on_try_again_pressed() -> void:
	_set_manual_pause(false)
	if _game_over and is_instance_valid(_game_over):
		_game_over.queue_free()
	_game_over = null
	GameState.reset_run()
	_setup_default_party()
	# Field listens for stage_started to clear/respawn enemies + recenter the
	# party. set_party (above) already triggered party_changed → fresh visuals.
	GameState.advance_stage()


# ─── Debug ────────────────────────────────────────────────────────────
func _set_manual_pause(is_paused: bool) -> void:
	_is_manually_paused = is_paused
	_pause_overlay.visible = is_paused
	get_tree().paused = is_paused


func _can_toggle_manual_pause() -> bool:
	return not (_town and is_instance_valid(_town)) and not (_game_over and is_instance_valid(_game_over))


## F1 = instant stage clear (skip combat to test town)
## F2 = stress spawn 20 battle windows
## F3 = spawn one of each field enemy type
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE and _can_toggle_manual_pause():
			_set_manual_pause(not _is_manually_paused)
			get_viewport().set_input_as_handled()
			return
		if _is_manually_paused:
			return
		match event.physical_keycode:
			KEY_F1:
				print("[main] DEBUG: forcing stage_cleared")
				EventBus.stage_cleared.emit(GameState.current_stage)
			KEY_F2:
				_debug_stress_spawn(20)
			KEY_F3:
				_debug_spawn_all_enemy_types()


func _debug_stress_spawn(count: int) -> void:
	var mgr: BattleManager = get_node_or_null("BattleManager")
	if mgr == null:
		return
	for i in count:
		mgr.spawn_battle(SLIME_DATA)
	print("[main] DEBUG: spawned %d battle windows (active=%d)" % [count, mgr.active_window_count()])


func _debug_spawn_all_enemy_types() -> void:
	var spawned_count: int = _field.debug_spawn_all_enemy_types()
	print("[main] DEBUG: spawned %d field enemy types" % spawned_count)
