extends Node
## EventManager: 랜덤 팝업 이벤트 (보물/장비/스토리).

signal event_triggered(event_type: String, event_data: Dictionary)

const EVENT_WINDOW_SCENE_PATH := "res://scenes/ui/event_window.tscn"

var event_window_scene: PackedScene
var event_enabled: bool = false
var event_timer: float = 0.0
var _next_event_at: float = 0.0
var event_interval_min: float = 15.0
var event_interval_max: float = 30.0
var current_event_table: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	event_window_scene = load(EVENT_WINDOW_SCENE_PATH)

func _process(delta: float) -> void:
	if not event_enabled:
		return
	if current_event_table.is_empty():
		return
	event_timer += delta
	if event_timer >= _next_event_at:
		_trigger_random_event()
		event_timer = 0.0
		_roll_next_event()

func start_events(event_table_id: String) -> void:
	var table: Dictionary = DataLoader.load_field_table(event_table_id)
	if table.is_empty():
		current_event_table = []
		event_enabled = false
		return
	current_event_table = table.get("events", [])
	event_interval_min = float(table.get("event_interval_min", 15.0))
	event_interval_max = float(table.get("event_interval_max", 30.0))
	event_timer = 0.0
	_roll_next_event()
	event_enabled = true

func stop_events() -> void:
	event_enabled = false
	current_event_table = []

func _roll_next_event() -> void:
	_next_event_at = randf_range(event_interval_min, event_interval_max)

func _trigger_random_event() -> void:
	var ev: Dictionary = _pick_weighted_event()
	if ev.is_empty():
		return
	spawn_event(ev)

func _pick_weighted_event() -> Dictionary:
	var total_weight := 0
	for ev in current_event_table:
		total_weight += int(ev.get("weight", 1))
	if total_weight <= 0:
		return {}
	var pick := randi() % total_weight
	var accum := 0
	for ev in current_event_table:
		accum += int(ev.get("weight", 1))
		if pick < accum:
			return ev
	return current_event_table[0]

func spawn_event(event_data: Dictionary) -> void:
	if event_window_scene == null:
		event_window_scene = load(EVENT_WINDOW_SCENE_PATH)
	if event_window_scene == null:
		push_error("Event window scene missing")
		return
	var container := _get_event_container()
	if container == null:
		return
	var ev_win := event_window_scene.instantiate()
	if ev_win.has_method("setup"):
		ev_win.setup(event_data)
	container.add_child(ev_win)
	event_triggered.emit(String(event_data.get("type", "")), event_data)

func _get_event_container() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("event_container")
	if nodes.is_empty():
		return null
	return nodes[0]
