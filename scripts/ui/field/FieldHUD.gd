extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## - TopBar: 스테이지, 골드, 배속, 메뉴
## - LogPanel: 전투 로그 (좌측 하단)
## - BottomPartyPanel: 파티 정보 (하단 중앙) - 외부 씬
## - MinimapPanel: 미니맵 (우측 하단)

signal menu_pressed
signal move_style_changed(style: int)  # 이동 스타일 변경 시그널

# === 이동 스타일 ===
enum MoveStyle { RANDOM, HUNT_ENEMY, OFF, TO_TOWN, TO_BOSS }
var current_move_style: MoveStyle = MoveStyle.RANDOM
var move_style_panel: PanelContainer = null

# === 상단 바 ===
@onready var stage_label: Label = %StageLabel
@onready var gold_label: Label = %GoldLabel
@onready var speed_button: Button = %SpeedButton
@onready var menu_button: Button = %MenuButton

# === 로그 패널 (좌측 하단) ===
@onready var log_panel: PanelContainer = %LogPanel
@onready var log_scroll: ScrollContainer = %LogScroll
@onready var log_container: VBoxContainer = %LogContainer

# === 하단 파티 패널 (중앙) - 외부 씬 ===
@onready var bottom_party_panel: BottomPartyPanel = %BottomPartyPanel

# === 미니맵 패널 (우측 하단) ===
@onready var minimap_panel: PanelContainer = %MinimapPanel
@onready var minimap_viewport: SubViewportContainer = %MinimapViewport
@onready var minimap_camera: Camera2D = %MinimapCamera

# === 특성 패널 (우측) ===
@onready var trait_panel: PanelContainer = %TraitPanel
@onready var trait_vbox: VBoxContainer = %TraitVBox

# === 원념 선택 팝업 (전체 화면) ===
var grudge_popup: CanvasLayer = null
var is_grudge_popup_active: bool = false

# === 마을 진입 확인 팝업 ===
var town_popup: CanvasLayer = null
var is_town_popup_active: bool = false
signal town_enter_confirmed(claim_rewards: bool)  # 마을 진입 확정 시그널

# === 컴포넌트 ===
var battle_log: BattleLogUI = null

# === 미니맵 설정 ===
var minimap_zoom: float = 0.1  # 미니맵 줌 레벨 (작을수록 더 넓은 영역 표시)
var minimap_target: Node2D = null  # 추적할 대상 (파티 리더)


func _ready() -> void:
	add_to_group("field_hud")
	_setup_components()
	_setup_grudge_popup()
	_setup_town_popup()
	_connect_signals()
	update_all()
	_update_trait_display()


func _process(_delta: float) -> void:
	_update_minimap()


func _setup_components() -> void:
	_setup_speed_button()
	_setup_move_style_panel()

	# 배틀 로그
	battle_log = BattleLogUI.new()
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if log_container:
		log_container.add_child(battle_log)

	# 미니맵 카메라 초기 설정
	if minimap_camera:
		minimap_camera.zoom = Vector2(minimap_zoom, minimap_zoom)


func _setup_speed_button() -> void:
	if not speed_button:
		return
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.6, 0.9)
	speed_button.add_theme_stylebox_override("normal", style)
	
	var hover := style.duplicate()
	hover.bg_color = Color(0.25, 0.25, 0.3, 0.95)
	speed_button.add_theme_stylebox_override("hover", hover)


func _setup_move_style_panel() -> void:
	## 우측 중단에 이동 스타일 패널 생성
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	move_style_panel = PanelContainer.new()
	move_style_panel.name = "MoveStylePanel"

	# 스타일
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.3, 0.5, 0.7)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	move_style_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	move_style_panel.add_child(vbox)

	# 제목
	var title := Label.new()
	title.text = "[ 이동 ]"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 버튼들
	var styles: Array[Dictionary] = [
		{"text": "랜덤", "style": MoveStyle.RANDOM},
		{"text": "적 사냥", "style": MoveStyle.HUNT_ENEMY},
		{"text": "끄기", "style": MoveStyle.OFF},
		{"text": "마을로", "style": MoveStyle.TO_TOWN},
		{"text": "보스에게", "style": MoveStyle.TO_BOSS},
	]

	for item in styles:
		var btn := Button.new()
		btn.text = item["text"]
		btn.custom_minimum_size = Vector2(70, 24)
		btn.add_theme_font_size_override("font_size", 10)
		btn.focus_mode = Control.FOCUS_NONE

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
		btn_style.corner_radius_top_left = 3
		btn_style.corner_radius_top_right = 3
		btn_style.corner_radius_bottom_left = 3
		btn_style.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", btn_style)

		var btn_hover := btn_style.duplicate()
		btn_hover.bg_color = Color(0.25, 0.25, 0.35, 0.95)
		btn.add_theme_stylebox_override("hover", btn_hover)

		var style_value: int = item["style"]
		btn.pressed.connect(_on_move_style_button_pressed.bind(style_value))
		vbox.add_child(btn)

	ctrl.add_child(move_style_panel)

	# 우측 중단 위치 (앵커 사용)
	move_style_panel.anchor_left = 1.0
	move_style_panel.anchor_right = 1.0
	move_style_panel.anchor_top = 0.5
	move_style_panel.anchor_bottom = 0.5
	move_style_panel.offset_left = -90
	move_style_panel.offset_right = -10
	move_style_panel.offset_top = -90
	move_style_panel.offset_bottom = 90
	move_style_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	move_style_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	# 초기 스타일 표시 업데이트
	call_deferred("_update_move_style_buttons")


func _on_move_style_button_pressed(style: int) -> void:
	## 이동 스타일 버튼 클릭
	current_move_style = style as MoveStyle
	_update_move_style_buttons()
	move_style_changed.emit(style)

	# 파티 리더에게 직접 전달
	var leader := get_tree().get_first_node_in_group("party_leader")
	if leader and leader.has_method("set_move_style"):
		leader.set_move_style(style)


func _update_move_style_buttons() -> void:
	## 현재 선택된 스타일 버튼 강조
	if not move_style_panel:
		return

	var vbox := move_style_panel.get_child(0)
	if not vbox:
		return

	var idx: int = 0
	for child in vbox.get_children():
		if child is Button:
			var is_selected: bool = (idx == current_move_style)
			if is_selected:
				child.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
				var sel_style := StyleBoxFlat.new()
				sel_style.bg_color = Color(0.2, 0.4, 0.3, 0.95)
				sel_style.corner_radius_top_left = 3
				sel_style.corner_radius_top_right = 3
				sel_style.corner_radius_bottom_left = 3
				sel_style.corner_radius_bottom_right = 3
				sel_style.border_width_left = 2
				sel_style.border_width_right = 2
				sel_style.border_color = Color(0.4, 0.8, 0.5)
				child.add_theme_stylebox_override("normal", sel_style)
			else:
				child.remove_theme_color_override("font_color")
				var norm_style := StyleBoxFlat.new()
				norm_style.bg_color = Color(0.15, 0.15, 0.2, 0.9)
				norm_style.corner_radius_top_left = 3
				norm_style.corner_radius_top_right = 3
				norm_style.corner_radius_bottom_left = 3
				norm_style.corner_radius_bottom_right = 3
				child.add_theme_stylebox_override("normal", norm_style)
			idx += 1


func _connect_signals() -> void:
	if menu_button:
		menu_button.pressed.connect(func(): menu_pressed.emit())
	if speed_button:
		speed_button.pressed.connect(_on_speed_button_pressed)

	if GameManager:
		GameManager.gold_changed.connect(func(_g): update_top_bar())

	if BattleManager:
		if not BattleManager.battle_log_received.is_connected(_on_battle_log_received):
			BattleManager.battle_log_received.connect(_on_battle_log_received)
		if not BattleManager.party_hp_changed.is_connected(update_party_display):
			BattleManager.party_hp_changed.connect(update_party_display)
		if not BattleManager.loot_animation_requested.is_connected(_on_loot_animation_requested):
			BattleManager.loot_animation_requested.connect(_on_loot_animation_requested)
		if not BattleManager.danger_level_up.is_connected(show_grudge_choice_popup):
			BattleManager.danger_level_up.connect(show_grudge_choice_popup)

	if PartyManager:
		if not PartyManager.hero_leveled_up.is_connected(_on_hero_leveled_up):
			PartyManager.hero_leveled_up.connect(_on_hero_leveled_up)


#region 미니맵
func _update_minimap() -> void:
	if not minimap_camera:
		return
	
	# 추적 대상이 없으면 파티 리더 찾기
	if not is_instance_valid(minimap_target):
		_find_minimap_target()
	
	# 대상이 있으면 카메라 위치 업데이트
	if is_instance_valid(minimap_target):
		minimap_camera.global_position = minimap_target.global_position


func _find_minimap_target() -> void:
	# 필드 씬에서 PartyMember (리더) 찾기
	var field = get_tree().get_first_node_in_group("field")
	if field:
		var leader = field.get_node_or_null("PartyLeader")
		if leader:
			minimap_target = leader
			return
	
	# 그룹으로 찾기
	var party_members = get_tree().get_nodes_in_group("party_member")
	if party_members.size() > 0:
		minimap_target = party_members[0]


func set_minimap_target(target: Node2D) -> void:
	## 미니맵이 추적할 대상 설정
	minimap_target = target


func set_minimap_zoom(zoom_level: float) -> void:
	## 미니맵 줌 레벨 설정 (0.05 ~ 0.5 권장)
	minimap_zoom = clamp(zoom_level, 0.02, 1.0)
	if minimap_camera:
		minimap_camera.zoom = Vector2(minimap_zoom, minimap_zoom)


func get_minimap_viewport() -> SubViewport:
	## 미니맵 SubViewport 반환 (외부에서 레이어 추가 등에 사용)
	if minimap_viewport:
		return minimap_viewport.get_node_or_null("SubViewport")
	return null
#endregion


#region 이벤트 핸들러
func _on_speed_button_pressed() -> void:
	## 턴제 전투에서는 배속 버튼 미사용
	pass


func _update_speed_button() -> void:
	## 턴제 전투 - 배속 버튼 숨김
	if speed_button:
		speed_button.visible = false


func _on_battle_log_received(message: String, color: Color) -> void:
	add_log(message, color)


func _on_loot_animation_requested(item_id: String, start_pos: Vector2) -> void:
	# 미니맵 패널 위치로 애니메이션 (또는 하단 중앙)
	var target_pos: Vector2 = _get_loot_target_position()
	
	var loot_anim := LootAnimationUI.new()
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(loot_anim)
	else:
		add_child(loot_anim)
	
	loot_anim.animation_completed.connect(_on_loot_animation_completed)
	loot_anim.setup(item_id, start_pos, target_pos)


func _get_loot_target_position() -> Vector2:
	# 하단 파티 패널 중앙으로 루팅 애니메이션
	if bottom_party_panel and is_instance_valid(bottom_party_panel):
		return bottom_party_panel.global_position + bottom_party_panel.size / 2
	return Vector2(240, 200)


func _on_loot_animation_completed(_item_id: String) -> void:
	# 인벤토리 패널 삭제됨 - 필요시 다른 피드백 추가
	pass
#endregion


#region 업데이트
func update_all() -> void:
	update_top_bar()
	update_party_display()
	_update_speed_button()


func update_top_bar() -> void:
	if stage_label and FieldManager:
		var fn = FieldManager.get_current_field_name()
		stage_label.text = FieldManager.get_display_name() + (": " + fn if fn else "")
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold
	_update_speed_button()


func update_party_display() -> void:
	if bottom_party_panel:
		bottom_party_panel.update_display()
#endregion


#region 로그
func add_log(msg: String, color: Color = Color.WHITE) -> void:
	if battle_log:
		battle_log.add_log(msg, color)

func add_battle_log(msg: String) -> void:
	if battle_log:
		battle_log.add_battle(msg)

func add_damage_log(atk: String, tgt: String, dmg: int, crit: bool = false) -> void:
	if battle_log:
		battle_log.add_damage(atk, tgt, dmg, crit)

func add_heal_log(h: String, t: String, amt: int) -> void:
	if battle_log:
		battle_log.add_heal(h, t, amt)

func add_defeat_log(t: String) -> void:
	if battle_log:
		battle_log.add_defeat(t)

func add_exp_log(e: int) -> void:
	if battle_log:
		battle_log.add_exp(e)

func add_gold_log(g: int) -> void:
	if battle_log:
		battle_log.add_gold(g)

func add_item_log(n: String) -> void:
	if battle_log:
		battle_log.add_item(n)

func add_system_log(msg: String) -> void:
	if battle_log:
		battle_log.add_system(msg)

func add_level_up_log(hero_name: String, new_level: int) -> void:
	if battle_log:
		battle_log.add_level_up(hero_name, new_level)

func clear_logs() -> void:
	if battle_log:
		battle_log.clear()


func _on_hero_leveled_up(hero: Hero, new_level: int) -> void:
	## 영웅 레벨업 알림
	add_level_up_log(hero.hero_name, new_level)
	update_party_display()
#endregion


#region 특성 시스템
func _update_trait_display() -> void:
	## 파티원별 룬/특성을 패널에 표시
	if trait_vbox == null:
		return

	# 기존 자식 제거
	for child in trait_vbox.get_children():
		child.queue_free()

	# 룬을 가진 파티원 수집
	var heroes_with_runes: Array = []
	for hero in PartyManager.get_alive_heroes():
		if not hero.equipped_rune_id.is_empty():
			heroes_with_runes.append(hero)

	if heroes_with_runes.is_empty():
		if trait_panel:
			trait_panel.visible = false
		return

	if trait_panel:
		trait_panel.visible = true
		# 반투명 배경 스타일
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0, 0, 0, 0.5)
		panel_style.corner_radius_top_left = 4
		panel_style.corner_radius_bottom_left = 4
		panel_style.content_margin_left = 8
		panel_style.content_margin_right = 8
		panel_style.content_margin_top = 6
		panel_style.content_margin_bottom = 6
		trait_panel.add_theme_stylebox_override("panel", panel_style)

	# 제목
	var title_label := Label.new()
	title_label.text = "[ 장착 룬 ]"
	title_label.add_theme_font_size_override("font_size", 10)
	title_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	trait_vbox.add_child(title_label)

	# 구분선
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	trait_vbox.add_child(separator)

	# 파티원별 특성 표시
	for hero in heroes_with_runes:
		var rune_data: Dictionary = hero.get_equipped_rune()
		var trait_data: Dictionary = DataManager.get_rune_trait(hero.equipped_rune_id)
		if trait_data.is_empty():
			continue

		# 파티원별 컨테이너
		var hero_container := VBoxContainer.new()
		hero_container.add_theme_constant_override("separation", 0)
		trait_vbox.add_child(hero_container)

		# 상단: 영웅 이름 + 룬 아이콘
		var hero_hbox := HBoxContainer.new()
		hero_hbox.add_theme_constant_override("separation", 4)
		hero_container.add_child(hero_hbox)

		# 영웅 이름
		var hero_label := Label.new()
		hero_label.text = hero.hero_name
		hero_label.add_theme_font_size_override("font_size", 9)
		hero_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		hero_hbox.add_child(hero_label)

		# 룬 아이콘
		var rune_icon := Label.new()
		rune_icon.text = rune_data.get("icon", "")
		rune_icon.add_theme_font_size_override("font_size", 10)
		hero_hbox.add_child(rune_icon)

		# 중단: 특성 아이콘 + 이름
		var trait_hbox := HBoxContainer.new()
		trait_hbox.add_theme_constant_override("separation", 4)
		hero_container.add_child(trait_hbox)

		# 특성 아이콘
		var trait_icon := Label.new()
		trait_icon.text = "  " + trait_data.get("icon", "")
		trait_icon.add_theme_font_size_override("font_size", 10)
		trait_hbox.add_child(trait_icon)

		# 특성 이름
		var trait_name := Label.new()
		trait_name.text = trait_data.get("name", "")
		trait_name.add_theme_font_size_override("font_size", 9)
		trait_name.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		trait_name.add_theme_color_override("font_outline_color", Color.BLACK)
		trait_name.add_theme_constant_override("outline_size", 2)
		trait_hbox.add_child(trait_name)

		# 하단: 설명
		var desc_label := Label.new()
		desc_label.text = "    " + trait_data.get("description", "")
		desc_label.add_theme_font_size_override("font_size", 8)
		desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		hero_container.add_child(desc_label)


func refresh_traits() -> void:
	## 외부에서 특성 갱신 요청 시 호출
	_update_trait_display()
#endregion


#region 원념 선택 팝업
func _setup_grudge_popup() -> void:
	## 원념 레벨업 시 표시되는 전체 화면 선택 팝업
	grudge_popup = CanvasLayer.new()
	grudge_popup.name = "GrudgePopup"
	grudge_popup.layer = 100  # 최상위 레이어
	grudge_popup.visible = false
	grudge_popup.process_mode = Node.PROCESS_MODE_ALWAYS  # 일시정지 중에도 동작
	add_child(grudge_popup)


func show_grudge_choice_popup(danger_level: int) -> void:
	## 원념 레벨업 선택 팝업 표시
	if is_grudge_popup_active:
		return

	is_grudge_popup_active = true
	get_tree().paused = true  # 게임 일시정지
	grudge_popup.visible = true

	# 기존 내용 제거
	for child in grudge_popup.get_children():
		child.queue_free()

	# 전체 화면 컨테이너
	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	grudge_popup.add_child(full_screen)

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
	center_panel.offset_top = -120
	center_panel.offset_bottom = 120
	center_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.05, 0.15, 0.95)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.8, 0.4, 1.0)
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
	vbox.add_theme_constant_override("separation", 10)
	center_panel.add_child(vbox)

	# 제목
	var title := Label.new()
	title.text = "⚠ 원념 %d단계!" % danger_level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.8))
	vbox.add_child(title)

	# 설명
	var desc := Label.new()
	desc.text = "적이 더 강해집니다.\n계속 원념을 쌓으시겠습니까?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(desc)

	# 구분선
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 현재 보상 목록
	var reward_title := Label.new()
	reward_title.text = "[ 현재 보상 ]"
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_title.add_theme_font_size_override("font_size", 10)
	reward_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(reward_title)

	var rewards: Dictionary = BattleManager.get_accumulated_rewards()

	# EXP/Gold
	var reward_info := HBoxContainer.new()
	reward_info.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_info.add_theme_constant_override("separation", 20)
	vbox.add_child(reward_info)

	var exp_lbl := Label.new()
	exp_lbl.text = "EXP: %d" % rewards.exp
	exp_lbl.add_theme_font_size_override("font_size", 11)
	exp_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	reward_info.add_child(exp_lbl)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: %d" % rewards.gold
	gold_lbl.add_theme_font_size_override("font_size", 11)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	reward_info.add_child(gold_lbl)

	# 아이템 목록 (타입 + 희귀도 색상)
	if rewards.items.size() > 0:
		var items_hbox := HBoxContainer.new()
		items_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		items_hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(items_hbox)

		for item in rewards.items:
			var item_lbl := Label.new()
			var type_name: String = InventoryManager.get_item_type_name(item.id)
			item_lbl.text = "?" + type_name
			item_lbl.add_theme_font_size_override("font_size", 10)
			var rarity_color: Color = InventoryManager.get_rarity_color(item.id)
			item_lbl.add_theme_color_override("font_color", rarity_color)
			items_hbox.add_child(item_lbl)

	# 구분선
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# 선택 버튼
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 30)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)

	var go_btn := Button.new()
	go_btn.text = "▶ 고 (계속) ◀"
	go_btn.custom_minimum_size = Vector2(100, 35)
	go_btn.add_theme_font_size_override("font_size", 12)
	go_btn.focus_mode = Control.FOCUS_NONE
	var go_style := StyleBoxFlat.new()
	go_style.bg_color = Color(0.3, 0.6, 0.3)
	go_style.border_width_left = 2
	go_style.border_width_top = 2
	go_style.border_width_right = 2
	go_style.border_width_bottom = 2
	go_style.border_color = Color.WHITE
	go_style.corner_radius_top_left = 4
	go_style.corner_radius_top_right = 4
	go_style.corner_radius_bottom_left = 4
	go_style.corner_radius_bottom_right = 4
	go_btn.add_theme_stylebox_override("normal", go_style)
	go_btn.add_theme_stylebox_override("hover", go_style)
	btn_hbox.add_child(go_btn)

	var stop_btn := Button.new()
	stop_btn.text = "스톱 (보상)"
	stop_btn.custom_minimum_size = Vector2(100, 35)
	stop_btn.add_theme_font_size_override("font_size", 12)
	stop_btn.focus_mode = Control.FOCUS_NONE
	var stop_style := StyleBoxFlat.new()
	stop_style.bg_color = Color(0.3, 0.2, 0.2)
	stop_style.corner_radius_top_left = 4
	stop_style.corner_radius_top_right = 4
	stop_style.corner_radius_bottom_left = 4
	stop_style.corner_radius_bottom_right = 4
	stop_btn.add_theme_stylebox_override("normal", stop_style)
	stop_btn.add_theme_stylebox_override("hover", stop_style)
	stop_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	btn_hbox.add_child(stop_btn)

	# 힌트
	var hint := Label.new()
	hint.text = "[← →] 선택  [Enter] 결정"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(hint)

	# 선택 상태 추적
	var selection: int = 0  # 0 = 고, 1 = 스톱
	var buttons: Array = [go_btn, stop_btn]
	var go_style_selected := go_style.duplicate()
	var stop_style_selected := stop_style.duplicate()
	stop_style_selected.bg_color = Color(0.6, 0.3, 0.3)
	stop_style_selected.border_width_left = 2
	stop_style_selected.border_width_top = 2
	stop_style_selected.border_width_right = 2
	stop_style_selected.border_width_bottom = 2
	stop_style_selected.border_color = Color.WHITE

	# 입력 처리 노드
	var input_handler := Node.new()
	input_handler.name = "InputHandler"
	input_handler.process_mode = Node.PROCESS_MODE_ALWAYS
	input_handler.set_script(load("res://scripts/ui/field/GrudgePopupInput.gd"))
	input_handler.set("hud", self)
	input_handler.set("go_btn", go_btn)
	input_handler.set("stop_btn", stop_btn)
	input_handler.set("go_style", go_style)
	input_handler.set("stop_style", stop_style)
	input_handler.set("go_style_selected", go_style_selected)
	input_handler.set("stop_style_selected", stop_style_selected)
	full_screen.add_child(input_handler)


func _on_grudge_go_selected() -> void:
	## "고" 선택 - 계속 진행
	is_grudge_popup_active = false
	grudge_popup.visible = false
	get_tree().paused = false

	# 기존 내용 제거
	for child in grudge_popup.get_children():
		child.queue_free()

	BattleManager.battle_log_received.emit("원념을 계속 쌓는다!", Color.MAGENTA)


func _on_grudge_stop_selected() -> void:
	## "스톱" 선택 - 보상 수령
	is_grudge_popup_active = false
	grudge_popup.visible = false
	get_tree().paused = false

	# 기존 내용 제거
	for child in grudge_popup.get_children():
		child.queue_free()

	# 보상 수령
	BattleManager.claim_accumulated_rewards()

	# 모든 전투창 닫기
	BattleManager.close_all_battles()

	BattleManager.battle_log_received.emit("보상을 획득했다!", Color.CYAN)
#endregion


#region 마을 진입 확인 팝업
func _setup_town_popup() -> void:
	## 마을 진입 확인 팝업 초기화
	town_popup = CanvasLayer.new()
	town_popup.name = "TownPopup"
	town_popup.layer = 100
	town_popup.visible = false
	town_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(town_popup)


func show_town_enter_popup() -> void:
	## 마을 진입 시 누적 보상 확인 팝업 표시
	if is_town_popup_active:
		return

	is_town_popup_active = true
	get_tree().paused = true
	town_popup.visible = true

	# 기존 내용 제거
	for child in town_popup.get_children():
		child.queue_free()

	# 전체 화면 컨테이너
	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	town_popup.add_child(full_screen)

	# 어둡게 처리
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.7)
	full_screen.add_child(dimmer)

	# 중앙 패널
	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -180
	center_panel.offset_right = 180
	center_panel.offset_top = -140
	center_panel.offset_bottom = 140
	center_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(0.4, 0.7, 1.0)
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
	vbox.add_theme_constant_override("separation", 10)
	center_panel.add_child(vbox)

	# 제목
	var title := Label.new()
	title.text = "🏠 마을로 돌아가시겠습니까?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	vbox.add_child(title)

	# 설명
	var desc := Label.new()
	desc.text = "받지 않은 보상이 있습니다.\n보상을 받고 마을로 들어가시겠습니까?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(desc)

	# 구분선
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 현재 보상 목록
	var reward_title := Label.new()
	reward_title.text = "[ 누적 보상 ]"
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_title.add_theme_font_size_override("font_size", 10)
	reward_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(reward_title)

	var rewards: Dictionary = BattleManager.get_accumulated_rewards()

	# EXP/Gold
	var reward_info := HBoxContainer.new()
	reward_info.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_info.add_theme_constant_override("separation", 20)
	vbox.add_child(reward_info)

	var exp_lbl := Label.new()
	exp_lbl.text = "EXP: %d" % rewards.exp
	exp_lbl.add_theme_font_size_override("font_size", 12)
	exp_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	reward_info.add_child(exp_lbl)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: %d" % rewards.gold
	gold_lbl.add_theme_font_size_override("font_size", 12)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	reward_info.add_child(gold_lbl)

	# 아이템 목록
	if rewards.items.size() > 0:
		var items_hbox := HBoxContainer.new()
		items_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		items_hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(items_hbox)

		for item in rewards.items:
			var item_lbl := Label.new()
			var type_name: String = InventoryManager.get_item_type_name(item.id)
			item_lbl.text = "?" + type_name
			item_lbl.add_theme_font_size_override("font_size", 10)
			var rarity_color: Color = InventoryManager.get_rarity_color(item.id)
			item_lbl.add_theme_color_override("font_color", rarity_color)
			items_hbox.add_child(item_lbl)

	# 구분선
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# 선택 버튼
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_vbox)

	# 보상 받고 들어가기 버튼
	var claim_btn := Button.new()
	claim_btn.text = "✓ 보상을 받고 마을로"
	claim_btn.custom_minimum_size = Vector2(200, 35)
	claim_btn.add_theme_font_size_override("font_size", 12)
	claim_btn.focus_mode = Control.FOCUS_NONE
	var claim_style := StyleBoxFlat.new()
	claim_style.bg_color = Color(0.2, 0.5, 0.3)
	claim_style.border_width_left = 2
	claim_style.border_width_top = 2
	claim_style.border_width_right = 2
	claim_style.border_width_bottom = 2
	claim_style.border_color = Color.WHITE
	claim_style.corner_radius_top_left = 4
	claim_style.corner_radius_top_right = 4
	claim_style.corner_radius_bottom_left = 4
	claim_style.corner_radius_bottom_right = 4
	claim_btn.add_theme_stylebox_override("normal", claim_style)
	var claim_hover := claim_style.duplicate()
	claim_hover.bg_color = Color(0.3, 0.6, 0.4)
	claim_btn.add_theme_stylebox_override("hover", claim_hover)
	claim_btn.pressed.connect(_on_town_claim_and_enter)
	btn_vbox.add_child(claim_btn)

	# 그냥 들어가기 버튼
	var skip_btn := Button.new()
	skip_btn.text = "보상 포기하고 마을로"
	skip_btn.custom_minimum_size = Vector2(200, 30)
	skip_btn.add_theme_font_size_override("font_size", 11)
	skip_btn.focus_mode = Control.FOCUS_NONE
	var skip_style := StyleBoxFlat.new()
	skip_style.bg_color = Color(0.25, 0.2, 0.2)
	skip_style.corner_radius_top_left = 4
	skip_style.corner_radius_top_right = 4
	skip_style.corner_radius_bottom_left = 4
	skip_style.corner_radius_bottom_right = 4
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	skip_btn.add_theme_color_override("font_color", Color(0.7, 0.6, 0.6))
	skip_btn.pressed.connect(_on_town_skip_and_enter)
	btn_vbox.add_child(skip_btn)

	# 취소 버튼
	var cancel_btn := Button.new()
	cancel_btn.text = "돌아가기"
	cancel_btn.custom_minimum_size = Vector2(200, 28)
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	var cancel_style := StyleBoxFlat.new()
	cancel_style.bg_color = Color(0.2, 0.2, 0.25)
	cancel_style.corner_radius_top_left = 4
	cancel_style.corner_radius_top_right = 4
	cancel_style.corner_radius_bottom_left = 4
	cancel_style.corner_radius_bottom_right = 4
	cancel_btn.add_theme_stylebox_override("normal", cancel_style)
	cancel_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	cancel_btn.pressed.connect(_on_town_cancel)
	btn_vbox.add_child(cancel_btn)


func _on_town_claim_and_enter() -> void:
	## 보상 받고 마을로
	is_town_popup_active = false
	town_popup.visible = false
	get_tree().paused = false

	for child in town_popup.get_children():
		child.queue_free()

	# 보상 수령
	BattleManager.claim_accumulated_rewards()
	BattleManager.battle_log_received.emit("보상을 획득했다!", Color.CYAN)

	town_enter_confirmed.emit(true)


func _on_town_skip_and_enter() -> void:
	## 보상 포기하고 마을로
	is_town_popup_active = false
	town_popup.visible = false
	get_tree().paused = false

	for child in town_popup.get_children():
		child.queue_free()

	# 보상 초기화 (포기)
	BattleManager.reset_accumulated_rewards()
	BattleManager.battle_log_received.emit("보상을 포기했다...", Color.GRAY)

	town_enter_confirmed.emit(false)


func _on_town_cancel() -> void:
	## 마을 진입 취소
	is_town_popup_active = false
	town_popup.visible = false
	get_tree().paused = false

	for child in town_popup.get_children():
		child.queue_free()


func has_unclaimed_rewards() -> bool:
	## 받지 않은 보상이 있는지 확인
	var rewards: Dictionary = BattleManager.get_accumulated_rewards()
	return rewards.exp > 0 or rewards.gold > 0 or rewards.items.size() > 0
#endregion
