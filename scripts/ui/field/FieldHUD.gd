extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## - TopBar: 스테이지, 골드, 배속, 메뉴
## - LogPanel: 전투 로그 (좌측 하단)
## - BottomPartyPanel: 파티 정보 (하단 중앙) - 외부 씬
## - InventoryPanel: 인벤토리 (우측 하단)

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

# === 인벤토리 패널 (우측 하단) ===
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var inventory_scroll: ScrollContainer = %InventoryScroll
@onready var inventory_list: VBoxContainer = %InventoryList

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

# === 인벤토리 아이템 목록 ===
var inventory_slots: Array = []


func _ready() -> void:
	add_to_group("field_hud")
	_setup_components()
	_setup_grudge_popup()
	_setup_town_popup()
	_connect_signals()
	_setup_inventory_panel()
	update_all()
	_update_trait_display()
	_update_inventory_display()


func _setup_components() -> void:
	_setup_speed_button()

	# 배틀 로그
	battle_log = BattleLogUI.new()
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if log_container:
		log_container.add_child(battle_log)


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
		if not BattleManager.loot_animation_requested.is_connected(_on_loot_animation_requested):
			BattleManager.loot_animation_requested.connect(_on_loot_animation_requested)
		if not BattleManager.danger_level_up.is_connected(show_grudge_choice_popup):
			BattleManager.danger_level_up.connect(show_grudge_choice_popup)



#region 인벤토리 패널
func _setup_inventory_panel() -> void:
	## 인벤토리 패널 초기 설정
	if not inventory_list:
		return

	# 인벤토리 변경 시그널 연결
	if InventoryManager and not InventoryManager.inventory_changed.is_connected(_update_inventory_display):
		InventoryManager.inventory_changed.connect(_update_inventory_display)


func _update_inventory_display() -> void:
	## 인벤토리 UI 업데이트 (목록 형태)
	if not inventory_list:
		return

	# 기존 아이템 제거
	for child in inventory_list.get_children():
		child.queue_free()
	inventory_slots.clear()

	# 인벤토리 아이템 가져오기
	var items: Array = InventoryManager.get_all_items() if InventoryManager else []

	# 아이템 행 생성 (최대 10개)
	var count: int = 0
	for item in items:
		if count >= 10:
			break
		var row := _create_inventory_row(item)
		inventory_list.add_child(row)
		inventory_slots.append(row)
		count += 1


func _create_inventory_row(item: Dictionary) -> Button:
	## 아이템 행 UI 생성: 클릭 시 자동 장착
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var rarity: String = item.data.get("rarity", "common")
	var rarity_color: Color = InventoryManager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))

	# 버튼 텍스트
	var item_type: String = item.data.get("type", "?")
	var icon: String = _get_item_type_icon(item_type)
	var item_name: String = item.data.get("name", item.id)
	if item.quantity > 1:
		btn.text = "%s %s x%d" % [icon, item_name, item.quantity]
	else:
		btn.text = "%s %s" % [icon, item_name]

	btn.add_theme_font_size_override("font_size", 9)
	btn.add_theme_color_override("font_color", rarity_color)
	btn.add_theme_color_override("font_hover_color", rarity_color * 1.2)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 버튼 스타일
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(1, 1, 1, 0.1)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(1, 1, 1, 0.2)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# 클릭 시 자동 장착
	btn.pressed.connect(_on_inventory_item_clicked.bind(item.id))

	# 툴팁
	var slot: String = item.data.get("slot", "")
	var stats: Dictionary = item.data.get("stats", {})
	var tooltip: String = item_name + "\n"
	tooltip += "희귀도: " + rarity + "\n"
	for stat_key in stats:
		tooltip += "%s: %+d\n" % [stat_key.to_upper(), stats[stat_key]]
	tooltip += "\n[클릭: 자동 장착]"
	btn.tooltip_text = tooltip

	return btn


func _on_inventory_item_clicked(item_id: String) -> void:
	## 인벤토리 아이템 클릭 - 자동 장착 시도
	if not InventoryManager:
		return

	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		# 장비가 아님 (소비 아이템 등)
		return

	# 자동 장착 시도
	if InventoryManager.try_auto_equip(item_id):
		# 장착 성공 - 로그 출력
		var item_name: String = item_data.get("name", item_id)
		add_log("%s 장착!" % item_name, Color(0.5, 1.0, 0.5))
	else:
		# 장착 실패 - 모든 슬롯이 더 좋은 장비로 채워져 있음
		add_log("장착할 수 없습니다.", Color(1.0, 0.5, 0.5))


func _get_item_type_icon(item_type: String) -> String:
	## 아이템 타입별 아이콘 반환
	match item_type:
		"sword": return "⚔"
		"dagger": return "🗡"
		"staff": return "🪄"
		"bow": return "🏹"
		"axe": return "🪓"
		"shield": return "🛡"
		"helmet": return "⛑"
		"heavy_armor", "medium_armor", "light_armor": return "🥋"
		"robe": return "👘"
		"ring": return "💍"
		"amulet": return "📿"
		"boots": return "👢"
		"potion": return "🧪"
		_: return "?"
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
	# 인벤토리 패널 중앙으로 루팅 애니메이션
	if inventory_panel and is_instance_valid(inventory_panel):
		return inventory_panel.global_position + inventory_panel.size / 2
	return Vector2(420, 320)


func _on_loot_animation_completed(_item_id: String) -> void:
	# 인벤토리 디스플레이 갱신
	_update_inventory_display()
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
			var item_data: Dictionary = DataManager.get_equipment(item.id)
			if item_data.is_empty():
				item_data = DataManager.get_item(item.id)
			var item_name: String = item_data.get("name", item.id)
			item_lbl.text = item_name
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

	# Gold
	var reward_info := HBoxContainer.new()
	reward_info.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_info.add_theme_constant_override("separation", 20)
	vbox.add_child(reward_info)

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
			var item_data: Dictionary = DataManager.get_equipment(item.id)
			if item_data.is_empty():
				item_data = DataManager.get_item(item.id)
			var item_name: String = item_data.get("name", item.id)
			item_lbl.text = item_name
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
	return rewards.gold > 0 or rewards.items.size() > 0
#endregion
