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

# === 우측 파티 패널 ===
var right_party_panel: PanelContainer = null
var right_party_slots: Array = []  # 파티원별 슬롯 데이터

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
	_setup_right_party_panel()
	update_all()
	_update_trait_display()
	_update_inventory_display()

	# 하단 파티 패널 숨김
	if bottom_party_panel:
		bottom_party_panel.visible = false


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


func _create_inventory_row(item: Dictionary) -> HBoxContainer:
	## 아이템 행 UI 생성: [아이콘] 이름 x수량
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var rarity: String = item.data.get("rarity", "common")
	var rarity_color: Color = InventoryManager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))

	# 아이콘
	var icon_label := Label.new()
	var item_type: String = item.data.get("type", "?")
	icon_label.text = _get_item_type_icon(item_type)
	icon_label.add_theme_font_size_override("font_size", 11)
	icon_label.add_theme_color_override("font_color", rarity_color)
	icon_label.custom_minimum_size.x = 16
	row.add_child(icon_label)

	# 이름
	var name_label := Label.new()
	var item_name: String = item.data.get("name", item.id)
	if item.quantity > 1:
		name_label.text = "%s x%d" % [item_name, item.quantity]
	else:
		name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", rarity_color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	return row


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


#region 우측 파티 패널
const SLOT_ICONS := {"main_hand": "⚔", "off_hand": "🛡", "head": "👒", "body": "👕", "acc1": "💍", "acc2": "💍"}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]
const RARITY_COLORS := {
	"common": Color(0.7, 0.7, 0.7),
	"uncommon": Color(0.4, 0.8, 0.4),
	"magic": Color(0.4, 0.6, 1.0),
	"rare": Color(0.8, 0.6, 1.0),
	"epic": Color(1.0, 0.5, 0.2),
	"legendary": Color(1.0, 0.8, 0.2)
}

class RightPartySlot:
	var container: HBoxContainer  # 전체 컨테이너
	var face_container: Control   # 페이스칩 컨테이너
	var face: TextureRect
	var damage_overlay: ColorRect
	var hp_label: Label
	var atb_bar: ProgressBar
	var equip_vbox: VBoxContainer  # 장비 목록
	var equip_rows: Dictionary = {}  # slot_name -> HBoxContainer
	var hero_id: String = ""

func _setup_right_party_panel() -> void:
	## 우측 파티 패널 초기화
	var ctrl := get_node_or_null("Control")
	if not ctrl:
		return

	# 메인 패널 생성
	right_party_panel = PanelContainer.new()
	right_party_panel.name = "RightPartyPanel"

	# 위치: 우측 중단
	right_party_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right_party_panel.offset_left = -200
	right_party_panel.offset_right = -4
	right_party_panel.offset_top = -120
	right_party_panel.offset_bottom = 120
	right_party_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# 스타일
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.9)
	panel_style.border_width_left = 2
	panel_style.border_color = Color(0.3, 0.3, 0.4)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 6
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	right_party_panel.add_theme_stylebox_override("panel", panel_style)

	ctrl.add_child(right_party_panel)

	# 스크롤 컨테이너
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_party_panel.add_child(scroll)

	# 파티 목록 (세로)
	var party_vbox := VBoxContainer.new()
	party_vbox.add_theme_constant_override("separation", 8)
	party_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(party_vbox)

	# 파티원별 슬롯 생성
	right_party_slots.clear()
	for i in range(4):
		var slot := _create_right_party_slot(i)
		right_party_slots.append(slot)
		party_vbox.add_child(slot.container)

	# ATB 업데이트 연결
	if ATBManager and ATBManager.has_signal("atb_updated"):
		if not ATBManager.atb_updated.is_connected(_on_right_panel_atb_updated):
			ATBManager.atb_updated.connect(_on_right_panel_atb_updated)


func _create_right_party_slot(index: int) -> RightPartySlot:
	var slot := RightPartySlot.new()

	# 전체 컨테이너 (가로: 페이스칩 + 장비목록)
	slot.container = HBoxContainer.new()
	slot.container.add_theme_constant_override("separation", 6)
	slot.container.visible = false

	# === 페이스칩 영역 ===
	var face_vbox := VBoxContainer.new()
	face_vbox.add_theme_constant_override("separation", 2)
	slot.container.add_child(face_vbox)

	# 페이스 컨테이너 (40x40)
	slot.face_container = Control.new()
	slot.face_container.custom_minimum_size = Vector2(40, 40)
	face_vbox.add_child(slot.face_container)

	# 페이스 이미지
	slot.face = TextureRect.new()
	slot.face.custom_minimum_size = Vector2(40, 40)
	slot.face.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.face_container.add_child(slot.face)

	# 데미지 오버레이
	slot.damage_overlay = ColorRect.new()
	slot.damage_overlay.color = Color(0.8, 0.1, 0.1, 0.6)
	slot.damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.damage_overlay.anchor_top = 1.0
	slot.face_container.add_child(slot.damage_overlay)

	# HP 라벨
	slot.hp_label = Label.new()
	slot.hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.hp_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	slot.hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot.hp_label.add_theme_font_size_override("font_size", 9)
	slot.hp_label.add_theme_color_override("font_color", Color.WHITE)
	slot.hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	slot.hp_label.add_theme_constant_override("outline_size", 2)
	slot.hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.face_container.add_child(slot.hp_label)

	# ATB 바
	slot.atb_bar = ProgressBar.new()
	slot.atb_bar.custom_minimum_size = Vector2(40, 5)
	slot.atb_bar.max_value = 100.0
	slot.atb_bar.value = 0.0
	slot.atb_bar.show_percentage = false

	var atb_bg := StyleBoxFlat.new()
	atb_bg.bg_color = Color(0.15, 0.15, 0.2)
	atb_bg.corner_radius_top_left = 2
	atb_bg.corner_radius_top_right = 2
	atb_bg.corner_radius_bottom_left = 2
	atb_bg.corner_radius_bottom_right = 2
	slot.atb_bar.add_theme_stylebox_override("background", atb_bg)

	var atb_fill := StyleBoxFlat.new()
	atb_fill.bg_color = Color(0.3, 0.7, 1.0)
	atb_fill.corner_radius_top_left = 2
	atb_fill.corner_radius_top_right = 2
	atb_fill.corner_radius_bottom_left = 2
	atb_fill.corner_radius_bottom_right = 2
	slot.atb_bar.add_theme_stylebox_override("fill", atb_fill)
	face_vbox.add_child(slot.atb_bar)

	# === 장비 목록 영역 ===
	slot.equip_vbox = VBoxContainer.new()
	slot.equip_vbox.add_theme_constant_override("separation", 1)
	slot.equip_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.container.add_child(slot.equip_vbox)

	# 6개 장비 슬롯 행 생성
	for slot_name in SLOT_ORDER:
		var row := _create_equip_row(slot_name)
		slot.equip_vbox.add_child(row)
		slot.equip_rows[slot_name] = row

	return slot


func _create_equip_row(slot_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# 아이콘
	var icon_lbl := Label.new()
	icon_lbl.name = "Icon"
	icon_lbl.text = SLOT_ICONS.get(slot_name, "?")
	icon_lbl.add_theme_font_size_override("font_size", 9)
	icon_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	icon_lbl.custom_minimum_size.x = 14
	row.add_child(icon_lbl)

	# 이름
	var name_lbl := Label.new()
	name_lbl.name = "Name"
	name_lbl.text = "-"
	name_lbl.add_theme_font_size_override("font_size", 8)
	name_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_lbl)

	return row


func _update_right_party_panel() -> void:
	## 우측 파티 패널 업데이트
	if right_party_slots.is_empty():
		return

	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(right_party_slots.size()):
		var slot: RightPartySlot = right_party_slots[i]

		if i < party.size() and party[i] != null:
			var hero: Hero = party[i]
			slot.container.visible = true
			slot.hero_id = hero.id

			# 페이스 업데이트
			if SpriteManager and slot.face:
				slot.face.texture = SpriteManager.get_hero_face_sprite(hero.id)

			# HP 오버레이 업데이트
			var max_hp := hero.get_max_hp()
			var hp_percent: float = float(hero.current_hp) / float(max_hp) if max_hp > 0 else 1.0
			_update_right_damage_overlay(slot, hp_percent)
			slot.hp_label.text = "%d/%d" % [hero.current_hp, max_hp]

			# 장비 업데이트
			_update_right_equip_list(slot, hero)
		else:
			slot.container.visible = false


func _update_right_damage_overlay(slot: RightPartySlot, hp_percent: float) -> void:
	if not slot.damage_overlay:
		return

	slot.damage_overlay.anchor_top = hp_percent
	slot.damage_overlay.anchor_bottom = 1.0

	if hp_percent <= 0.25:
		slot.damage_overlay.color = Color(0.9, 0.1, 0.1, 0.7)
	elif hp_percent <= 0.5:
		slot.damage_overlay.color = Color(0.85, 0.2, 0.1, 0.6)
	else:
		slot.damage_overlay.color = Color(0.8, 0.3, 0.2, 0.5)


func _update_right_equip_list(slot: RightPartySlot, hero: Hero) -> void:
	for slot_name in SLOT_ORDER:
		var row: HBoxContainer = slot.equip_rows.get(slot_name)
		if not row:
			continue

		var icon_lbl: Label = row.get_node_or_null("Icon")
		var name_lbl: Label = row.get_node_or_null("Name")
		if not icon_lbl or not name_lbl:
			continue

		var equip_id: String = hero.equipment.get(slot_name, "")
		if equip_id.is_empty():
			icon_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			name_lbl.text = "-"
			name_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		else:
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			var rarity: String = equip_data.get("rarity", "common")
			var rarity_color: Color = RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))

			icon_lbl.add_theme_color_override("font_color", rarity_color)
			name_lbl.text = equip_data.get("name", equip_id)
			name_lbl.add_theme_color_override("font_color", rarity_color)


func _on_right_panel_atb_updated() -> void:
	## ATB 업데이트
	for slot in right_party_slots:
		if slot.hero_id.is_empty() or slot.atb_bar == null:
			continue

		var atb_percent: float = ATBManager.get_hero_atb_percent(slot.hero_id)
		slot.atb_bar.value = atb_percent * 100.0

		# ATB 100% = 금색
		var fill_color: Color
		if atb_percent >= 1.0:
			fill_color = Color(1.0, 0.8, 0.2)
		else:
			fill_color = Color(0.3, 0.7, 1.0)

		var fill := StyleBoxFlat.new()
		fill.bg_color = fill_color
		fill.corner_radius_top_left = 2
		fill.corner_radius_top_right = 2
		fill.corner_radius_bottom_left = 2
		fill.corner_radius_bottom_right = 2
		slot.atb_bar.add_theme_stylebox_override("fill", fill)
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
	_update_right_party_panel()
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
