extends Node
## BattleManager: 랜덤 인카운터 → 전투창 생성/관리.

signal battle_started(battle_window: Node)
signal battle_ended(battle_window: Node, result: String)

const BATTLE_WINDOW_SCENE_PATH := "res://scenes/battle_window/battle_window.tscn"
const WINDOW_MIN_DISTANCE := 200.0

var battle_window_scene: PackedScene
var active_battles: Array[Node] = []
var encounter_enabled: bool = false
var encounter_timer: float = 0.0
var _next_encounter_at: float = 0.0
var encounter_interval_min: float = 8.0
var encounter_interval_max: float = 15.0
var current_enemy_table: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	battle_window_scene = load(BATTLE_WINDOW_SCENE_PATH)

func _process(delta: float) -> void:
	if not encounter_enabled:
		return
	if current_enemy_table.is_empty():
		return
	encounter_timer += delta
	if encounter_timer >= _next_encounter_at:
		_trigger_random_encounter()
		encounter_timer = 0.0
		_roll_next_encounter()

func start_encounters(enemy_table_id: String) -> void:
	var table: Dictionary = DataLoader.load_field_table(enemy_table_id)
	if table.is_empty():
		push_warning("Unknown enemy table: " + enemy_table_id)
		current_enemy_table = []
		encounter_enabled = false
		return
	current_enemy_table = table.get("enemies", [])
	encounter_interval_min = float(table.get("encounter_interval_min", 8.0))
	encounter_interval_max = float(table.get("encounter_interval_max", 15.0))
	encounter_timer = 0.0
	_roll_next_encounter()
	encounter_enabled = true

func stop_encounters() -> void:
	encounter_enabled = false
	current_enemy_table = []

func _roll_next_encounter() -> void:
	_next_encounter_at = randf_range(encounter_interval_min, encounter_interval_max)

func _trigger_random_encounter() -> void:
	if current_enemy_table.is_empty():
		return
	var enemy_id: String = current_enemy_table[randi() % current_enemy_table.size()]
	var enemy_data: Dictionary = DataLoader.load_enemy(enemy_id)
	if enemy_data.is_empty():
		return
	spawn_battle(enemy_data)

func spawn_battle(enemy_data: Dictionary) -> void:
	if battle_window_scene == null:
		battle_window_scene = load(BATTLE_WINDOW_SCENE_PATH)
	if battle_window_scene == null:
		push_error("Battle window scene missing")
		return
	var container := _get_battle_container()
	if container == null:
		return
	var battle_win := battle_window_scene.instantiate()
	if battle_win.has_method("setup"):
		battle_win.setup(enemy_data)
	container.add_child(battle_win)
	if battle_win is Control:
		(battle_win as Control).position = _find_window_position(battle_win as Control)
	active_battles.append(battle_win)
	if battle_win.has_signal("battle_finished"):
		battle_win.battle_finished.connect(_on_battle_finished.bind(battle_win))
	GameManager.increment_encounter_count()
	battle_started.emit(battle_win)

func _on_battle_finished(result: String, battle_win: Node) -> void:
	if battle_win in active_battles:
		active_battles.erase(battle_win)
	battle_ended.emit(battle_win, result)

func clear_all_battles() -> void:
	for b in active_battles:
		if is_instance_valid(b):
			b.queue_free()
	active_battles.clear()

func _get_battle_container() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("battle_container")
	if nodes.is_empty():
		return null
	return nodes[0]

func _find_window_position(new_win: Control) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var size := new_win.size
	if size == Vector2.ZERO:
		size = Vector2(420, 360)
	var safe_margin := Vector2(40, 100)
	var max_pos := viewport_size - size - safe_margin
	if max_pos.x < safe_margin.x:
		max_pos.x = safe_margin.x
	if max_pos.y < safe_margin.y:
		max_pos.y = safe_margin.y
	var best := Vector2(safe_margin.x, safe_margin.y)
	for attempt in 20:
		var candidate := Vector2(
			randf_range(safe_margin.x, max_pos.x),
			randf_range(safe_margin.y, max_pos.y)
		)
		if _is_position_clear(candidate, size):
			return candidate
		best = candidate
	return best

func _is_position_clear(pos: Vector2, size: Vector2) -> bool:
	for b in active_battles:
		if not is_instance_valid(b) or not (b is Control):
			continue
		var other := b as Control
		var dist := (other.position - pos).length()
		if dist < WINDOW_MIN_DISTANCE:
			return false
	return true
