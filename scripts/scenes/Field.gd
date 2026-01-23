extends Node2D
## 필드 씬 컨트롤러

signal battle_triggered(battle_enemies: Array)
signal exit_reached(next_destination: String)
signal town_entered
signal field_cleared

@export var spawn_point: Marker2D
@export var exit_area: Area2D
@export var town_area: Area2D  ## 마을 진입 영역
@export var tilemap: TileMapLayer

var party_leader: PartyLeader
var party_followers: Array[PartyFollower] = []
var field_enemies: Array[FieldEnemy] = []
var hud: FieldHUD
var game_over_ui: GameOverUI
var loot_select_ui: LootSelectUI  # 3지선다 UI

var party_leader_scene: PackedScene
var party_follower_scene: PackedScene
var field_enemy_scene: PackedScene
var hud_scene: PackedScene

#=============================================================================
# 🏠 마을 결계 시스템
#=============================================================================
var town_barrier: StaticBody2D = null  # 결계 충돌체
var town_barrier_visual: ColorRect = null  # 결계 시각 효과
var town_speech_bubble: Control = null  # 말풍선
var speech_bubble_timer: Timer = null
var barrier_tween: Tween = null  # 결계 애니메이션용

#=============================================================================
# 🎮 에너미 스포너 설정 (여기서 조절하세요!)
#=============================================================================
var respawn_timer: Timer

# 리스폰 간격 (초) - 낮출수록 더 자주 스폰됨
# 예: 1.0 = 1초마다, 5.0 = 5초마다
const RESPAWN_INTERVAL: float = 3.0

# 필드에 존재할 수 있는 최대 적 수
# 예: 10 = 최대 10마리, 30 = 최대 30마리
const MAX_ENEMIES: int = 15

# 한 번에 스폰되는 적 수 (최소, 최대)
# _on_respawn_timer() 함수에서 randi_range(1, 2)로 설정됨
# 더 많이 스폰하려면 randi_range(2, 4) 등으로 변경

# 플레이어로부터 최소 스폰 거리 (픽셀)
# 너무 가까이 스폰되지 않도록 함
const MIN_SPAWN_DISTANCE: float = 150.0

# 엘리트 스폰 확률 (0.0 ~ 1.0)
# 0.15 = 15% 확률로 엘리트 스폰
const ELITE_SPAWN_CHANCE: float = 0.15

# 초기 스폰 수는 stages.json의 enemy_count에서 설정
# "enemy_count": { "min": 8, "max": 12 }
#=============================================================================

var spawnable_tiles: Array = []

@export var tile_type_map: Dictionary = {
	0: "grass",
	1: "forest",
	2: "road",
	3: "water",
	4: "cave"
}


func _ready() -> void:
	_load_scenes()
	_setup_hud()
	_setup_game_over_ui()
	_spawn_party()
	
	# 스폰 가능한 타일 캐싱
	spawnable_tiles = _collect_spawnable_tiles()
	
	_spawn_field_enemies()
	_setup_exit()
	_setup_respawn_timer()
	
	# 파티 전멸 시그널 연결
	if PartyManager:
		if not PartyManager.party_wiped.is_connected(_on_party_wiped):
			PartyManager.party_wiped.connect(_on_party_wiped)
			print("[Field] PartyManager.party_wiped 연결됨")
	
	# GameManager 게임오버 시그널도 연결
	if GameManager:
		if not GameManager.game_over.is_connected(_on_party_wiped):
			GameManager.game_over.connect(_on_party_wiped)
			print("[Field] GameManager.game_over 연결됨")
	
	# 엘리트 전투 승리 시그널 연결
	if BattleManager:
		if not BattleManager.elite_victory.is_connected(_on_elite_victory):
			BattleManager.elite_victory.connect(_on_elite_victory)
			print("[Field] BattleManager.elite_victory 연결됨")
		if not BattleManager.boss_victory.is_connected(_on_boss_victory):
			BattleManager.boss_victory.connect(_on_boss_victory)
			print("[Field] BattleManager.boss_victory 연결됨")
	
	hud.add_system_log("필드에 입장했다.")


func _load_scenes() -> void:
	party_leader_scene = load("res://scenes/field/PartyLeader.tscn")
	party_follower_scene = load("res://scenes/field/PartyFollower.tscn")
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	hud_scene = load("res://scenes/ui/FieldHUD.tscn")


func _setup_hud() -> void:
	# 기존 HUD 제거 (씬에 미리 있으면)
	var old_hud = get_node_or_null("CanvasLayer")
	if old_hud:
		old_hud.queue_free()
	
	hud = hud_scene.instantiate() as FieldHUD
	add_child(hud)
	hud.menu_pressed.connect(_on_menu_pressed)


func _setup_game_over_ui() -> void:
	game_over_ui = GameOverUI.new()
	add_child(game_over_ui)
	game_over_ui.restart_pressed.connect(_on_restart_game)
	game_over_ui.quit_pressed.connect(_on_quit_game)
	
	# 3지선다 루트 UI
	loot_select_ui = LootSelectUI.new()
	add_child(loot_select_ui)
	loot_select_ui.item_selected.connect(_on_loot_item_selected)


func _spawn_party() -> void:
	var start_pos: Vector2 = Vector2(100, 100)
	
	# 저장된 위치가 있으면 사용
	var saved_pos: Vector2 = SaveManager.get_saved_field_position()
	if saved_pos != Vector2.ZERO:
		start_pos = saved_pos
		print("[Field] 저장된 위치로 복귀: ", start_pos)
	elif spawn_point:
		start_pos = spawn_point.global_position
	
	# PartyManager.get_party() 사용
	var party_members: Array = []
	if PartyManager:
		party_members = PartyManager.get_party()
	
	# 리더 생성
	party_leader = party_leader_scene.instantiate() as PartyLeader
	party_leader.global_position = start_pos
	add_child(party_leader)
	
	if party_members.size() > 0:
		party_leader.setup_hero(party_members[0])
	
	print("[Field] 리더 생성 at ", start_pos)
	
	# 팔로워 생성
	if party_members.size() > 1:
		await get_tree().create_timer(0.1).timeout
		
		for i in range(1, party_members.size()):
			var follower: PartyFollower = party_follower_scene.instantiate() as PartyFollower
			add_child(follower)
			follower.setup(party_leader, i, party_members[i])
			party_followers.append(follower)
		
		print("[Field] 팔로워: ", party_followers.size())
	
	# 로드 후 위치 초기화 (중복 사용 방지)
	SaveManager.last_field_position = Vector2.ZERO


func _spawn_field_enemies() -> void:
	# 보스 필드인 경우 보스만 스폰
	if FieldManager.is_boss_field():
		_spawn_boss()
		return
	
	var spawn_data: Array = FieldManager.spawn_field_enemies(spawnable_tiles)
	
	for data in spawn_data:
		_spawn_single_enemy(data)
	
	print("[Field] 적 스폰: ", field_enemies.size())


func _spawn_boss() -> void:
	## 보스 필드에서 보스 스폰
	var boss_id: String = FieldManager.get_boss_enemy()
	if boss_id.is_empty():
		push_error("[Field] 보스 ID가 없음!")
		return
	
	var boss_pos: Vector2 = Vector2(350, 135)  # 필드 오른쪽에 배치
	
	var enemy: FieldEnemy = field_enemy_scene.instantiate() as FieldEnemy
	add_child(enemy)
	
	enemy.setup(boss_id, "grass", boss_pos, false)  # 보스는 elite가 아닌 boss 타입
	enemy.is_boss = true  # 보스 플래그
	enemy.player_contacted.connect(_on_field_enemy_contacted)
	field_enemies.append(enemy)
	
	print("[Field] 🔥 보스 스폰: ", boss_id)
	
	if hud:
		var boss_data: Dictionary = DataManager.get_enemy(boss_id)
		var boss_name: String = str(boss_data.get("name", boss_id))
		hud.add_system_log("⚠ %s이(가) 앞을 막아서고 있다!" % boss_name)


func _spawn_single_enemy(data: Dictionary, force_elite: bool = false) -> void:
	var enemy: FieldEnemy = field_enemy_scene.instantiate() as FieldEnemy
	add_child(enemy)
	
	# 엘리트 여부 결정
	var is_elite: bool = force_elite or (randf() < ELITE_SPAWN_CHANCE)
	
	enemy.setup(
		str(data.get("enemy_id", "slime")),
		str(data.get("tile_type", "grass")),
		data.get("position", Vector2.ZERO) as Vector2,
		is_elite
	)
	enemy.player_contacted.connect(_on_field_enemy_contacted)
	field_enemies.append(enemy)
	
	if is_elite:
		print("[Field] 엘리트 스폰: ", data.get("enemy_id", "slime"))


func _setup_respawn_timer() -> void:
	# 보스 필드에서는 리스폰 안 함
	if FieldManager.is_boss_field():
		print("[Field] 보스 필드 - 리스폰 비활성화")
		return
	
	respawn_timer = Timer.new()
	respawn_timer.wait_time = RESPAWN_INTERVAL
	respawn_timer.one_shot = false
	respawn_timer.timeout.connect(_on_respawn_timer)
	add_child(respawn_timer)
	respawn_timer.start()
	print("[Field] 리스폰 타이머 시작")


func _on_respawn_timer() -> void:
	# 최대 적 수 미만이면 리스폰
	if field_enemies.size() >= MAX_ENEMIES:
		return
	
	# 플레이어 위치에서 멀리 스폰
	var safe_tiles: Array = _get_safe_spawn_tiles()
	if safe_tiles.is_empty():
		return
	
	#=============================================================================
	# 🎮 한 번에 스폰되는 적 수 조절
	# randi_range(최소, 최대) - 예: (1, 2) = 1~2마리, (3, 5) = 3~5마리
	#=============================================================================
	var spawn_count: int = randi_range(1, 2)
	
	for i in range(spawn_count):
		if field_enemies.size() >= MAX_ENEMIES:
			break
		if safe_tiles.is_empty():
			break
		
		var tile_idx: int = randi() % safe_tiles.size()
		var tile_data: Dictionary = safe_tiles[tile_idx]
		safe_tiles.remove_at(tile_idx)
		
		var tile_type: String = str(tile_data.get("tile_type", "grass"))
		var enemy_id: String = FieldManager.select_field_enemy_for_tile(tile_type)
		
		var spawn_data: Dictionary = {
			"enemy_id": enemy_id,
			"position": tile_data.get("position", Vector2.ZERO),
			"tile_type": tile_type
		}
		_spawn_single_enemy(spawn_data)
	
	print("[Field] 리스폰! 현재 적: ", field_enemies.size())


func _get_safe_spawn_tiles() -> Array:
	## 플레이어에서 일정 거리 이상 떨어진 타일만 반환
	var safe_tiles: Array = []
	var player_pos: Vector2 = party_leader.global_position if party_leader else Vector2.ZERO
	
	for tile_data in spawnable_tiles:
		var tile_dict: Dictionary = tile_data as Dictionary
		var tile_pos: Vector2 = tile_dict.get("position", Vector2.ZERO) as Vector2
		
		if tile_pos.distance_to(player_pos) > MIN_SPAWN_DISTANCE:
			safe_tiles.append(tile_dict)
	
	return safe_tiles


func _collect_spawnable_tiles() -> Array:
	var result: Array = []
	
	if tilemap:
		var used_cells: Array = tilemap.get_used_cells()
		for cell in used_cells:
			var cell_vec: Vector2i = cell as Vector2i
			var source_id: int = tilemap.get_cell_source_id(cell_vec)
			var tile_type: String = str(tile_type_map.get(source_id, "grass"))
			
			if FieldManager.can_spawn_on_tile(tile_type):
				result.append({
					"position": tilemap.map_to_local(cell_vec),
					"tile_type": tile_type
				})
	
	if result.is_empty():
		for i in range(8):
			result.append({
				"position": Vector2(150 + (i % 4) * 100, 100 + (i / 4) * 80),
				"tile_type": "grass"
			})
	
	return result


func _setup_exit() -> void:
	print("[Field] _setup_exit 호출")
	print("[Field] exit_area: ", exit_area)
	print("[Field] town_area: ", town_area)
	
	# exit_area가 null이면 직접 찾기
	if not exit_area:
		exit_area = get_node_or_null("ExitArea")
		print("[Field] exit_area 수동 탐색: ", exit_area)
	
	if exit_area:
		if not exit_area.body_entered.is_connected(_on_exit_body_entered):
			exit_area.body_entered.connect(_on_exit_body_entered)
			print("[Field] ✅ exit_area 시그널 연결됨")
	else:
		print("[Field] ❌ WARNING: exit_area가 null!")
	
	# town_area가 null이면 직접 찾기
	if not town_area:
		town_area = get_node_or_null("TownArea")
		print("[Field] town_area 수동 탐색: ", town_area)
	
	if town_area:
		if not town_area.body_entered.is_connected(_on_town_body_entered):
			town_area.body_entered.connect(_on_town_body_entered)
			print("[Field] ✅ town_area 시그널 연결됨")
		# 결계 시스템 초기화
		_setup_town_barrier()
	else:
		# 보스 필드는 town_area가 없을 수 있음
		if not FieldManager.is_boss_field():
			print("[Field] ⚠ WARNING: town_area가 null! (보스필드 아님)")
		else:
			print("[Field] 보스 필드 - town_area 없음 (정상)")
	
	# 위치 저장 타이머 (3초마다)
	var save_timer := Timer.new()
	save_timer.wait_time = 3.0
	save_timer.one_shot = false
	save_timer.timeout.connect(_save_field_position)
	add_child(save_timer)
	save_timer.start()


#=============================================================================
# 🏠 마을 결계 시스템
#=============================================================================
func _setup_town_barrier() -> void:
	## 마을 결계 초기화 - 전투 시작/종료에 따라 활성화/비활성화
	if not town_area:
		return
	
	# 결계 충돌체 생성 (StaticBody2D)
	town_barrier = StaticBody2D.new()
	town_barrier.name = "TownBarrier"
	town_barrier.collision_layer = 4  # 벽 레이어
	town_barrier.collision_mask = 0
	town_area.add_child(town_barrier)
	
	# 충돌 shape 복사
	var barrier_shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	rect_shape.size = Vector2(60, 60)  # 마을 영역보다 약간 크게
	barrier_shape.shape = rect_shape
	town_barrier.add_child(barrier_shape)
	
	# 결계 시각 효과 (반투명 보라색 사각형)
	town_barrier_visual = ColorRect.new()
	town_barrier_visual.size = Vector2(64, 64)
	town_barrier_visual.position = Vector2(-32, -32)
	town_barrier_visual.color = Color(0.6, 0.3, 0.8, 0.5)  # 보라색 반투명
	town_barrier.add_child(town_barrier_visual)
	
	# 결계 테두리 효과
	var border := ColorRect.new()
	border.size = Vector2(68, 68)
	border.position = Vector2(-34, -34)
	border.color = Color(0.8, 0.4, 1.0, 0.3)
	town_barrier.add_child(border)
	border.z_index = -1
	
	# 말풍선 생성
	_create_speech_bubble()
	
	# 결계 충돌 감지용 Area2D
	var barrier_area := Area2D.new()
	barrier_area.collision_layer = 0
	barrier_area.collision_mask = 2  # 플레이어 감지
	barrier_area.monitoring = true
	town_barrier.add_child(barrier_area)
	
	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = Vector2(70, 70)
	area_shape.shape = area_rect
	barrier_area.add_child(area_shape)
	barrier_area.body_entered.connect(_on_barrier_touched)
	
	# BattleManager 시그널 연결
	if BattleManager:
		BattleManager.battle_started.connect(_on_battle_started_barrier)
		BattleManager.all_battles_ended.connect(_on_all_battles_ended_barrier)
	
	# 초기 상태: 전투 없으면 결계 비활성화
	if BattleManager and BattleManager.get_active_battle_count() == 0:
		_deactivate_barrier()
	else:
		_activate_barrier()
	
	print("[Field] 마을 결계 시스템 초기화 완료")


func _create_speech_bubble() -> void:
	## 말풍선 UI 생성
	town_speech_bubble = Control.new()
	town_speech_bubble.z_index = 100
	town_area.add_child(town_speech_bubble)
	
	# 말풍선 배경
	var bubble_bg := NinePatchRect.new()
	bubble_bg.size = Vector2(180, 60)
	bubble_bg.position = Vector2(-90, -90)
	
	# NinePatchRect 대신 Panel 사용 (더 간단)
	var panel := PanelContainer.new()
	panel.size = Vector2(180, 70)
	panel.position = Vector2(-90, -100)
	town_speech_bubble.add_child(panel)
	
	# 스타일 설정
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.6, 0.4, 0.8, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	
	# 말풍선 텍스트
	var label := Label.new()
	label.text = "몬스터를 데려올 셈인가?\n먼저 처치하고 오게나."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0))
	label.add_theme_font_size_override("font_size", 11)
	panel.add_child(label)
	
	# 말풍선 꼬리 (삼각형)
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([
		Vector2(-8, 0),
		Vector2(8, 0),
		Vector2(0, 12)
	])
	tail.position = Vector2(0, -30)
	tail.color = Color(0.1, 0.1, 0.15, 0.95)
	town_speech_bubble.add_child(tail)
	
	# 초기에는 숨김
	town_speech_bubble.visible = false


func _on_barrier_touched(body: Node2D) -> void:
	## 결계에 부딪혔을 때
	if not body.is_in_group("party_leader"):
		return
	
	if not town_barrier or not town_barrier.visible:
		return
	
	# 말풍선 표시
	_show_speech_bubble()


func _show_speech_bubble() -> void:
	## 말풍선 표시 (2초 후 자동 숨김)
	if not town_speech_bubble:
		return
	
	town_speech_bubble.visible = true
	
	# 이전 타이머 정리
	if speech_bubble_timer and is_instance_valid(speech_bubble_timer):
		speech_bubble_timer.queue_free()
	
	# 새 타이머
	speech_bubble_timer = Timer.new()
	speech_bubble_timer.wait_time = 2.5
	speech_bubble_timer.one_shot = true
	speech_bubble_timer.timeout.connect(_hide_speech_bubble)
	add_child(speech_bubble_timer)
	speech_bubble_timer.start()


func _hide_speech_bubble() -> void:
	if town_speech_bubble:
		town_speech_bubble.visible = false


func _activate_barrier() -> void:
	## 결계 활성화 (전투 시작 시)
	if not town_barrier:
		return
	
	town_barrier.visible = true
	town_barrier.process_mode = Node.PROCESS_MODE_INHERIT
	
	# 등장 애니메이션
	if town_barrier_visual:
		town_barrier_visual.modulate.a = 0
		if barrier_tween and barrier_tween.is_valid():
			barrier_tween.kill()
		barrier_tween = create_tween()
		barrier_tween.tween_property(town_barrier_visual, "modulate:a", 1.0, 0.3)
		
		# 펄스 애니메이션 (반복)
		barrier_tween.tween_property(town_barrier_visual, "modulate:a", 0.6, 0.8)
		barrier_tween.tween_property(town_barrier_visual, "modulate:a", 1.0, 0.8)
		barrier_tween.set_loops()
	
	print("[Field] 🛡️ 마을 결계 활성화!")


func _deactivate_barrier() -> void:
	## 결계 비활성화 (전투 종료 시)
	if not town_barrier:
		return
	
	# 말풍선 숨기기
	_hide_speech_bubble()
	
	# 사라지는 애니메이션
	if barrier_tween and barrier_tween.is_valid():
		barrier_tween.kill()
	
	if town_barrier_visual:
		barrier_tween = create_tween()
		barrier_tween.tween_property(town_barrier_visual, "modulate:a", 0.0, 0.5)
		barrier_tween.tween_callback(_finish_deactivate_barrier)
	else:
		_finish_deactivate_barrier()
	
	print("[Field] ✨ 마을 결계 해제!")


func _finish_deactivate_barrier() -> void:
	if town_barrier:
		town_barrier.visible = false
		town_barrier.process_mode = Node.PROCESS_MODE_DISABLED


func _on_battle_started_barrier(_battle_id: int) -> void:
	## 전투 시작 시 결계 활성화
	_activate_barrier()


func _on_all_battles_ended_barrier() -> void:
	## 모든 전투 종료 시 결계 해제
	_deactivate_barrier()


func _save_field_position() -> void:
	## 현재 위치를 SaveManager에 저장
	if party_leader and SaveManager:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_stage_id,
			FieldManager.current_field_id
		)
		SaveManager.auto_save("필드 위치 저장")


func _update_hud() -> void:
	var hud_label: Label = get_node_or_null("CanvasLayer/HUD/StageLabel") as Label
	if hud_label:
		hud_label.text = FieldManager.get_display_name()
	
	var enemy_label: Label = get_node_or_null("CanvasLayer/HUD/EnemyCount") as Label
	if enemy_label:
		enemy_label.text = "적: %d" % field_enemies.size()
	
	var gold_label: Label = get_node_or_null("CanvasLayer/HUD/GoldLabel") as Label
	if gold_label and GameManager:
		gold_label.text = "Gold: %d" % GameManager.gold


func _on_field_enemy_contacted(field_enemy: FieldEnemy) -> void:
	print("[Field] 적 접촉: ", field_enemy.enemy_id, " (엘리트:", field_enemy.is_elite, ")")
	
	var enemy_data: Dictionary = DataManager.get_enemy(field_enemy.enemy_id)
	var enemy_name: String = str(enemy_data.get("name", field_enemy.enemy_id))
	
	var battle_enemies: Array = FieldManager.generate_battle_enemies(
		field_enemy.enemy_id,
		field_enemy.tile_type
	)
	
	print("[Field] 전투 구성: ", battle_enemies)
	
	# 로그 추가
	if hud:
		var log_msg: String = ""
		if field_enemy.is_elite:
			log_msg = "⭐ 엘리트 %s이(가) 나타났다!" % enemy_name
		elif battle_enemies.size() > 1:
			log_msg = "%s 외 %d마리가 나타났다!" % [enemy_name, battle_enemies.size() - 1]
		else:
			log_msg = "%s이(가) 나타났다!" % enemy_name
		hud.add_battle_log(log_msg)
	
	field_enemies.erase(field_enemy)
	var was_elite: bool = field_enemy.is_elite
	field_enemy.despawn()
	
	if BattleManager:
		# 엘리트 정보를 BattleManager에 전달
		var battle_id: int = BattleManager.start_battle(battle_enemies, self, was_elite)
		print("[Field] 전투 ID: ", battle_id, " 엘리트전투:", was_elite)
	
	battle_triggered.emit(battle_enemies)


func _on_exit_body_entered(body: Node2D) -> void:
	print("[Field] _on_exit_body_entered 호출! body: ", body.name)
	
	if not body.is_in_group("party_leader"):
		print("[Field] party_leader 아님, 무시")
		return
	
	print("[Field] 전투 수: ", BattleManager.get_active_battle_count() if BattleManager else "BM없음")
	print("[Field] 보스필드: ", FieldManager.is_boss_field())
	print("[Field] 필드적 수: ", field_enemies.size())
	
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		if hud:
			hud.add_system_log("전투 중에는 출구를 사용할 수 없다!")
		return
	
	if FieldManager.is_boss_field() and field_enemies.size() > 0:
		if hud:
			hud.add_system_log("보스를 처치해야 진행할 수 있다!")
		return
	
	var next: String = FieldManager.get_next_destination()
	print("[Field] 출구! 다음 목적지: ", next)
	
	if hud:
		hud.add_system_log("다음 구역으로 이동한다...")
	
	exit_reached.emit(next)
	
	if GameManager:
		GameManager.go_to_next_from_field()


func _on_town_body_entered(body: Node2D) -> void:
	## 마을 타일 진입 시 호출
	print("[Field] _on_town_body_entered 호출됨! body: ", body.name)
	
	if not body.is_in_group("party_leader"):
		print("[Field] party_leader 그룹이 아님, 무시")
		return
	
	# 전투 중이면 결계가 물리적으로 막아줌 - 여기까지 오면 전투 없음
	# (안전을 위한 더블 체크)
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		print("[Field] 전투 중 - 결계가 막아야 하는데?")
		return
	
	print("[Field] 🏠 마을 진입!")
	
	if hud:
		hud.add_system_log("마을로 향한다...")
	
	town_entered.emit()
	
	# 마을 다녀온 후 다음 필드로 진행하도록 설정
	# (Town.gd에서 출발 시 current_field를 사용)
	GameManager.advance_to_next_field()
	
	if GameManager:
		GameManager.go_to_town()


func _on_menu_pressed() -> void:
	_show_pause_menu()


#=============================================================================
# 🎮 일시정지 메뉴
#=============================================================================
var pause_menu: Control = null

func _show_pause_menu() -> void:
	if pause_menu:
		pause_menu.queue_free()
	
	# 게임 일시정지
	get_tree().paused = true
	
	# 메뉴 UI 생성
	pause_menu = Control.new()
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS  # 일시정지 중에도 동작
	
	# 어두운 배경
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	pause_menu.add_child(bg)
	
	# 중앙 패널
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(center)
	
	var panel := PanelContainer.new()
	center.add_child(panel)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	# 타이틀
	var title := Label.new()
	title.text = "일시정지"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# 버튼들
	var resume_btn := Button.new()
	resume_btn.text = "게임 계속"
	resume_btn.custom_minimum_size = Vector2(150, 35)
	resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_btn)
	
	var title_btn := Button.new()
	title_btn.text = "타이틀로"
	title_btn.custom_minimum_size = Vector2(150, 35)
	title_btn.pressed.connect(_on_title_pressed)
	vbox.add_child(title_btn)
	
	var quit_btn := Button.new()
	quit_btn.text = "게임 종료"
	quit_btn.custom_minimum_size = Vector2(150, 35)
	quit_btn.pressed.connect(_on_quit_game)
	vbox.add_child(quit_btn)
	
	add_child(pause_menu)
	resume_btn.grab_focus()


func _on_resume_pressed() -> void:
	_close_pause_menu()


func _on_title_pressed() -> void:
	# 저장 후 타이틀로
	if party_leader:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_stage_id,
			FieldManager.current_field_id
		)
	SaveManager.save_game()
	
	_close_pause_menu()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _close_pause_menu() -> void:
	get_tree().paused = false
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null


func _input(event: InputEvent) -> void:
	# ESC 키로 일시정지 토글
	if event.is_action_pressed("ui_cancel"):
		if pause_menu:
			_close_pause_menu()
		else:
			_show_pause_menu()


func get_remaining_enemies() -> int:
	return field_enemies.size()


func get_party_leader() -> PartyLeader:
	return party_leader


func get_hud() -> FieldHUD:
	return hud


#=============================================================================
# 🎮 게임오버 & 다시하기
#=============================================================================
func _on_party_wiped() -> void:
	print("[Field] ====== 파티 전멸! 게임오버 ======")
	
	# 리스폰 타이머 정지
	if respawn_timer:
		respawn_timer.stop()
		print("[Field] 리스폰 타이머 정지")
	
	# 모든 전투창 닫기
	if BattleManager:
		BattleManager.close_all_battles()
		print("[Field] 모든 전투창 닫음")
	
	# 세이브 데이터 삭제 (게임오버 = 로그라이크 사망)
	SaveManager.delete_save()
	print("[Field] 세이브 데이터 삭제됨")
	
	# 게임오버 UI 표시
	if game_over_ui:
		print("[Field] 게임오버 UI 표시")
		game_over_ui.show_game_over("파티가 전멸했습니다...")
	else:
		print("[Field] ERROR: game_over_ui가 없음!")


func _on_restart_game() -> void:
	# 타이틀 화면으로 이동
	print("[Field] 타이틀로 이동")
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_quit_game() -> void:
	print("[Field] 게임 종료")
	get_tree().quit()


func _on_loot_item_selected(item_id: String) -> void:
	print("[Field] 루트 선택: ", item_id)
	
	# 아이템 지급
	InventoryManager.add_item(item_id)
	
	# 로그 표시
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		item_data = DataManager.get_item(item_id)
	var item_name: String = str(item_data.get("name", item_id))
	
	if hud:
		hud.add_log("🎁 %s 획득!" % item_name, Color.GOLD)


func show_elite_loot() -> void:
	## 엘리트 전투 승리 시 3지선다 표시
	var loot_pool: Array[String] = _generate_elite_loot_pool()
	if loot_pool.size() >= 3 and loot_select_ui:
		loot_select_ui.show_loot_selection(loot_pool)


func _on_elite_victory(_battle_id: int) -> void:
	print("[Field] 엘리트 전투 승리! 3지선다 표시")
	show_elite_loot()


func _on_boss_victory(_battle_id: int) -> void:
	## 보스 전투 승리 시 호출
	print("[Field] 🎉 보스 전투 승리! 다음 스테이지로 진행 가능")
	
	if hud:
		hud.add_system_log("🎉 보스를 처치했다!")
		hud.add_system_log("출구로 향해 다음 스테이지로 진행하자!")
	
	# 리스폰 타이머 정지
	if respawn_timer:
		respawn_timer.stop()
	
	# 보스 루트 표시 (3지선다)
	show_boss_loot()


func show_boss_loot() -> void:
	## 보스 전투 승리 시 레전더리 포함 3지선다 표시
	var loot_pool: Array[String] = _generate_boss_loot_pool()
	if loot_pool.size() >= 3 and loot_select_ui:
		loot_select_ui.show_loot_selection(loot_pool)


func _generate_boss_loot_pool() -> Array[String]:
	## 보스 3지선다 - 레전더리 1개 + 매직 2개 보장
	var pool: Array[String] = []
	
	var magic_items: Array[String] = DataManager.get_equipment_by_rarity("magic")
	var legendary_items: Array[String] = DataManager.get_equipment_by_rarity("legendary")
	
	magic_items.shuffle()
	legendary_items.shuffle()
	
	# 1. 레전더리 1개 확정
	if not legendary_items.is_empty():
		pool.append(legendary_items[0])
	elif not magic_items.is_empty():
		pool.append(magic_items[0])
	
	# 2. 매직 2개 추가
	for item_id in magic_items:
		if pool.size() >= 3:
			break
		if not pool.has(item_id):
			pool.append(item_id)
	
	pool.shuffle()
	return pool


func _generate_elite_loot_pool() -> Array[String]:
	## 3지선다 아이템 풀 생성 - 매직 이상 아이템 최소 1개 보장
	var pool: Array[String] = []
	
	# DataManager에서 실제 존재하는 장비 가져오기
	var common_items: Array[String] = DataManager.get_equipment_by_rarity("common")
	var magic_items: Array[String] = DataManager.get_equipment_by_rarity("magic")
	var legendary_items: Array[String] = DataManager.get_equipment_by_rarity("legendary")
	
	# 셔플
	common_items.shuffle()
	magic_items.shuffle()
	legendary_items.shuffle()
	
	# 1. 먼저 매직 이상 아이템 최소 1개 확정
	# 20% 확률로 레전더리, 아니면 매직
	if randf() < 0.2 and not legendary_items.is_empty():
		pool.append(legendary_items[0])
	elif not magic_items.is_empty():
		pool.append(magic_items[0])
	elif not legendary_items.is_empty():
		# 매직이 없으면 레전더리라도
		pool.append(legendary_items[0])
	
	# 2. 나머지 2개는 전체 장비에서 랜덤 (common 포함)
	var all_items: Array[String] = []
	all_items.append_array(common_items)
	all_items.append_array(magic_items)
	all_items.append_array(legendary_items)
	all_items.shuffle()
	
	for item_id in all_items:
		if pool.size() >= 3:
			break
		if not pool.has(item_id):
			pool.append(item_id)
	
	# 최종 셔플 (매직이 항상 첫 번째에 안 오도록)
	pool.shuffle()
	
	return pool
