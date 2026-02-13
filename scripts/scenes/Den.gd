extends Control
## Den(기지): 상단 정보 + 출발 버튼만 유지, 본문은 4x4 방 그리드

signal exit_requested

const GRID_COLS: int = 4
const GRID_ROWS: int = 4
const GRID_GAP: int = 10
const ROOM_RATIO: float = 1.5 # 3:2 (width:height)

const ROOM_BG: Color = Color(0.12, 0.11, 0.13)
const ROOM_BORDER: Color = Color(0.34, 0.32, 0.38)
const ROOM_PLACEHOLDER_TEXT: Color = Color(0.55, 0.55, 0.62)

const WALKER_MIN_SPEED: float = 16.0
const WALKER_MAX_SPEED: float = 34.0
const WALKER_MIN_TURN_TIME: float = 1.0
const WALKER_MAX_TURN_TIME: float = 3.0
const WALKER_IDLE_CHANCE: float = 0.32
const WALKER_IDLE_MIN_TIME: float = 0.45
const WALKER_IDLE_MAX_TIME: float = 1.4
const WALKER_SCALE: float = 1.6
const WALKER_BASE_SIZE: Vector2 = Vector2(16.0, 24.0)

var gold_label: Label = null
var body_container: MarginContainer = null
var rooms_grid: GridContainer = null
var room_cells: Array[PanelContainer] = []

# 1번 방(테스트): 영웅 랜덤 좌우 이동
var room_one_view: Control = null
var room_one_sky: ColorRect = null
var room_one_floor: ColorRect = null
var room_one_floor_line: ColorRect = null
var room_one_walkers: Array[Dictionary] = []


func _ready() -> void:
	if GameManager:
		GameManager.change_state(GameManager.GameState.DEN)
	_build_ui()
	_update_gold_display()
	if GameManager and GameManager.has_signal("gold_changed"):
		GameManager.gold_changed.connect(_on_gold_changed)
	if PartyManager and PartyManager.has_signal("party_changed"):
		PartyManager.party_changed.connect(_on_party_changed)
	resized.connect(_on_den_resized)
	_layout_rooms()
	call_deferred("_layout_rooms")
	_spawn_room_one_walkers()
	set_process(true)


func _process(delta: float) -> void:
	_update_room_one_walkers(delta)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_build_header(root)
	_build_rooms_grid(root)


func _build_header(parent: VBoxContainer) -> void:
	var header := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", style)
	parent.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	header.add_child(hbox)

	var title := Label.new()
	title.text = "🏰 기지"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	hbox.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var gold_icon := Label.new()
	gold_icon.text = "💰"
	gold_icon.add_theme_font_size_override("font_size", 16)
	hbox.add_child(gold_icon)

	gold_label = Label.new()
	gold_label.text = "0"
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	hbox.add_child(gold_label)

	var exit_btn := Button.new()
	exit_btn.text = "출발"
	exit_btn.custom_minimum_size = Vector2(74, 30)
	exit_btn.add_theme_font_size_override("font_size", 14)
	exit_btn.pressed.connect(_on_exit_pressed)
	hbox.add_child(exit_btn)


func _build_rooms_grid(parent: VBoxContainer) -> void:
	body_container = MarginContainer.new()
	body_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_container.add_theme_constant_override("margin_left", 16)
	body_container.add_theme_constant_override("margin_right", 16)
	body_container.add_theme_constant_override("margin_top", 16)
	body_container.add_theme_constant_override("margin_bottom", 16)
	parent.add_child(body_container)

	rooms_grid = GridContainer.new()
	rooms_grid.columns = GRID_COLS
	rooms_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rooms_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rooms_grid.add_theme_constant_override("h_separation", GRID_GAP)
	rooms_grid.add_theme_constant_override("v_separation", GRID_GAP)
	body_container.add_child(rooms_grid)

	room_cells.clear()
	for i in range(GRID_COLS * GRID_ROWS):
		var cell := _create_room_cell()
		rooms_grid.add_child(cell)
		room_cells.append(cell)
		if i == 0:
			_setup_room_one(cell)
		else:
			var placeholder := Label.new()
			placeholder.text = "빈 방"
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			placeholder.add_theme_font_size_override("font_size", 12)
			placeholder.add_theme_color_override("font_color", ROOM_PLACEHOLDER_TEXT)
			placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
			cell.add_child(placeholder)


func _create_room_cell() -> PanelContainer:
	var cell := PanelContainer.new()
	cell.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = ROOM_BG
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = ROOM_BORDER
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	cell.add_theme_stylebox_override("panel", style)
	return cell


func _setup_room_one(cell: PanelContainer) -> void:
	room_one_view = Control.new()
	room_one_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_one_view.clip_contents = true
	room_one_view.resized.connect(_layout_room_one)
	cell.add_child(room_one_view)

	room_one_sky = ColorRect.new()
	room_one_sky.color = Color(0.18, 0.17, 0.2)
	room_one_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_one_view.add_child(room_one_sky)

	room_one_floor = ColorRect.new()
	room_one_floor.color = Color(0.0, 0.0, 0.0, 0.0)
	room_one_floor.position = Vector2.ZERO
	room_one_floor.size = Vector2.ZERO
	room_one_view.add_child(room_one_floor)

	room_one_floor_line = ColorRect.new()
	room_one_floor_line.color = Color(0.5, 0.43, 0.3, 0.85)
	room_one_floor_line.position = Vector2.ZERO
	room_one_floor_line.size = Vector2.ZERO
	room_one_view.add_child(room_one_floor_line)

	var room_label := Label.new()
	room_label.text = "1번 방"
	room_label.position = Vector2(6, 4)
	room_label.add_theme_font_size_override("font_size", 10)
	room_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92, 0.85))
	room_one_view.add_child(room_label)


func _layout_rooms() -> void:
	if rooms_grid == null or body_container == null:
		return

	var area_size: Vector2 = body_container.size
	if area_size.x <= 64.0 or area_size.y <= 64.0:
		var vp: Vector2 = get_viewport_rect().size
		area_size = Vector2(maxf(0.0, vp.x - 32.0), maxf(0.0, vp.y - 110.0))
		if area_size.x <= 64.0 or area_size.y <= 64.0:
			return

	# 화면을 거의 채우되, 약간의 여백은 유지
	var fill_w: float = area_size.x * 0.93
	var fill_h: float = area_size.y * 0.9
	var avail_w: float = fill_w - float(GRID_GAP * (GRID_COLS - 1))
	var avail_h: float = fill_h - float(GRID_GAP * (GRID_ROWS - 1))
	var by_width: float = avail_w / float(GRID_COLS)
	var by_height: float = (avail_h / float(GRID_ROWS)) * ROOM_RATIO
	var cell_w: float = floor(minf(by_width, by_height))
	var cell_h: float = floor(cell_w / ROOM_RATIO)
	if cell_w < 96.0:
		cell_w = 96.0
		cell_h = floor(cell_w / ROOM_RATIO)

	for cell in room_cells:
		if cell and is_instance_valid(cell):
			cell.custom_minimum_size = Vector2(cell_w, cell_h)

	call_deferred("_layout_room_one")


func _layout_room_one() -> void:
	if room_one_view == null or room_one_floor == null:
		return
	var w: float = room_one_view.size.x
	var h: float = room_one_view.size.y
	if w <= 0.0 or h <= 0.0:
		return
	var floor_y: float = floor(h * 0.8)
	room_one_floor.position = Vector2(0.0, floor_y)
	room_one_floor.size = Vector2(w, 0.0)
	if room_one_floor_line:
		room_one_floor_line.position = Vector2(-1.0, floor_y - 1.0)
		room_one_floor_line.size = Vector2(w + 2.0, 2.0)
	_refresh_room_one_walker_bounds()


func _spawn_room_one_walkers() -> void:
	if room_one_view == null:
		return

	for walker in room_one_walkers:
		var node: AnimatedSprite2D = walker.get("node") as AnimatedSprite2D
		if node and is_instance_valid(node):
			node.queue_free()
	room_one_walkers.clear()

	if PartyManager == null:
		return
	var heroes: Array = []
	heroes.append_array(PartyManager.get_party())
	if PartyManager.has_method("get_bench_heroes"):
		heroes.append_array(PartyManager.get_bench_heroes())
	if heroes.is_empty():
		return

	var max_count: int = mini(6, heroes.size())
	for i in range(max_count):
		var hero: Hero = heroes[i] as Hero
		if hero == null:
			continue
		var walker := AnimatedSprite2D.new()
		walker.centered = false
		walker.scale = Vector2(WALKER_SCALE, WALKER_SCALE)
		var frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero.id) if SpriteManager else null
		if frames:
			walker.sprite_frames = frames
		room_one_view.add_child(walker)

		var dir: int = -1 if randf() < 0.5 else 1
		var anim_name: String = "walk_right" if dir > 0 else "walk_left"
		if walker.sprite_frames and walker.sprite_frames.has_animation(anim_name):
			walker.play(anim_name)
		var walker_size: Vector2 = WALKER_BASE_SIZE
		if walker.sprite_frames and walker.sprite_frames.has_animation("walk_right") and walker.sprite_frames.get_frame_count("walk_right") > 0:
			var frame_tex: Texture2D = walker.sprite_frames.get_frame_texture("walk_right", 0)
			if frame_tex:
				walker_size = frame_tex.get_size()
		walker_size *= WALKER_SCALE
		room_one_walkers.append({
			"node": walker,
			"dir": dir,
			"speed": randf_range(WALKER_MIN_SPEED, WALKER_MAX_SPEED),
			"turn_timer": randf_range(WALKER_MIN_TURN_TIME, WALKER_MAX_TURN_TIME),
			"is_idle": false,
			"idle_timer": 0.0,
			"min_x": 4.0,
			"max_x": 32.0,
			"y": 0.0,
			"w": walker_size.x,
			"h": walker_size.y,
			"spawn_index": i,
			"initialized": false,
		})

	call_deferred("_layout_room_one")


func _refresh_room_one_walker_bounds() -> void:
	if room_one_view == null:
		return
	if room_one_walkers.is_empty():
		return

	var floor_y: float = room_one_floor.position.y
	for i in range(room_one_walkers.size()):
		var w: Dictionary = room_one_walkers[i]
		var node: AnimatedSprite2D = w.get("node") as AnimatedSprite2D
		if node == null or not is_instance_valid(node):
			continue
		var min_x: float = 2.0
		var walker_w: float = float(w.get("w", WALKER_BASE_SIZE.x * WALKER_SCALE))
		var walker_h: float = float(w.get("h", WALKER_BASE_SIZE.y * WALKER_SCALE))
		var max_x: float = maxf(min_x + 1.0, room_one_view.size.x - walker_w - 2.0)
		var y: float = floor_y - walker_h + 8.0
		w["min_x"] = min_x
		w["max_x"] = max_x
		w["y"] = y
		var initialized: bool = bool(w.get("initialized", false))
		if not initialized:
			var count: int = maxi(1, room_one_walkers.size())
			var idx: int = int(w.get("spawn_index", i))
			var t: float = (float(idx) + 0.5) / float(count)
			var base_x: float = lerpf(min_x, max_x, t)
			var jitter: float = randf_range(-10.0, 10.0)
			node.position.x = clampf(base_x + jitter, min_x, max_x)
			w["initialized"] = true
		elif node.position.x < min_x or node.position.x > max_x:
			node.position.x = clampf(node.position.x, min_x, max_x)
		node.position.y = y
		var dir_now: int = int(w.get("dir", 1))
		_play_walker_anim(node, dir_now)
		room_one_walkers[i] = w


func _update_room_one_walkers(delta: float) -> void:
	if room_one_walkers.is_empty():
		return

	for i in range(room_one_walkers.size()):
		var w: Dictionary = room_one_walkers[i]
		var node: AnimatedSprite2D = w.get("node") as AnimatedSprite2D
		if node == null or not is_instance_valid(node):
			continue

		var prev_dir: int = int(w.get("dir", 1))
		var dir: int = prev_dir
		var speed: float = float(w.get("speed", WALKER_MIN_SPEED))
		var min_x: float = float(w.get("min_x", 4.0))
		var max_x: float = float(w.get("max_x", min_x + 1.0))
		var is_idle: bool = bool(w.get("is_idle", false))
		var idle_timer: float = float(w.get("idle_timer", 0.0))

		if is_idle:
			idle_timer -= delta
			if idle_timer <= 0.0:
				is_idle = false
				_play_walker_anim(node, dir, false)
		else:
			node.position.x += float(dir) * speed * delta
			if node.position.x <= min_x:
				node.position.x = min_x
				dir = 1
			elif node.position.x >= max_x:
				node.position.x = max_x
				dir = -1

			var turn_timer: float = float(w.get("turn_timer", 1.0)) - delta
			if turn_timer <= 0.0:
				if randf() < WALKER_IDLE_CHANCE:
					is_idle = true
					idle_timer = randf_range(WALKER_IDLE_MIN_TIME, WALKER_IDLE_MAX_TIME)
					_play_walker_anim(node, dir, true)
				else:
					if randf() < 0.35:
						dir *= -1
					_play_walker_anim(node, dir, false)
				turn_timer = randf_range(WALKER_MIN_TURN_TIME, WALKER_MAX_TURN_TIME)
			w["turn_timer"] = turn_timer

		if dir != prev_dir:
			_play_walker_anim(node, dir, is_idle)
		w["dir"] = dir
		w["is_idle"] = is_idle
		w["idle_timer"] = idle_timer
		room_one_walkers[i] = w


func _play_walker_anim(node: AnimatedSprite2D, dir: int, idle: bool = false) -> void:
	if node == null:
		return
	if node.sprite_frames == null:
		return
	var walk_anim: String = "walk_right" if dir > 0 else "walk_left"
	var idle_anim: String = "idle_right" if dir > 0 else "idle_left"
	if idle and node.sprite_frames.has_animation(idle_anim):
		if node.animation != idle_anim or not node.is_playing():
			node.play(idle_anim)
		return
	if idle:
		if node.sprite_frames.has_animation(walk_anim):
			if node.animation != walk_anim:
				node.play(walk_anim)
			node.stop()
		return
	if node.sprite_frames.has_animation(walk_anim):
		if node.animation != walk_anim or not node.is_playing():
			node.play(walk_anim)


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = str(GameManager.gold)


func _on_gold_changed(_new_gold: int) -> void:
	_update_gold_display()


func _on_party_changed() -> void:
	_spawn_room_one_walkers()


func _on_den_resized() -> void:
	_layout_rooms()


func _on_exit_pressed() -> void:
	exit_requested.emit()
	GameManager.go_to_field()
