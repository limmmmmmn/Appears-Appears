extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## 구성:
##   TopBar     - 스테이지, 골드, 킬, 배속, 메뉴 (상단)
##   PartyCards - 파티 카드 (하단 중앙)
##   GrudgePopup - 팝업

signal menu_pressed


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

# 일시정지 메뉴
var pause_menu: CanvasLayer = null
var is_pause_menu_active: bool = false
#endregion


#region 내부 상태
# 팝업
var grudge_popup: CanvasLayer = null
var is_grudge_popup_active: bool = false

#endregion


func _ready() -> void:
	add_to_group("field_hud")
	# ESC로 일시정지 메뉴를 열고 닫기 위해 ALWAYS 설정
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_topbar()
	_init_party_cards()
	_init_retreat_button()
	_init_pause_menu()
	_init_recruit_button()
	_init_popups()
	_connect_signals()
	update_all()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_grudge_popup_active:
			return  # 원념 팝업 중에는 무시
		# 이미 다른 이유(게임오버, 보스 팝업 등)로 일시정지 중이면 무시
		if get_tree().paused and not is_pause_menu_active:
			return
		toggle_pause_menu()
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


func _init_pause_menu() -> void:
	pause_menu = CanvasLayer.new()
	pause_menu.name = "PauseMenu"
	pause_menu.layer = 110
	pause_menu.visible = false
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_menu)


func show_pause_menu() -> void:
	if is_pause_menu_active or is_grudge_popup_active:
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


func _init_popups() -> void:
	grudge_popup = _create_popup_layer("GrudgePopup")
	add_child(grudge_popup)


func _create_popup_layer(popup_name: String) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = popup_name
	layer.layer = 100
	layer.visible = false
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	return layer
#endregion


#region 시그널 연결
func _connect_signals() -> void:
	if menu_button:
		menu_button.pressed.connect(func(): menu_pressed.emit())
	if speed_button:
		speed_button.pressed.connect(_on_speed_pressed)

	if GameManager:
		GameManager.gold_changed.connect(func(_g): update_top_bar())

	if BattleManager:
		if not BattleManager.party_hp_changed.is_connected(update_party_display):
			BattleManager.party_hp_changed.connect(update_party_display)
		if not BattleManager.loot_animation_requested.is_connected(_on_loot_anim):
			BattleManager.loot_animation_requested.connect(_on_loot_anim)

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


#region 원념 선택 팝업
func show_grudge_choice_popup(danger_level: int) -> void:
	if is_grudge_popup_active:
		return

	is_grudge_popup_active = true
	get_tree().paused = true
	grudge_popup.visible = true

	for child in grudge_popup.get_children():
		child.queue_free()

	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	grudge_popup.add_child(full_screen)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.7)
	full_screen.add_child(dimmer)

	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -160
	center_panel.offset_right = 160
	center_panel.offset_top = -120
	center_panel.offset_bottom = 120
	center_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := _make_flat_style(STYLE.bg_popup, STYLE.border_popup, 8, 3)
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 15
	panel_style.content_margin_bottom = 15
	center_panel.add_theme_stylebox_override("panel", panel_style)
	full_screen.add_child(center_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	center_panel.add_child(vbox)

	var title := Label.new()
	title.text = "⚠ 원념 %d단계!" % danger_level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", STYLE.font_title)
	title.add_theme_color_override("font_color", STYLE.text_purple)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "적이 더 강해집니다.\n계속 원념을 쌓으시겠습니까?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	var reward_title := Label.new()
	reward_title.text = "[ 현재 보상 ]"
	reward_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_title.add_theme_font_size_override("font_size", STYLE.font_small)
	reward_title.add_theme_color_override("font_color", STYLE.text_dim)
	vbox.add_child(reward_title)

	var rewards: Dictionary = BattleManager.get_accumulated_rewards()

	var reward_info := HBoxContainer.new()
	reward_info.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_info.add_theme_constant_override("separation", 20)
	vbox.add_child(reward_info)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: %d" % rewards.gold
	gold_lbl.add_theme_font_size_override("font_size", STYLE.font_normal)
	gold_lbl.add_theme_color_override("font_color", STYLE.text_gold)
	reward_info.add_child(gold_lbl)

	if rewards.items.size() > 0:
		var items_hbox := HBoxContainer.new()
		items_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		items_hbox.add_theme_constant_override("separation", 8)
		vbox.add_child(items_hbox)
		for item in rewards.items:
			var item_lbl := Label.new()
			var idata: Dictionary = DataManager.get_equipment(item.id)
			if idata.is_empty():
				idata = DataManager.get_item(item.id)
			item_lbl.text = idata.get("name", item.id)
			item_lbl.add_theme_font_size_override("font_size", 10)
			item_lbl.add_theme_color_override("font_color", InventoryManager.get_rarity_color(item.id))
			items_hbox.add_child(item_lbl)

	vbox.add_child(HSeparator.new())

	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 30)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_hbox)

	var go_style := _make_flat_style(Color(0.3, 0.6, 0.3), Color.WHITE, 4, 2)
	var go_btn := _make_popup_button("▶ 고 (계속) ◀", Vector2(100, 35), go_style)
	btn_hbox.add_child(go_btn)

	var stop_style := _make_flat_style(Color(0.3, 0.2, 0.2), Color.TRANSPARENT, 4)
	var stop_btn := _make_popup_button("스톱 (보상)", Vector2(100, 35), stop_style)
	stop_btn.add_theme_color_override("font_color", STYLE.text_dim)
	btn_hbox.add_child(stop_btn)

	var hint := Label.new()
	hint.text = "[← →] 선택  [Enter] 결정"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", STYLE.font_small)
	hint.add_theme_color_override("font_color", STYLE.text_dim)
	vbox.add_child(hint)

	var go_style_selected := go_style.duplicate()
	var stop_style_selected := stop_style.duplicate()
	stop_style_selected.bg_color = Color(0.6, 0.3, 0.3)
	stop_style_selected.border_width_left = 2
	stop_style_selected.border_width_top = 2
	stop_style_selected.border_width_right = 2
	stop_style_selected.border_width_bottom = 2
	stop_style_selected.border_color = Color.WHITE

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


func _make_popup_button(text: String, min_size: Vector2, style: StyleBoxFlat) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", STYLE.font_medium)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	return btn


func _on_grudge_go_selected() -> void:
	is_grudge_popup_active = false
	grudge_popup.visible = false
	get_tree().paused = false
	for child in grudge_popup.get_children():
		child.queue_free()
	BattleManager.battle_log_received.emit("원념을 계속 쌓는다!", Color.MAGENTA)


func _on_grudge_stop_selected() -> void:
	is_grudge_popup_active = false
	grudge_popup.visible = false
	get_tree().paused = false
	for child in grudge_popup.get_children():
		child.queue_free()
	BattleManager.claim_accumulated_rewards()
	BattleManager.close_all_battles()
	BattleManager.battle_log_received.emit("보상을 획득했다!", Color.CYAN)
#endregion


