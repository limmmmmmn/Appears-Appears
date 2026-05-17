extends Node2D

## Main entry point.
## Sets up the party and drives Field -> Town -> Field stage progression.
## Battle window spawning lives in BattleManager.

const TOWN_SCENE: PackedScene = preload("res://scenes/town.tscn")
const HOME_BASE_SCENE: PackedScene = preload("res://scenes/home_base.tscn")
const RESULTS_PANEL_SCENE: PackedScene = preload("res://scenes/results_panel.tscn")
const NODE_TREE_PANEL_SCENE: PackedScene = preload("res://scenes/node_tree_panel.tscn")
const EVENT_WINDOW_SCENE: PackedScene = preload("res://scenes/event_window.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")

## The run starts with the leader alone. Companions are recruited via
## town cards from the active prototype modifier pool — or, once their
## skill-tree node is unlocked, auto-joined here at deploy.
const DEFAULT_PARTY_PATHS: PackedStringArray = [
	"res://data/characters/hero.tres",
]

## Maps a node's effect_data["recruit_character_id"] value to a CharacterData
## resource path. Add an entry here when a new recruit node lands.
const RECRUIT_NODE_CHARACTER_PATHS: Dictionary = {
	&"mage": "res://data/characters/mage.tres",
	&"priest": "res://data/characters/priest.tres",
	&"thief": "res://data/characters/thief.tres",
}

@onready var _field: Field = $Field
@onready var _battle_manager: BattleManager = $BattleManager
@onready var _hud: HUD = $HUD
@onready var _pause_overlay: CanvasLayer = $PauseOverlay

var _town: Town
var _home_base: HomeBase
var _results_panel: ResultsPanel
var _node_tree_panel: NodeTreePanel
var _event_layer: CanvasLayer
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
	# Field run lifecycle: party_wipe and timer expiry both funnel through
	# GameState.field_run_ended → results panel. The old home_base-on-wipe
	# path is retained as a defensive fallback.
	GameState.field_run_ended.connect(_on_field_run_ended)
	EventBus.event_tile_triggered.connect(_on_event_tile_triggered)
	# Kick off the first field. Field listens to stage_started for enemy
	# spawns; GameState.start_field_run arms the run-end timer.
	GameState.advance_stage()
	GameState.start_field_run()


func _setup_default_party() -> void:
	var members: Array[CharacterData] = []
	var seen_ids: Dictionary = {}
	for path in DEFAULT_PARTY_PATHS:
		_append_unique_member(members, seen_ids, load(path) as CharacterData)
	# Each unlocked recruit node auto-joins its character at deploy. Doing
	# this here (instead of via add_recruit at unlock time) keeps the party
	# fresh after reset_run() wipes party state.
	for node: NodeData in SkillTreeDB.get_all():
		if not GameState.has_node_unlocked(node.id):
			continue
		var recruit_id: StringName = node.effect_data.get("recruit_character_id", &"")
		if recruit_id == &"":
			continue
		var character_path: String = RECRUIT_NODE_CHARACTER_PATHS.get(recruit_id, "")
		if character_path == "":
			continue
		_append_unique_member(members, seen_ids, load(character_path) as CharacterData)
	GameState.set_party(members)
	print("[main] party loaded: %d members" % GameState.party_size())


func _append_unique_member(members: Array[CharacterData], seen_ids: Dictionary, data: CharacterData) -> void:
	if data == null or seen_ids.has(data.id):
		return
	seen_ids[data.id] = true
	members.append(data)


# ─── Field run lifecycle ──────────────────────────────────────────────
## Single funnel for "field is over": timer expiry, party wipe, or debug.
## Aborts in-flight battles so reward popups don't fire over the results
## screen, then shows ResultsPanel.
func _on_field_run_ended(reason: StringName) -> void:
	print("[main] field run ended (%s) — gold=%d, completed=%d" % [
		reason, GameState.gold, GameState.field_runs_completed,
	])
	_battle_manager.abort_all_battles()
	_show_results_panel()


func _show_results_panel() -> void:
	if _results_panel and is_instance_valid(_results_panel):
		return
	_set_manual_pause(false)
	_results_panel = RESULTS_PANEL_SCENE.instantiate()
	_results_panel.upgrade_pressed.connect(_on_results_upgrade_pressed)
	_results_panel.continue_pressed.connect(_on_results_continue_pressed)
	add_child(_results_panel)
	# Field/HUD stay visible behind the dimmed overlay so the player still
	# sees their party — only the field is frozen by pausing.
	get_tree().paused = true


## [업그레이드] swaps the results panel for the node tree panel. The tree
## panel's own [계속] funnels back to _on_tree_continue_pressed.
func _on_results_upgrade_pressed() -> void:
	if _results_panel and is_instance_valid(_results_panel):
		_results_panel.queue_free()
	_results_panel = null
	if _node_tree_panel and is_instance_valid(_node_tree_panel):
		return
	_node_tree_panel = NODE_TREE_PANEL_SCENE.instantiate()
	_node_tree_panel.continue_pressed.connect(_on_tree_continue_pressed)
	add_child(_node_tree_panel)


## [계속] on results — straight back to the field, skipping the tree.
func _on_results_continue_pressed() -> void:
	if _results_panel and is_instance_valid(_results_panel):
		_results_panel.queue_free()
	_results_panel = null
	_start_next_field()


## [계속] on the tree — same path back to field, just one panel deeper.
func _on_tree_continue_pressed() -> void:
	if _node_tree_panel and is_instance_valid(_node_tree_panel):
		_node_tree_panel.queue_free()
	_node_tree_panel = null
	_start_next_field()


func _start_next_field() -> void:
	get_tree().paused = false
	# Stage stays where it is — node tree drives all progression now.
	# prepare_next_field heals the party + re-emits stage_started so Field
	# clears and respawns enemies for a fresh round.
	GameState.prepare_next_field()
	GameState.start_field_run()


# ─── Field events ─────────────────────────────────────────────────────
## Campfire (and future event tiles) walk-into trigger. Pauses the field,
## pops a non-combat event window with the matching dialogue, and on
## completion applies the recruit + frees the tile so it can't re-fire.
func _on_event_tile_triggered(tile: Node) -> void:
	if _event_layer != null and is_instance_valid(_event_layer):
		return
	var ev_id: StringName = &""
	if tile != null and tile.has_method("event_id"):
		ev_id = tile.event_id()
	var dialogue: Array = _dialogue_for_event(ev_id)
	var recruit: CharacterData = _recruit_for_event(ev_id)
	var tile_tex: Texture2D = _tile_texture_for_event(ev_id)
	if dialogue.is_empty():
		return
	_set_manual_pause(false)
	var layer := CanvasLayer.new()
	layer.layer = 10
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_event_layer = layer
	var window: EventWindow = EVENT_WINDOW_SCENE.instantiate()
	# IMPORTANT: setup must run before add_child. Once we add the window,
	# its _ready fires immediately and reads recruit_data — if we set it
	# afterwards the mage visual never gets built.
	window.setup(ev_id, dialogue, recruit, tile_tex)
	layer.add_child(window)
	get_tree().paused = true
	window.event_completed.connect(_on_event_completed.bind(tile, recruit, layer))


func _dialogue_for_event(ev_id: StringName) -> Array:
	if ev_id == FieldCampfire.EVENT_ID:
		return [
			{"speaker": "마법사", "line": "난 불이 좋아"},
			{"speaker": "용사", "line": "더 태워볼래?"},
			{"speaker": "마법사", "line": "좋아 함께 가자"},
		]
	if ev_id == FieldShrine.EVENT_ID:
		return [
			{"speaker": "사제", "line": "상처를 입은 어린양이 여기 있군"},
			{"speaker": "용사", "line": "그게 바로 나야."},
		]
	return []


func _recruit_for_event(ev_id: StringName) -> CharacterData:
	if ev_id == FieldCampfire.EVENT_ID:
		var path: String = "res://data/characters/mage.tres"
		if ResourceLoader.exists(path):
			return load(path) as CharacterData
	if ev_id == FieldShrine.EVENT_ID:
		var path: String = "res://data/characters/priest.tres"
		if ResourceLoader.exists(path):
			return load(path) as CharacterData
	return null


## Picks the centerpiece sprite for the event window. New event tiles add
## a branch here so the right texture follows them into the popup.
func _tile_texture_for_event(ev_id: StringName) -> Texture2D:
	if ev_id == FieldCampfire.EVENT_ID:
		return load("res://assets/sprites/objects/bonfire.png") as Texture2D
	if ev_id == FieldShrine.EVENT_ID:
		return load("res://assets/sprites/objects/shrine.png") as Texture2D
	return null


func _on_event_completed(_ev_id: StringName, tile: Node, recruit: CharacterData, layer: CanvasLayer) -> void:
	if recruit != null:
		GameState.add_recruit(recruit)
	if tile != null and is_instance_valid(tile) and tile.has_method("consume"):
		tile.consume()
	if is_instance_valid(layer):
		layer.queue_free()
	if _event_layer == layer:
		_event_layer = null
	get_tree().paused = false


func _set_run_layers_visible(should_show: bool) -> void:
	_field.visible = should_show
	_battle_manager.visible = should_show
	_hud.visible = should_show


func _set_run_layers_process_mode(mode: ProcessMode) -> void:
	_field.process_mode = mode
	_battle_manager.process_mode = mode
	_hud.process_mode = mode


# ─── Debug ────────────────────────────────────────────────────────────
func _set_manual_pause(is_paused: bool) -> void:
	_is_manually_paused = is_paused
	_pause_overlay.visible = is_paused
	get_tree().paused = is_paused


## F1 = instant stage_cleared signal (legacy debug)
## F2 = stress spawn 20 battle windows
## F4 = +100 meta gold (for tuning the skill-tree economy)
## F5 = force-end field run → results panel (no need to die or wait)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _is_manually_paused:
			return
		match event.physical_keycode:
			KEY_F1:
				if get_tree().paused: return
				print("[main] DEBUG: forcing stage_cleared")
				EventBus.stage_cleared.emit(GameState.current_stage)
			KEY_F2:
				if get_tree().paused: return
				_debug_stress_spawn(20)
			KEY_F4:
				GameState.add_gold(100)
				print("[main] DEBUG: +100 gold (now %d)" % GameState.gold)
			KEY_F5:
				print("[main] DEBUG: forcing field_run_ended")
				GameState.end_field_run(&"debug")


func _debug_stress_spawn(count: int) -> void:
	var mgr: BattleManager = get_node_or_null("BattleManager")
	if mgr == null:
		return
	for i in count:
		mgr.spawn_battle(SLIME_DATA)
	print("[main] DEBUG: spawned %d battle windows (active=%d)" % [count, mgr.active_window_count()])
