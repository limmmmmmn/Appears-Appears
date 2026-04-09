extends Node2D
## Field: 아이작 방식 맵. 생성된 방들을 배치하고 파티가 경로를 따라 꼬물꼬물 이동.

signal field_completed

const ROOM_SCENE := preload("res://scenes/field/room.tscn")
const FORK_CHOICE_SCENE := preload("res://scenes/ui/fork_choice.tscn")
const ROOM_SIZE := Vector2(640, 640)

@onready var room_container: Node2D = $RoomContainer
@onready var party_sprite: Node2D = $PartySprite
@onready var camera: Camera2D = $Camera
@onready var field_name_label: Label = $FieldOverlay/FieldName

var _node_data: Dictionary = {}
var _floor_data: Dictionary = {}
var _rooms_by_pos: Dictionary = {}
var _path: Array = []
var _path_idx: int = 0
var _is_boss: bool = false
var _boss_spawned: bool = false
var _finished: bool = false
var _fork_waiting: bool = false

var _current_curve: Curve2D = null
var _curve_progress: float = 0.0
var _curve_length: float = 0.0

var _entered_rooms: Dictionary = {}
var _field_type: String = "plains"

func setup(node_data: Dictionary) -> void:
	_node_data = node_data
	_field_type = String(node_data.get("field_type", "plains"))
	if field_name_label:
		field_name_label.text = String(node_data.get("name", ""))
	_generate_and_build()
	_start_on_first_room()
	var enemy_table := String(node_data.get("enemy_table", ""))
	if enemy_table != "":
		BattleManager.start_encounters(enemy_table)

func setup_boss(node_data: Dictionary) -> void:
	_is_boss = true
	setup(node_data)

func _generate_and_build() -> void:
	var room_count := int(_node_data.get("room_count", 10))
	var special := {
		"treasure": 1 if room_count >= 6 else 0,
		"event": 1 if room_count >= 8 else 0,
		"fork": 1 if bool(_node_data.get("has_fork", false)) else 0,
	}
	_floor_data = MapGenerator.generate_floor({
		"grid_width": 6,
		"grid_height": 6,
		"room_count": room_count,
		"room_pixel_size": ROOM_SIZE,
		"field_type": _field_type,
		"special_rooms": special,
	})
	for r_data in _floor_data.get("rooms", []):
		var room_inst: Room = ROOM_SCENE.instantiate() as Room
		room_container.add_child(room_inst)
		room_inst.position = r_data.get("world_pos", Vector2.ZERO)
		room_inst.setup(r_data, _field_type)
		_rooms_by_pos[r_data.get("grid_pos")] = room_inst

func _start_on_first_room() -> void:
	_path = _floor_data.get("path", [])
	if _path.is_empty():
		return
	_path_idx = 0
	var first_pos: Vector2i = _path[0]
	var first_room: Room = _rooms_by_pos.get(first_pos) as Room
	if first_room == null:
		return
	party_sprite.position = first_room.position + ROOM_SIZE * 0.5
	camera.position = party_sprite.position
	_trigger_room_enter(first_pos)
	_build_curve_to_next()

func _build_curve_to_next() -> void:
	if _path_idx + 1 >= _path.size():
		_current_curve = null
		return
	var from_pos: Vector2i = _path[_path_idx]
	var to_pos: Vector2i = _path[_path_idx + 1]
	var from_room: Room = _rooms_by_pos.get(from_pos) as Room
	var to_room: Room = _rooms_by_pos.get(to_pos) as Room
	if from_room == null or to_room == null:
		_current_curve = null
		return

	var to_center: Vector2 = to_room.position + ROOM_SIZE * 0.5
	var dir: Vector2i = to_pos - from_pos
	var from_exit: Vector2 = from_room.entry_point_for_direction(dir)
	var to_entry: Vector2 = to_room.entry_point_for_direction(-dir)

	_current_curve = Curve2D.new()
	_current_curve.bake_interval = 8.0

	# 방 내부 꼬물꼬물: 현재 위치 → 출구 경계 (웨이포인트 2~3개)
	var wiggle_amp := _wiggle_amount()
	var waypoint_count := 3
	var start_p: Vector2 = party_sprite.position
	_current_curve.add_point(start_p)
	for i in range(1, waypoint_count + 1):
		var t := float(i) / float(waypoint_count + 1)
		var base := start_p.lerp(from_exit, t)
		var offset := Vector2(
			randf_range(-wiggle_amp.x, wiggle_amp.x),
			randf_range(-wiggle_amp.y, wiggle_amp.y)
		)
		_current_curve.add_point(base + offset)
	_current_curve.add_point(from_exit)
	# 방 경계 → 다음 방 중앙
	_current_curve.add_point(to_entry)
	var next_wp_count := 2
	for i in range(1, next_wp_count + 1):
		var t2 := float(i) / float(next_wp_count + 1)
		var base2 := to_entry.lerp(to_center, t2)
		var offset2 := Vector2(
			randf_range(-wiggle_amp.x * 0.6, wiggle_amp.x * 0.6),
			randf_range(-wiggle_amp.y * 0.6, wiggle_amp.y * 0.6)
		)
		_current_curve.add_point(base2 + offset2)
	_current_curve.add_point(to_center)

	_curve_length = _current_curve.get_baked_length()
	_curve_progress = 0.0

func _wiggle_amount() -> Vector2:
	match _field_type:
		"plains": return Vector2(60, 60)
		"forest": return Vector2(90, 90)
		"dungeon": return Vector2(30, 30)
		"mountain": return Vector2(50, 110)
		_: return Vector2(60, 60)

func _process(delta: float) -> void:
	if _finished or _fork_waiting:
		return
	if not GameManager.is_moving:
		return
	if _current_curve == null:
		return
	_curve_progress += GameManager.move_speed * delta
	if _curve_progress >= _curve_length:
		party_sprite.position = _current_curve.sample_baked(_curve_length)
		camera.position = party_sprite.position
		_on_reach_next_room()
	else:
		party_sprite.position = _current_curve.sample_baked(_curve_progress)
		camera.position = party_sprite.position

func _on_reach_next_room() -> void:
	_path_idx += 1
	if _path_idx >= _path.size():
		_on_field_done()
		return
	var pos: Vector2i = _path[_path_idx]
	_trigger_room_enter(pos)
	if _finished or _fork_waiting:
		return
	_build_curve_to_next()

func _trigger_room_enter(pos: Vector2i) -> void:
	if _entered_rooms.has(pos):
		return
	_entered_rooms[pos] = true
	var room: Room = _rooms_by_pos.get(pos) as Room
	if room == null:
		return
	var rtype: String = room.room_type
	match rtype:
		"start":
			pass
		"normal":
			pass  # 전투는 BattleManager가 타이머로 처리
		"treasure":
			_spawn_treasure_event()
		"event":
			_spawn_story_event()
		"fork":
			_open_fork_choice()
		"exit":
			# 출구 방 진입 시 보스라면 보스 스폰
			if _is_boss and not _boss_spawned:
				_boss_spawned = true
				_spawn_boss_battle()

func _spawn_treasure_event() -> void:
	var ev := {"type": "treasure", "gold": 30 + randi() % 80}
	EventManager.spawn_event(ev)

func _spawn_story_event() -> void:
	var table_id := String(_node_data.get("event_table", "events_common"))
	var evs: Array = DataLoader.load_field_table(table_id).get("events", [])
	if evs.is_empty():
		return
	var total := 0
	for e in evs:
		total += int(e.get("weight", 1))
	var pick: int = randi() % maxi(1, total)
	var accum := 0
	for e in evs:
		accum += int(e.get("weight", 1))
		if pick < accum:
			EventManager.spawn_event(e)
			return

func _open_fork_choice() -> void:
	_fork_waiting = true
	var fork := FORK_CHOICE_SCENE.instantiate()
	var options: Array = _node_data.get("fork_options", [])
	if options.is_empty():
		options = [
			{"label": "그대로 진행", "route": "continue"},
			{"label": "잠시 쉬어간다 (HP 조금 회복)", "route": "rest"},
		]
	if fork.has_method("setup"):
		fork.setup(options)
	var container := get_tree().get_first_node_in_group("event_container")
	if container:
		container.add_child(fork)
	if fork.has_signal("option_selected"):
		fork.option_selected.connect(_on_fork_selected)

func _on_fork_selected(option: Dictionary) -> void:
	match String(option.get("route", "")):
		"rest":
			GameManager.heal(20)
		"dungeon":
			_insert_extra_nodes(option.get("extra_nodes", []))
		"event":
			_spawn_story_event()
		_:
			pass
	_fork_waiting = false
	_build_curve_to_next()

func _insert_extra_nodes(extra: Array) -> void:
	if extra.is_empty():
		return
	var nodes: Array = GameManager.current_journey.get("nodes", [])
	var idx := GameManager.current_node_index + 1
	for i in range(extra.size()):
		nodes.insert(idx + i, extra[i])
	GameManager.current_journey["nodes"] = nodes

func _spawn_boss_battle() -> void:
	BattleManager.stop_encounters()
	var boss_id := String(_node_data.get("boss_id", "demon_king"))
	var boss_data: Dictionary = DataLoader.load_enemy(boss_id)
	if boss_data.is_empty():
		return
	BattleManager.spawn_battle(boss_data)
	var active := BattleManager.active_battles
	if active.size() > 0:
		var w: Node = active[active.size() - 1]
		if w.has_signal("battle_finished"):
			w.battle_finished.connect(_on_boss_battle_finished)

func _on_boss_battle_finished(result: String) -> void:
	if result == "victory":
		_finished = true
		var main := get_tree().get_first_node_in_group("main")
		if main and main.has_method("show_victory"):
			main.show_victory()

func _on_field_done() -> void:
	if _finished:
		return
	if _is_boss:
		# 출구 방 진입 후 보스 전투 대기
		return
	_finished = true
	BattleManager.stop_encounters()
	BattleManager.clear_all_battles()
	var main := get_tree().get_first_node_in_group("main")
	if main and main.has_method("on_field_completed"):
		main.on_field_completed()
