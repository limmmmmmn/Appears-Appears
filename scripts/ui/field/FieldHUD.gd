extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## 구성:
##   TopBar     - 스테이지, 골드, 킬, 배속, 메뉴 (상단)
##   PartyCards - 파티 카드 (하단 중앙)

signal menu_pressed
signal hero_recruited(hero_id: String)


#region 공통 스타일 상수
const STYLE := {
	"bg_dark":    Color(0.04, 0.04, 0.07, 0.92),
	"bg_panel":   Color(0.06, 0.06, 0.09, 0.95),
	"bg_popup":   Color(0.08, 0.05, 0.12, 0.95),
	"bg_btn":     Color(0.12, 0.12, 0.16, 0.9),
	"bg_btn_hover": Color(0.25, 0.25, 0.15, 0.95),
	"border_default": Color(0.3, 0.33, 0.45, 0.7),
	"border_gold":    Color(0.5, 0.42, 0.25, 0.7),
	"border_accent":  Color(0.4, 0.6, 0.9, 0.8),
	"border_popup":   Color(0.8, 0.4, 1.0),
	"text_normal":    Color(0.85, 0.85, 0.9),
	"text_dim":       Color(0.55, 0.55, 0.6),
	"text_gold":      Color(1.0, 0.85, 0.3),
	"text_green":     Color(0.5, 1.0, 0.5),
	"text_red":       Color(1.0, 0.5, 0.5),
	"text_purple":    Color(1.0, 0.5, 0.8),
	"corner_radius":  6,
	"font_tiny":      8,
	"font_small":     9,
	"font_normal":    11,
	"font_medium":    12,
	"font_large":     14,
	"font_title":     16,
}
#endregion


#region 노드 참조
# TopBar
@onready var stage_label: Label = %StageLabel
@onready var gold_label: Label = %GoldLabel
@onready var speed_button: Button = %SpeedButton
@onready var menu_button: Button = %MenuButton
# BottomPartyCards
var bottom_party_cards: BottomPartyCards = null

# 철수 버튼
var retreat_button: Button = null

# 전투 정지 버튼
var battle_pause_button: Button = null

# 일시정지 메뉴
var pause_menu: CanvasLayer = null
var is_pause_menu_active: bool = false

# 장비 화면
var equipment_screen: EquipmentScreen = null

# 중앙 하단 알림 박스
var notice_panel: PanelContainer = null
var notice_label: Label = null
var notice_timer: SceneTreeTimer = null
#endregion


#endregion


func _ready() -> void:
	add_to_group("field_hud")
	# ESC로 일시정지 메뉴를 열고 닫기 위해 ALWAYS 설정
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_topbar()
	_init_party_cards()
	_init_retreat_button()
	_init_pause_menu()
	_init_equipment_screen()
	_init_notice_box()
	_init_recruit_button()
	_init_battle_pause_button()
	_connect_signals()
	update_all()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# 장비 화면이 열려있으면 장비 화면 닫기 (EquipmentScreen 자체에서 처리)
		if equipment_screen and equipment_screen.is_open:
			return
		# 이미 다른 이유(게임오버, 보스 팝업 등)로 일시정지 중이면 무시
		# 단, 전투정지 또는 일시정지 메뉴에서는 허용
		if get_tree().paused and not is_pause_menu_active and not BattleManager.is_battle_paused:
			return
		_toggle_equipment_screen()
		get_viewport().set_input_as_handled()

	# 스페이스바: 전투 정지/재개 토글
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			if not is_pause_menu_active and not (equipment_screen and equipment_screen.is_open):
				_toggle_battle_pause()
				get_viewport().set_input_as_handled()


#region 초기화
func _init_topbar() -> void:
	if speed_button:
		speed_button.visible = false
		var style := _make_flat_style(STYLE.bg_btn, STYLE.border_accent, 3, 2)
		speed_button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = Color(0.18, 0.18, 0.22, 0.95)
		speed_button.add_theme_stylebox_override("hover", hover)



func _init_party_cards() -> void:
	var scene := preload("res://scenes/ui/BottomPartyCards.tscn")
	bottom_party_cards = scene.instantiate() as BottomPartyCards
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(bottom_party_cards)


func _init_retreat_button() -> void:
	## 우측 하단 철수 버튼 생성
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	retreat_button = Button.new()
	retreat_button.text = "🏰 철수"
	retreat_button.custom_minimum_size = Vector2(70, 36)
	retreat_button.add_theme_font_size_override("font_size", STYLE.font_normal)

	var style := _make_flat_style(Color(0.2, 0.12, 0.1, 0.9), Color(0.6, 0.3, 0.2, 0.8), STYLE.corner_radius, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	retreat_button.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.3, 0.15, 0.12, 0.95)
	hover.border_color = Color(0.8, 0.4, 0.3)
	retreat_button.add_theme_stylebox_override("hover", hover)

	retreat_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	retreat_button.offset_left = -80
	retreat_button.offset_top = -46
	retreat_button.offset_right = -8
	retreat_button.offset_bottom = -8
	retreat_button.pressed.connect(_on_retreat_pressed)
	ctrl.add_child(retreat_button)


func _on_retreat_pressed() -> void:
	## 철수: 전투 종료 후 기지로 이동
	if BattleManager:
		BattleManager.close_all_battles()
	GameManager.go_to_den()


func _init_recruit_button() -> void:
	## 좌측 하단 테스트용 영입 버튼
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	var btn := Button.new()
	btn.text = "👤+ 영입"
	btn.custom_minimum_size = Vector2(70, 36)
	btn.add_theme_font_size_override("font_size", STYLE.font_normal)

	var style := _make_flat_style(Color(0.1, 0.15, 0.25, 0.9), Color(0.3, 0.4, 0.6, 0.8), STYLE.corner_radius, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.15, 0.22, 0.35, 0.95)
	hover.border_color = Color(0.5, 0.6, 0.9)
	btn.add_theme_stylebox_override("hover", hover)

	btn.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	btn.offset_left = 8
	btn.offset_top = -46
	btn.offset_right = 88
	btn.offset_bottom = -8
	btn.pressed.connect(_on_recruit_pressed)
	ctrl.add_child(btn)


func _on_recruit_pressed() -> void:
	## 테스트: 랜덤 동료 영입 (최대 4명)
	if not PartyManager:
		return
	var party: Array = PartyManager.get_party()
	if party.size() >= 4:
		return

	var party_ids: Array = []
	for hero in party:
		if hero:
			party_ids.append(hero.id)

	var all_heroes: Array = DataManager.get_all_hero_ids()
	var available: Array = []
	for hero_id in all_heroes:
		if hero_id not in party_ids:
			available.append(hero_id)

	if available.is_empty():
		return

	var random_id: String = available[randi() % available.size()]
	if PartyManager.add_hero_by_id(random_id):
		if bottom_party_cards:
			bottom_party_cards.update_display()
		hero_recruited.emit(random_id)


func _init_battle_pause_button() -> void:
	## 영입 버튼 옆에 전투 정지 토글 버튼 생성
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	battle_pause_button = Button.new()
	battle_pause_button.text = "⏸ 정지"
	battle_pause_button.toggle_mode = true
	battle_pause_button.custom_minimum_size = Vector2(70, 36)
	battle_pause_button.add_theme_font_size_override("font_size", STYLE.font_normal)
	battle_pause_button.tooltip_text = "전투 정지/재개 (Space)"

	var style := _make_flat_style(Color(0.15, 0.12, 0.2, 0.9), Color(0.4, 0.3, 0.6, 0.8), STYLE.corner_radius, 1)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	battle_pause_button.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.22, 0.18, 0.3, 0.95)
	hover.border_color = Color(0.6, 0.5, 0.9)
	battle_pause_button.add_theme_stylebox_override("hover", hover)

	var pressed_style := style.duplicate()
	pressed_style.bg_color = Color(0.3, 0.15, 0.1, 0.95)
	pressed_style.border_color = Color(0.9, 0.4, 0.3, 0.9)
	battle_pause_button.add_theme_stylebox_override("pressed", pressed_style)

	battle_pause_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	battle_pause_button.offset_left = 96
	battle_pause_button.offset_top = -46
	battle_pause_button.offset_right = 176
	battle_pause_button.offset_bottom = -8
	battle_pause_button.toggled.connect(_on_battle_pause_toggled)
	ctrl.add_child(battle_pause_button)


func _toggle_battle_pause() -> void:
	## 전투+필드 정지 토글 (스페이스바 또는 버튼)
	if not BattleManager:
		return
	BattleManager.toggle_battle_pause()
	# 필드+전투 모두 정지/재개
	get_tree().paused = BattleManager.is_battle_paused
	# 버튼 상태 동기화
	if battle_pause_button:
		battle_pause_button.set_pressed_no_signal(BattleManager.is_battle_paused)
		_update_battle_pause_button_text(BattleManager.is_battle_paused)


func _on_battle_pause_toggled(toggled_on: bool) -> void:
	## 전투+필드 정지 버튼 토글
	if not BattleManager:
		return
	BattleManager.set_battle_paused(toggled_on)
	get_tree().paused = toggled_on
	_update_battle_pause_button_text(toggled_on)


func _update_battle_pause_button_text(paused: bool) -> void:
	if battle_pause_button:
		if paused:
			battle_pause_button.text = "▶ 재개"
		else:
			battle_pause_button.text = "⏸ 정지"


func _init_equipment_screen() -> void:
	equipment_screen = EquipmentScreen.new()
	equipment_screen.name = "EquipmentScreen"
	equipment_screen.closed.connect(func():
		# 장비 화면 닫힌 후 파티 카드 갱신
		update_party_display()
	)
	add_child(equipment_screen)


func _init_notice_box() -> void:
	## 중앙 하단 알림 박스 (보상/레벨업/장비 안내)
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	notice_panel = PanelContainer.new()
	notice_panel.visible = false
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	notice_panel.offset_left = 170
	notice_panel.offset_right = -170
	notice_panel.offset_top = -68
	notice_panel.offset_bottom = -26

	var style := _make_flat_style(Color(0.04, 0.04, 0.08, 0.92), STYLE.border_gold, 6, 1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	notice_panel.add_theme_stylebox_override("panel", style)
	ctrl.add_child(notice_panel)

	notice_label = Label.new()
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_label.add_theme_font_size_override("font_size", STYLE.font_normal)
	notice_label.add_theme_color_override("font_color", STYLE.text_normal)
	notice_panel.add_child(notice_label)


func _toggle_equipment_screen() -> void:
	if equipment_screen == null:
		return
	if equipment_screen.is_open:
		equipment_screen.close()
	else:
		equipment_screen.open()


func _init_pause_menu() -> void:
	pause_menu = CanvasLayer.new()
	pause_menu.name = "PauseMenu"
	pause_menu.layer = 110
	pause_menu.visible = false
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_menu)


func show_pause_menu() -> void:
	if is_pause_menu_active:
		return

	is_pause_menu_active = true
	get_tree().paused = true
	pause_menu.visible = true

	# 기존 내용 정리
	for child in pause_menu.get_children():
		child.queue_free()

	# 전체 화면 컨테이너
	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.add_child(full_screen)

	# 어두운 배경 (클릭으로 닫기)
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			hide_pause_menu()
	)
	full_screen.add_child(dimmer)

	# 중앙 패널
	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -120
	center_panel.offset_right = 120
	center_panel.offset_top = -100
	center_panel.offset_bottom = 100
	center_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := _make_flat_style(STYLE.bg_popup, STYLE.border_accent, 8, 2)
	panel_style.content_margin_left = 24
	panel_style.content_margin_right = 24
	panel_style.content_margin_top = 20
	panel_style.content_margin_bottom = 20
	center_panel.add_theme_stylebox_override("panel", panel_style)
	full_screen.add_child(center_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center_panel.add_child(vbox)

	# 타이틀
	var title := Label.new()
	title.text = "메뉴"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", STYLE.font_title)
	title.add_theme_color_override("font_color", STYLE.text_normal)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# 계속하기 버튼
	var resume_btn := _create_menu_button("▶ 계속하기", Color(0.2, 0.35, 0.2))
	resume_btn.pressed.connect(hide_pause_menu)
	vbox.add_child(resume_btn)

	# 기지로 철수 버튼
	var retreat_btn := _create_menu_button("🏰 기지로 철수", Color(0.3, 0.18, 0.12))
	retreat_btn.pressed.connect(func():
		hide_pause_menu()
		if BattleManager:
			BattleManager.close_all_battles()
		GameManager.go_to_den()
	)
	vbox.add_child(retreat_btn)

	# 타이틀로 버튼
	var title_btn := _create_menu_button("🏠 타이틀 화면", Color(0.15, 0.15, 0.25))
	title_btn.pressed.connect(func():
		hide_pause_menu()
		if BattleManager:
			BattleManager.close_all_battles()
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	)
	vbox.add_child(title_btn)


func hide_pause_menu() -> void:
	if not is_pause_menu_active:
		return
	is_pause_menu_active = false
	pause_menu.visible = false
	# 전투 정지 중이면 트리는 paused 유지
	if not BattleManager or not BattleManager.is_battle_paused:
		get_tree().paused = false
	for child in pause_menu.get_children():
		child.queue_free()


func toggle_pause_menu() -> void:
	if is_pause_menu_active:
		hide_pause_menu()
	else:
		show_pause_menu()


func _create_menu_button(text: String, bg_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180, 38)
	btn.add_theme_font_size_override("font_size", STYLE.font_medium)
	btn.focus_mode = Control.FOCUS_NONE

	var style := _make_flat_style(bg_color, STYLE.border_default, 5, 1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = bg_color.lightened(0.2)
	hover.border_color = Color.WHITE
	btn.add_theme_stylebox_override("hover", hover)

	return btn


#endregion


#region 시그널 연결
func _connect_signals() -> void:
	if menu_button:
		menu_button.pressed.connect(func():
			_toggle_equipment_screen()
			menu_pressed.emit()
		)
	if speed_button:
		speed_button.pressed.connect(_on_speed_pressed)

	if GameManager:
		GameManager.gold_changed.connect(func(_g): update_top_bar())

	if BattleManager:
		if not BattleManager.party_hp_changed.is_connected(update_party_display):
			BattleManager.party_hp_changed.connect(update_party_display)
		if not BattleManager.loot_animation_requested.is_connected(_on_loot_anim):
			BattleManager.loot_animation_requested.connect(_on_loot_anim)
		if BattleManager.has_signal("hud_notice_requested"):
			if not BattleManager.hud_notice_requested.is_connected(_on_hud_notice_requested):
				BattleManager.hud_notice_requested.connect(_on_hud_notice_requested)

	if InventoryManager:
		if InventoryManager.has_signal("item_equipped"):
			if not InventoryManager.item_equipped.is_connected(_on_item_equipped):
				InventoryManager.item_equipped.connect(_on_item_equipped)

	if bottom_party_cards:
		if not bottom_party_cards.equipment_dropped.is_connected(_on_equip_dropped):
			bottom_party_cards.equipment_dropped.connect(_on_equip_dropped)
#endregion


#region 스타일 유틸리티
static func _make_flat_style(
	bg: Color, border: Color = Color.TRANSPARENT,
	radius: int = 6, border_w: int = 1
) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border != Color.TRANSPARENT:
		s.border_width_left = border_w
		s.border_width_top = border_w
		s.border_width_right = border_w
		s.border_width_bottom = border_w
		s.border_color = border
	return s
#endregion


#region 이벤트 핸들러
func _on_speed_pressed() -> void:
	pass


func _on_loot_anim(item_id: String, start_pos: Vector2) -> void:
	var target_pos := Vector2(420, 320)
	var loot_anim := LootAnimationUI.new()
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(loot_anim)
	else:
		add_child(loot_anim)
	loot_anim.setup(item_id, start_pos, target_pos)


func _on_equip_dropped(_hero_index: int, _item_id: String) -> void:
	pass


func _on_hud_notice_requested(message: String, duration: float = 2.0, color: Color = Color.WHITE) -> void:
	_show_notice(message, duration, color)


func _on_item_equipped(hero_name: String, item_id: String, _slot: String, _replaced_id: String) -> void:
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(item_data.get("name", item_id))
	_show_notice("%s 장착: %s" % [hero_name, item_name], 2.0, Color(0.8, 1.0, 0.6))
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
	if bottom_party_cards:
		bottom_party_cards.update_display()
#endregion


func _show_notice(message: String, duration: float = 2.0, color: Color = Color.WHITE) -> void:
	if notice_panel == null or notice_label == null:
		return
	if message.strip_edges().is_empty():
		_hide_notice()
		return

	notice_label.text = message
	notice_label.add_theme_color_override("font_color", color)
	notice_panel.visible = true
	notice_panel.modulate.a = 1.0

	# 이전 타이머 무시 (새 메시지로 교체)
	notice_timer = get_tree().create_timer(maxf(0.3, duration))
	await notice_timer.timeout
	if notice_label.text == message:
		_hide_notice()


func _hide_notice() -> void:
	if notice_panel:
		notice_panel.visible = false


#region 로그 (스텁 - 외부 호출 호환용)
func add_log(_msg: String, _color: Color = Color.WHITE) -> void:
	pass

func add_battle_log(_msg: String) -> void:
	pass

func add_damage_log(_atk: String, _tgt: String, _dmg: int, _crit: bool = false) -> void:
	pass

func add_heal_log(_h: String, _t: String, _amt: int) -> void:
	pass

func add_defeat_log(_t: String) -> void:
	pass

func add_gold_log(_g: int) -> void:
	pass

func add_item_log(_n: String) -> void:
	pass

func add_system_log(_msg: String) -> void:
	pass

func clear_logs() -> void:
	pass
#endregion



