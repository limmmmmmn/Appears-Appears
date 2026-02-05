extends Node2D
## 필드 씬 컨트롤러 (리팩토링 버전)

signal battle_triggered(battle_enemies: Array)
signal exit_reached(next_destination: String)
signal town_entered
signal field_cleared

@export var spawn_point: Marker2D
@export var exit_area: Area2D
@export var town_area: Area2D
@export var tilemap: TileMapLayer

var party_leader: PartyMember
var party_followers: Array[PartyMember] = []
var field_enemies: Array[FieldEnemy] = []
var hud: FieldHUD
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
var town_barrier: TownBarrier
var pause_menu: PauseMenu


func _ready() -> void:
	_load_scenes()
	_find_tilemap()
	_setup_systems()
	_spawn_party()
	_spawn_field_enemies()
	_setup_exit()
	_connect_signals()
	
	if hud:
		hud.add_system_log("필드에 입장했다.")


func _process(_delta: float) -> void:
	# 이동 기반 적 스폰 체크
	if spawner and not FieldManager.is_boss_field():
		spawner.update_movement_spawn(field_enemies)
		
		# 새로 스폰된 적에게 시그널 연결
		for enemy in field_enemies:
			if not enemy.player_contacted.is_connected(_on_field_enemy_contacted):
				enemy.player_contacted.connect(_on_field_enemy_contacted)


func _load_scenes() -> void:
	party_leader_scene = load("res://scenes/field/PartyMember.tscn")
	party_follower_scene = load("res://scenes/field/PartyMember.tscn")
	field_enemy_scene = load("res://scenes/field/FieldEnemy.tscn")
	hud_scene = load("res://scenes/ui/FieldHUD.tscn")


func _find_tilemap() -> void:
	if tilemap:
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


func _setup_systems() -> void:
	# HUD - 씬에 이미 존재하는 HUD 노드를 재사용하거나 새로 생성
	var existing_hud = get_node_or_null("HUD")
	if existing_hud and existing_hud is FieldHUD:
		hud = existing_hud as FieldHUD
	else:
		# 혹시 다른 이름으로 존재할 경우 제거
		var old_hud = get_node_or_null("CanvasLayer")
		if old_hud:
			old_hud.queue_free()
		hud = hud_scene.instantiate() as FieldHUD
		add_child(hud)
	if not hud.menu_pressed.is_connected(_on_menu_pressed):
		hud.menu_pressed.connect(_on_menu_pressed)
	
	# 게임오버 UI
	game_over_ui = GameOverUI.new()
	add_child(game_over_ui)
	game_over_ui.restart_pressed.connect(_on_restart_game)
	game_over_ui.quit_pressed.connect(_on_quit_game)
	
	# 스포너
	spawner = EnemySpawner.new()
	spawner.setup(self, tilemap)
	
	# 일시정지 메뉴
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume_pressed.connect(_on_resume_pressed)
	pause_menu.title_pressed.connect(_on_title_pressed)
	pause_menu.quit_pressed.connect(_on_quit_game)


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
		# 보스전 관전 시스템
		if not BattleManager.boss_battle_started.is_connected(_on_boss_battle_started):
			BattleManager.boss_battle_started.connect(_on_boss_battle_started)
		if not BattleManager.boss_battle_ended.is_connected(_on_boss_battle_ended):
			BattleManager.boss_battle_ended.connect(_on_boss_battle_ended)


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


#=============================================================================
# 출구/마을 설정
#=============================================================================
func _setup_exit() -> void:
	if not exit_area:
		exit_area = get_node_or_null("ExitArea")
	if exit_area and not exit_area.body_entered.is_connected(_on_exit_body_entered):
		exit_area.body_entered.connect(_on_exit_body_entered)
	
	if not town_area:
		town_area = get_node_or_null("TownArea")
	if town_area:
		if not town_area.body_entered.is_connected(_on_town_body_entered):
			town_area.body_entered.connect(_on_town_body_entered)
		# 결계 시스템
		town_barrier = TownBarrier.new()
		town_barrier.setup(self, town_area)
	
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
	## 필드 적과 충돌 시 - 전투창 증식 시스템 (1:1 대응)
	## 필드 적 1마리 = 전투창 적 1마리

	# 적만 잠시 멈춤 효과 (조우 시 멈칫)
	field_enemy.brief_pause(0.25)

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

	# 로그
	if hud:
		var msg: String
		if field_enemy.is_elite:
			msg = "⭐ 엘리트 %s이(가) 나타났다!" % enemy_name
		else:
			msg = "%s이(가) 나타났다!" % enemy_name
		hud.add_battle_log(msg)

	# 리스폰 큐에 추가 (보스가 아닌 경우)
	if spawner:
		spawner.on_enemy_killed(tile_type, enemy_pos)

	field_enemies.erase(field_enemy)
	field_enemy.despawn()

	# 새 시스템: 적 1마리씩 전투에 추가 (기존 창에 추가되거나 새 창 생성)
	if BattleManager:
		BattleManager.add_enemy_to_battle(enemy_id, self, was_elite, collision_pos)

	battle_triggered.emit([enemy_id])


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
	if hud and hud.has_unclaimed_rewards():
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
	var field_enemy: FieldEnemy = pending_boss_data.get("field_enemy")

	# 로그
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	var enemy_name: String = str(enemy_data.get("name", enemy_id))
	if hud:
		hud.add_system_log("👑 %s와(과)의 보스전 시작!" % enemy_name)

	# 필드 적 제거
	if is_instance_valid(field_enemy):
		field_enemies.erase(field_enemy)
		field_enemy.despawn()

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


func _on_town_body_entered(body: Node2D) -> void:
	if not body.is_in_group("party_leader"):
		return

	if BattleManager and BattleManager.get_active_battle_count() > 0:
		return

	# 누적 보상이 있으면 확인 팝업 표시
	if hud and hud.has_unclaimed_rewards():
		if not hud.town_enter_confirmed.is_connected(_on_town_enter_confirmed):
			hud.town_enter_confirmed.connect(_on_town_enter_confirmed, CONNECT_ONE_SHOT)
		hud.show_town_enter_popup()
		return

	# 보상이 없으면 바로 마을로
	_enter_town()


func _on_town_enter_confirmed(_claimed_rewards: bool) -> void:
	## 마을 진입 확인 팝업에서 선택 완료
	_enter_town()


func _enter_town() -> void:
	## 실제 마을 진입 처리
	if hud:
		hud.add_system_log("마을로 향한다...")

	town_entered.emit()
	GameManager.advance_to_next_field()
	if GameManager:
		GameManager.go_to_town()


#=============================================================================
# 메뉴 & 게임오버
#=============================================================================
func _on_menu_pressed() -> void:
	pause_menu.show_menu()


func _on_resume_pressed() -> void:
	# 메뉴에서 돌아올 때 특별한 처리가 필요하면 여기에
	pass


func _on_title_pressed() -> void:
	if party_leader:
		SaveManager.save_field_position(
			party_leader.global_position,
			FieldManager.current_stage_id,
			FieldManager.current_field_id
		)
	SaveManager.save_game()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_party_wiped() -> void:
	spawner.stop_respawn()
	
	if BattleManager:
		BattleManager.close_all_battles()
	
	SaveManager.delete_save()
	
	if game_over_ui:
		game_over_ui.show_game_over("파티가 전멸했습니다...")


func _on_restart_game() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


func _on_quit_game() -> void:
	get_tree().quit()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if pause_menu.is_visible_menu():
			pause_menu.hide_menu()
		else:
			pause_menu.show_menu()


func _on_elite_victory(_battle_id: int) -> void:
	# 엘리트 보상은 누적 보상 시스템으로 처리됨
	pass


func _on_boss_victory(_battle_id: int) -> void:
	if hud:
		hud.add_system_log("🎉 보스를 처치했다!")
		hud.add_system_log("출구로 향해 다음 스테이지로 진행하자!")

	spawner.stop_respawn()
	# 보스 보상은 누적 보상 시스템으로 처리됨


func _on_boss_battle_started(_battle_id: int) -> void:
	## 보스전 시작 - 모든 필드 적이 관전 모드로 전환
	var camera_rect := _get_camera_rect()

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
# 유틸리티
#=============================================================================
func get_remaining_enemies() -> int:
	return field_enemies.size()


func get_party_leader() -> PartyMember:
	return party_leader


func get_hud() -> FieldHUD:
	return hud
