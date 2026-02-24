extends Node2D
## 필드 씬 컨트롤러 (리팩토링 버전)

signal battle_triggered(battle_enemies: Array)
signal exit_reached(next_destination: String)
signal town_entrance_entered(next_town_area_id: String)
signal field_cleared

const FIELD_TILE_SIZE := 16
const FIELD_TILE_TYPE_MAP := {
	0: "grass",
	1: "desert",
	2: "forest",
	3: "hill",
	4: "mountain",
	5: "water",
	6: "bridge",
	7: "cave",
	8: "shiren",
	9: "castle",
	10: "town",
}
const RECRUIT_TRIGGER_DISTANCE: float = 46.0
const RECRUIT_MIN_DIST_FROM_PLAYER: float = 170.0
const RECRUIT_MIN_DIST_FROM_BOSS: float = 130.0
const TREASURE_CHEST_RATIOS: Array[Vector2] = [
	Vector2(0.56, 0.46),
]
const TREASURE_LOCKED_CHEST_INDEX: int = -1
const SANCTUARY_SPAWN_RATIO := Vector2(0.5, 0.58)
const SANCTUARY_HEAL_RADIUS: float = 34.0
const SANCTUARY_HEAL_INTERVAL: float = 0.28
const SANCTUARY_HP_PER_TICK: int = 1
const RECRUIT_EVENT_LINE_INTERVAL: float = 1.55
const EVENT_WINDOW_SCENE := preload("res://scenes/event/EventWindow.tscn")
const REWARD_WINDOW_SCENE := preload("res://scenes/ui/RewardWindow.tscn")
const WINDOW_SHELL_SCRIPT := preload("res://scripts/ui/window/WindowShell.gd")
const FIELD_LAYOUT_HELPER_SCRIPT := preload("res://scripts/scenes/field/FieldLayoutHelper.gd")
const FIELD_PARTY_CHATTER_CONTROLLER_SCRIPT := preload("res://scripts/scenes/field/FieldPartyChatterController.gd")
const FIELD_PAUSE_OVERLAY_CONTROLLER_SCRIPT := preload("res://scripts/scenes/field/FieldPauseOverlayController.gd")
const FIELD_DROP_CONTROLLER_SCRIPT := preload("res://scripts/scenes/field/FieldDropController.gd")
const FIELD_TREASURE_CONTROLLER_SCRIPT := preload("res://scripts/scenes/field/FieldTreasureController.gd")
const FIELD_BOSS_CONTROLLER_SCRIPT := preload("res://scripts/scenes/field/FieldBossController.gd")
const RECRUIT_NPC_SCENE := preload("res://scenes/field/RecruitNPC.tscn")
const EVENT_WINDOW_MARGIN: float = 20.0
const EVENT_CENTER_SAFE_SIZE: float = 100.0
const EVENT_HUD_TOP_HEIGHT: float = 32.0
const EVENT_HUD_BOTTOM_HEIGHT: float = 60.0
const EVENT_WINDOW_SIZE_FALLBACK := Vector2(280, 200)
const FIELD_WORLD_OBJECT_Z: int = 48
const FIELD_WORLD_EFFECT_Z: int = 52
const BOSS_TRINKET_CHOICE_COUNT: int = 3

@export var spawn_point: Marker2D
@export var boss_spawn_point: Marker2D
@export var exit_area: Area2D
@export var tilemap_bg: TileMapLayer
@export var tilemap: TileMapLayer
@export var enemy_spawner_node: EnemySpawner
@export var enemy_spawner_scene: PackedScene = preload("res://scenes/field/EnemySpawner.tscn")
@export var field_template_id: String = ""
@export var default_start_position: Vector2 = Vector2(100.0, 100.0)
@export var enable_runtime_field_content: bool = false
@export var play_area_origin: Vector2 = Vector2.ZERO
@export var play_area_size: Vector2 = Vector2.ZERO

var party_leader: PartyMember
var party_followers: Array[PartyMember] = []
var field_enemies: Array[FieldEnemy] = []
var hud = null
var game_over_ui: GameOverUI

# 보스전 대기 데이터
# 씬 리소스
var party_leader_scene: PackedScene
var party_follower_scene: PackedScene
var hud_scene: PackedScene

# 분리된 시스템들
var spawner: EnemySpawner
var layout_helper = FIELD_LAYOUT_HELPER_SCRIPT.new()
var party_chatter_controller = FIELD_PARTY_CHATTER_CONTROLLER_SCRIPT.new()
var pause_overlay_controller = FIELD_PAUSE_OVERLAY_CONTROLLER_SCRIPT.new()
var drop_controller = FIELD_DROP_CONTROLLER_SCRIPT.new()
var treasure_controller = FIELD_TREASURE_CONTROLLER_SCRIPT.new()
var boss_controller = FIELD_BOSS_CONTROLLER_SCRIPT.new()

# 필드 동료 NPC
var recruit_npc_root: RecruitNPC = null
var recruit_npc_hero_id: String = ""
var recruit_dialog_active: bool = false
var recruit_retry_cooldown: float = 0.0
var recruit_followup_pending: bool = false
var recruit_followup_active: bool = false
var recruit_followup_hero_id: String = ""
var recruit_followup_lines: Array[String] = []
var recruit_event_active: bool = false
var recruit_event_layer: CanvasLayer = null
var recruit_event_window: BattleWindow = null
var recruit_event_on_complete: Callable = Callable()
var recruit_event_lines: Array[Dictionary] = []
var recruit_event_line_index: int = 0
var recruit_event_line_timer: float = 0.0
var recruit_event_left_hero_id: String = ""
var recruit_event_right_hero_id: String = ""

# 보물상자
var field_treasure_chests: Array[Dictionary] = []
var sanctuary_root: Node2D = null
var grudge_spawn_eval_timer: float = 0.0
var grudge_extra_target: int = 0
var grudge_extra_despawn_timer: float = 0.0
var town_tile_trigger_cooldown: float = 0.0
var shiren_tick_timer: float = SANCTUARY_HEAL_INTERVAL
var boss_trinket_choice_layer: CanvasLayer = null

const PARTY_CHATTER_LAYER: int = 220
const PARTY_CHATTER_BUBBLE_EXTRA_LIFT: float = 24.0
const PARTY_CHATTER_BUBBLE_HOLD_TIME: float = 1.65
const PARTY_CHATTER_BUBBLE_FADE_TIME: float = 0.22
const GRUDGE_EXTRA_ENEMY_PER_LEVEL: float = 0.5
const GRUDGE_EXTRA_ENEMY_MAX: int = 8
const GRUDGE_SPAWN_EVAL_INTERVAL: float = 0.45
const GRUDGE_EXTRA_DESPAWN_INTERVAL: float = 0.85



func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	town_tile_trigger_cooldown = 0.0
	shiren_tick_timer = SANCTUARY_HEAL_INTERVAL
	_apply_field_template_fallback()
	_resolve_scene_nodes()
	_load_scenes()
	_find_tilemap()
	_setup_systems()
	_spawn_party()
	_apply_camera_limits()
	_spawn_field_enemies()
	_spawn_recruit_npc()
	_spawn_field_treasure_chests()
	_spawn_sanctuary()
	_ensure_pause_dim_overlay()
	_ensure_party_chatter_overlay()
	_setup_exit()
	_connect_signals()
	
	if hud:
		hud.add_system_log("필드에 입장했다.")


func _apply_field_template_fallback() -> void:
	# 씬 단독 실행 시(현재 area 데이터가 비어있을 때) 필드 JSON 데이터를 적용한다.
	if field_template_id.is_empty() or FieldManager == null:
		return
	if not FieldManager.current_area_data.is_empty():
		return

	FieldManager.ensure_runtime_acts()
	if FieldManager.current_act_id.is_empty():
		var act_id: String = "act_1"
		if FieldManager.get_runtime_act(act_id).is_empty():
			var acts: Array[Dictionary] = FieldManager.get_runtime_acts()
			if not acts.is_empty():
				act_id = str((acts[0] as Dictionary).get("id", "act_1"))
		if not act_id.is_empty():
			FieldManager.set_current_act(act_id)

	var area_data: Dictionary = _load_field_json(field_template_id)
	if area_data.is_empty():
		return
	var area_id: String = str(area_data.get("id", ""))
	if area_id.is_empty():
		area_id = field_template_id
	if area_id.is_empty():
		area_id = String(name).to_snake_case()
	if area_id.is_empty():
		area_id = "field_start"
	area_data["id"] = area_id
	if not area_data.has("type"):
		area_data["type"] = "field"

	FieldManager.current_area_id = area_id
	FieldManager.current_area_data = area_data


func _load_field_json(fid: String) -> Dictionary:
	var json_path: String = "res://data/fields.json"
	if not FileAccess.file_exists(json_path):
		return {}
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if not (json.data is Dictionary):
		return {}
	var all_fields: Dictionary = json.data as Dictionary
	return (all_fields.get(fid, {}) as Dictionary).duplicate(true)


func _process(_delta: float) -> void:
	_update_party_chatter_runtime_context()
	_update_pause_dim_overlay()
	_update_active_party_chatter_position()
	if get_tree().paused:
		# pause 중에는 필수 후속 처리만 유지
		_update_recruit_followup_dialog(_delta)
		return
	if party_chatter_controller != null:
		party_chatter_controller.update_cooldowns_and_lifecycle(_delta)

	_update_treasure_system(_delta)

	# 이동 기반 적 스폰 체크
	if spawner and not FieldManager.is_boss_field():
		spawner.update_movement_spawn(field_enemies)
		
		# 새로 스폰된 적에게 시그널 연결
		for enemy in field_enemies:
			if not enemy.player_contacted.is_connected(_on_field_enemy_contacted):
				enemy.player_contacted.connect(_on_field_enemy_contacted)

	_update_recruit_npc(_delta)
	_update_recruit_event_dialog(_delta)
	_update_recruit_followup_dialog(_delta)
	_update_shiren_tile_effect(_delta)
	_update_town_tile_transition(_delta)
	_update_grudge_spawn_pressure(_delta)
	_update_party_chatter_blocking_state()
	_update_party_chatter(_delta)


func _physics_process(_delta: float) -> void:
	_clamp_party_members_to_bounds()


func _load_scenes() -> void:
	party_leader_scene = load("res://scenes/field/PartyMember.tscn")
	party_follower_scene = load("res://scenes/field/PartyMember.tscn")
	hud_scene = load("res://scenes/ui/FieldHUD.tscn")


func _resolve_scene_nodes() -> void:
	if spawn_point == null:
		spawn_point = get_node_or_null("SpawnPoint") as Marker2D
	if boss_spawn_point == null:
		boss_spawn_point = get_node_or_null("BossSpawnPoint") as Marker2D
	if tilemap_bg == null:
		tilemap_bg = get_node_or_null("TileMapLayerBg") as TileMapLayer
	if enemy_spawner_node == null:
		enemy_spawner_node = get_node_or_null("EnemySpawner") as EnemySpawner


func _find_tilemap() -> void:
	if layout_helper == null:
		return
	tilemap = layout_helper.find_tilemap(self, tilemap)
	if tilemap_bg == null:
		tilemap_bg = get_node_or_null("TileMapLayerBg") as TileMapLayer


func get_field_boss_spawn_position() -> Vector2:
	if boss_spawn_point != null and is_instance_valid(boss_spawn_point):
		return boss_spawn_point.global_position
	return Vector2.ZERO


func _apply_camera_limits() -> void:
	if party_leader == null:
		return
	var camera := party_leader.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return
	camera.limit_enabled = false


func _get_map_bounds() -> Rect2:
	var fg_bounds := Rect2()
	var bg_bounds := Rect2()
	if layout_helper != null:
		fg_bounds = layout_helper.get_map_bounds(tilemap, Rect2(), FIELD_TILE_SIZE)
		bg_bounds = layout_helper.get_map_bounds(tilemap_bg, Rect2(), FIELD_TILE_SIZE)
	if fg_bounds.size.x > 0.0 and fg_bounds.size.y > 0.0 and bg_bounds.size.x > 0.0 and bg_bounds.size.y > 0.0:
		return fg_bounds.merge(bg_bounds)
	if bg_bounds.size.x > 0.0 and bg_bounds.size.y > 0.0:
		return bg_bounds
	if fg_bounds.size.x > 0.0 and fg_bounds.size.y > 0.0:
		return fg_bounds
	return get_play_area_bounds()


func get_play_area_bounds() -> Rect2:
	if play_area_size.x <= 0.0 or play_area_size.y <= 0.0:
		return Rect2()
	return Rect2(play_area_origin, play_area_size)


func get_tile_type_at_world(world_pos: Vector2) -> String:
	if tilemap == null:
		return "grass"
	if tilemap.tile_set == null:
		return "grass"
	var cell: Vector2i = tilemap.local_to_map(tilemap.to_local(world_pos))
	var source_id: int = tilemap.get_cell_source_id(cell)
	if source_id == -1:
		return "grass"
	return str(FIELD_TILE_TYPE_MAP.get(source_id, "grass"))


func is_world_position_walkable(world_pos: Vector2) -> bool:
	var tile_type: String = get_tile_type_at_world(world_pos)
	if FieldManager == null:
		return true
	return FieldManager.is_tile_walkable(tile_type)


func _clamp_party_members_to_bounds() -> void:
	var bounds: Rect2 = _get_map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	var min_x: float = bounds.position.x + 8.0
	var max_x: float = bounds.end.x - 8.0
	var min_y: float = bounds.position.y + 8.0
	var max_y: float = bounds.end.y - 8.0

	if party_leader != null and is_instance_valid(party_leader):
		party_leader.global_position = Vector2(
			clampf(party_leader.global_position.x, min_x, max_x),
			clampf(party_leader.global_position.y, min_y, max_y)
		)

	for follower in party_followers:
		if follower == null or not is_instance_valid(follower):
			continue
		follower.global_position = Vector2(
			clampf(follower.global_position.x, min_x, max_x),
			clampf(follower.global_position.y, min_y, max_y)
		)


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
	spawner = enemy_spawner_node
	if spawner == null and enemy_spawner_scene != null:
		var node: Node = enemy_spawner_scene.instantiate()
		if node is EnemySpawner:
			spawner = node as EnemySpawner
			spawner.name = "EnemySpawner"
			add_child(spawner)
	if spawner == null:
		var fallback_spawner := EnemySpawner.new()
		fallback_spawner.name = "EnemySpawner"
		add_child(fallback_spawner)
		spawner = fallback_spawner
	spawner.setup(self, tilemap)
	if party_chatter_controller != null:
		party_chatter_controller.setup(
			self,
			FIELD_WORLD_EFFECT_Z,
			PARTY_CHATTER_LAYER,
			PARTY_CHATTER_BUBBLE_EXTRA_LIFT,
			PARTY_CHATTER_BUBBLE_HOLD_TIME,
			PARTY_CHATTER_BUBBLE_FADE_TIME
		)
	if pause_overlay_controller != null:
		pause_overlay_controller.setup(self)
	if drop_controller != null:
		drop_controller.setup(self)
	if treasure_controller != null:
		treasure_controller.setup(
			self,
			REWARD_WINDOW_SCENE,
			Callable(self, "_close_blocking_ui_for_recruit_followup"),
			Callable(self, "_show_field_notice")
		)
	if boss_controller != null:
		boss_controller.setup(
			self,
			Callable(self, "_start_boss_battle"),
			Callable(self, "_log_system"),
			Callable(self, "_has_unclaimed_battle_rewards")
		)
	



func _connect_signals() -> void:
	if PartyManager and not PartyManager.party_wiped.is_connected(_on_party_wiped):
		PartyManager.party_wiped.connect(_on_party_wiped)
	if PartyManager and not PartyManager.hero_died.is_connected(_on_party_hero_died):
		PartyManager.hero_died.connect(_on_party_hero_died)

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
		if not BattleManager.hero_attacked.is_connected(_on_battle_hero_attacked):
			BattleManager.hero_attacked.connect(_on_battle_hero_attacked)
		if not BattleManager.hero_damaged.is_connected(_on_battle_hero_damaged):
			BattleManager.hero_damaged.connect(_on_battle_hero_damaged)

	if not town_entrance_entered.is_connected(_on_town_entrance_entered):
		town_entrance_entered.connect(_on_town_entrance_entered)


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
	if SaveManager != null:
		var saved_info: Dictionary = SaveManager.get_saved_field_info()
		var saved_act_id: String = str(saved_info.get("act_id", ""))
		var saved_area_id: String = str(saved_info.get("area_id", ""))
		var current_act_id: String = FieldManager.current_act_id if FieldManager != null else ""
		var current_area_id: String = FieldManager.current_area_id if FieldManager != null else ""
		if saved_act_id == current_act_id and saved_area_id == current_area_id:
			var saved_pos: Vector2 = SaveManager.get_saved_field_position()
			if saved_pos != Vector2.ZERO:
				return saved_pos
	if spawn_point:
		return spawn_point.global_position
	return default_start_position


#=============================================================================
# 적 스폰
#=============================================================================
func _spawn_field_enemies() -> void:
	spawner.spawn_initial_enemies(field_enemies)

	var logged_boss_notice: bool = false
	for enemy in field_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.player_contacted.is_connected(_on_field_enemy_contacted):
			enemy.player_contacted.connect(_on_field_enemy_contacted)
		if enemy.is_boss and not logged_boss_notice:
			logged_boss_notice = true
			var boss_data: Dictionary = DataManager.get_enemy(enemy.enemy_id)
			if hud:
				hud.add_system_log("⚠ %s이(가) 앞을 막아서고 있다!" % boss_data.get("name", enemy.enemy_id))


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
	var recruit_scene: PackedScene = RECRUIT_NPC_SCENE
	if recruit_scene == null:
		return
	var npc: RecruitNPC = recruit_scene.instantiate() as RecruitNPC
	if npc == null:
		return
	recruit_npc_hero_id = hero_id
	recruit_npc_root = npc
	recruit_npc_root.name = "RecruitNPC"
	recruit_npc_root.position = spawn_pos
	recruit_npc_root.z_index = FIELD_WORLD_OBJECT_Z
	add_child(recruit_npc_root)
	recruit_npc_root.setup_recruit(hero_id)


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
	return is_world_position_walkable(pos)


func _update_recruit_npc(delta: float) -> void:
	if recruit_npc_root == null or not is_instance_valid(recruit_npc_root):
		return
	recruit_retry_cooldown = maxf(0.0, recruit_retry_cooldown - delta)
	recruit_npc_root.tick_bubble_float(delta)
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
	_clear_party_chatter_queue()
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
	var recruit_help_text: String = "앗... 도와줘..! 여긴 너무 위험해!"
	if DialogueManager != null and DialogueManager.has_method("get_speech_bubble_line"):
		var loaded_line: String = str(DialogueManager.call("get_speech_bubble_line", "recruit_npc", "help", recruit_npc_hero_id))
		if not loaded_line.is_empty():
			recruit_help_text = loaded_line
	var lines: Array[Dictionary] = [
		{"speaker": "right", "name": recruit_name, "text": recruit_help_text},
		{"speaker": "left", "name": leader_name, "text": "괜찮아. 진정하고 상황부터 말해줘."},
		{"speaker": "right", "name": recruit_name, "text": "같이 가게 해줘. 혼자론 못 버티겠어!"},
	]
	if recruit_npc_root != null and is_instance_valid(recruit_npc_root):
		recruit_npc_root.set_bubble_text("")
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
		recruit_npc_hero_id = ""
		_schedule_recruit_followup_dialog(recruited_id, hero_name)
	else:
		var recruit_full_text: String = "파티가 가득 찼어..."
		if DialogueManager != null and DialogueManager.has_method("get_speech_bubble_line"):
			var loaded_line: String = str(DialogueManager.call("get_speech_bubble_line", "recruit_npc", "party_full", recruit_npc_hero_id))
			if not loaded_line.is_empty():
				recruit_full_text = loaded_line
		if recruit_npc_root != null and is_instance_valid(recruit_npc_root):
			recruit_npc_root.set_bubble_text(recruit_full_text, Color(1.0, 0.90, 0.90, 1.0))
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


func _update_shiren_tile_effect(delta: float) -> void:
	if not enable_runtime_field_content:
		return
	if party_leader == null or PartyManager == null:
		return
	if get_tile_type_at_world(party_leader.global_position) != "shiren":
		shiren_tick_timer = SANCTUARY_HEAL_INTERVAL
		return

	shiren_tick_timer -= delta
	if shiren_tick_timer > 0.0:
		return
	shiren_tick_timer = SANCTUARY_HEAL_INTERVAL

	var healed_total: int = 0
	var revived_count: int = 0
	for hero_any in PartyManager.get_party():
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		if hero.is_dead:
			hero.revive(0.35)
			revived_count += 1
			continue
		healed_total += hero.heal(SANCTUARY_HP_PER_TICK)

	if revived_count > 0 or healed_total > 0:
		PartyManager.party_changed.emit()
	if healed_total > 0 and BattleManager != null:
		BattleManager.party_hp_changed.emit()
	if revived_count > 0 and hud != null:
		hud.add_system_log("⛩ 시렌의 가호로 동료가 부활했다.")


func _update_town_tile_transition(delta: float) -> void:
	town_tile_trigger_cooldown = maxf(0.0, town_tile_trigger_cooldown - delta)
	if town_tile_trigger_cooldown > 0.0:
		return
	if party_leader == null:
		return
	if get_tile_type_at_world(party_leader.global_position) != "town":
		return
	if BattleManager != null and BattleManager.get_active_battle_count() > 0:
		return

	var next_town_area_id: String = _find_next_town_area_id()
	if next_town_area_id.is_empty():
		return

	town_tile_trigger_cooldown = 0.9
	town_entrance_entered.emit(next_town_area_id)


func _find_next_town_area_id() -> String:
	if FieldManager == null:
		return ""
	var next_ids: Array[String] = FieldManager.get_next_area_ids()
	for next_id in next_ids:
		if next_id.is_empty():
			continue
		var area: Dictionary = FieldManager.get_runtime_area(FieldManager.current_act_id, next_id)
		if str(area.get("type", "")) == "town":
			return next_id
	return ""


func _has_immediate_next_town_area() -> bool:
	return not _find_next_town_area_id().is_empty()


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
	recruit_event_left_hero_id = left_hero_id
	recruit_event_right_hero_id = right_hero_id
	recruit_event_lines = lines.duplicate(true)
	recruit_event_line_index = 0
	recruit_event_line_timer = 0.0
	_clear_party_chatter_queue()
	_advance_recruit_event_dialog_line()


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
	recruit_event_lines.clear()
	recruit_event_line_index = 0
	recruit_event_line_timer = 0.0
	recruit_event_left_hero_id = ""
	recruit_event_right_hero_id = ""


func _update_recruit_event_dialog(delta: float) -> void:
	if not recruit_event_active:
		return
	if recruit_event_line_timer > 0.0:
		recruit_event_line_timer = maxf(0.0, recruit_event_line_timer - delta)
		return
	if party_chatter_controller != null and party_chatter_controller.is_showing():
		return
	_advance_recruit_event_dialog_line()


func _advance_recruit_event_dialog_line() -> void:
	if not recruit_event_active:
		return
	if recruit_event_line_index >= recruit_event_lines.size():
		var finished_callback: Callable = recruit_event_on_complete
		_close_recruit_event_dialog()
		if finished_callback.is_valid():
			finished_callback.call_deferred()
		return

	var line_data: Dictionary = recruit_event_lines[recruit_event_line_index]
	recruit_event_line_index += 1
	var speaker_side: String = str(line_data.get("speaker", "left"))
	var speaker_hero_id: String = _get_recruit_event_speaker_hero_id(speaker_side)
	if _is_party_hero_dead(speaker_hero_id):
		var dead_speaker: PartyMember = _find_party_member_by_hero_id(speaker_hero_id)
		if dead_speaker != null and is_instance_valid(dead_speaker):
			_show_party_chatter_on_node(dead_speaker, "...", Color(0.8, 0.8, 0.8, 1.0))
			recruit_event_line_timer = 0.85
		else:
			recruit_event_line_timer = 0.01
		recruit_event_line_index = recruit_event_lines.size()
		return

	var text: String = str(line_data.get("text", "")).strip_edges()
	if text.is_empty():
		recruit_event_line_timer = 0.01
		return

	var speaker_node: Node2D = _resolve_recruit_event_speaker_node(speaker_side)
	if speaker_node == null:
		recruit_event_line_timer = 0.01
		return

	var bubble_color := Color(0.95, 0.95, 1.0, 1.0)
	if speaker_side == "right":
		bubble_color = Color(0.9, 0.98, 1.0, 1.0)
	_show_party_chatter_on_node(speaker_node, text, bubble_color)
	recruit_event_line_timer = maxf(RECRUIT_EVENT_LINE_INTERVAL, 0.55 + float(text.length()) * 0.05)


func _get_recruit_event_speaker_hero_id(speaker_side: String) -> String:
	var side := speaker_side.to_lower()
	if side == "right":
		return recruit_event_right_hero_id
	return recruit_event_left_hero_id


func _is_party_hero_dead(hero_id: String) -> bool:
	if hero_id.is_empty() or PartyManager == null:
		return false
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	return hero != null and hero.is_dead


func _resolve_recruit_event_speaker_node(speaker_side: String) -> Node2D:
	var side := speaker_side.to_lower()
	if side == "right":
		if recruit_npc_root != null and is_instance_valid(recruit_npc_root):
			return recruit_npc_root
		if not recruit_event_right_hero_id.is_empty():
			var right_member: PartyMember = _find_party_member_by_hero_id(recruit_event_right_hero_id)
			if right_member != null and is_instance_valid(right_member):
				return right_member
	else:
		if not recruit_event_left_hero_id.is_empty():
			var left_member: PartyMember = _find_party_member_by_hero_id(recruit_event_left_hero_id)
			if left_member != null and is_instance_valid(left_member):
				return left_member
	if party_leader != null and is_instance_valid(party_leader):
		return party_leader
	return null


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
func _ensure_pause_dim_overlay() -> void:
	if pause_overlay_controller == null:
		return
	pause_overlay_controller.ensure_overlay()


func _update_pause_dim_overlay() -> void:
	if pause_overlay_controller == null:
		return
	var chatter_root: Control = null
	if party_chatter_controller != null:
		chatter_root = party_chatter_controller.get_overlay_root()
	pause_overlay_controller.update_overlay(get_tree().paused, chatter_root)


func _spawn_field_treasure_chests() -> void:
	if treasure_controller == null:
		return
	treasure_controller.spawn_field_treasure_chests(
		enable_runtime_field_content,
		FieldManager.is_boss_field(),
		_get_map_bounds(),
		TREASURE_CHEST_RATIOS,
		TREASURE_LOCKED_CHEST_INDEX,
		FIELD_WORLD_OBJECT_Z
	)
	_sync_treasure_runtime_refs()


func _spawn_sanctuary() -> void:
	if treasure_controller == null:
		return
	if enable_runtime_field_content:
		# runtime 타일에서 shiren 타일이 성소 역할을 담당한다.
		sanctuary_root = null
		return
	treasure_controller.spawn_sanctuary(
		enable_runtime_field_content,
		_get_map_bounds(),
		SANCTUARY_SPAWN_RATIO,
		FIELD_WORLD_OBJECT_Z,
		SANCTUARY_HEAL_INTERVAL,
		SANCTUARY_HEAL_RADIUS
	)
	_sync_treasure_runtime_refs()


func _update_treasure_system(delta: float) -> void:
	if treasure_controller == null:
		return
	treasure_controller.update(
		delta,
		party_leader,
		SANCTUARY_HEAL_RADIUS,
		SANCTUARY_HEAL_INTERVAL,
		SANCTUARY_HP_PER_TICK,
		FIELD_WORLD_EFFECT_Z
	)
	_sync_treasure_runtime_refs()


func _sync_treasure_runtime_refs() -> void:
	if treasure_controller == null:
		return
	field_treasure_chests = treasure_controller.get_treasure_chests()
	sanctuary_root = treasure_controller.get_sanctuary_root()

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
			FieldManager.current_act_id,
			FieldManager.current_area_id
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
	if boss_controller != null:
		boss_controller.handle_boss_contact(enemy_id, is_elite, collision_pos, field_enemy, party_leader)
		return
	if party_leader:
		party_leader.set_boss_battle_mode(true)
	if BattleManager != null:
		BattleManager.close_all_battles()
		BattleManager.start_boss_battle(enemy_id, self, is_elite, collision_pos)
	battle_triggered.emit([enemy_id])


func _has_unclaimed_battle_rewards() -> bool:
	if hud != null and hud.has_method("has_unclaimed_rewards"):
		return bool(hud.call("has_unclaimed_rewards"))
	if BattleManager != null:
		var rewards: Dictionary = BattleManager.get_accumulated_rewards()
		return int(rewards.get("gold", 0)) > 0 or int(rewards.get("exp", 0)) > 0 or not (rewards.get("items", []) as Array).is_empty()
	return false


func _log_system(text: String) -> void:
	if hud != null:
		hud.add_system_log(text)


func _start_boss_battle() -> void:
	if boss_controller == null:
		return
	var boss_data: Dictionary = boss_controller.get_pending_boss_data()
	if boss_data.is_empty():
		return
	var enemy_id: String = str(boss_data.get("enemy_id", ""))
	var is_elite: bool = bool(boss_data.get("is_elite", false))
	var collision_pos: Vector2 = boss_data.get("collision_pos", Vector2.ZERO)
	if enemy_id.is_empty():
		return
	if DataManager != null and hud != null:
		var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
		var enemy_name: String = str(enemy_data.get("name", enemy_id))
		hud.add_system_log("👑 %s(과) 보스전 시작!" % enemy_name)
	if BattleManager != null:
		BattleManager.close_all_battles()
		BattleManager.start_boss_battle(enemy_id, self, is_elite, collision_pos)
	boss_controller.clear_pending_boss_data()
	battle_triggered.emit([enemy_id])


func _on_exit_body_entered(body: Node2D) -> void:
	if not _is_party_leader_body(body):
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
		var next_town_area_id: String = _find_next_town_area_id()
		if not next_town_area_id.is_empty():
			GameManager.queue_node_travel(FieldManager.current_act_id, FieldManager.current_area_id, next_town_area_id)
		else:
			GameManager.go_to_next_from_area()


func _is_party_leader_body(body: Node2D) -> bool:
	if body == null:
		return false
	if body.is_in_group("party_leader"):
		return true
	if party_leader == null or not is_instance_valid(party_leader):
		return false
	if body == party_leader:
		return true
	if party_leader.is_ancestor_of(body):
		return true
	var parent: Node = body.get_parent()
	while parent != null:
		if parent == party_leader:
			return true
		parent = parent.get_parent()
	return false


func _on_town_entrance_entered(next_town_area_id: String) -> void:
	if hud != null:
		hud.add_system_log("🏘️ 마을 입구에 도착했다.")

	if GameManager == null:
		return

	if not next_town_area_id.is_empty():
		GameManager.queue_node_travel(FieldManager.current_act_id, FieldManager.current_area_id, next_town_area_id)
		return

	if hud != null:
		hud.add_system_log("연결된 다음 마을이 없다.")


#=============================================================================
# 메뉴 & 게임오버
#=============================================================================
func _on_menu_pressed() -> void:
	if hud:
		hud.toggle_pause_menu()


func _on_title_pressed() -> void:
	if recruit_event_active:
		_close_recruit_event_dialog()
	if boss_controller != null:
		boss_controller.clear_popup()
	if party_leader:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_act_id,
			FieldManager.current_area_id
		)
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_party_wiped() -> void:
	if recruit_event_active:
		_close_recruit_event_dialog()
	if boss_controller != null:
		boss_controller.clear_popup()
	spawner.stop_respawn()

	if BattleManager:
		BattleManager.close_all_battles()

	if game_over_ui:
		game_over_ui.show_game_over("파티가 전멸했습니다...\n타이틀로 이동합니다.")


func _on_party_hero_died(_hero: Hero) -> void:
	# 전멸은 기존 game over 플로우로 처리
	if PartyManager and PartyManager.is_party_wiped():
		return
	# 사망자 후순위/리더 교체를 필드 파티 노드에 반영
	call_deferred("_rebuild_field_party_formation")


func _rebuild_field_party_formation() -> void:
	if not PartyManager:
		return
	var party_members: Array = PartyManager.get_party()
	var field_order_members: Array = _get_field_order_members_dead_last(party_members)
	if field_order_members.is_empty():
		return
	if party_members.is_empty():
		return

	var start_pos: Vector2 = _get_start_position()
	if party_leader and is_instance_valid(party_leader):
		start_pos = party_leader.global_position

	# 기존 노드 정리
	if party_leader and is_instance_valid(party_leader):
		party_leader.queue_free()
	for follower in party_followers:
		if follower and is_instance_valid(follower):
			follower.queue_free()
	party_followers.clear()

	# 새 리더 (항상 생존자 우선 정렬된 party[0])
	party_leader = party_leader_scene.instantiate() as PartyMember
	add_child(party_leader)
	party_leader.setup_as_leader(field_order_members[0], start_pos)

	# 팔로워 재생성
	if field_order_members.size() > 1:
		for i in range(1, field_order_members.size()):
			var follower: PartyMember = party_follower_scene.instantiate()
			add_child(follower)
			follower.setup_as_follower(field_order_members[i], party_leader, i)
			party_followers.append(follower)

	# 카메라 한 번 더 보정
	_apply_camera_limits()


func _get_field_order_members_dead_last(party_members: Array) -> Array:
	var alive: Array = []
	var dead: Array = []
	for hero_any in party_members:
		var hero: Hero = hero_any as Hero
		if hero == null:
			continue
		if hero.is_dead:
			dead.append(hero)
		else:
			alive.append(hero)
	alive.append_array(dead)
	return alive


func _on_restart_game() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.call_deferred("change_scene_to_file", "res://scenes/main/Main.tscn")


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
		hud.add_system_log("트링켓 1개를 선택할 수 있다.")

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
	_show_boss_trinket_choice()
	# 보스 보상은 누적 보상 시스템으로 처리됨


func _show_boss_trinket_choice() -> void:
	if boss_trinket_choice_layer != null and is_instance_valid(boss_trinket_choice_layer):
		return

	var choices: Array[String] = []
	if GameManager != null and GameManager.has_method("get_trinket_choices"):
		choices = GameManager.get_trinket_choices("boss", BOSS_TRINKET_CHOICE_COUNT, false)

	if choices.is_empty():
		if hud:
			hud.add_system_log("선택 가능한 트링켓이 없다.")
			hud.add_system_log("출구로 향해 다음 스테이지로 진행하자!")
		return

	var tree := get_tree()
	if tree:
		tree.paused = true

	boss_trinket_choice_layer = CanvasLayer.new()
	boss_trinket_choice_layer.layer = 320
	boss_trinket_choice_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(boss_trinket_choice_layer)

	var full := ColorRect.new()
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	full.color = Color(0.0, 0.02, 0.08, 0.78)
	boss_trinket_choice_layer.add_child(full)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	boss_trinket_choice_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(840.0, 360.0)
	panel.add_theme_stylebox_override("panel", _make_boss_trinket_panel_style())
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24.0
	root.offset_top = 20.0
	root.offset_right = -24.0
	root.offset_bottom = -20.0
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.text = "보스 보상: 트링켓 선택"
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.modulate = Color(0.9, 0.94, 1.0, 0.95)
	subtitle.text = "세 가지 중 하나를 선택하세요."
	root.add_child(subtitle)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 14)
	root.add_child(cards)

	for trinket_id in choices:
		var data: Dictionary = DataManager.get_trinket(trinket_id) if DataManager != null else {}
		cards.add_child(_build_boss_trinket_choice_card(trinket_id, data))


func _build_boss_trinket_choice_card(trinket_id: String, data: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(238.0, 240.0)
	card.add_theme_stylebox_override("panel", _make_boss_trinket_card_style())

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12.0
	vbox.offset_top = 12.0
	vbox.offset_right = -12.0
	vbox.offset_bottom = -12.0
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var emoji_label := Label.new()
	emoji_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji_label.add_theme_font_size_override("font_size", 42)
	emoji_label.text = str(data.get("emoji", "🧿"))
	vbox.add_child(emoji_label)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.text = str(data.get("name", trinket_id))
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.modulate = Color(0.9, 0.93, 0.98, 0.95)
	desc_label.text = str(data.get("description", ""))
	vbox.add_child(desc_label)

	var pick_btn := Button.new()
	pick_btn.text = "획득"
	pick_btn.custom_minimum_size = Vector2(0.0, 36.0)
	pick_btn.add_theme_font_size_override("font_size", 15)
	pick_btn.pressed.connect(_on_boss_trinket_choice_pressed.bind(trinket_id))
	vbox.add_child(pick_btn)
	return card


func _on_boss_trinket_choice_pressed(trinket_id: String) -> void:
	var obtained: bool = false
	if GameManager != null and GameManager.has_method("obtain_trinket"):
		obtained = bool(GameManager.call("obtain_trinket", trinket_id, "boss"))

	if obtained:
		var tdata: Dictionary = DataManager.get_trinket(trinket_id) if DataManager != null else {}
		var tname: String = str(tdata.get("name", trinket_id))
		var temoji: String = str(tdata.get("emoji", "🧿"))
		if hud:
			hud.add_system_log("%s 트링켓 획득: %s" % [temoji, tname])
	else:
		if hud:
			hud.add_system_log("트링켓 획득에 실패했다.")

	_close_boss_trinket_choice()
	if hud:
		hud.add_system_log("출구로 향해 다음 스테이지로 진행하자!")


func _close_boss_trinket_choice() -> void:
	if boss_trinket_choice_layer != null and is_instance_valid(boss_trinket_choice_layer):
		boss_trinket_choice_layer.queue_free()
	boss_trinket_choice_layer = null
	var tree := get_tree()
	if tree:
		tree.paused = false


func _make_boss_trinket_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.18, 0.96)
	style.border_color = Color(0.36, 0.45, 0.7, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	return style


func _make_boss_trinket_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.22, 0.98)
	style.border_color = Color(0.46, 0.56, 0.82, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


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


func _update_party_chatter(_delta: float) -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.update_enemy_seen_chatter(field_enemies, _get_camera_rect())


func _update_grudge_spawn_pressure(delta: float) -> void:
	if FieldManager.is_boss_field():
		return
	if spawner == null:
		return

	grudge_spawn_eval_timer -= delta
	if grudge_spawn_eval_timer <= 0.0:
		grudge_spawn_eval_timer = GRUDGE_SPAWN_EVAL_INTERVAL
		var total_grudge: int = _get_active_battle_total_grudge_level()
		var target_bonus: int = clampi(
			int(floor(float(total_grudge) * GRUDGE_EXTRA_ENEMY_PER_LEVEL)),
			0,
			GRUDGE_EXTRA_ENEMY_MAX
		)
		grudge_extra_target = target_bonus
		spawner.set_dynamic_bonus_enemy_count(grudge_extra_target)

	var desired_non_boss: int = spawner.get_target_enemy_count()
	var current_non_boss: int = _get_current_non_boss_enemy_count()
	if current_non_boss > desired_non_boss:
		grudge_extra_despawn_timer -= delta
		if grudge_extra_despawn_timer <= 0.0:
			grudge_extra_despawn_timer = GRUDGE_EXTRA_DESPAWN_INTERVAL
			_despawn_one_extra_field_enemy()
	else:
		grudge_extra_despawn_timer = 0.0


func _get_active_battle_total_grudge_level() -> int:
	if BattleManager == null:
		return 0
	if BattleManager.get_active_battle_count() <= 0:
		return 0
	var total: int = 0
	for battle_id in BattleManager.active_battles:
		var bd: Dictionary = BattleManager.active_battles.get(battle_id, {})
		var window_ref: Node = bd.get("window_ref", null)
		if window_ref == null or not is_instance_valid(window_ref):
			continue
		if window_ref.has_method("get_local_grudge_level"):
			total += int(window_ref.call("get_local_grudge_level"))
		else:
			total += int(window_ref.get("local_grudge_level"))
	return maxi(0, total)


func _get_current_non_boss_enemy_count() -> int:
	var count: int = 0
	for enemy in field_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.is_boss:
			continue
		count += 1
	return count


func _despawn_one_extra_field_enemy() -> void:
	if party_leader == null:
		return
	var candidate: FieldEnemy = null
	var best_score: float = -1.0
	for enemy in field_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.is_boss:
			continue
		if enemy.is_contacted:
			continue
		if enemy.is_despawning:
			continue
		var score: float = enemy.global_position.distance_to(party_leader.global_position)
		if score > best_score:
			best_score = score
			candidate = enemy
	if candidate == null:
		return
	field_enemies.erase(candidate)
	candidate.freeze_and_despawn(0.25)


func _on_battle_hero_attacked(hero_id: String) -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.on_hero_attacked(hero_id)


func _on_battle_hero_damaged(hero_id: String) -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.on_hero_damaged(hero_id)


func _show_party_chatter_exchange(
	hero_id: String,
	first_text: String,
	second_text: String,
	first_color: Color = Color(0.95, 0.95, 1.0, 1.0),
	second_color: Color = Color(0.95, 0.95, 1.0, 1.0)
) -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.show_party_chatter_exchange(hero_id, first_text, second_text, first_color, second_color)


func _show_party_chatter(hero_id: String, text: String, color: Color = Color(0.95, 0.95, 1.0, 1.0)) -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.show_party_chatter(hero_id, text, color)


func _show_party_chatter_on_node(
	speaker: Node2D,
	text: String,
	color: Color = Color(0.95, 0.95, 1.0, 1.0)
) -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.show_party_chatter_on_node(speaker, text, color)


func _update_active_party_chatter_position() -> void:
	if party_chatter_controller == null:
		return
	var battles: Dictionary = {}
	if BattleManager != null:
		battles = BattleManager.active_battles
	party_chatter_controller.update_active_bubble_position(battles)


func _update_party_chatter_blocking_state() -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.update_blocking_state()


func _clear_party_chatter_queue() -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.clear_queue()


func _is_external_event_blocking_party_chatter() -> bool:
	if recruit_dialog_active and not recruit_event_active:
		return true
	if recruit_followup_active and not recruit_event_active:
		return true
	if treasure_controller != null and treasure_controller.is_reward_window_visible():
		return true
	return false


func _ensure_party_chatter_overlay() -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.ensure_overlay()


func _update_party_chatter_runtime_context() -> void:
	if party_chatter_controller == null:
		return
	party_chatter_controller.set_runtime_context(
		get_tree().paused,
		recruit_event_active,
		_is_external_event_blocking_party_chatter(),
		party_leader,
		party_followers
	)


func _find_party_member_by_hero_id(hero_id: String) -> PartyMember:
	if hero_id.is_empty():
		return null
	if party_leader and is_instance_valid(party_leader) and party_leader.hero_id == hero_id:
		return party_leader
	for follower in party_followers:
		if follower == null or not is_instance_valid(follower):
			continue
		if follower.hero_id == hero_id:
			return follower
	return null


func _get_camera_rect() -> Rect2:
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport: Viewport = get_viewport()
	if viewport == null:
		var bounds: Rect2 = _get_map_bounds()
		return bounds if bounds.size.x > 0.0 and bounds.size.y > 0.0 else Rect2()
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		var fallback_rect: Rect2 = viewport.get_visible_rect()
		if fallback_rect.size.x > 0.0 and fallback_rect.size.y > 0.0:
			viewport_size = fallback_rect.size
		else:
			viewport_size = Vector2(512.0, 288.0)
	var camera: Camera2D = viewport.get_camera_2d()
	var player_pos: Vector2 = party_leader.global_position if party_leader else _get_map_bounds().get_center()
	if camera:
		var zoom_x: float = maxf(0.001, camera.zoom.x)
		var zoom_y: float = maxf(0.001, camera.zoom.y)
		var view_size: Vector2 = Vector2(viewport_size.x / zoom_x, viewport_size.y / zoom_y)
		return Rect2(camera.global_position - view_size / 2, view_size)
	return Rect2(player_pos - viewport_size / 2, viewport_size)


#=============================================================================
# 필드 드롭 시스템
#=============================================================================
func _on_field_drops_requested(hp_orbs: int, gold_amount: int, item_ids: Array, world_pos: Vector2, window_rect: Rect2, exp_amount: int = 0, mp_orbs: int = 0) -> void:
	if drop_controller == null:
		return
	drop_controller.spawn_battle_drops(hp_orbs, gold_amount, item_ids, world_pos, window_rect, party_leader, FIELD_WORLD_EFFECT_Z, exp_amount, mp_orbs)


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
