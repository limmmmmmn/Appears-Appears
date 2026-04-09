extends Node
## MapGenerator: 아이작 방식 맵 생성.
## generate_floor(config) → {grid, rooms, rooms_by_pos, start_pos, exit_pos, path}

const DIRS: Array[Vector2i] = [
	Vector2i(0, -1),  # N
	Vector2i(1, 0),   # E
	Vector2i(0, 1),   # S
	Vector2i(-1, 0),  # W
]

func generate_floor(config: Dictionary) -> Dictionary:
	var grid_w := int(config.get("grid_width", 6))
	var grid_h := int(config.get("grid_height", 6))
	var target_count := int(config.get("room_count", 10))
	target_count = clampi(target_count, 4, grid_w * grid_h)
	var room_pixel_size: Vector2 = config.get("room_pixel_size", Vector2(640, 640))
	var special: Dictionary = config.get("special_rooms", {})

	var result: Dictionary = {}
	for attempt in 30:
		result = _try_generate(grid_w, grid_h, target_count)
		if int(result.get("room_count", 0)) >= target_count:
			break

	_assign_special_rooms(result, special)
	_compute_path(result)
	_compute_world_positions(result, room_pixel_size)
	return result

func _try_generate(w: int, h: int, target: int) -> Dictionary:
	var grid: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(0)
		grid.append(row)

	var rooms_by_pos: Dictionary = {}
	var start := Vector2i(1, h / 2)
	grid[start.y][start.x] = 1
	rooms_by_pos[start] = _make_room(start, "start")

	var queue: Array[Vector2i] = [start]
	var safety := 0
	while rooms_by_pos.size() < target and safety < 500:
		safety += 1
		if queue.is_empty():
			break
		queue.shuffle()
		var current: Vector2i = queue[0]
		queue.remove_at(0)
		var placed_any := false
		var dirs_shuffled := DIRS.duplicate()
		dirs_shuffled.shuffle()
		for d in dirs_shuffled:
			if rooms_by_pos.size() >= target:
				break
			var npos: Vector2i = current + d
			if npos.x < 0 or npos.x >= w or npos.y < 0 or npos.y >= h:
				continue
			if grid[npos.y][npos.x] != 0:
				continue
			# Count existing neighbors of the candidate
			var nb_count := 0
			for d2 in DIRS:
				var nn: Vector2i = npos + d2
				if nn.x < 0 or nn.x >= w or nn.y < 0 or nn.y >= h:
					continue
				if grid[nn.y][nn.x] != 0:
					nb_count += 1
			# Reject if it would create loops (more than 1 existing neighbor)
			if nb_count > 1:
				continue
			# Some randomness: 50% skip to encourage branching
			if randi() % 2 == 0 and rooms_by_pos.size() > 2:
				continue
			grid[npos.y][npos.x] = 1
			rooms_by_pos[npos] = _make_room(npos, "normal")
			queue.append(npos)
			queue.append(current)  # allow current to branch again
			placed_any = true
		if not placed_any and queue.is_empty():
			# Seed more from any existing room
			queue = rooms_by_pos.keys().duplicate()

	# Compute neighbor lists
	for pos in rooms_by_pos.keys():
		var r: Dictionary = rooms_by_pos[pos]
		var nbs: Array = []
		for d in DIRS:
			var n: Vector2i = pos + d
			if rooms_by_pos.has(n):
				nbs.append(n)
		r["neighbors"] = nbs

	return {
		"grid": grid,
		"rooms": rooms_by_pos.values(),
		"rooms_by_pos": rooms_by_pos,
		"start_pos": start,
		"exit_pos": start,
		"room_count": rooms_by_pos.size(),
	}

func _make_room(pos: Vector2i, type_str: String) -> Dictionary:
	return {
		"grid_pos": pos,
		"world_pos": Vector2.ZERO,
		"type": type_str,
		"neighbors": [],
	}

func _assign_special_rooms(result: Dictionary, special: Dictionary) -> void:
	var rooms_by_pos: Dictionary = result.get("rooms_by_pos", {})
	var start: Vector2i = result.get("start_pos", Vector2i.ZERO)

	# Find dead-ends (neighbors.size() == 1), excluding start
	var dead_ends: Array = []
	for r in result.get("rooms", []):
		if r.get("type") == "start":
			continue
		if (r.get("neighbors") as Array).size() <= 1:
			dead_ends.append(r)

	# Exit: farthest dead-end from start (by BFS distance)
	var distances := _bfs_distances(rooms_by_pos, start)
	var exit_room: Dictionary = {}
	var max_dist := -1
	for r in dead_ends:
		var pos: Vector2i = r.get("grid_pos")
		var d: int = int(distances.get(pos, 0))
		if d > max_dist:
			max_dist = d
			exit_room = r
	if not exit_room.is_empty():
		exit_room["type"] = "exit"
		result["exit_pos"] = exit_room.get("grid_pos")
		dead_ends.erase(exit_room)
	else:
		# No dead-end; use farthest of any room
		var max_d2 := -1
		var farthest: Dictionary = {}
		for r in result.get("rooms", []):
			if r.get("type") == "start":
				continue
			var d2: int = int(distances.get(r.get("grid_pos"), 0))
			if d2 > max_d2:
				max_d2 = d2
				farthest = r
		if not farthest.is_empty():
			farthest["type"] = "exit"
			result["exit_pos"] = farthest.get("grid_pos")

	dead_ends.shuffle()
	var t_need := int(special.get("treasure", 1))
	while t_need > 0 and dead_ends.size() > 0:
		var r: Dictionary = dead_ends.pop_back()
		r["type"] = "treasure"
		t_need -= 1

	var e_need := int(special.get("event", 1))
	while e_need > 0 and dead_ends.size() > 0:
		var r2: Dictionary = dead_ends.pop_back()
		r2["type"] = "event"
		e_need -= 1

	# Fork: a room with 2+ neighbors that is a normal room
	var f_need := int(special.get("fork", 0))
	if f_need > 0:
		for r3 in result.get("rooms", []):
			if r3.get("type") != "normal":
				continue
			if (r3.get("neighbors") as Array).size() >= 2:
				r3["type"] = "fork"
				f_need -= 1
				if f_need <= 0:
					break

func _bfs_distances(rooms_by_pos: Dictionary, start: Vector2i) -> Dictionary:
	var dist: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		var cur_d: int = int(dist[cur])
		var room: Dictionary = rooms_by_pos[cur]
		for n in room.get("neighbors", []):
			if dist.has(n):
				continue
			dist[n] = cur_d + 1
			queue.append(n)
	return dist

func _compute_path(result: Dictionary) -> void:
	var start: Vector2i = result.get("start_pos")
	var goal: Vector2i = result.get("exit_pos")
	var rooms_by_pos: Dictionary = result.get("rooms_by_pos", {})
	if not rooms_by_pos.has(start) or not rooms_by_pos.has(goal):
		result["path"] = []
		return
	var prev: Dictionary = {start: start}
	var queue: Array[Vector2i] = [start]
	var found := false
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		if cur == goal:
			found = true
			break
		var room: Dictionary = rooms_by_pos[cur]
		for n in room.get("neighbors", []):
			if prev.has(n):
				continue
			prev[n] = cur
			queue.append(n)
	var path: Array = []
	if found:
		var cur2: Vector2i = goal
		while cur2 != start:
			path.append(cur2)
			cur2 = prev[cur2]
		path.append(start)
		path.reverse()
	result["path"] = path

func _compute_world_positions(result: Dictionary, size: Vector2) -> void:
	for r in result.get("rooms", []):
		var gp: Vector2i = r.get("grid_pos")
		r["world_pos"] = Vector2(float(gp.x), float(gp.y)) * size
