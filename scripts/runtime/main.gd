extends Node2D

## Main entry point.
## Sets up the party and drives Field -> Settlement report -> Base/Field loops.
## Battle window spawning lives in BattleManager.

const SETTLEMENT_REPORT_SCENE: PackedScene = preload("res://scenes/settlement_report.tscn")
const GAME_OVER_SCENE: PackedScene = preload("res://scenes/game_over.tscn")
const OPENING_SEQUENCE_SCENE: PackedScene = preload("res://scenes/ui/opening_sequence.tscn")
const STORY_NOTICE_SCENE: PackedScene = preload("res://scenes/ui/story_notice.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")

## The run starts with the leader alone. Companions are recruited via
## base cards from the active prototype modifier pool.
const DEFAULT_PARTY_PATHS: PackedStringArray = [
	"res://data/characters/hero.tres",
]

@onready var _field: Node2D = $Field
@onready var _battle_manager: BattleManager = $BattleManager
@onready var _hud: CanvasLayer = $HudLayer  ## the always-on UI layer (gold/party/panels/popups)
@onready var _pause_overlay: CanvasLayer = $PauseOverlay

var _settlement_report: SettlementReport
var _game_over: GameOver
var _is_manually_paused: bool = false
var _story_notice_layer: CanvasLayer


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
	EventBus.field_loop_settled.connect(_on_field_loop_settled)
	EventBus.gold_changed.connect(_on_gold_changed)
	await _start_run()


func _start_run() -> void:
	if GameState.STORY_MODE_ENABLED and GameState.OPENING_SEQUENCE_ENABLED:
		_set_run_layers_visible(false)
		await _play_opening_sequence()
		_set_run_layers_visible(true)
	# Kick off the first field loop. Field listens to field_loop_started and spawns enemies.
	GameState.start_next_field_loop()


func _setup_default_party() -> void:
	var members: Array[CharacterData] = []
	for path in DEFAULT_PARTY_PATHS:
		var data: CharacterData = load(path)
		if data:
			members.append(data)
	GameState.set_party(members)
	print("[main] party loaded: %d members" % GameState.party_size())


# ─── Field loop flow ──────────────────────────────────────────────────
func _on_field_loop_settled(loop_num: int) -> void:
	print("[main] field loop settled: loop=%d region=%s gold=%d earned=%d nodes=%d" % [
		loop_num,
		GameState.field_region_name(),
		GameState.gold,
		GameState.total_gold_earned,
		GameState.unlocked_field_node_count(),
	])
	_battle_manager.abort_all_battles()
	_show_settlement_report("%s 정산" % GameState.current_field_region_display_name())


func _show_settlement_report(title: String = "") -> void:
	if _settlement_report and is_instance_valid(_settlement_report):
		return
	_set_manual_pause(false)
	_set_run_layers_visible(false)
	_settlement_report = SETTLEMENT_REPORT_SCENE.instantiate()
	_settlement_report.setup(title, GameStats.current_field_loop_report_lines(), GameState.gold)
	_settlement_report.continue_requested.connect(_on_settlement_continue_requested)
	# Town flow has been removed (no more campfire tile / town scene); route
	# the legacy "back to base" button to the same continue path so debug
	# settlements don't get stuck.
	_settlement_report.town_requested.connect(_on_settlement_continue_requested)
	add_child(_settlement_report)
	get_tree().paused = true


func _on_settlement_continue_requested() -> void:
	_settlement_report = null
	get_tree().paused = false
	_set_run_layers_visible(true)
	GameState.start_next_field_loop(GameState.FIELD_REGION_GRASS)


func _on_gold_changed(new_gold: int) -> void:
	if not GameState.story_should_announce_gold_goal(new_gold):
		return
	GameState.story_gold_goal_announced = true
	_show_story_notice("1000골드가 모였습니다.\n이제 잠자리를 만들 수 있을 것 같습니다.")


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
	if _settlement_report and is_instance_valid(_settlement_report):
		_settlement_report.queue_free()
		_settlement_report = null
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
	await _start_run()


func _play_opening_sequence() -> void:
	var opening := OPENING_SEQUENCE_SCENE.instantiate()
	add_child(opening)
	opening.call("play_lines", GameState.story_opening_lines())
	await opening.tree_exited


func _show_story_notice(text: String) -> void:
	if _story_notice_layer and is_instance_valid(_story_notice_layer):
		_story_notice_layer.queue_free()
	_story_notice_layer = STORY_NOTICE_SCENE.instantiate()
	add_child(_story_notice_layer)
	_story_notice_layer.call("show_notice", text)


# ─── Debug ────────────────────────────────────────────────────────────
func _set_manual_pause(is_paused: bool) -> void:
	_is_manually_paused = is_paused
	_pause_overlay.visible = is_paused
	get_tree().paused = is_paused


func _can_toggle_manual_pause() -> bool:
	return not (_settlement_report and is_instance_valid(_settlement_report)) \
		and not (_game_over and is_instance_valid(_game_over))


## F1 = instant settlement (skip combat to test the upgrade tree)
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
				print("[main] DEBUG: forcing field loop settlement")
				EventBus.field_loop_settled.emit(GameState.field_loop_count)
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
