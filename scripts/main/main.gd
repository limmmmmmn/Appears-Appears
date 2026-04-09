extends Node2D
## Main: 씬 전환의 루트. 필드/월드맵/마을 전환을 담당.

@onready var scene_container: Node = $GameLayer/SceneContainer
@onready var ui_scene_container: Control = $UILayer/UISceneContainer
@onready var hud: CanvasItem = $UILayer/HUD

const FIELD_SCENE := preload("res://scenes/field/field.tscn")
const WORLD_MAP_SCENE := preload("res://scenes/world_map/world_map.tscn")
const TOWN_SCENE := preload("res://scenes/town/town.tscn")
const GAME_OVER_SCENE := preload("res://scenes/ui/game_over_screen.tscn")
const VICTORY_SCENE := preload("res://scenes/ui/victory_screen.tscn")

var _current_scene: Node = null
var _game_ended: bool = false

func _ready() -> void:
	GameManager.game_over.connect(_on_game_over)
	_start_new_game()

func _start_new_game() -> void:
	_game_ended = false
	GameManager.reset()
	var journey: Dictionary = DataLoader.load_journey("journey_01")
	if journey.is_empty():
		push_error("Failed to load journey_01")
		return
	GameManager.start_new_journey(journey)
	change_to_world_map()

func _clear_current_scene() -> void:
	if _current_scene != null and is_instance_valid(_current_scene):
		_current_scene.queue_free()
	_current_scene = null
	BattleManager.clear_all_battles()
	BattleManager.stop_encounters()
	EventManager.stop_events()

func change_to_field(node_data: Dictionary) -> void:
	_clear_current_scene()
	var field := FIELD_SCENE.instantiate()
	scene_container.add_child(field)
	_current_scene = field
	if field.has_method("setup"):
		field.setup(node_data)

func change_to_world_map() -> void:
	_clear_current_scene()
	var map := WORLD_MAP_SCENE.instantiate()
	ui_scene_container.add_child(map)
	_current_scene = map
	if map.has_signal("depart_requested"):
		map.depart_requested.connect(_on_world_map_depart)

func change_to_town(node_data: Dictionary) -> void:
	_clear_current_scene()
	var town := TOWN_SCENE.instantiate()
	ui_scene_container.add_child(town)
	_current_scene = town
	if town.has_method("setup"):
		town.setup(node_data)
	if town.has_signal("depart_requested"):
		town.depart_requested.connect(_on_town_depart)

func change_to_boss(node_data: Dictionary) -> void:
	_clear_current_scene()
	var field := FIELD_SCENE.instantiate()
	scene_container.add_child(field)
	_current_scene = field
	if field.has_method("setup_boss"):
		field.setup_boss(node_data)
	elif field.has_method("setup"):
		field.setup(node_data)

func _on_world_map_depart() -> void:
	var node_data := GameManager.get_current_node_data()
	if node_data.is_empty():
		show_victory()
		return
	_enter_node(node_data)

func _enter_node(node_data: Dictionary) -> void:
	var t: String = String(node_data.get("type", ""))
	match t:
		"field":
			change_to_field(node_data)
		"town":
			change_to_town(node_data)
		"boss":
			change_to_boss(node_data)
		_:
			push_warning("Unknown node type: " + t)

func _on_town_depart() -> void:
	GameManager.advance_to_next_node()
	if GameManager.is_journey_complete():
		show_victory()
		return
	change_to_world_map()

## Field 종료 시 호출되는 공개 메서드
func on_field_completed() -> void:
	GameManager.advance_to_next_node()
	if GameManager.is_journey_complete():
		show_victory()
		return
	change_to_world_map()

func _on_game_over() -> void:
	if _game_ended:
		return
	_game_ended = true
	_clear_current_scene()
	var over := GAME_OVER_SCENE.instantiate()
	$UILayer.add_child(over)

func show_victory() -> void:
	if _game_ended:
		return
	_game_ended = true
	_clear_current_scene()
	var win := VICTORY_SCENE.instantiate()
	$UILayer.add_child(win)

func restart_game() -> void:
	get_tree().reload_current_scene()
