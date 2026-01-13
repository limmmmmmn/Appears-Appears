extends Node

const FIELD_SCENE_PATH := "res://field/scenes/field.tscn"
const TOWN_SCENE_PATH := "res://town/scenes/town.tscn"

@onready var scene_host: Node = $SceneHost
var _current_scene: Node = null

func _ready() -> void:
	# M2: 저장/신규게임 부팅 호출(1프레임 뒤)
	SaveManager.call_deferred("boot_auto_load_or_new_game", 0)

	# Events(Autoload)에서 씬 변경 요청을 받으면 여기서 처리
	var events := get_node_or_null("/root/Events")
	if events:
		events.connect("request_scene_change", Callable(self, "_on_request_scene_change"))

	_load_scene(FIELD_SCENE_PATH)
	_debug_autoload_check()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				_call_events_change_scene("field")
			KEY_F2:
				_call_events_change_scene("town")
			KEY_F5:
				SaveManager.save_game(0)
			KEY_F6:
				SaveManager.load_game(0)

func _on_request_scene_change(target: String) -> void:
	match target:
		"field":
			_load_scene(FIELD_SCENE_PATH)
		"town":
			_load_scene(TOWN_SCENE_PATH)
		_:
			push_warning("Unknown scene target: %s" % target)

func _load_scene(scene_path: String) -> void:
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null

	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load scene: %s" % scene_path)
		return

	_current_scene = packed.instantiate()
	scene_host.add_child(_current_scene)

func _call_events_change_scene(target: String) -> void:
	var events := get_node_or_null("/root/Events")
	if events:
		events.call("change_scene", target)

func _debug_autoload_check() -> void:
	print("=== Autoload Check ===")
	print("Events:", get_node_or_null("/root/Events"))
	print("DataRegistry:", get_node_or_null("/root/DataRegistry"))
	print("SaveManager:", get_node_or_null("/root/SaveManager"))
	print("InventoryManager:", get_node_or_null("/root/InventoryManager"))
	print("PartyManager:", get_node_or_null("/root/PartyManager"))
	print("FieldStateManager:", get_node_or_null("/root/FieldStateManager"))
	print("RunSystem:", get_node_or_null("/root/RunSystem"))
	print("UIRoot:", get_node_or_null("/root/UIRoot"))
	print("SoundManager:", get_node_or_null("/root/SoundManager"))
