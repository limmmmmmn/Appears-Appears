extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## 구성:
##   TopBar     - 스테이지, 골드, 배속, 메뉴 (상단)
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
# PartyPanel
var party_panel: PartyPanel = null

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

const NOTICE_FONT_SIZE: int = 18
const NOTICE_MIN_WIDTH: float = 220.0
const NOTICE_MIN_HEIGHT: float = 50.0
const NOTICE_MAX_WIDTH_RATIO: float = 0.72
const NOTICE_TOP_RATIO: float = 0.22
const NOTICE_PADDING_X: float = 20.0
const NOTICE_PADDING_Y: float = 12.0
const EQUIP_STAT_LABELS: Dictionary = {
	"atk": "ATK", "def": "DEF", "mag": "MAG", "int": "INT", "wis": "WIS",
	"str": "STR", "dex": "DEX", "agi": "AGI", "luk": "LUK", "hp": "HP",
	"mp": "MP", "spd": "SPD", "hit": "HIT", "eva": "EVA",
}
const EQUIP_STAT_ORDER: Array[String] = [
	"atk", "def", "mag", "int", "wis", "str", "dex", "agi", "luk", "hp", "mp", "spd", "hit", "eva"
]

# 우측 장비 장착 카드
var equip_notice_panel: PanelContainer = null
var equip_notice_face: TextureRect = null
var equip_notice_name: Label = null
var equip_notice_slot_rows: Dictionary = {} # slot_key -> {panel, item_label}
var equip_notice_stat_rows: Array = [] # [{key, value_label, delta_label}]
var equip_row_style_normal: StyleBoxFlat = null
var equip_row_style_highlight: StyleBoxFlat = null
var equip_notice_queue: Array = []
var equip_notice_playing: bool = false
var equip_notice_left_panel: PanelContainer = null
var equip_notice_left_face: TextureRect = null
var equip_notice_left_name: Label = null
var equip_notice_left_slot_rows: Dictionary = {}
var equip_notice_pending_events: Array = []
var equip_notice_flush_scheduled: bool = false
var equip_notice_recent_keys: Dictionary = {}
var equip_notice_right_payload: Dictionary = {}
var equip_notice_left_payload: Dictionary = {}
var equip_notice_right_expire_ms: int = 0
var equip_notice_left_expire_ms: int = 0
var equip_notice_right_token: int = 0
var equip_notice_left_token: int = 0
var right_inventory_panel: PanelContainer = null
var right_inventory_rows: GridContainer = null
var right_desc_panel: PanelContainer = null
var right_desc_label: Label = null
var right_inventory_slots: Array = []
var selected_hero_index: int = -1
var right_panel_opened: bool = false
var last_equip_hero_id: String = ""
var right_collapse_button: Button = null
var right_expand_button: Button = null
var right_panel_collapsed: bool = false

const EQUIP_CARD_FACE_SIZE: float = 92.0
const EQUIP_CARD_WIDTH: float = EQUIP_CARD_FACE_SIZE
const EQUIP_CARD_MARGIN_RIGHT: float = 12.0
const EQUIP_CARD_GAP: float = 8.0
const EQUIP_CARD_STAY_TIME: float = 2.0
const EQUIP_CARD_INVENTORY_HEIGHT: float = 112.0
const EQUIP_CARD_INVENTORY_GAP: float = 8.0
const INVENTORY_COLS: int = 2
const INVENTORY_ROWS: int = 4
const SLOT_NAMES_KR: Dictionary = {
	"main_hand": "무기",
	"off_hand": "보조손",
	"head": "투구",
	"body": "갑옷",
	"acc1": "악세1",
	"acc2": "악세2",
}
const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️",
	"off_hand": "🛡️",
	"head": "⛑️",
	"body": "🛡️",
	"acc1": "💍",
	"acc2": "💎",
}
const SLOT_ORDER: Array[String] = [
	"main_hand", "off_hand", "head", "body", "acc1", "acc2"
]
#endregion


#endregion


func _ready() -> void:
	add_to_group("field_hud")
	# ESC로 일시정지 메뉴를 열고 닫기 위해 ALWAYS 설정
	process_mode = Node.PROCESS_MODE_ALWAYS
	_init_topbar()
	_init_party_cards()
	_init_pause_menu()
	_init_equipment_screen()
	_init_notice_box()
	_init_equip_notice_card()
	_init_right_panel_toggle_buttons()
	_init_recruit_button()
	_init_battle_pause_button()
	_connect_signals()
	_apply_pause_ui_state(false)
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
				return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if right_panel_opened and not _is_click_inside_right_ui(mb.global_position) and not _is_click_on_party_panel(mb.global_position):
				_close_right_panel()


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
	var scene := preload("res://scenes/ui/PartyPanel.tscn")
	party_panel = scene.instantiate() as PartyPanel
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(party_panel)


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
		if party_panel:
			party_panel.update_display()
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
	_apply_pause_ui_state(BattleManager.is_battle_paused)
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
	_apply_pause_ui_state(toggled_on)
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
	## 상단 중앙 알림 박스 (보상/레벨업/장비 안내)
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	notice_panel = PanelContainer.new()
	notice_panel.visible = false
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	notice_panel.position = Vector2.ZERO
	notice_panel.size = Vector2(NOTICE_MIN_WIDTH, NOTICE_MIN_HEIGHT)

	var style := _make_flat_style(Color(0.04, 0.04, 0.08, 0.92), STYLE.border_gold, 6, 1)
	style.content_margin_left = NOTICE_PADDING_X
	style.content_margin_right = NOTICE_PADDING_X
	style.content_margin_top = NOTICE_PADDING_Y
	style.content_margin_bottom = NOTICE_PADDING_Y
	notice_panel.add_theme_stylebox_override("panel", style)
	ctrl.add_child(notice_panel)

	notice_label = Label.new()
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	notice_label.offset_left = NOTICE_PADDING_X
	notice_label.offset_top = NOTICE_PADDING_Y
	notice_label.offset_right = -NOTICE_PADDING_X
	notice_label.offset_bottom = -NOTICE_PADDING_Y
	notice_label.add_theme_font_size_override("font_size", NOTICE_FONT_SIZE)
	notice_label.add_theme_color_override("font_color", STYLE.text_normal)
	notice_panel.add_child(notice_label)


func _init_equip_notice_card() -> void:
	## 우측 중앙 장비 장착 카드 (전투 중 장착 연출)
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	equip_notice_panel = _create_equip_notice_panel_instance(ctrl)
	equip_notice_face = equip_notice_panel.get_meta("face") as TextureRect
	equip_notice_name = equip_notice_panel.get_meta("name_label") as Label
	equip_notice_slot_rows = equip_notice_panel.get_meta("slot_rows") as Dictionary

	equip_notice_left_panel = _create_equip_notice_panel_instance(ctrl)
	equip_notice_left_face = equip_notice_left_panel.get_meta("face") as TextureRect
	equip_notice_left_name = equip_notice_left_panel.get_meta("name_label") as Label
	equip_notice_left_slot_rows = equip_notice_left_panel.get_meta("slot_rows") as Dictionary

	equip_notice_stat_rows.clear()
	right_desc_panel = null
	right_desc_label = null

	equip_row_style_normal = _make_flat_style(Color(0.05, 0.06, 0.09, 0.95), Color(0.42, 0.36, 0.18, 0.7), 4, 1)
	equip_row_style_normal.content_margin_left = 4
	equip_row_style_normal.content_margin_right = 4
	equip_row_style_normal.content_margin_top = 2
	equip_row_style_normal.content_margin_bottom = 2
	equip_row_style_highlight = _make_flat_style(Color(0.09, 0.08, 0.02, 0.98), Color(1.0, 0.9, 0.35, 1.0), 4, 2)
	equip_row_style_highlight.content_margin_left = 4
	equip_row_style_highlight.content_margin_right = 4
	equip_row_style_highlight.content_margin_top = 2
	equip_row_style_highlight.content_margin_bottom = 2
	_apply_equip_row_styles(equip_notice_slot_rows)
	_apply_equip_row_styles(equip_notice_left_slot_rows)


func _create_equip_notice_panel_instance(parent_ctrl: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(EQUIP_CARD_WIDTH, 214)
	var card_style := _make_flat_style(Color(0.03, 0.03, 0.06, 0.94), STYLE.border_gold, 6, 1)
	card_style.content_margin_left = 4
	card_style.content_margin_right = 4
	card_style.content_margin_top = 4
	card_style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", card_style)
	parent_ctrl.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(EQUIP_CARD_WIDTH, EQUIP_CARD_FACE_SIZE)
	face.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(face)

	var box_w: float = EQUIP_CARD_WIDTH - 16.0
	var box_h: float = 150.0
	var equip_box := PanelContainer.new()
	equip_box.custom_minimum_size = Vector2(box_w, box_h)
	equip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var equip_style := _make_flat_style(Color(0.08, 0.08, 0.12, 0.95), STYLE.border_default, 5, 1)
	equip_style.content_margin_left = 6
	equip_style.content_margin_right = 6
	equip_style.content_margin_top = 6
	equip_style.content_margin_bottom = 6
	equip_box.add_theme_stylebox_override("panel", equip_style)
	root.add_child(equip_box)

	var equip_vbox := VBoxContainer.new()
	equip_vbox.add_theme_constant_override("separation", 2)
	equip_box.add_child(equip_vbox)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", STYLE.font_small)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	equip_vbox.add_child(name_label)

	var rows: Dictionary = {}
	for slot_key in SLOT_ORDER:
		var row_panel := PanelContainer.new()
		row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		equip_vbox.add_child(row_panel)

		var slot_row_hbox := HBoxContainer.new()
		slot_row_hbox.add_theme_constant_override("separation", 3)
		row_panel.add_child(slot_row_hbox)

		var slot_icon := Label.new()
		slot_icon.custom_minimum_size = Vector2(14, 12)
		slot_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_icon.add_theme_font_size_override("font_size", STYLE.font_tiny)
		slot_icon.text = str(SLOT_ICONS.get(slot_key, "📦"))
		slot_row_hbox.add_child(slot_icon)

		var item_label := Label.new()
		item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_label.clip_text = false
		item_label.add_theme_font_size_override("font_size", STYLE.font_tiny)
		item_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		item_label.text = "— 비어있음 —"
		slot_row_hbox.add_child(item_label)

		rows[slot_key] = {
			"panel": row_panel,
			"item_label": item_label
		}

	panel.set_meta("face", face)
	panel.set_meta("name_label", name_label)
	panel.set_meta("slot_rows", rows)
	return panel


func _apply_equip_row_styles(rows: Dictionary) -> void:
	for slot_key in SLOT_ORDER:
		var row: Dictionary = rows.get(slot_key, {}) as Dictionary
		if row.is_empty():
			continue
		var panel: PanelContainer = row.get("panel") as PanelContainer
		if panel and equip_row_style_normal:
			panel.add_theme_stylebox_override("panel", equip_row_style_normal)


func _init_right_inventory_panel() -> void:
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	right_inventory_panel = PanelContainer.new()
	right_inventory_panel.visible = false
	right_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	right_inventory_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	right_inventory_panel.size = Vector2(EQUIP_CARD_WIDTH, EQUIP_CARD_INVENTORY_HEIGHT)

	var panel_style := _make_flat_style(Color(0.03, 0.03, 0.06, 0.94), STYLE.border_gold, 6, 1)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	right_inventory_panel.add_theme_stylebox_override("panel", panel_style)
	ctrl.add_child(right_inventory_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	right_inventory_panel.add_child(root)

	var inv_box := PanelContainer.new()
	inv_box.custom_minimum_size = Vector2(EQUIP_CARD_WIDTH - 12.0, EQUIP_CARD_INVENTORY_HEIGHT - 12.0)
	inv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inv_style := _make_flat_style(Color(0.05, 0.06, 0.09, 0.95), STYLE.border_default, 4, 1)
	inv_style.content_margin_left = 4
	inv_style.content_margin_right = 4
	inv_style.content_margin_top = 4
	inv_style.content_margin_bottom = 4
	inv_box.add_theme_stylebox_override("panel", inv_style)
	root.add_child(inv_box)

	right_inventory_rows = GridContainer.new()
	right_inventory_rows.columns = INVENTORY_COLS
	right_inventory_rows.add_theme_constant_override("h_separation", 3)
	right_inventory_rows.add_theme_constant_override("v_separation", 3)
	inv_box.add_child(right_inventory_rows)

	right_inventory_slots.clear()
	for i in range(INVENTORY_COLS * INVENTORY_ROWS):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2((EQUIP_CARD_WIDTH - 24.0) * 0.5, 22)
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", STYLE.font_tiny)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_entered.connect(_on_inventory_slot_hovered.bind(i))
		btn.mouse_exited.connect(_on_inventory_slot_unhovered)
		btn.pressed.connect(_on_inventory_slot_pressed.bind(i))
		right_inventory_rows.add_child(btn)
		right_inventory_slots.append({"button": btn, "item_id": "", "slot": "", "replaced_id": ""})


func _init_right_panel_toggle_buttons() -> void:
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	right_collapse_button = Button.new()
	right_collapse_button.text = "▶"
	right_collapse_button.custom_minimum_size = Vector2(18, 24)
	right_collapse_button.visible = false
	right_collapse_button.focus_mode = Control.FOCUS_NONE
	right_collapse_button.pressed.connect(_on_right_panel_collapse_pressed)
	ctrl.add_child(right_collapse_button)

	right_expand_button = Button.new()
	right_expand_button.text = "◀"
	right_expand_button.custom_minimum_size = Vector2(20, 26)
	right_expand_button.visible = false
	right_expand_button.focus_mode = Control.FOCUS_NONE
	right_expand_button.pressed.connect(_on_right_panel_expand_pressed)
	ctrl.add_child(right_expand_button)


func _toggle_equipment_screen() -> void:
	if equipment_screen == null:
		return
	if equipment_screen.is_open:
		equipment_screen.close()
	else:
		equipment_screen.open()


func close_blocking_ui() -> void:
	## 필드 이벤트(대화/보상) 진행을 위해 열려있는 UI를 강제로 정리
	if equipment_screen and equipment_screen.is_open:
		equipment_screen.close()
	if is_pause_menu_active:
		hide_pause_menu()

	# 먼저 상태를 끈 뒤 패널 정리를 해야 재표시되지 않는다.
	equip_notice_playing = false
	equip_notice_queue.clear()
	equip_notice_pending_events.clear()
	equip_notice_flush_scheduled = false
	equip_notice_recent_keys.clear()
	equip_notice_right_payload.clear()
	equip_notice_left_payload.clear()

	_close_right_panel()
	_hide_equip_hover_desc()

	if equip_notice_panel:
		equip_notice_panel.visible = false
	if equip_notice_left_panel:
		equip_notice_left_panel.visible = false
	if right_inventory_panel:
		right_inventory_panel.visible = false
	if right_desc_panel:
		right_desc_panel.visible = false
	if right_desc_label:
		right_desc_label.text = ""

	_refresh_selected_hero_panels()
	_update_right_toggle_buttons()

	# 전투 일시정지 중이 아닐 때만 트리 pause 해제
	if not BattleManager or not BattleManager.is_battle_paused:
		get_tree().paused = false


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
		if BattleManager.has_signal("hud_notice_requested"):
			if not BattleManager.hud_notice_requested.is_connected(_on_hud_notice_requested):
				BattleManager.hud_notice_requested.connect(_on_hud_notice_requested)
		if BattleManager.has_signal("battle_pause_changed"):
			if not BattleManager.battle_pause_changed.is_connected(_on_battle_pause_changed):
				BattleManager.battle_pause_changed.connect(_on_battle_pause_changed)

	if InventoryManager:
		if InventoryManager.has_signal("item_equipped"):
			if not InventoryManager.item_equipped.is_connected(_on_item_equipped):
				InventoryManager.item_equipped.connect(_on_item_equipped)
		if InventoryManager.has_signal("item_auto_equipped"):
			if not InventoryManager.item_auto_equipped.is_connected(_on_item_auto_equipped):
				InventoryManager.item_auto_equipped.connect(_on_item_auto_equipped)
		if InventoryManager.has_signal("inventory_changed"):
			if not InventoryManager.inventory_changed.is_connected(_on_inventory_changed):
				InventoryManager.inventory_changed.connect(_on_inventory_changed)

	if party_panel:
		if not party_panel.equipment_dropped.is_connected(_on_equip_dropped):
			party_panel.equipment_dropped.connect(_on_equip_dropped)
		if party_panel.has_signal("hero_selected"):
			if not party_panel.hero_selected.is_connected(_on_party_hero_selected):
				party_panel.hero_selected.connect(_on_party_hero_selected)
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


func _on_equip_dropped(_hero_index: int, _item_id: String) -> void:
	pass


func _on_hud_notice_requested(message: String, duration: float = 2.0, color: Color = Color.WHITE) -> void:
	_show_notice(message, duration, color)


func _on_battle_pause_changed(paused: bool) -> void:
	if battle_pause_button:
		battle_pause_button.set_pressed_no_signal(paused)
	_update_battle_pause_button_text(paused)
	_apply_pause_ui_state(paused)


func _on_item_equipped(hero_name: String, item_id: String, _slot: String, replaced_id: String) -> void:
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(item_data.get("name", item_id))
	var delta_text: String = _build_equip_stat_delta_text(item_id, replaced_id)
	_show_notice("%s 장착: %s\n%s" % [hero_name, item_name, delta_text], 2.2, Color(0.8, 1.0, 0.6))
	_enqueue_equip_notice_event(hero_name, item_id, _slot)


func _on_item_auto_equipped(hero_name: String, item_id: String, slot: String, replaced_id: String) -> void:
	_enqueue_equip_notice_event(hero_name, item_id, slot)


func _on_party_hero_selected(hero_index: int) -> void:
	selected_hero_index = hero_index


func _on_inventory_changed() -> void:
	_refresh_selected_hero_panels()
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
	if party_panel:
		party_panel.update_display()
		if party_panel.has_method("get_selected_hero_index"):
			var panel_selected: int = party_panel.get_selected_hero_index()
			if selected_hero_index < 0:
				selected_hero_index = panel_selected
	_refresh_selected_hero_panels()
#endregion


func _refresh_selected_hero_panels() -> void:
	if not equip_notice_playing:
		if equip_notice_panel:
			equip_notice_panel.visible = false
		if equip_notice_left_panel:
			equip_notice_left_panel.visible = false
		if right_inventory_panel:
			right_inventory_panel.visible = false
		_hide_equip_hover_desc()
		_update_right_toggle_buttons()
		return

	_hide_equip_hover_desc()
	_layout_right_panels()
	if equip_notice_panel:
		equip_notice_panel.visible = true
	_update_right_toggle_buttons()


func _get_selected_hero() -> Hero:
	if not PartyManager:
		return null
	var party: Array = PartyManager.get_party()
	if party.is_empty():
		selected_hero_index = -1
		return null
	if selected_hero_index < 0 or selected_hero_index >= party.size():
		selected_hero_index = 0
	return party[selected_hero_index] as Hero


func _layout_right_panels() -> void:
	if equip_notice_panel == null:
		return
	_layout_equip_notice_cards()
	_update_right_toggle_buttons()


func _layout_equip_notice_cards() -> void:
	if equip_notice_panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var right_x: float = viewport_size.x - EQUIP_CARD_WIDTH - EQUIP_CARD_MARGIN_RIGHT
	var left_x: float = right_x - EQUIP_CARD_WIDTH - EQUIP_CARD_GAP
	var y: float = (viewport_size.y - equip_notice_panel.size.y) * 0.5
	if equip_notice_left_panel and equip_notice_left_panel.visible:
		equip_notice_left_panel.position = Vector2(left_x, y)
	if equip_notice_panel.visible:
		equip_notice_panel.position = Vector2(right_x, y)


func _refresh_right_inventory(hero: Hero) -> void:
	if right_inventory_rows == null:
		return
	right_desc_panel.visible = false
	if right_desc_label:
		right_desc_label.text = ""

	for i in range(right_inventory_slots.size()):
		var s: Dictionary = right_inventory_slots[i]
		var btn: Button = s.get("button") as Button
		if btn:
			btn.text = "—"
			btn.disabled = true
			btn.tooltip_text = ""
		s["item_id"] = ""
		s["slot"] = ""
		s["replaced_id"] = ""
		right_inventory_slots[i] = s

	if InventoryManager == null or hero == null:
		return
	var equips: Array = InventoryManager.get_equipment_items()
	var write_idx: int = 0
	for entry_any in equips:
		if write_idx >= right_inventory_slots.size():
			break
		var entry: Dictionary = entry_any as Dictionary
		var item_id: String = str(entry.get("id", ""))
		var qty: int = int(entry.get("quantity", 0))
		var data: Dictionary = entry.get("data", {}) as Dictionary
		if not hero.can_equip(item_id):
			continue
		var target_slot: String = _resolve_target_slot(hero, data)
		if target_slot.is_empty():
			continue
		var replaced_id: String = str(hero.equipment.get(target_slot, ""))
		var item_name: String = str(data.get("name", item_id))
		var icon: String = str(SLOT_ICONS.get(Hero.normalize_equipment_slot(str(data.get("slot", ""))), "📦"))
		var s: Dictionary = right_inventory_slots[write_idx]
		var btn: Button = s.get("button") as Button
		if btn:
			btn.text = "%s %s" % [icon, item_name]
			btn.disabled = false
			btn.tooltip_text = "%s x%d" % [item_name, qty]
		s["item_id"] = item_id
		s["slot"] = target_slot
		s["replaced_id"] = replaced_id
		right_inventory_slots[write_idx] = s
		write_idx += 1


func _resolve_target_slot(hero: Hero, item_data: Dictionary) -> String:
	var raw_slot: String = Hero.normalize_equipment_slot(str(item_data.get("slot", "")))
	if raw_slot == "acc":
		if str(hero.equipment.get("acc1", "")).is_empty():
			return "acc1"
		if str(hero.equipment.get("acc2", "")).is_empty():
			return "acc2"
		return "acc1"
	if raw_slot == "main_hand":
		if str(hero.equipment.get("main_hand", "")).is_empty():
			return "main_hand"
		if hero.can_dual_wield() and str(hero.equipment.get("off_hand", "")).is_empty() and not hero.is_off_hand_disabled():
			return "off_hand"
		return "main_hand"
	if SLOT_ORDER.has(raw_slot):
		return raw_slot
	return ""


func _on_inventory_slot_hovered(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= right_inventory_slots.size():
		return
	var hero: Hero = _get_selected_hero()
	if hero == null:
		return
	var s: Dictionary = right_inventory_slots[slot_index]
	var item_id: String = str(s.get("item_id", ""))
	if item_id.is_empty():
		return
	var target_slot: String = str(s.get("slot", ""))
	var replaced_id: String = str(s.get("replaced_id", ""))
	_refresh_equip_notice_slots(hero, target_slot)
	var delta: Dictionary = _build_equip_stat_delta(item_id, replaced_id)
	_refresh_equip_notice_stats(hero, delta)


func _on_inventory_slot_unhovered() -> void:
	var hero: Hero = _get_selected_hero()
	if hero:
		_refresh_equip_notice_slots(hero, "")
		_refresh_equip_notice_stats(hero, {})
	_hide_equip_hover_desc()


func _on_inventory_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= right_inventory_slots.size():
		return
	var hero: Hero = _get_selected_hero()
	if hero == null:
		return
	var s: Dictionary = right_inventory_slots[slot_index]
	var item_id: String = str(s.get("item_id", ""))
	var target_slot: String = str(s.get("slot", ""))
	if item_id.is_empty() or target_slot.is_empty():
		return
	InventoryManager.equip_item(hero, item_id, target_slot)


func _show_equip_hover_desc(item_id: String, delta: Dictionary) -> void:
	if right_desc_panel == null or right_desc_label == null:
		return
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(data.get("name", item_id))
	var desc: String = str(data.get("description", data.get("desc", "")))
	var parts: Array[String] = []
	for key in EQUIP_STAT_ORDER:
		var d: int = int(delta.get(key, 0))
		if d == 0:
			continue
		var arrow: String = "▲" if d > 0 else "▼"
		var sign: String = "+" if d > 0 else ""
		parts.append("%s %s%s%d" % [str(EQUIP_STAT_LABELS.get(key, key.to_upper())), arrow, sign, d])
	var delta_text: String = ", ".join(parts)
	right_desc_label.text = "%s\n%s\n%s" % [item_name, desc, delta_text]
	right_desc_panel.visible = true


func _hide_equip_hover_desc() -> void:
	if right_desc_panel:
		right_desc_panel.visible = false
	if right_desc_label:
		right_desc_label.text = ""


func _on_right_panel_collapse_pressed() -> void:
	right_panel_collapsed = true
	_refresh_selected_hero_panels()


func _on_right_panel_expand_pressed() -> void:
	right_panel_collapsed = false
	right_panel_opened = true
	_refresh_selected_hero_panels()


func _close_right_panel() -> void:
	right_panel_opened = false
	right_panel_collapsed = false
	_hide_equip_hover_desc()
	if party_panel and party_panel.has_method("set_selected_hero_index"):
		party_panel.set_selected_hero_index(-1, false)
	selected_hero_index = -1
	_refresh_selected_hero_panels()


func _update_right_toggle_buttons() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var block_top: float = 0.0
	var block_h: float = 0.0
	if equip_notice_panel:
		var card_top: float = equip_notice_panel.position.y
		if equip_notice_left_panel and equip_notice_left_panel.visible:
			card_top = minf(card_top, equip_notice_left_panel.position.y)
		block_top = card_top
		block_h = equip_notice_panel.size.y
		if right_inventory_panel and right_inventory_panel.visible:
			block_h += EQUIP_CARD_INVENTORY_GAP + right_inventory_panel.size.y
	var center_y: float = block_top + block_h * 0.5 if block_h > 0.0 else viewport_size.y * 0.5
	if right_collapse_button:
		right_collapse_button.visible = right_panel_opened and not right_panel_collapsed and equip_notice_panel and equip_notice_panel.visible
		if right_collapse_button.visible:
			right_collapse_button.position = Vector2(
				equip_notice_panel.position.x - right_collapse_button.size.x - 2.0,
				center_y - right_collapse_button.size.y * 0.5
			)
	if right_expand_button:
		right_expand_button.visible = right_panel_opened and right_panel_collapsed
		if right_expand_button.visible:
			right_expand_button.position = Vector2(
				viewport_size.x - right_expand_button.size.x + 2.0,
				center_y - right_expand_button.size.y * 0.5
			)


func _is_click_inside_right_ui(pos: Vector2) -> bool:
	if equip_notice_panel and equip_notice_panel.visible and equip_notice_panel.get_global_rect().has_point(pos):
		return true
	if equip_notice_left_panel and equip_notice_left_panel.visible and equip_notice_left_panel.get_global_rect().has_point(pos):
		return true
	if right_inventory_panel and right_inventory_panel.visible and right_inventory_panel.get_global_rect().has_point(pos):
		return true
	if right_collapse_button and right_collapse_button.visible and right_collapse_button.get_global_rect().has_point(pos):
		return true
	if right_expand_button and right_expand_button.visible and right_expand_button.get_global_rect().has_point(pos):
		return true
	return false


func _is_click_on_party_panel(pos: Vector2) -> bool:
	return party_panel != null and party_panel.get_global_rect().has_point(pos)


func _on_equip_slot_row_hovered(slot_key: String, hovered: bool) -> void:
	var row: Dictionary = equip_notice_slot_rows.get(slot_key, {}) as Dictionary
	if row.is_empty():
		return
	var panel: PanelContainer = row.get("panel") as PanelContainer
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", equip_row_style_highlight if hovered else equip_row_style_normal)
	if hovered:
		var hero: Hero = _get_selected_hero()
		if hero == null:
			return
		var equip_id: String = str(hero.equipment.get(slot_key, ""))
		if not equip_id.is_empty():
			_show_equip_hover_desc(equip_id, {})
	else:
		_hide_equip_hover_desc()


func _apply_pause_ui_state(paused: bool) -> void:
	if party_panel and party_panel.has_method("set_selection_enabled"):
		party_panel.set_selection_enabled(true)

	if paused:
		selected_hero_index = _resolve_default_selected_hero_index()
		if party_panel and party_panel.has_method("set_selected_hero_index"):
			party_panel.set_selected_hero_index(selected_hero_index, false)
	else:
		right_panel_opened = false
		right_panel_collapsed = false
		_hide_equip_hover_desc()
		if party_panel and party_panel.has_method("set_selected_hero_index"):
			party_panel.set_selected_hero_index(-1, false)

	_refresh_selected_hero_panels()


func _resolve_default_selected_hero_index() -> int:
	if not PartyManager:
		return 0
	var party: Array = PartyManager.get_party()
	if party.is_empty():
		return 0

	if not last_equip_hero_id.is_empty():
		for i in range(party.size()):
			var hero: Hero = party[i]
			if hero != null and hero.id == last_equip_hero_id:
				return i
	return 0

func _show_notice(message: String, duration: float = 2.0, color: Color = Color.WHITE) -> void:
	if notice_panel == null or notice_label == null:
		return
	if message.strip_edges().is_empty():
		_hide_notice()
		return

	notice_label.text = message
	notice_label.add_theme_color_override("font_color", color)
	_layout_notice_box(message)
	notice_panel.visible = true
	notice_panel.scale = Vector2.ONE
	notice_panel.modulate.a = 1.0

	# paused 상태에서도 알림이 멈추지 않도록 process_always=true
	notice_timer = get_tree().create_timer(maxf(0.3, duration), true)
	await notice_timer.timeout
	if notice_label.text == message:
		_hide_notice()


func _hide_notice() -> void:
	if notice_panel:
		notice_panel.visible = false
		notice_panel.scale = Vector2.ONE
		notice_panel.modulate = Color.WHITE


func _layout_notice_box(message: String) -> void:
	if notice_panel == null or notice_label == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var max_panel_width: float = viewport_size.x * NOTICE_MAX_WIDTH_RATIO
	var max_text_width: float = maxf(120.0, max_panel_width - (NOTICE_PADDING_X * 2.0))

	var font_size: int = notice_label.get_theme_font_size("font_size")
	var font: Font = notice_label.get_theme_font("font")
	var text_size := Vector2(180.0, 24.0)
	if font != null:
		text_size = font.get_multiline_string_size(
			message,
			HORIZONTAL_ALIGNMENT_CENTER,
			max_text_width,
			font_size
		)

	var panel_width: float = clampf(text_size.x + NOTICE_PADDING_X * 2.0, NOTICE_MIN_WIDTH, max_panel_width)
	var panel_height: float = maxf(NOTICE_MIN_HEIGHT, text_size.y + NOTICE_PADDING_Y * 2.0)

	notice_panel.size = Vector2(panel_width, panel_height)
	notice_panel.position = Vector2(
		(viewport_size.x - panel_width) * 0.5,
		viewport_size.y * NOTICE_TOP_RATIO
	)


func _build_equip_stat_delta_text(item_id: String, replaced_id: String) -> String:
	var new_data: Dictionary = DataManager.get_equipment(item_id)
	if new_data.is_empty():
		return "(능력치 변화 없음)"
	var old_data: Dictionary = DataManager.get_equipment(replaced_id) if not replaced_id.is_empty() else {}
	var new_stats: Dictionary = new_data.get("stats", {})
	var old_stats: Dictionary = old_data.get("stats", {})

	var delta := {}
	_accumulate_equip_stat_delta(delta, new_stats, 1)
	_accumulate_equip_stat_delta(delta, old_stats, -1)

	var parts: Array[String] = []
	for key in EQUIP_STAT_ORDER:
		var d: int = int(delta.get(key, 0))
		if d == 0:
			continue
		var label: String = str(EQUIP_STAT_LABELS.get(key, key.to_upper()))
		var sign: String = "+" if d > 0 else ""
		parts.append("%s %s%d" % [label, sign, d])

	return ", ".join(parts) if not parts.is_empty() else "(능력치 변화 없음)"


func _accumulate_equip_stat_delta(dest: Dictionary, stats: Dictionary, mult: int) -> void:
	if stats.is_empty():
		return
	for key_any in stats.keys():
		var key: String = str(key_any)
		var normalized: String = key
		if key == "p_def":
			normalized = "def"
		elif key == "acc":
			normalized = "hit"
		dest[normalized] = int(dest.get(normalized, 0)) + int(stats[key_any]) * mult


func _queue_equip_notice_card(hero_name: String, item_id: String, slot: String, _replaced_id: String = "") -> void:
	_enqueue_equip_notice_event(hero_name, item_id, slot)


func _find_hero_by_name(hero_name: String) -> Hero:
	if not PartyManager:
		return null
	for h in PartyManager.get_party():
		var hero: Hero = h
		if hero != null and hero.hero_name == hero_name:
			return hero
	return null


func _play_next_equip_notice_card() -> void:
	# 레거시 호출 호환: 새 이벤트 집계 플로우로 위임
	_flush_equip_notice_events()


func _enqueue_equip_notice_event(hero_name: String, item_id: String, slot: String) -> void:
	if slot.is_empty():
		return
	var hero: Hero = _find_hero_by_name(hero_name)
	if hero == null:
		return
	var key: String = "%s|%s|%s" % [hero.id, item_id, slot]
	var now_ms: int = Time.get_ticks_msec()
	var prev_ms: int = int(equip_notice_recent_keys.get(key, 0))
	if prev_ms > 0 and now_ms - prev_ms < 120:
		return
	equip_notice_recent_keys[key] = now_ms
	equip_notice_pending_events.append({
		"hero_id": hero.id,
		"hero_name": hero.hero_name,
		"item_id": item_id,
		"slot_key": slot,
	})
	if equip_notice_flush_scheduled:
		return
	equip_notice_flush_scheduled = true
	call_deferred("_flush_equip_notice_events_deferred")


func _flush_equip_notice_events_deferred() -> void:
	await get_tree().create_timer(0.08, true).timeout
	_flush_equip_notice_events()


func _flush_equip_notice_events() -> void:
	equip_notice_flush_scheduled = false
	if equip_notice_pending_events.is_empty():
		return
	var grouped: Dictionary = {}
	var order: Array[String] = []
	for ev_any in equip_notice_pending_events:
		var ev: Dictionary = ev_any as Dictionary
		var hero_id: String = str(ev.get("hero_id", ""))
		if hero_id.is_empty():
			continue
		if not grouped.has(hero_id):
			grouped[hero_id] = {
				"hero_id": hero_id,
				"hero_name": str(ev.get("hero_name", "")),
				"slot_keys": [],
			}
			order.append(hero_id)
		var g: Dictionary = grouped[hero_id] as Dictionary
		var slots: Array = g.get("slot_keys", [])
		var slot_key: String = str(ev.get("slot_key", ""))
		if not slot_key.is_empty() and not slots.has(slot_key):
			slots.append(slot_key)
		g["slot_keys"] = slots
		grouped[hero_id] = g
	equip_notice_pending_events.clear()
	for hero_id in order:
		var payload: Dictionary = grouped.get(hero_id, {}) as Dictionary
		if payload.is_empty():
			continue
		_show_equip_notice_payload(payload)


func _show_equip_notice_payload(payload: Dictionary) -> void:
	if equip_notice_panel == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	_layout_equip_notice_cards()

	# 오른쪽 카드가 이미 보이는 상태에서 새 카드가 오면, 기존 카드를 왼쪽으로 밀어 보관
	if equip_notice_panel.visible and not equip_notice_right_payload.is_empty():
		equip_notice_left_payload = equip_notice_right_payload.duplicate(true)
		equip_notice_left_expire_ms = equip_notice_right_expire_ms
		_render_payload_to_card(equip_notice_left_panel, equip_notice_left_face, equip_notice_left_name, equip_notice_left_slot_rows, equip_notice_left_payload, false)
		equip_notice_left_token += 1
		_schedule_hide_card(equip_notice_left_panel, false, maxf(0.05, float(equip_notice_left_expire_ms - now_ms) / 1000.0), equip_notice_left_token)

	equip_notice_right_payload = payload.duplicate(true)
	equip_notice_right_expire_ms = now_ms + int((EQUIP_CARD_STAY_TIME + 0.2) * 1000.0)
	last_equip_hero_id = str(payload.get("hero_id", ""))
	_render_payload_to_card(equip_notice_panel, equip_notice_face, equip_notice_name, equip_notice_slot_rows, equip_notice_right_payload, true)
	equip_notice_right_token += 1
	_schedule_hide_card(equip_notice_panel, true, EQUIP_CARD_STAY_TIME, equip_notice_right_token)
	equip_notice_playing = true
	_layout_equip_notice_cards()


func _render_payload_to_card(
	panel: PanelContainer,
	face: TextureRect,
	name_label: Label,
	rows: Dictionary,
	payload: Dictionary,
	play_fx: bool
) -> void:
	if panel == null:
		return
	var hero_id: String = str(payload.get("hero_id", ""))
	var hero_name: String = str(payload.get("hero_name", ""))
	var hero: Hero = _find_hero_by_id(hero_id)
	var highlight_slots: Array[String] = []
	for s in payload.get("slot_keys", []):
		highlight_slots.append(str(s))
	if face and SpriteManager:
		face.texture = SpriteManager.get_hero_face_sprite(hero_id)
	if name_label:
		name_label.text = hero_name
	_refresh_equip_notice_slots_for_rows(rows, hero, highlight_slots)
	panel.modulate = Color.WHITE
	panel.scale = Vector2.ONE
	panel.visible = true
	if play_fx:
		if SoundManager:
			SoundManager.play_equip()
		for slot_key in highlight_slots:
			var row_panel: PanelContainer = _get_equip_notice_row_panel_from_rows(rows, slot_key)
			if row_panel:
				var flash_tween := create_tween()
				flash_tween.tween_property(row_panel, "modulate", Color(1.25, 1.2, 0.85, 1.0), 0.07)
				flash_tween.tween_property(row_panel, "modulate", Color.WHITE, 0.11)


func _schedule_hide_card(panel: PanelContainer, is_right: bool, stay_sec: float, token: int) -> void:
	if panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	await get_tree().create_timer(stay_sec, true).timeout
	if is_right and token != equip_notice_right_token:
		return
	if not is_right and token != equip_notice_left_token:
		return
	var out_tween := create_tween()
	out_tween.set_parallel(true)
	out_tween.tween_property(panel, "position:x", viewport_size.x + 4.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	out_tween.tween_property(panel, "scale:x", 0.03, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out_tween.tween_property(panel, "modulate:a", 0.0, 0.18)
	await out_tween.finished
	panel.visible = false
	panel.scale = Vector2.ONE
	panel.modulate = Color.WHITE
	if is_right:
		equip_notice_right_payload.clear()
	else:
		equip_notice_left_payload.clear()
	equip_notice_playing = equip_notice_panel.visible or (equip_notice_left_panel != null and equip_notice_left_panel.visible)
	_layout_equip_notice_cards()


func _find_hero_by_id(hero_id: String) -> Hero:
	if not PartyManager:
		return null
	for h in PartyManager.get_party():
		var hero: Hero = h
		if hero != null and hero.id == hero_id:
			return hero
	return null


func _refresh_equip_notice_slots(hero: Hero, highlighted_slot: String) -> void:
	var highlighted_slots: Array[String] = []
	if not highlighted_slot.is_empty():
		highlighted_slots.append(highlighted_slot)
	_refresh_equip_notice_slots_for_rows(equip_notice_slot_rows, hero, highlighted_slots)


func _refresh_equip_notice_slots_for_rows(rows: Dictionary, hero: Hero, highlighted_slots: Array[String]) -> void:
	for slot_key in SLOT_ORDER:
		var row: Dictionary = rows.get(slot_key, {}) as Dictionary
		if row.is_empty():
			continue
		var panel: PanelContainer = row.get("panel") as PanelContainer
		var item_label: Label = row.get("item_label") as Label
		var item_text: String = "— 비어있음 —"
		var item_color: Color = Color(0.75, 0.75, 0.8)
		if hero != null:
			var equip_id: String = str(hero.equipment.get(slot_key, ""))
			if not equip_id.is_empty():
				var equip_data: Dictionary = DataManager.get_equipment(equip_id)
				item_text = str(equip_data.get("name", equip_id))
				item_color = Color(0.95, 0.95, 0.8)
		var is_highlighted: bool = highlighted_slots.has(slot_key)
		if is_highlighted and item_text != "— 비어있음 —":
			item_text += " [장착]"
		if item_label:
			item_label.text = item_text
			item_label.add_theme_color_override("font_color", item_color)
		if panel:
			panel.modulate = Color.WHITE
			if is_highlighted and equip_row_style_highlight:
				panel.add_theme_stylebox_override("panel", equip_row_style_highlight)
			elif equip_row_style_normal:
				panel.add_theme_stylebox_override("panel", equip_row_style_normal)


func _build_equip_stat_delta(item_id: String, replaced_id: String) -> Dictionary:
	var new_data: Dictionary = DataManager.get_equipment(item_id)
	var old_data: Dictionary = DataManager.get_equipment(replaced_id) if not replaced_id.is_empty() else {}
	var new_stats: Dictionary = new_data.get("stats", {})
	var old_stats: Dictionary = old_data.get("stats", {})
	var delta := {}
	_accumulate_equip_stat_delta(delta, new_stats, 1)
	_accumulate_equip_stat_delta(delta, old_stats, -1)
	return delta


func _refresh_equip_notice_stats(hero: Hero, delta: Dictionary) -> void:
	for entry in equip_notice_stat_rows:
		var e: Dictionary = entry as Dictionary
		var key: String = str(e.get("key", ""))
		var value_label: Label = e.get("value_label") as Label
		var delta_label: Label = e.get("delta_label") as Label
		if value_label == null or delta_label == null:
			continue
		value_label.text = _format_equip_stat_value(key, _get_hero_stat_value(hero, key))
		var d: int = int(delta.get(key, 0))
		if d > 0:
			delta_label.text = "▲ +%d" % d
			delta_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
		elif d < 0:
			delta_label.text = "▼ %d" % d
			delta_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		else:
			delta_label.text = "—"
			delta_label.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))


func _get_hero_stat_value(hero: Hero, key: String) -> float:
	if hero == null:
		return 0.0
	match key:
		"atk":
			return float(hero.get_atk())
		"def":
			return float(hero.get_def())
		"mag":
			return float(hero.get_magic_attack())
		"spd":
			return float(hero.get_spd())
		"hit":
			return float(hero.get_hit_rate())
		"eva":
			return float(hero.get_eva())
		"str":
			return float(hero.get_str())
		"agi":
			return float(hero.get_dex())
		"wis":
			return float(hero.get_base_stat("wis"))
		"luk":
			return float(hero.get_luk())
		"hp":
			return float(hero.get_max_hp())
		_:
			return 0.0


func _format_equip_stat_value(key: String, value: float) -> String:
	if key == "hit" or key == "eva":
		return "%.1f%%" % value
	return str(int(round(value)))


func _get_equip_notice_row_panel(slot_key: String) -> PanelContainer:
	return _get_equip_notice_row_panel_from_rows(equip_notice_slot_rows, slot_key)


func _get_equip_notice_row_panel_from_rows(rows: Dictionary, slot_key: String) -> PanelContainer:
	var row: Dictionary = rows.get(slot_key, {}) as Dictionary
	if row.is_empty():
		return null
	return row.get("panel") as PanelContainer


func has_unclaimed_rewards() -> bool:
	if not BattleManager:
		return false
	var rewards: Dictionary = BattleManager.get_accumulated_rewards()
	var gold: int = int(rewards.get("gold", 0))
	var exp: int = int(rewards.get("exp", 0))
	var items: Array = rewards.get("items", []) as Array
	return gold > 0 or exp > 0 or not items.is_empty()


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
