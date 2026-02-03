extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## - TopBar: 스테이지, 골드, 배속, 메뉴
## - LogPanel: 전투 로그 (좌측 하단)
## - BottomPartyPanel: 파티 정보 (하단 중앙) - 외부 씬
## - MinimapPanel: 미니맵 (우측 하단)

signal menu_pressed

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

# === 컴포넌트 ===
var battle_log: BattleLogUI = null

# === 미니맵 설정 ===
var minimap_zoom: float = 0.1  # 미니맵 줌 레벨 (작을수록 더 넓은 영역 표시)
var minimap_target: Node2D = null  # 추적할 대상 (파티 리더)


func _ready() -> void:
	_setup_components()
	_connect_signals()
	update_all()
	_update_trait_display()


func _process(_delta: float) -> void:
	_update_minimap()


func _setup_components() -> void:
	_setup_speed_button()
	
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
		if not BattleManager.battle_speed_changed.is_connected(_on_battle_speed_changed):
			BattleManager.battle_speed_changed.connect(_on_battle_speed_changed)
		if not BattleManager.loot_animation_requested.is_connected(_on_loot_animation_requested):
			BattleManager.loot_animation_requested.connect(_on_loot_animation_requested)
		if not BattleManager.hero_atb_changed.is_connected(_on_hero_atb_changed):
			BattleManager.hero_atb_changed.connect(_on_hero_atb_changed)


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
	if BattleManager:
		var new_speed = BattleManager.toggle_battle_speed()
		speed_button.text = "x%d" % int(new_speed)


func _on_battle_speed_changed(speed: float) -> void:
	if speed_button:
		speed_button.text = "x%d" % int(speed)


func _on_hero_atb_changed(hero_id: String, atb_value: float) -> void:
	if bottom_party_panel:
		bottom_party_panel.update_hero_atb(hero_id, atb_value)


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


func update_top_bar() -> void:
	if stage_label and FieldManager:
		var fn = FieldManager.get_current_field_name()
		stage_label.text = FieldManager.get_display_name() + (": " + fn if fn else "")
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold


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

func clear_logs() -> void:
	if battle_log:
		battle_log.clear()
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
		var rune_data := hero.get_equipped_rune()
		var trait_data := DataManager.get_rune_trait(hero.equipped_rune_id)
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
