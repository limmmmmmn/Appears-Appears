extends Node2D
## 필드 씬 컨트롤러 (리팩토링 버전)

signal battle_triggered(battle_enemies: Array)
signal exit_reached(next_destination: String)
signal field_cleared

const TEST_FIELD_ID := "field_1_1"
const TEST_MAP_TILES := Vector2i(60, 34) # 960x544 (tile 16 기준)
const TEST_TILE_SIZE := 16
const TEST_CAMERA_MARGIN_TILES := 0
const FIELD_OBJECT_SIZE := 16
const TEST_FLOOR_SOURCE_ID := 0
const TEST_WALL_SOURCE_ID := 2
const FIELD_TILE_TYPE_MAP := {
	0: "grass",
	1: "forest",
	2: "mountain",
	3: "water",
	4: "cave",
}
const TEST_PLAYER_SPAWN_RATIO := Vector2(0.18, 0.72)
const TEST_BOSS_SPAWN_RATIO := Vector2(0.82, 0.28)
const RECRUIT_TRIGGER_DISTANCE: float = 46.0
const RECRUIT_MIN_DIST_FROM_PLAYER: float = 170.0
const RECRUIT_MIN_DIST_FROM_BOSS: float = 130.0
const TREASURE_CHEST_RATIOS: Array[Vector2] = [
	Vector2(0.56, 0.46),
]
const TREASURE_LOCKED_CHEST_INDEX: int = -1
const TREASURE_KEY_ITEM_ID: String = "treasure_key"
const TREASURE_REWARD_RARITIES: Array[String] = ["uncommon", "magic", "rare"]
const SANCTUARY_SPAWN_RATIO := Vector2(0.5, 0.58)
const SANCTUARY_HEAL_RADIUS: float = 34.0
const SANCTUARY_HEAL_INTERVAL: float = 0.28
const SANCTUARY_HP_PER_TICK: int = 1
const SANCTUARY_MP_PER_TICK: int = 2
const RECRUIT_EVENT_LINE_INTERVAL: float = 1.55
const EVENT_WINDOW_SCENE := preload("res://scenes/event/EventWindow.tscn")
const REWARD_WINDOW_SCENE := preload("res://scenes/ui/RewardWindow.tscn")
const WINDOW_SHELL_SCRIPT := preload("res://scripts/ui/window/WindowShell.gd")
const FIELD_GRASS_SCENE := preload("res://scenes/field/Grass.tscn")
const DEFAULT_GRASS_TEXTURE := preload("res://assets/sprites/tilesets/grass.png")
const TEST_FIELD_OVERLAY_TEXTURE := preload("res://assets/sprites/maps/fieldmap_1.png")
const EVENT_WINDOW_MARGIN: float = 20.0
const EVENT_CENTER_SAFE_SIZE: float = 100.0
const EVENT_HUD_TOP_HEIGHT: float = 32.0
const EVENT_HUD_BOTTOM_HEIGHT: float = 60.0
const EVENT_WINDOW_SIZE_FALLBACK := Vector2(280, 200)
const FIELD_GRASS_A_CANDIDATE_PATHS: Array[String] = [
	"res://assets/sprites/tilesets/Grass_A.png",
	"res://assets/sprites/tilesets/grass_a.png",
	"res://assets/sprites/tilesets/GrassA.png",
]
const FIELD_GRASS_B_CANDIDATE_PATHS: Array[String] = [
	"res://assets/sprites/tilesets/Grass_B.png",
	"res://assets/sprites/tilesets/grass_b.png",
	"res://assets/sprites/tilesets/GrassB.png",
]
const FIELD_GRASS_MIN_COUNT: int = 420
const FIELD_GRASS_MAX_COUNT: int = 620
const FIELD_GRASS_PATCH_COUNT: int = 96
const FIELD_GRASS_PATCH_SIZE_MIN: int = 8
const FIELD_GRASS_PATCH_SIZE_MAX: int = 22
const FIELD_GRASS_PATCH_RADIUS_MIN_TILES: float = 1.3
const FIELD_GRASS_PATCH_RADIUS_MAX_TILES: float = 3.6
const FIELD_GRASS_FILL_ATTEMPTS: int = 1800
const FIELD_GRASS_MIN_SEPARATION: float = 2.3
const FIELD_GRASS_PADDING: float = 24.0
const FIELD_GRASS_MIN_DIST_PLAYER: float = 34.0
const FIELD_GRASS_MIN_DIST_ENEMY: float = 26.0
const FIELD_GRASS_MIN_DIST_OBJECT: float = 22.0
const FIELD_GRASS_INTERACT_RADIUS: float = 30.0
const FIELD_GRASS_INTERACT_STRENGTH: float = 1.0
const FIELD_GRASS_ENEMY_INTERACT_RADIUS: float = 26.0
const FIELD_GRASS_ENEMY_INTERACT_STRENGTH: float = 0.85
const FIELD_GRASS_WIND_INTERVAL_MIN: float = 2.4
const FIELD_GRASS_WIND_INTERVAL_MAX: float = 6.0
const FIELD_GRASS_WIND_DURATION_MIN: float = 1.1
const FIELD_GRASS_WIND_DURATION_MAX: float = 2.6
const FIELD_GRASS_WIND_PEAK_MIN: float = 0.35
const FIELD_GRASS_WIND_PEAK_MAX: float = 1.0
const FIELD_GRASS_BACK_Z: int = 36
const FIELD_GRASS_FRONT_Z: int = 108
const FIELD_GRASS_FRONT_RATIO: float = 0.42
const FIELD_GRASS_FRONT_ALPHA: float = 0.9
const FIELD_WORLD_OBJECT_Z: int = 48
const FIELD_WORLD_EFFECT_Z: int = 52

@export var spawn_point: Marker2D
@export var exit_area: Area2D
@export var tilemap: TileMapLayer

var party_leader: PartyMember
var party_followers: Array[PartyMember] = []
var field_enemies: Array[FieldEnemy] = []
var hud = null
var game_over_ui: GameOverUI

# 보스전 대기 데이터
var pending_boss_data: Dictionary = {}
var boss_reward_popup: CanvasLayer = null

# 씬 리소스
var party_leader_scene: PackedScene
var party_follower_scene: PackedScene
var field_enemy_scene: PackedScene
var hud_scene: PackedScene

# 분리된 시스템들
var spawner: EnemySpawner
var test_field_bounds: Rect2 = Rect2()

# 필드 동료 NPC
var recruit_npc_root: Node2D = null
var recruit_npc_label: Label = null
var recruit_npc_bubble: PanelContainer = null
var recruit_npc_bubble_base_y: float = -52.0
var recruit_npc_hero_id: String = ""
var recruit_dialog_active: bool = false
var recruit_float_t: float = 0.0
var recruit_retry_cooldown: float = 0.0
var recruit_followup_pending: bool = false
var recruit_followup_active: bool = false
var recruit_followup_hero_id: String = ""
var recruit_followup_lines: Array[String] = []
var recruit_event_active: bool = false
var recruit_event_layer: CanvasLayer = null
var recruit_event_window: BattleWindow = null
var recruit_event_on_complete: Callable = Callable()

# 보물상자
var field_treasure_chests: Array[Dictionary] = []
var reward_window_layer: CanvasLayer = null
var reward_window: RewardWindow = null
var pause_dim_layer: CanvasLayer = null
var pause_dim_rect: ColorRect = null
var pending_treasure_chest_index: int = -1
var treasure_interact_cooldown: float = 0.0
var sanctuary_root: Node2D = null
var sanctuary_area: Area2D = null
var sanctuary_tick_timer: float = 0.0
var field_grass_container: Node2D = null
var field_grass_nodes: Array = []
var field_grass_texture_a: Texture2D = null
var field_grass_texture_b: Texture2D = null
var grass_wind_strength: float = 0.0
var grass_wind_dir: float = 1.0
var grass_wind_active: bool = false
var grass_wind_timer: float = 0.0
var grass_wind_duration: float = 0.0
var grass_wind_peak: float = 0.0



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_scenes()
	_find_tilemap()
	_setup_test_field_layout()
	_setup_systems()
	_spawn_party()
	_apply_camera_limits()
	_spawn_field_enemies()
	_spawn_recruit_npc()
	_spawn_field_treasure_chests()
	_spawn_sanctuary()
	_spawn_field_grass()
	_ensure_pause_dim_overlay()
	_setup_exit()
	_connect_signals()
	
	if hud:
		hud.add_system_log("필드에 입장했다.")


func _process(_delta: float) -> void:
	_update_pause_dim_overlay()
	if get_tree().paused:
		# pause 중에는 필수 후속 처리만 유지
		_update_recruit_followup_dialog(_delta)
		return

	treasure_interact_cooldown = maxf(0.0, treasure_interact_cooldown - _delta)

	# 이동 기반 적 스폰 체크
	if spawner and not FieldManager.is_boss_field():
		spawner.update_movement_spawn(field_enemies)
		
		# 새로 스폰된 적에게 시그널 연결
		for enemy in field_enemies:
			if not enemy.player_contacted.is_connected(_on_field_enemy_contacted):
				enemy.player_contacted.connect(_on_field_enemy_contacted)

	_update_recruit_npc(_delta)
	_update_recruit_followup_dialog(_delta)
	_poll_treasure_chest_interaction()
	_update_sanctuary(_delta)
	_update_field_grass(_delta)


func _load_scenes() -> void:
	party_leader_scene = load("res://scenes/field/PartyMember.tscn")
	party_follower_scene = load("res://scenes/field/PartyMember.tscn")
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	hud_scene = load("res://scenes/ui/FieldHUD.tscn")
	field_grass_texture_a = _load_first_existing_texture(FIELD_GRASS_A_CANDIDATE_PATHS)
	field_grass_texture_b = _load_first_existing_texture(FIELD_GRASS_B_CANDIDATE_PATHS)
	if field_grass_texture_a == null:
		field_grass_texture_a = DEFAULT_GRASS_TEXTURE
	if field_grass_texture_b == null:
		field_grass_texture_b = field_grass_texture_a


func _load_first_existing_texture(candidate_paths: Array[String]) -> Texture2D:
	for path in candidate_paths:
		if not ResourceLoader.exists(path):
			continue
		var tex_res := load(path)
		if tex_res is Texture2D:
			return tex_res as Texture2D
	return null


func _find_tilemap() -> void:
	if tilemap:
		return

	var named_tilemap := get_node_or_null("TileMapLayer")
	if named_tilemap is TileMapLayer:
		tilemap = named_tilemap as TileMapLayer
		return
	
	# 직접 자식에서 찾기
	for child in get_children():
		if child is TileMapLayer:
			tilemap = child
			return
	
	# 재귀 탐색
	tilemap = _find_node_recursive(self, TileMapLayer) as TileMapLayer


func _find_node_recursive(node: Node, type) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var found = _find_node_recursive(child, type)
		if found:
			return found
	return null


func _is_test_field() -> bool:
	return FieldManager != null and FieldManager.current_field_id == TEST_FIELD_ID


func _setup_test_field_layout() -> void:
	if not _is_test_field():
		return

	var collision_map := get_node_or_null("TileMapLayer") as TileMapLayer
	var background_map := get_node_or_null("TileMapLayerBg") as TileMapLayer

	if collision_map:
		_build_test_map(collision_map, true)
		tilemap = collision_map
	if background_map:
		_build_test_map(background_map, false)

	var map_size_px := Vector2(TEST_MAP_TILES.x * TEST_TILE_SIZE, TEST_MAP_TILES.y * TEST_TILE_SIZE)
	test_field_bounds = Rect2(Vector2.ZERO, map_size_px)
	_apply_test_field_overlay(map_size_px)

	var bg_rect := get_node_or_null("Background") as ColorRect
	if bg_rect:
		bg_rect.offset_right = map_size_px.x
		bg_rect.offset_bottom = map_size_px.y

	var player_spawn := map_size_px * TEST_PLAYER_SPAWN_RATIO
	if spawn_point:
		spawn_point.global_position = player_spawn

	var preview_player := get_node_or_null("Player") as Node2D
	if preview_player:
		preview_player.global_position = player_spawn


func _apply_test_field_overlay(map_size_px: Vector2) -> void:
	var existing := get_node_or_null("FieldMapOverlay") as Sprite2D
	if existing:
		existing.queue_free()

	if TEST_FIELD_OVERLAY_TEXTURE == null:
		return

	var overlay := Sprite2D.new()
	overlay.name = "FieldMapOverlay"
	overlay.centered = false
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.texture = TEST_FIELD_OVERLAY_TEXTURE
	overlay.position = Vector2.ZERO
	overlay.z_index = 8
	add_child(overlay)

	var tex_size: Vector2 = TEST_FIELD_OVERLAY_TEXTURE.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		overlay.scale = Vector2(map_size_px.x / tex_size.x, map_size_px.y / tex_size.y)


func get_test_field_boss_position() -> Vector2:
	if not _is_test_field():
		return Vector2.ZERO
	var bounds := _get_map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Vector2.ZERO
	return bounds.position + bounds.size * TEST_BOSS_SPAWN_RATIO


func _build_test_map(layer: TileMapLayer, add_border_wall: bool) -> void:
	layer.clear()
	for y in range(TEST_MAP_TILES.y):
		for x in range(TEST_MAP_TILES.x):
			var source_id := TEST_FLOOR_SOURCE_ID
			if add_border_wall and (x == 0 or y == 0 or x == TEST_MAP_TILES.x - 1 or y == TEST_MAP_TILES.y - 1):
				source_id = TEST_WALL_SOURCE_ID
			layer.set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)


func _apply_camera_limits() -> void:
	if not party_leader:
		return

	var camera := _ensure_player_camera()
	if not camera:
		return

	# 카메라 제한 제거: 항상 플레이어를 추적
	camera.limit_enabled = false


func _ensure_player_camera() -> Camera2D:
	if not party_leader:
		return null

	var camera := party_leader.get_node_or_null("Camera2D") as Camera2D
	if not camera:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		party_leader.add_child(camera)

	camera.enabled = true
	camera.make_current()
	return camera


func _get_map_bounds() -> Rect2:
	if test_field_bounds.size.x > 0.0 and test_field_bounds.size.y > 0.0:
		return test_field_bounds

	if tilemap:
		var used_rect: Rect2i = tilemap.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0:
			var tile_size: Vector2 = Vector2(TEST_TILE_SIZE, TEST_TILE_SIZE)
			if tilemap.tile_set:
				tile_size = Vector2(tilemap.tile_set.tile_size)
			return Rect2(Vector2(used_rect.position) * tile_size, Vector2(used_rect.size) * tile_size)

	return Rect2()


func _setup_systems() -> void:
	# HUD - 씬에 이미 존재하는 HUD 노드를 재사용하거나 새로 생성
	var existing_hud = get_node_or_null("HUD")
	if existing_hud:
		hud = existing_hud as CanvasLayer
	else:
		# 혹시 다른 이름으로 존재할 경우 제거
		var old_hud = get_node_or_null("CanvasLayer")
		if old_hud:
			old_hud.queue_free()
		hud = hud_scene.instantiate() as CanvasLayer
		add_child(hud)
	if not hud.menu_pressed.is_connected(_on_menu_pressed):
		hud.menu_pressed.connect(_on_menu_pressed)
	if not hud.hero_recruited.is_connected(_on_hero_recruited):
		hud.hero_recruited.connect(_on_hero_recruited)
	
	# 게임오버 UI
	game_over_ui = GameOverUI.new()
	add_child(game_over_ui)
	game_over_ui.restart_pressed.connect(_on_restart_game)
	game_over_ui.quit_pressed.connect(_on_quit_game)
	
	# 스포너
	spawner = EnemySpawner.new()
	spawner.setup(self, tilemap)
	



func _connect_signals() -> void:
	if PartyManager and not PartyManager.party_wiped.is_connected(_on_party_wiped):
		PartyManager.party_wiped.connect(_on_party_wiped)

	if GameManager and not GameManager.game_over.is_connected(_on_party_wiped):
		GameManager.game_over.connect(_on_party_wiped)

	if BattleManager:
		if not BattleManager.elite_victory.is_connected(_on_elite_victory):
			BattleManager.elite_victory.connect(_on_elite_victory)
		if not BattleManager.boss_victory.is_connected(_on_boss_victory):
			BattleManager.boss_victory.connect(_on_boss_victory)
		if not BattleManager.all_battles_ended.is_connected(_on_all_battles_ended):
			BattleManager.all_battles_ended.connect(_on_all_battles_ended)
		# 보스전 관전 시스템
		if not BattleManager.boss_battle_started.is_connected(_on_boss_battle_started):
			BattleManager.boss_battle_started.connect(_on_boss_battle_started)
		if not BattleManager.boss_battle_ended.is_connected(_on_boss_battle_ended):
			BattleManager.boss_battle_ended.connect(_on_boss_battle_ended)
		# 필드 드롭 시스템
		if not BattleManager.field_drops_requested.is_connected(_on_field_drops_requested):
			BattleManager.field_drops_requested.connect(_on_field_drops_requested)


#=============================================================================
# 파티 스폰
#=============================================================================
func _spawn_party() -> void:
	var start_pos: Vector2 = _get_start_position()
	var party_members: Array = PartyManager.get_party() if PartyManager else []
	
	# 리더 생성
	party_leader = party_leader_scene.instantiate() as PartyMember
	add_child(party_leader)
	
	if party_members.size() > 0:
		party_leader.setup_as_leader(party_members[0], start_pos)
	else:
		party_leader.setup_as_leader(null, start_pos)
	
	# 팔로워 생성
	if party_members.size() > 1:
		# 트리에 있는지 확인 후 await
		if is_inside_tree():
			await get_tree().create_timer(0.05).timeout
		
		for i in range(1, party_members.size()):
			var follower: PartyMember = party_follower_scene.instantiate()
			add_child(follower)
			# 트리에 있는지 확인 후 await
			if follower.is_inside_tree():
				await follower.get_tree().process_frame
			follower.setup_as_follower(party_members[i], party_leader, i)
			party_followers.append(follower)
	
	SaveManager.last_field_position = Vector2.ZERO


func _get_start_position() -> Vector2:
	if _is_test_field():
		if spawn_point:
			return spawn_point.global_position
		var bounds := _get_map_bounds()
		return bounds.position + bounds.size * TEST_PLAYER_SPAWN_RATIO if bounds.size.x > 0.0 else Vector2(180, 390)

	var saved_pos: Vector2 = SaveManager.get_saved_field_position()
	if saved_pos != Vector2.ZERO:
		return saved_pos
	if spawn_point:
		return spawn_point.global_position
	return Vector2(100, 100)


#=============================================================================
# 적 스폰
#=============================================================================
func _spawn_field_enemies() -> void:
	spawner.spawn_initial_enemies(field_enemies)
	
	# 보스 로그
	if FieldManager.is_boss_field() and not field_enemies.is_empty():
		var boss = field_enemies[0]
		boss.player_contacted.connect(_on_field_enemy_contacted)
		var boss_data: Dictionary = DataManager.get_enemy(boss.enemy_id)
		if hud:
			hud.add_system_log("⚠ %s이(가) 앞을 막아서고 있다!" % boss_data.get("name", boss.enemy_id))
	else:
		# 일반 적 시그널 연결
		for enemy in field_enemies:
			enemy.player_contacted.connect(_on_field_enemy_contacted)


func _spawn_recruit_npc() -> void:
	if FieldManager.is_boss_field():
		return
	if not PartyManager or not DataManager:
		return
	if PartyManager.get_party().size() >= 4:
		return

	var hero_id: String = _pick_random_recruit_hero_id()
	if hero_id.is_empty():
		return

	var spawn_pos: Vector2 = _find_recruit_spawn_position()
	if spawn_pos == Vector2.ZERO:
		return

	recruit_npc_hero_id = hero_id
	recruit_npc_root = Node2D.new()
	recruit_npc_root.name = "RecruitNPC"
	recruit_npc_root.position = spawn_pos
	recruit_npc_root.z_index = FIELD_WORLD_OBJECT_Z
	add_child(recruit_npc_root)

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.position = Vector2(0, -12)
	if SpriteManager:
		sprite.sprite_frames = SpriteManager.get_hero_sprite_frames(hero_id)
		sprite.animation = "walk_down"
		sprite.frame = 1
		sprite.stop()
	recruit_npc_root.add_child(sprite)

	recruit_npc_bubble = PanelContainer.new()
	recruit_npc_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	recruit_npc_bubble.position = Vector2(-44, recruit_npc_bubble_base_y)
	var bubble_style := StyleBoxFlat.new()
	bubble_style.bg_color = Color(0.96, 0.96, 1.0, 0.95)
	bubble_style.border_width_left = 1
	bubble_style.border_width_top = 1
	bubble_style.border_width_right = 1
	bubble_style.border_width_bottom = 1
	bubble_style.border_color = Color(0.25, 0.28, 0.38, 1.0)
	bubble_style.corner_radius_top_left = 6
	bubble_style.corner_radius_top_right = 6
	bubble_style.corner_radius_bottom_left = 6
	bubble_style.corner_radius_bottom_right = 6
	bubble_style.content_margin_left = 8
	bubble_style.content_margin_right = 8
	bubble_style.content_margin_top = 4
	bubble_style.content_margin_bottom = 4
	recruit_npc_bubble.add_theme_stylebox_override("panel", bubble_style)
	recruit_npc_root.add_child(recruit_npc_bubble)

	recruit_npc_label = Label.new()
	recruit_npc_label.text = "도와줘!"
	recruit_npc_label.add_theme_font_size_override("font_size", 11)
	recruit_npc_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.12, 1.0))
	recruit_npc_bubble.add_child(recruit_npc_label)


func _pick_random_recruit_hero_id() -> String:
	var party_ids: Array[String] = []
	for hero in PartyManager.get_party():
		if hero:
			party_ids.append(hero.id)

	var available: Array[String] = []
	for hero_id in DataManager.get_all_hero_ids():
		var hid: String = str(hero_id)
		if hid not in party_ids:
			available.append(hid)

	if available.is_empty():
		return ""
	available.shuffle()
	return str(available[0])


func _find_recruit_spawn_position() -> Vector2:
	var bounds: Rect2 = _get_map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Vector2.ZERO

	var player_pos: Vector2 = party_leader.global_position if party_leader else bounds.get_center()
	var boss_pos := Vector2.ZERO
	for enemy in field_enemies:
		if is_instance_valid(enemy) and enemy.is_boss:
			boss_pos = enemy.global_position
			break

	for _i in range(80):
		var pos := Vector2(
			randf_range(bounds.position.x + 56.0, bounds.end.x - 56.0),
			randf_range(bounds.position.y + 56.0, bounds.end.y - 56.0)
		)
		if pos.distance_to(player_pos) < RECRUIT_MIN_DIST_FROM_PLAYER:
			continue
		if boss_pos != Vector2.ZERO and pos.distance_to(boss_pos) < RECRUIT_MIN_DIST_FROM_BOSS:
			continue
		var near_enemy: bool = false
		for enemy in field_enemies:
			if is_instance_valid(enemy) and pos.distance_to(enemy.global_position) < 72.0:
				near_enemy = true
				break
		if near_enemy:
			continue
		if not _can_place_recruit_npc_at(pos):
			continue
		return pos

	return Vector2.ZERO


func _can_place_recruit_npc_at(pos: Vector2) -> bool:
	if not tilemap:
		return true

	var cell: Vector2i = tilemap.local_to_map(pos)
	var source_id: int = tilemap.get_cell_source_id(cell)
	if source_id == -1:
		return true

	var tile_type: String = str(FIELD_TILE_TYPE_MAP.get(source_id, "grass"))
	return FieldManager.is_tile_walkable(tile_type)


func _update_recruit_npc(delta: float) -> void:
	if recruit_npc_root == null or not is_instance_valid(recruit_npc_root):
		return

	recruit_float_t += delta
	recruit_retry_cooldown = maxf(0.0, recruit_retry_cooldown - delta)
	if recruit_npc_bubble and is_instance_valid(recruit_npc_bubble):
		recruit_npc_bubble.position.y = recruit_npc_bubble_base_y + sin(recruit_float_t * 2.6) * 2.0

	if recruit_dialog_active or recruit_event_active:
		return

	if not party_leader:
		return

	var distance: float = party_leader.global_position.distance_to(recruit_npc_root.global_position)
	if distance <= RECRUIT_TRIGGER_DISTANCE and recruit_retry_cooldown <= 0.0:
		_start_recruit_dialog()


func _start_recruit_dialog() -> void:
	if recruit_dialog_active:
		return
	recruit_dialog_active = true
	var leader_hero_id: String = _get_party_leader_hero_id()
	var recruit_name: String = recruit_npc_hero_id
	var recruit_hero_data: Dictionary = DataManager.get_hero(recruit_npc_hero_id) if DataManager else {}
	if not recruit_hero_data.is_empty():
		recruit_name = str(recruit_hero_data.get("name", recruit_npc_hero_id))
	var leader_name: String = "리더"
	if PartyManager:
		var leader_hero: Hero = PartyManager.get_hero_by_id(leader_hero_id)
		if leader_hero != null:
			leader_name = leader_hero.hero_name

	var lines: Array[Dictionary] = [
		{"speaker": "right", "name": recruit_name, "text": "도, 도와줘...! 여기 너무 위험해!"},
		{"speaker": "left", "name": leader_name, "text": "괜찮아. 진정하고 상황부터 말해줘."},
		{"speaker": "right", "name": recruit_name, "text": "같이 가게 해줘. 나도 싸울 수 있어!"},
	]
	if recruit_npc_label and is_instance_valid(recruit_npc_label):
		recruit_npc_label.text = "..."
	_close_blocking_ui_for_recruit_followup()
	_start_recruit_event_dialog(leader_hero_id, recruit_npc_hero_id, lines, Callable(self, "_on_recruit_intro_dialog_finished"))


func _on_recruit_intro_dialog_finished() -> void:
	recruit_dialog_active = false
	_complete_recruit_dialog()


func _complete_recruit_dialog() -> void:
	if recruit_npc_hero_id.is_empty():
		return
	if not PartyManager:
		return

	var hero_name: String = recruit_npc_hero_id
	var hero_data: Dictionary = DataManager.get_hero(recruit_npc_hero_id)
	if not hero_data.is_empty():
		hero_name = str(hero_data.get("name", recruit_npc_hero_id))

	if PartyManager.add_hero_by_id(recruit_npc_hero_id):
		var recruited_id: String = recruit_npc_hero_id
		_on_hero_recruited(recruit_npc_hero_id)
		_show_field_notice("%s(이)가 동료가 되었다!" % hero_name, 1.6, Color(0.78, 1.0, 0.82))
		if is_instance_valid(recruit_npc_root):
			recruit_npc_root.queue_free()
		recruit_npc_root = null
		recruit_npc_bubble = null
		recruit_npc_label = null
		recruit_npc_hero_id = ""
		_schedule_recruit_followup_dialog(recruited_id, hero_name)
	else:
		if recruit_npc_label and is_instance_valid(recruit_npc_label):
			recruit_npc_label.text = "파티가 가득 찼어..."
		_show_field_notice("파티가 가득 차서 동료를 받을 수 없다.", 1.8, Color(1.0, 0.75, 0.75))
		recruit_retry_cooldown = 2.0


func _show_field_notice(message: String, duration: float = 1.5, color: Color = Color.WHITE) -> void:
	if hud and hud.has_method("_show_notice"):
		hud.call("_show_notice", message, duration, color)


func _schedule_recruit_followup_dialog(_hero_id: String, hero_name: String) -> void:
	recruit_followup_hero_id = _hero_id
	recruit_followup_lines = _build_recruit_followup_lines(hero_name)
	if recruit_followup_lines.is_empty():
		return
	recruit_followup_pending = true
	recruit_followup_active = false
	_try_start_recruit_followup_dialog()


func _build_recruit_followup_lines(hero_name: String) -> Array[String]:
	var lines: Array[String] = []
	lines.append("%s: 살았다... 정말 고마워." % hero_name)
	lines.append("%s: 주변 몬스터 동선은 내가 먼저 확인할게." % hero_name)
	lines.append("파티: 좋아, 이제 같이 움직이자.")
	return lines


func _try_start_recruit_followup_dialog() -> void:
	if not recruit_followup_pending:
		return
	if recruit_followup_active or recruit_dialog_active or recruit_event_active:
		return
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		return
	if get_tree().paused:
		# 장비창/메뉴로 pause된 경우 후속 대화 전에 닫아준다.
		_close_blocking_ui_for_recruit_followup()
		if get_tree().paused:
			return

	recruit_followup_pending = false
	recruit_followup_active = true
	var leader_hero_id: String = _get_party_leader_hero_id()
	var lines: Array[Dictionary] = _build_recruit_followup_event_lines()
	_start_recruit_event_dialog(
		leader_hero_id,
		recruit_followup_hero_id,
		lines,
		Callable(self, "_on_recruit_followup_dialog_finished")
	)


func _update_recruit_followup_dialog(_delta: float) -> void:
	if recruit_followup_pending:
		_try_start_recruit_followup_dialog()


func _on_recruit_followup_dialog_finished() -> void:
	recruit_followup_active = false
	recruit_followup_hero_id = ""
	recruit_followup_lines.clear()


func _get_party_leader_hero_id() -> String:
	if not PartyManager:
		return ""
	var party: Array = PartyManager.get_party()
	if party.is_empty():
		return ""
	var leader: Hero = party[0] as Hero
	if leader == null:
		return ""
	return leader.id


func _build_recruit_followup_event_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var leader_name: String = "리더"
	var leader_hero_id: String = _get_party_leader_hero_id()
	if PartyManager:
		var leader_hero: Hero = PartyManager.get_hero_by_id(leader_hero_id)
		if leader_hero != null:
			leader_name = leader_hero.hero_name

	for raw in recruit_followup_lines:
		var line: String = str(raw)
		var split_idx: int = line.find(":")
		if split_idx <= 0:
			lines.append({
				"speaker": "left",
				"name": leader_name,
				"text": line,
			})
			continue

		var speaker_name: String = line.substr(0, split_idx).strip_edges()
		var content: String = line.substr(split_idx + 1).strip_edges()
		var speaker_side: String = "left"
		if recruit_followup_hero_id != "" and speaker_name != "파티":
			speaker_side = "right"
		lines.append({
			"speaker": speaker_side,
			"name": speaker_name,
			"text": content,
		})
	return lines


func _start_recruit_event_dialog(left_hero_id: String, right_hero_id: String, lines: Array[Dictionary], on_complete: Callable) -> void:
	if lines.is_empty():
		if on_complete.is_valid():
			on_complete.call_deferred()
		return

	_close_recruit_event_dialog()
	recruit_event_on_complete = on_complete
	recruit_event_active = true
	recruit_event_window = EVENT_WINDOW_SCENE.instantiate() as BattleWindow
	if recruit_event_window == null:
		recruit_event_active = false
		if on_complete.is_valid():
			on_complete.call_deferred()
		return

	recruit_event_layer = CanvasLayer.new()
	recruit_event_layer.layer = 180
	recruit_event_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(recruit_event_layer)
	recruit_event_layer.add_child(recruit_event_window)

	recruit_event_window.position = _get_event_window_spawn_position()
	recruit_event_window.event_finished.connect(_on_recruit_event_window_finished, CONNECT_ONE_SHOT)
	recruit_event_window.setup_event_dialog(
		"동료 이벤트",
		left_hero_id,
		right_hero_id,
		lines,
		{"line_interval": RECRUIT_EVENT_LINE_INTERVAL}
	)


func _on_recruit_event_window_finished(_result: Dictionary) -> void:
	var finished_callback: Callable = recruit_event_on_complete
	recruit_event_active = false
	recruit_event_window = null
	if recruit_event_layer and is_instance_valid(recruit_event_layer):
		recruit_event_layer.queue_free()
	recruit_event_layer = null
	recruit_event_on_complete = Callable()
	if finished_callback.is_valid():
		finished_callback.call()


func _close_recruit_event_dialog() -> void:
	if recruit_event_window and is_instance_valid(recruit_event_window):
		recruit_event_window.close_event_window_immediate()
	recruit_event_window = null
	if recruit_event_layer and is_instance_valid(recruit_event_layer):
		recruit_event_layer.queue_free()
	recruit_event_layer = null
	recruit_event_active = false
	recruit_event_on_complete = Callable()


func _get_event_window_spawn_position() -> Vector2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var window_size: Vector2 = EVENT_WINDOW_SIZE_FALLBACK
	if recruit_event_window:
		var cm: Vector2 = recruit_event_window.custom_minimum_size
		if cm != Vector2.ZERO:
			window_size = cm
		elif recruit_event_window.size != Vector2.ZERO:
			window_size = recruit_event_window.size

	var existing_rects: Array[Rect2] = []
	if BattleManager:
		for bid in BattleManager.active_battles:
			var bd: Dictionary = BattleManager.active_battles[bid]
			var window_ref: Variant = bd.get("window")
			if window_ref != null and is_instance_valid(window_ref):
				var w: Control = window_ref as Control
				if w != null:
					existing_rects.append(Rect2(w.position, window_size))

	return WINDOW_SHELL_SCRIPT.calculate_spawn_position(
		window_size,
		viewport_size,
		existing_rects,
		EVENT_WINDOW_MARGIN,
		EVENT_HUD_TOP_HEIGHT,
		EVENT_HUD_BOTTOM_HEIGHT,
		EVENT_CENTER_SAFE_SIZE
	)


func _close_blocking_ui_for_recruit_followup() -> void:
	if hud == null:
		return

	if hud.has_method("close_blocking_ui"):
		hud.call("close_blocking_ui")
		return

	# 장비 화면이 열려 있으면 우선 닫는다.
	var eq_screen: Variant = hud.get("equipment_screen")
	if eq_screen != null and eq_screen.has_method("close") and bool(eq_screen.get("is_open")):
		eq_screen.call("close")

	# 일시정지 메뉴가 열려 있으면 닫는다.
	if hud.has_method("hide_pause_menu"):
		hud.call("hide_pause_menu")

	# 장착 연출 패널/우측 패널이 남아있으면 정리한다.
	if hud.has_method("_close_right_panel"):
		hud.call("_close_right_panel")
	var equip_notice_panel: Variant = hud.get("equip_notice_panel")
	if equip_notice_panel != null:
		equip_notice_panel.set("visible", false)
	var right_inventory_panel: Variant = hud.get("right_inventory_panel")
	if right_inventory_panel != null:
		right_inventory_panel.set("visible", false)
	var right_desc_panel: Variant = hud.get("right_desc_panel")
	if right_desc_panel != null:
		right_desc_panel.set("visible", false)
	hud.set("equip_notice_playing", false)
	hud.set("equip_notice_queue", [])

	# 전투가 없는데 pause가 남아 있으면 해제
	if get_tree().paused and BattleManager and BattleManager.get_active_battle_count() <= 0:
		if BattleManager.is_battle_paused:
			BattleManager.set_battle_paused(false)
		else:
			get_tree().paused = false


#=============================================================================
# 보물상자
#=============================================================================
func _spawn_field_treasure_chests() -> void:
	field_treasure_chests.clear()
	if not _is_test_field():
		return
	if FieldManager.is_boss_field():
		return

	var bounds: Rect2 = _get_map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	_ensure_reward_window()

	for i in range(TREASURE_CHEST_RATIOS.size()):
		var ratio: Vector2 = TREASURE_CHEST_RATIOS[i]
		var locked: bool = (i == TREASURE_LOCKED_CHEST_INDEX)
		var pos := bounds.position + bounds.size * ratio
		_create_treasure_chest(i, pos, locked)

	_show_field_notice("보물상자 1개가 배치되었다.", 1.6, Color(0.98, 0.9, 0.65))


func _spawn_sanctuary() -> void:
	if not _is_test_field():
		return
	if sanctuary_root != null and is_instance_valid(sanctuary_root):
		return

	var bounds: Rect2 = _get_map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	sanctuary_root = Node2D.new()
	sanctuary_root.name = "Sanctuary"
	sanctuary_root.position = bounds.position + bounds.size * SANCTUARY_SPAWN_RATIO
	sanctuary_root.z_index = FIELD_WORLD_OBJECT_Z
	add_child(sanctuary_root)

	var sprite := Sprite2D.new()
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = _build_field_object_texture("sanctuary")
	sanctuary_root.add_child(sprite)

	sanctuary_area = Area2D.new()
	sanctuary_area.name = "SanctuaryArea"
	sanctuary_area.monitoring = true
	sanctuary_area.monitorable = true
	sanctuary_area.collision_layer = 1
	sanctuary_area.collision_mask = 2
	sanctuary_root.add_child(sanctuary_area)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SANCTUARY_HEAL_RADIUS
	shape.shape = circle
	sanctuary_area.add_child(shape)

	sanctuary_tick_timer = SANCTUARY_HEAL_INTERVAL
	_show_field_notice("성소를 발견했다. 가까이 가면 HP/MP가 회복된다.", 1.5, Color(0.64, 0.9, 1.0))


func _build_field_object_texture(kind: String) -> Texture2D:
	var img := Image.create(FIELD_OBJECT_SIZE, FIELD_OBJECT_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	match kind:
		"treasure", "treasure_locked", "treasure_opened":
			for y in range(5, 14):
				for x in range(2, 14):
					var c := Color(0.62, 0.38, 0.12, 1.0)
					if y <= 7:
						c = Color(0.74, 0.46, 0.16, 1.0)
					if x == 2 or x == 13 or y == 5 or y == 13:
						c = c.darkened(0.22)
					img.set_pixel(x, y, c)
			if kind == "treasure_locked":
				for y in range(8, 11):
					for x in range(7, 9):
						img.set_pixel(x, y, Color(1.0, 0.86, 0.3, 1.0))
			elif kind == "treasure_opened":
				for y in range(3, 6):
					for x in range(2, 14):
						var oc := Color(0.72, 0.44, 0.16, 1.0)
						if x == 2 or x == 13 or y == 3 or y == 5:
							oc = oc.darkened(0.25)
						img.set_pixel(x, y, oc)
				for y in range(8, 12):
					for x in range(6, 10):
						img.set_pixel(x, y, Color(0.67, 1.0, 0.78, 1.0))
		"sanctuary":
			for y in range(3, 14):
				for x in range(6, 10):
					var c := Color(0.56, 0.78, 0.88, 1.0)
					if x == 6 or x == 9 or y == 3 or y == 13:
						c = c.darkened(0.22)
					img.set_pixel(x, y, c)
			for y in range(12, 15):
				for x in range(3, 13):
					var b := Color(0.45, 0.6, 0.68, 1.0)
					if x == 3 or x == 12 or y == 12 or y == 14:
						b = b.darkened(0.25)
					img.set_pixel(x, y, b)
			for y in range(1, 4):
				for x in range(6, 10):
					img.set_pixel(x, y, Color(0.35, 0.9, 1.0, 1.0))
		_:
			for y in range(2, 14):
				for x in range(2, 14):
					img.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1.0))

	return ImageTexture.create_from_image(img)


func _make_colored_rect_texture(w: int, h: int, color: Color) -> Texture2D:
	var img := Image.create(maxi(1, w), maxi(1, h), false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _ensure_pause_dim_overlay() -> void:
	if pause_dim_layer != null and is_instance_valid(pause_dim_layer):
		return
	pause_dim_layer = CanvasLayer.new()
	pause_dim_layer.name = "PauseDimLayer"
	pause_dim_layer.layer = 9
	pause_dim_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_dim_layer)

	pause_dim_rect = ColorRect.new()
	pause_dim_rect.name = "PauseDimRect"
	pause_dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_dim_rect.color = Color(0.0, 0.0, 0.0, 0.28)
	pause_dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_dim_rect.visible = false
	pause_dim_layer.add_child(pause_dim_rect)


func _update_pause_dim_overlay() -> void:
	if pause_dim_rect == null or not is_instance_valid(pause_dim_rect):
		return
	pause_dim_rect.visible = get_tree().paused


func _ensure_reward_window() -> void:
	if reward_window != null and is_instance_valid(reward_window):
		return

	if reward_window_layer == null or not is_instance_valid(reward_window_layer):
		reward_window_layer = CanvasLayer.new()
		reward_window_layer.layer = 170
		reward_window_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(reward_window_layer)

	reward_window = REWARD_WINDOW_SCENE.instantiate() as RewardWindow
	if reward_window == null:
		return
	reward_window.name = "RewardWindow"
	if not reward_window.item_selected.is_connected(_on_treasure_loot_selected):
		reward_window.item_selected.connect(_on_treasure_loot_selected)
	if reward_window_layer:
		reward_window_layer.add_child(reward_window)
	else:
		add_child(reward_window)


func _create_treasure_chest(chest_index: int, world_pos: Vector2, is_locked: bool) -> void:
	var root := Node2D.new()
	root.name = "TreasureChest_%d" % chest_index
	root.position = world_pos
	root.z_index = FIELD_WORLD_OBJECT_Z
	add_child(root)

	var icon := Sprite2D.new()
	icon.name = "Icon"
	icon.centered = true
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _build_field_object_texture("treasure_locked" if is_locked else "treasure")
	root.add_child(icon)

	var area := Area2D.new()
	area.name = "ContactArea"
	area.monitoring = true
	area.monitorable = true
	# PartyMember는 collision_layer=2 이므로 마스크를 맞춰야 body_entered가 동작한다.
	area.collision_layer = 1
	area.collision_mask = 2
	root.add_child(area)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	shape.position = Vector2.ZERO
	area.add_child(shape)

	if not area.body_entered.is_connected(_on_treasure_chest_body_entered.bind(chest_index)):
		area.body_entered.connect(_on_treasure_chest_body_entered.bind(chest_index))

	field_treasure_chests.append({
		"index": chest_index,
		"root": root,
		"icon": icon,
		"area": area,
		"locked": is_locked,
		"opened": false,
	})


func _on_treasure_chest_body_entered(body: Node2D, chest_index: int) -> void:
	if body == null or not body.is_in_group("party_leader"):
		return
	if chest_index < 0 or chest_index >= field_treasure_chests.size():
		return
	if pending_treasure_chest_index >= 0:
		return
	if reward_window != null and is_instance_valid(reward_window) and reward_window.visible:
		return

	var chest: Dictionary = field_treasure_chests[chest_index]
	if bool(chest.get("opened", false)):
		return

	if bool(chest.get("locked", false)):
		if InventoryManager == null or not InventoryManager.has_item(TREASURE_KEY_ITEM_ID, 1):
			_show_field_notice("잠겨 있다. 보물상자 열쇠가 필요하다.", 1.5, Color(1.0, 0.72, 0.72))
			return
		InventoryManager.remove_item(TREASURE_KEY_ITEM_ID, 1)
		_show_field_notice("열쇠를 사용해 잠긴 상자를 열었다!", 1.4, Color(0.82, 1.0, 0.86))

	_open_treasure_chest(chest_index)


func _poll_treasure_chest_interaction() -> void:
	if party_leader == null:
		return
	if treasure_interact_cooldown > 0.0:
		return
	if field_treasure_chests.is_empty():
		return

	for i in range(field_treasure_chests.size()):
		var chest: Dictionary = field_treasure_chests[i]
		if bool(chest.get("opened", false)):
			continue
		var root: Node2D = chest.get("root") as Node2D
		if root == null:
			continue
		if party_leader.global_position.distance_to(root.global_position) <= 24.0:
			treasure_interact_cooldown = 0.25
			_on_treasure_chest_body_entered(party_leader, i)
			return


func _open_treasure_chest(chest_index: int) -> void:
	if chest_index < 0 or chest_index >= field_treasure_chests.size():
		return

	_close_blocking_ui_for_recruit_followup()

	var chest: Dictionary = field_treasure_chests[chest_index]
	if bool(chest.get("opened", false)):
		return

	chest["opened"] = true
	field_treasure_chests[chest_index] = chest

	var icon: Sprite2D = chest.get("icon") as Sprite2D
	if icon:
		icon.texture = _build_field_object_texture("treasure_opened")
	var area: Area2D = chest.get("area") as Area2D
	if area:
		area.set_deferred("monitoring", false)

	var choices: Array[String] = _roll_treasure_reward_choices(3)
	if choices.is_empty():
		_show_field_notice("보상 풀이 비어 있다.", 1.2, Color(1.0, 0.75, 0.75))
		return

	pending_treasure_chest_index = chest_index
	_ensure_reward_window()
	if reward_window and is_instance_valid(reward_window):
		reward_window.set_title("보상윈도우")
		reward_window.call_deferred("show_loot_selection", choices)
	else:
		# UI 생성 실패 시 첫 번째 보상 지급
		_grant_treasure_reward(choices[0])
		pending_treasure_chest_index = -1


func _roll_treasure_reward_choices(count: int) -> Array[String]:
	var pool: Array[String] = DataManager.get_equipment_by_rarities(TREASURE_REWARD_RARITIES)
	if pool.is_empty():
		return []

	pool.shuffle()
	var result: Array[String] = []
	for equip_id in pool:
		result.append(str(equip_id))
		if result.size() >= count:
			break

	while result.size() < count:
		result.append(str(pool[randi() % pool.size()]))

	return result


func _on_treasure_loot_selected(item_id: String) -> void:
	var target_hero_id: String = ""
	if reward_window != null and is_instance_valid(reward_window) and reward_window.has_method("get_selected_hero_id"):
		target_hero_id = str(reward_window.call("get_selected_hero_id"))
	_grant_treasure_reward(item_id, target_hero_id)
	pending_treasure_chest_index = -1

	if _are_all_treasure_chests_opened():
		_show_field_notice("필드의 보물상자를 모두 열었다!", 1.6, Color(1.0, 0.9, 0.65))


func _grant_treasure_reward(item_id: String, target_hero_id: String = "") -> void:
	if item_id.is_empty():
		return

	var added: bool = false
	if InventoryManager:
		added = InventoryManager.add_item(item_id, 1)
	else:
		return

	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(data.get("name", item_id))
	if not added:
		_show_field_notice("보상을 획득하지 못했다: 인벤토리 확인 필요", 1.4, Color(1.0, 0.75, 0.75))
		return

	var equipped: bool = false
	var hero_name: String = ""
	if not target_hero_id.is_empty() and PartyManager:
		var hero: Hero = PartyManager.get_hero_by_id(target_hero_id)
		if hero != null and InventoryManager:
			hero_name = hero.hero_name
			equipped = InventoryManager.equip_item(hero, item_id, "")

	# 명시 장착 실패/미선택 시: 더 좋은 장비면 자동장착
	if not equipped and InventoryManager:
		equipped = InventoryManager.try_auto_equip(item_id)
		if equipped and PartyManager:
			var equipped_hero: Hero = _find_hero_equipped_item(item_id)
			if equipped_hero != null:
				hero_name = equipped_hero.hero_name

	if equipped:
		if hero_name.is_empty():
			_show_field_notice("획득: %s → 자동 장착 완료" % item_name, 1.5, Color(0.82, 1.0, 0.86))
		else:
			_show_field_notice("획득: %s → %s 자동 장착" % [item_name, hero_name], 1.5, Color(0.82, 1.0, 0.86))
	else:
		_show_field_notice("획득: %s" % item_name, 1.4, Color(0.88, 0.96, 1.0))
	if SaveManager:
		SaveManager.auto_save("보물상자 개봉")


func _find_hero_equipped_item(item_id: String) -> Hero:
	if item_id.is_empty() or not PartyManager:
		return null
	for hero_any in PartyManager.get_party():
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		for slot in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
			if str(hero.equipment.get(slot, "")) == item_id:
				return hero
	return null


func _are_all_treasure_chests_opened() -> bool:
	if field_treasure_chests.is_empty():
		return false
	for chest in field_treasure_chests:
		var chest_dict: Dictionary = chest as Dictionary
		if not bool(chest_dict.get("opened", false)):
			return false
	return true


func _update_sanctuary(delta: float) -> void:
	if sanctuary_root == null or not is_instance_valid(sanctuary_root):
		return
	if party_leader == null:
		return

	var dist: float = party_leader.global_position.distance_to(sanctuary_root.global_position)
	if dist > SANCTUARY_HEAL_RADIUS:
		sanctuary_tick_timer = SANCTUARY_HEAL_INTERVAL
		return

	sanctuary_tick_timer -= delta
	if sanctuary_tick_timer > 0.0:
		return
	sanctuary_tick_timer = SANCTUARY_HEAL_INTERVAL

	var healed_total: int = 0
	if PartyManager:
		var party: Array = PartyManager.get_party()
		for hero_any in party:
			var hero: Hero = hero_any as Hero
			if hero == null or hero.is_dead:
				continue
			healed_total += hero.heal(SANCTUARY_HP_PER_TICK)
			hero.skill_action_timer = minf(
				hero.skill_action_timer + float(SANCTUARY_MP_PER_TICK) * 0.08,
				hero.get_skill_action_delay()
			)
		PartyManager.party_changed.emit()

	_spawn_sanctuary_particle(Color(1.0, 0.45, 0.65, 0.95))
	_spawn_sanctuary_particle(Color(0.35, 0.75, 1.0, 0.95))

	if healed_total > 0 and BattleManager:
		BattleManager.party_hp_changed.emit()


func _spawn_sanctuary_particle(color: Color) -> void:
	if sanctuary_root == null or not is_instance_valid(sanctuary_root):
		return
	var particle := Sprite2D.new()
	particle.centered = true
	particle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particle.texture = _make_colored_rect_texture(4, 4, color)
	particle.global_position = sanctuary_root.global_position + Vector2(
		randf_range(-6.0, 6.0),
		randf_range(-6.0, 2.0)
	)
	particle.z_index = FIELD_WORLD_EFFECT_Z
	add_child(particle)

	var start_pos: Vector2 = particle.global_position
	var tween := particle.create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		particle,
		"global_position",
		start_pos + Vector2(randf_range(-4.0, 4.0), -12.0),
		0.45
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(particle, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback(particle.queue_free)


#=============================================================================
# 필드 풀(Grass) 배치/업데이트
#=============================================================================
func _spawn_field_grass() -> void:
	field_grass_nodes.clear()
	if field_grass_container != null and is_instance_valid(field_grass_container):
		field_grass_container.queue_free()
	field_grass_container = null

	if not _is_test_field():
		return
	if FieldManager.is_boss_field():
		return

	var bounds: Rect2 = _get_map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	field_grass_container = Node2D.new()
	field_grass_container.name = "FieldGrass"
	field_grass_container.z_index = 0
	add_child(field_grass_container)
	var placed_positions: Array[Vector2] = []

	# 1) 군락(클러스터) 생성: 듬성듬성 대신 뭉쳐 보이게 배치
	for _patch_idx in range(FIELD_GRASS_PATCH_COUNT):
		if field_grass_nodes.size() >= FIELD_GRASS_MAX_COUNT:
			break
		var center := Vector2(
			randf_range(bounds.position.x + FIELD_GRASS_PADDING, bounds.end.x - FIELD_GRASS_PADDING),
			randf_range(bounds.position.y + FIELD_GRASS_PADDING, bounds.end.y - FIELD_GRASS_PADDING)
		)
		var patch_size: int = randi_range(FIELD_GRASS_PATCH_SIZE_MIN, FIELD_GRASS_PATCH_SIZE_MAX)
		var patch_radius_px: float = randf_range(
			FIELD_GRASS_PATCH_RADIUS_MIN_TILES * TEST_TILE_SIZE,
			FIELD_GRASS_PATCH_RADIUS_MAX_TILES * TEST_TILE_SIZE
		)

		for _i in range(patch_size):
			if field_grass_nodes.size() >= FIELD_GRASS_MAX_COUNT:
				break
			var angle: float = randf() * TAU
			var dist: float = patch_radius_px * pow(randf(), 1.45) # 중심부가 조금 더 조밀
			var spawn_pos := center + Vector2(cos(angle), sin(angle)) * dist
			spawn_pos += Vector2(randf_range(-2.0, 2.0), randf_range(-1.5, 1.5))
			if not _can_place_field_grass_at(spawn_pos):
				continue
			if not _is_grass_spacing_ok(spawn_pos, placed_positions):
				continue
			if _spawn_single_field_grass(spawn_pos):
				placed_positions.append(spawn_pos)

	# 2) 부족하면 랜덤 필로 최소 밀도 보장
	var fill_attempts: int = 0
	while field_grass_nodes.size() < FIELD_GRASS_MIN_COUNT and fill_attempts < FIELD_GRASS_FILL_ATTEMPTS:
		fill_attempts += 1
		var fill_pos := Vector2(
			randf_range(bounds.position.x + FIELD_GRASS_PADDING, bounds.end.x - FIELD_GRASS_PADDING),
			randf_range(bounds.position.y + FIELD_GRASS_PADDING, bounds.end.y - FIELD_GRASS_PADDING)
		)
		if not _can_place_field_grass_at(fill_pos):
			continue
		if not _is_grass_spacing_ok(fill_pos, placed_positions):
			continue
		if _spawn_single_field_grass(fill_pos):
			placed_positions.append(fill_pos)

	grass_wind_strength = 0.0
	grass_wind_active = false
	grass_wind_duration = 0.0
	grass_wind_peak = 0.0
	grass_wind_timer = randf_range(FIELD_GRASS_WIND_INTERVAL_MIN, FIELD_GRASS_WIND_INTERVAL_MAX)
	grass_wind_dir = -1.0 if randi() % 2 == 0 else 1.0


func _spawn_single_field_grass(spawn_pos: Vector2) -> bool:
	if field_grass_container == null or not is_instance_valid(field_grass_container):
		return false
	if field_grass_nodes.size() >= FIELD_GRASS_MAX_COUNT:
		return false
	var grass_node := FIELD_GRASS_SCENE.instantiate()
	if not (grass_node is Node2D):
		return false
	var grass := grass_node as Node2D
	grass.position = spawn_pos
	var front_layer: bool = randf() < FIELD_GRASS_FRONT_RATIO
	if grass is CanvasItem:
		var c := grass as CanvasItem
		c.z_index = FIELD_GRASS_FRONT_Z if front_layer else FIELD_GRASS_BACK_Z
		var alpha: float = FIELD_GRASS_FRONT_ALPHA if front_layer else 1.0
		c.modulate = Color(1.0, 1.0, 1.0, alpha)
	field_grass_container.add_child(grass)
	if grass.has_method("set_grass_textures"):
		grass.call("set_grass_textures", field_grass_texture_a, field_grass_texture_b)
	if grass.has_method("set_global_wind"):
		grass.call("set_global_wind", grass_wind_strength, grass_wind_dir)
	field_grass_nodes.append(grass)
	return true


func _is_grass_spacing_ok(spawn_pos: Vector2, placed_positions: Array[Vector2]) -> bool:
	for p in placed_positions:
		if p.distance_to(spawn_pos) < FIELD_GRASS_MIN_SEPARATION:
			return false
	return true


func _can_place_field_grass_at(world_pos: Vector2) -> bool:
	var tile_center := world_pos + Vector2(TEST_TILE_SIZE * 0.5, TEST_TILE_SIZE * 0.5)
	if not _is_walkable_tile_at_world(tile_center):
		return false

	if party_leader and world_pos.distance_to(party_leader.global_position) < FIELD_GRASS_MIN_DIST_PLAYER:
		return false

	if recruit_npc_root != null and is_instance_valid(recruit_npc_root):
		if world_pos.distance_to(recruit_npc_root.global_position) < FIELD_GRASS_MIN_DIST_OBJECT:
			return false

	if sanctuary_root != null and is_instance_valid(sanctuary_root):
		if world_pos.distance_to(sanctuary_root.global_position) < FIELD_GRASS_MIN_DIST_OBJECT + 8.0:
			return false

	for enemy_any in field_enemies:
		var enemy: FieldEnemy = enemy_any as FieldEnemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		if world_pos.distance_to(enemy.global_position) < FIELD_GRASS_MIN_DIST_ENEMY:
			return false

	for chest_any in field_treasure_chests:
		var chest: Dictionary = chest_any as Dictionary
		var root: Node2D = chest.get("root", null) as Node2D
		if root == null or not is_instance_valid(root):
			continue
		if world_pos.distance_to(root.global_position) < FIELD_GRASS_MIN_DIST_OBJECT:
			return false

	return true


func _is_walkable_tile_at_world(world_pos: Vector2) -> bool:
	if tilemap == null:
		return true
	var cell: Vector2i = tilemap.local_to_map(world_pos)
	var source_id: int = tilemap.get_cell_source_id(cell)
	if source_id == -1:
		return true
	var tile_type: String = str(FIELD_TILE_TYPE_MAP.get(source_id, "grass"))
	return FieldManager.is_tile_walkable(tile_type)


func _update_field_grass(delta: float) -> void:
	if field_grass_nodes.is_empty():
		return

	_update_field_grass_wind(delta)

	var actor_pos_list: Array[Vector2] = []
	var actor_vel_list: Array[Vector2] = []
	var actor_radius_list: Array[float] = []
	var actor_strength_list: Array[float] = []
	if party_leader:
		var p_speed := party_leader.velocity.length()
		actor_pos_list.append(party_leader.global_position)
		actor_vel_list.append(party_leader.velocity)
		actor_radius_list.append(FIELD_GRASS_INTERACT_RADIUS + clampf(p_speed * 0.08, 0.0, 12.0))
		actor_strength_list.append(FIELD_GRASS_INTERACT_STRENGTH + clampf(p_speed / 55.0, 0.0, 1.2))

	for enemy_any in field_enemies:
		var enemy: FieldEnemy = enemy_any as FieldEnemy
		if enemy == null or not is_instance_valid(enemy):
			continue
		var e_speed := enemy.velocity.length()
		actor_pos_list.append(enemy.global_position)
		actor_vel_list.append(enemy.velocity)
		actor_radius_list.append(FIELD_GRASS_ENEMY_INTERACT_RADIUS + clampf(e_speed * 0.08, 0.0, 9.0))
		actor_strength_list.append(FIELD_GRASS_ENEMY_INTERACT_STRENGTH + clampf(e_speed / 85.0, 0.0, 0.8))

	for i in range(field_grass_nodes.size() - 1, -1, -1):
		var node_ref = field_grass_nodes[i]
		if node_ref == null or not is_instance_valid(node_ref):
			field_grass_nodes.remove_at(i)
			continue
		if node_ref.has_method("set_global_wind"):
			node_ref.call("set_global_wind", grass_wind_strength, grass_wind_dir)
		if not node_ref.has_method("apply_player_influence"):
			continue

		var grass_node: Node2D = node_ref as Node2D
		if grass_node == null:
			continue

		var grass_world_pos: Vector2 = grass_node.global_position + Vector2(TEST_TILE_SIZE * 0.5, TEST_TILE_SIZE * 0.5)
		var best_idx: int = -1
		var best_effect: float = 0.0
		for j in range(actor_pos_list.size()):
			var radius: float = actor_radius_list[j]
			if radius <= 0.0:
				continue
			var dist: float = grass_world_pos.distance_to(actor_pos_list[j])
			if dist > radius:
				continue
			var effect: float = (1.0 - dist / radius) * actor_strength_list[j]
			if effect > best_effect:
				best_effect = effect
				best_idx = j

		if best_idx >= 0:
			node_ref.call(
				"apply_player_influence",
				actor_pos_list[best_idx],
				actor_vel_list[best_idx],
				actor_radius_list[best_idx],
				actor_strength_list[best_idx],
				delta
			)
		else:
			# 근처 대상이 없으면 접촉 굴절을 빠르게 풀어줌
			node_ref.call(
				"apply_player_influence",
				Vector2.ZERO,
				Vector2.ZERO,
				0.0,
				0.0,
				delta
			)


func _update_field_grass_wind(delta: float) -> void:
	if grass_wind_active:
		grass_wind_timer += delta
		var t := clampf(grass_wind_timer / maxf(0.001, grass_wind_duration), 0.0, 1.0)
		# 0 -> 1 -> 0 부드러운 거스트 파형
		grass_wind_strength = sin(t * PI) * grass_wind_peak
		if t >= 1.0:
			grass_wind_active = false
			grass_wind_strength = 0.0
			grass_wind_timer = randf_range(FIELD_GRASS_WIND_INTERVAL_MIN, FIELD_GRASS_WIND_INTERVAL_MAX)
			grass_wind_dir = -1.0 if randi() % 2 == 0 else 1.0
		return

	grass_wind_timer -= delta
	if grass_wind_timer > 0.0:
		return

	grass_wind_active = true
	grass_wind_timer = 0.0
	grass_wind_duration = randf_range(FIELD_GRASS_WIND_DURATION_MIN, FIELD_GRASS_WIND_DURATION_MAX)
	grass_wind_peak = randf_range(FIELD_GRASS_WIND_PEAK_MIN, FIELD_GRASS_WIND_PEAK_MAX)
	grass_wind_dir = -1.0 if randi() % 2 == 0 else 1.0


#=============================================================================
# 출구/마을 설정
#=============================================================================
func _setup_exit() -> void:
	if not exit_area:
		exit_area = get_node_or_null("ExitArea")
	if exit_area and not exit_area.body_entered.is_connected(_on_exit_body_entered):
		exit_area.body_entered.connect(_on_exit_body_entered)
	
	# 위치 자동 저장 타이머
	var save_timer := Timer.new()
	save_timer.wait_time = 3.0
	save_timer.one_shot = false
	save_timer.timeout.connect(_save_field_position)
	add_child(save_timer)
	save_timer.start()


func _save_field_position() -> void:
	if party_leader and SaveManager:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_stage_id,
			FieldManager.current_field_id
		)
		SaveManager.auto_save("필드 위치 저장")


#=============================================================================
# 이벤트 핸들러
#=============================================================================
func _on_field_enemy_contacted(field_enemy: FieldEnemy) -> void:
	## 필드 적과 충돌 시 - 전투창 생성 (1~3마리)

	var enemy_data: Dictionary = DataManager.get_enemy(field_enemy.enemy_id)
	var enemy_name: String = str(enemy_data.get("name", field_enemy.enemy_id))

	# 충돌 위치 계산
	var collision_pos: Vector2 = field_enemy.global_position
	if party_leader:
		collision_pos = (field_enemy.global_position + party_leader.global_position) / 2

	var was_elite: bool = field_enemy.is_elite
	var was_boss: bool = field_enemy.is_boss
	var enemy_id: String = field_enemy.enemy_id
	var tile_type: String = field_enemy.tile_type
	var enemy_pos: Vector2 = field_enemy.global_position

	# 보스 접촉 시 특별 처리
	if was_boss:
		_handle_boss_contact(enemy_id, was_elite, collision_pos, field_enemy)
		return

	# 전투 에너미 생성 (1~3마리, 조우 몬스터 + 맵 합류 몬스터)
	var battle_enemies: Array = FieldManager.generate_battle_enemies(enemy_id, tile_type)

	# 로그
	if hud:
		var msg: String
		if field_enemy.is_elite:
			msg = "⭐ 엘리트 %s이(가) 나타났다!" % enemy_name
		else:
			msg = "%s이(가) 나타났다!" % enemy_name
		if battle_enemies.size() > 1:
			msg += " (+%d마리 합류)" % (battle_enemies.size() - 1)
		hud.add_battle_log(msg)

	# 리스폰 큐에 추가 (보스가 아닌 경우)
	if spawner:
		spawner.on_enemy_killed(tile_type, enemy_pos)

	# 적 멈추고 0.25초 후 사라짐
	field_enemies.erase(field_enemy)
	field_enemy.freeze_and_despawn(0.25)

	# 전투창 생성 (1~3마리 한 전투창)
	if BattleManager:
		BattleManager.add_enemy_to_battle(battle_enemies, self, was_elite, collision_pos)

	battle_triggered.emit(battle_enemies)


#=============================================================================
# 보스 접촉 처리
#=============================================================================
func _handle_boss_contact(enemy_id: String, is_elite: bool, collision_pos: Vector2, field_enemy: FieldEnemy) -> void:
	## 보스 접촉 시 처리
	# 플레이어 이동 정지
	if party_leader:
		party_leader.set_boss_battle_mode(true)

	# 보스 데이터 저장
	pending_boss_data = {
		"enemy_id": enemy_id,
		"is_elite": is_elite,
		"collision_pos": collision_pos,
		"field_enemy": field_enemy
	}

	# 누적 보상이 있으면 확인 팝업 표시
	var has_rewards: bool = false
	if hud and hud.has_method("has_unclaimed_rewards"):
		has_rewards = bool(hud.call("has_unclaimed_rewards"))
	elif BattleManager:
		var rewards: Dictionary = BattleManager.get_accumulated_rewards()
		has_rewards = int(rewards.get("gold", 0)) > 0 or int(rewards.get("exp", 0)) > 0 or not (rewards.get("items", []) as Array).is_empty()

	if has_rewards:
		_show_boss_reward_popup()
	else:
		# 보상이 없으면 바로 보스전 시작
		_start_boss_battle()


func _show_boss_reward_popup() -> void:
	## 보스전 전 보상 확인 팝업 표시
	if boss_reward_popup:
		boss_reward_popup.queue_free()

	boss_reward_popup = CanvasLayer.new()
	boss_reward_popup.layer = 100
	boss_reward_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(boss_reward_popup)

	get_tree().paused = true

	# 전체 화면 컨테이너
	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	boss_reward_popup.add_child(full_screen)

	# 어둡게 처리
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.7)
	full_screen.add_child(dimmer)

	# 중앙 패널
	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -160
	center_panel.offset_right = 160
	center_panel.offset_top = -100
	center_panel.offset_bottom = 100
	center_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.1, 0.2, 0.95)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(1.0, 0.5, 0.3)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 15
	panel_style.content_margin_bottom = 15
	center_panel.add_theme_stylebox_override("panel", panel_style)
	full_screen.add_child(center_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center_panel.add_child(vbox)

	# 제목
	var title := Label.new()
	title.text = "👑 보스 발견!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	vbox.add_child(title)

	# 설명
	var desc := Label.new()
	desc.text = "누적된 보상이 있습니다.\n보상을 받고 보스전에 돌입하시겠습니까?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(desc)

	# 보상 정보
	var rewards: Dictionary = BattleManager.get_accumulated_rewards()
	var reward_hbox := HBoxContainer.new()
	reward_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(reward_hbox)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: %d" % rewards.gold
	gold_lbl.add_theme_font_size_override("font_size", 11)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	reward_hbox.add_child(gold_lbl)

	# 버튼
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_hbox)

	var claim_btn := Button.new()
	claim_btn.text = "보상 받기"
	claim_btn.custom_minimum_size = Vector2(100, 35)
	claim_btn.add_theme_font_size_override("font_size", 12)
	claim_btn.focus_mode = Control.FOCUS_NONE
	var claim_style := StyleBoxFlat.new()
	claim_style.bg_color = Color(0.3, 0.5, 0.3)
	claim_style.corner_radius_top_left = 4
	claim_style.corner_radius_top_right = 4
	claim_style.corner_radius_bottom_left = 4
	claim_style.corner_radius_bottom_right = 4
	claim_style.border_width_left = 2
	claim_style.border_width_top = 2
	claim_style.border_width_right = 2
	claim_style.border_width_bottom = 2
	claim_style.border_color = Color.WHITE
	claim_btn.add_theme_stylebox_override("normal", claim_style)
	claim_btn.pressed.connect(_on_boss_reward_claim)
	btn_hbox.add_child(claim_btn)

	var skip_btn := Button.new()
	skip_btn.text = "포기하고 전투"
	skip_btn.custom_minimum_size = Vector2(100, 35)
	skip_btn.add_theme_font_size_override("font_size", 12)
	skip_btn.focus_mode = Control.FOCUS_NONE
	var skip_style := StyleBoxFlat.new()
	skip_style.bg_color = Color(0.4, 0.2, 0.2)
	skip_style.corner_radius_top_left = 4
	skip_style.corner_radius_top_right = 4
	skip_style.corner_radius_bottom_left = 4
	skip_style.corner_radius_bottom_right = 4
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	skip_btn.add_theme_color_override("font_color", Color(0.8, 0.6, 0.6))
	skip_btn.pressed.connect(_on_boss_reward_skip)
	btn_hbox.add_child(skip_btn)


func _on_boss_reward_claim() -> void:
	## 보상 받고 보스전 시작
	get_tree().paused = false
	if boss_reward_popup:
		boss_reward_popup.queue_free()
		boss_reward_popup = null

	# 보상 수령
	BattleManager.claim_accumulated_rewards()
	if hud:
		hud.add_system_log("보상을 획득했다!")

	_start_boss_battle()


func _on_boss_reward_skip() -> void:
	## 보상 포기하고 보스전 시작
	get_tree().paused = false
	if boss_reward_popup:
		boss_reward_popup.queue_free()
		boss_reward_popup = null

	# 보상 초기화
	BattleManager.reset_accumulated_rewards()
	if hud:
		hud.add_system_log("보상을 포기했다...")

	_start_boss_battle()


func _start_boss_battle() -> void:
	## 실제 보스전 시작
	if pending_boss_data.is_empty():
		return

	var enemy_id: String = pending_boss_data.get("enemy_id", "")
	var is_elite: bool = pending_boss_data.get("is_elite", false)
	var collision_pos: Vector2 = pending_boss_data.get("collision_pos", Vector2.ZERO)

	# 로그
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	var enemy_name: String = str(enemy_data.get("name", enemy_id))
	if hud:
		hud.add_system_log("👑 %s와(과)의 보스전 시작!" % enemy_name)

	# 보스는 전투 시작 시 필드에서 제거하지 않음.
	# (도주 시에도 맵에 남아있어야 하므로 승리 시점에만 제거)

	# 기존 전투창 모두 닫기
	BattleManager.close_all_battles()

	# 보스 전투 시작
	if BattleManager:
		BattleManager.start_boss_battle(enemy_id, self, is_elite, collision_pos)

	pending_boss_data.clear()
	battle_triggered.emit([enemy_id])


func _on_exit_body_entered(body: Node2D) -> void:
	if not body.is_in_group("party_leader"):
		return
	
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		if hud:
			hud.add_system_log("전투 중에는 출구를 사용할 수 없다!")
		return
	
	if FieldManager.is_boss_field() and field_enemies.size() > 0:
		if hud:
			hud.add_system_log("보스를 처치해야 진행할 수 있다!")
		return
	
	var next: String = FieldManager.get_next_destination()
	if hud:
		hud.add_system_log("다음 구역으로 이동한다...")
	
	exit_reached.emit(next)
	if GameManager:
		GameManager.go_to_next_from_field()


#=============================================================================
# 메뉴 & 게임오버
#=============================================================================
func _on_menu_pressed() -> void:
	if hud:
		hud.toggle_pause_menu()


func _on_title_pressed() -> void:
	if recruit_event_active:
		_close_recruit_event_dialog()
	if party_leader:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_stage_id,
			FieldManager.current_field_id
		)
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_party_wiped() -> void:
	if recruit_event_active:
		_close_recruit_event_dialog()
	spawner.stop_respawn()

	if BattleManager:
		BattleManager.close_all_battles()

	if game_over_ui:
		game_over_ui.show_game_over("파티가 전멸했습니다...\n기지로 이동합니다.")


func _on_restart_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_quit_game() -> void:
	get_tree().quit()


func _input(_event: InputEvent) -> void:
	pass  # ESC 처리는 FieldHUD._unhandled_input에서 담당


func _on_elite_victory(_battle_id: int) -> void:
	# 엘리트 보상은 누적 보상 시스템으로 처리됨
	pass


func _on_boss_victory(_battle_id: int) -> void:
	if hud:
		hud.add_system_log("🎉 보스를 처치했다!")
		hud.add_system_log("출구로 향해 다음 스테이지로 진행하자!")

	# 보스 처치 확정 시에만 필드 보스 제거
	for i in range(field_enemies.size() - 1, -1, -1):
		var enemy: FieldEnemy = field_enemies[i]
		if not is_instance_valid(enemy):
			continue
		if enemy.is_boss:
			field_enemies.remove_at(i)
			enemy.despawn()
			break

	spawner.stop_respawn()
	# 보스 보상은 누적 보상 시스템으로 처리됨


func _on_boss_battle_started(_battle_id: int) -> void:
	## 보스전 시작 - 모든 필드 적이 관전 모드로 전환
	var camera_rect: Rect2 = _get_camera_rect()

	for enemy in field_enemies:
		if is_instance_valid(enemy) and enemy.has_method("start_spectating"):
			enemy.start_spectating(camera_rect)

	if hud:
		hud.add_system_log("⚔️ 보스전 시작! 필드의 적들이 지켜보고 있다...")


func _on_boss_battle_ended(_battle_id: int) -> void:
	## 보스전 종료 - 모든 필드 적이 원래 행동으로 복귀, 플레이어 이동 복구
	# 플레이어 이동 복구
	if party_leader:
		party_leader.set_boss_battle_mode(false)

	# 필드 적 관전 종료
	for enemy in field_enemies:
		if is_instance_valid(enemy) and enemy.has_method("stop_spectating"):
			enemy.stop_spectating()
		if is_instance_valid(enemy) and enemy.is_boss:
			# 도주/패배 등 보스전 종료 후 다시 접촉 가능하도록 복구
			enemy.is_contacted = false


func _on_all_battles_ended() -> void:
	## 전투창이 모두 닫힌 뒤 동료 후속 대화가 있으면 시작
	_try_start_recruit_followup_dialog()


func _get_camera_rect() -> Rect2:
	## 현재 카메라 뷰 영역 반환
	var viewport_size: Vector2 = get_viewport_rect().size
	var camera: Camera2D = get_viewport().get_camera_2d()
	var player_pos: Vector2 = party_leader.global_position if party_leader else Vector2.ZERO

	if camera:
		var view_size: Vector2 = viewport_size / camera.zoom
		return Rect2(camera.global_position - view_size / 2, view_size)

	return Rect2(player_pos - viewport_size / 2, viewport_size)


#=============================================================================
# 필드 드롭 시스템
#=============================================================================
func _on_field_drops_requested(hp_orbs: int, mp_orbs: int, world_pos: Vector2, window_rect: Rect2) -> void:
	## 전투 종료 시 필드에 HP/MP 오브 드롭 스폰
	var drops: Array[Dictionary] = []
	var delay: float = 0.0
	var delay_step: float = 0.08

	# HP 오브
	for i in range(hp_orbs):
		drops.append({"type": FieldDrop.DropType.HP_ORB, "delay": delay})
		delay += delay_step

	# MP 오브
	for i in range(mp_orbs):
		drops.append({"type": FieldDrop.DropType.MP_ORB, "delay": delay})
		delay += delay_step

	# 전투창 스크린 영역 → 월드 좌표 변환
	var scatter_rect: Rect2
	if window_rect.size != Vector2.ZERO:
		var canvas_xform: Transform2D = get_viewport().get_canvas_transform()
		var inv_xform: Transform2D = canvas_xform.affine_inverse()
		var world_tl: Vector2 = inv_xform * window_rect.position
		var world_br: Vector2 = inv_xform * (window_rect.position + window_rect.size)
		scatter_rect = Rect2(world_tl, world_br - world_tl)
	else:
		# Fallback: 플레이어 위치 주변
		if world_pos == Vector2.ZERO and party_leader:
			world_pos = party_leader.global_position
		scatter_rect = Rect2(world_pos - Vector2(40, 30), Vector2(80, 60))

	# 드롭 스폰 (전투창 영역 내 랜덤 산개)
	for i in range(drops.size()):
		var data: Dictionary = drops[i]
		var drop := FieldDrop.new()
		drop.drop_type = data.type
		drop.spawn_delay = data.delay

		match data.type:
			FieldDrop.DropType.HP_ORB:
				drop.heal_amount = FieldDrop.HP_PER_ORB
			FieldDrop.DropType.MP_ORB:
				drop.mana_amount = FieldDrop.MP_PER_ORB

		# 전투창 영역 내 랜덤 위치
		var rand_x: float = randf_range(scatter_rect.position.x, scatter_rect.end.x)
		var rand_y: float = randf_range(scatter_rect.position.y, scatter_rect.end.y)
		drop.position = Vector2(rand_x, rand_y)
		drop.z_index = FIELD_WORLD_EFFECT_Z

		add_child(drop)


#=============================================================================
# 유틸리티
#=============================================================================
func get_remaining_enemies() -> int:
	return field_enemies.size()


func get_party_leader() -> PartyMember:
	return party_leader


func get_hud():
	return hud


func _on_hero_recruited(hero_id: String) -> void:
	## 영입된 영웅을 필드에 팔로워로 추가
	if not party_leader:
		return
	var party: Array = PartyManager.get_party()
	# 새로 추가된 영웅 찾기 (마지막 멤버)
	var hero_data: Hero = null
	for h in party:
		if h and h.id == hero_id:
			hero_data = h
			break
	if not hero_data:
		return
	var follower_index: int = party_followers.size() + 1
	var follower: PartyMember = party_follower_scene.instantiate()
	add_child(follower)
	follower.setup_as_follower(hero_data, party_leader, follower_index)
	party_followers.append(follower)
