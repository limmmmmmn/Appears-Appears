extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러 (재구축)
## 모든 패널을 일관된 스타일로 통합 관리
##
## 구성:
##   TopBar       - 스테이지, 골드, 킬, 배속, 메뉴 (상단)
##   LogPanel     - 전투 로그 (좌측 하단)
##   PartyCards   - 파티 카드 (하단 중앙)
##   InventoryPanel - 인벤토리 (우측 하단)
##   TraitPanel   - 룬/특성 (우측 중앙)
##   GrudgePopup  - 원념 선택 (팝업)
##   TownPopup    - 마을 진입 확인 (팝업)

signal menu_pressed
signal town_enter_confirmed(claim_rewards: bool)


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

const ITEM_TYPE_ICONS := {
	"sword": "⚔", "dagger": "🗡", "staff": "🪄", "bow": "🏹", "axe": "🪓",
	"shield": "🛡", "helmet": "⛑", "heavy_armor": "🥋", "medium_armor": "🥋",
	"light_armor": "🥋", "robe": "👘", "ring": "💍", "amulet": "📿",
	"boots": "👢", "potion": "🧪",
}
#endregion


#region 노드 참조
# TopBar
@onready var stage_label: Label = %StageLabel
@onready var gold_label: Label = %GoldLabel
@onready var speed_button: Button = %SpeedButton
@onready var menu_button: Button = %MenuButton
var kill_label: Label = null

# LogPanel
@onready var log_panel: PanelContainer = %LogPanel
@onready var log_scroll: ScrollContainer = %LogScroll
@onready var log_container: VBoxContainer = %LogContainer

# BottomPartyCards
var bottom_party_cards: BottomPartyCards = null

# InventoryPanel
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var inventory_scroll: ScrollContainer = %InventoryScroll
@onready var inventory_list: VBoxContainer = %InventoryList

# TraitPanel
@onready var trait_panel: PanelContainer = %TraitPanel
@onready var trait_vbox: VBoxContainer = %TraitVBox
#endregion


#region 내부 상태
var battle_log: BattleLogUI = null
var inventory_slots: Array = []
var inventory_drop_target: _InventoryDropTarget = null

# 팝업
var grudge_popup: CanvasLayer = null
var is_grudge_popup_active: bool = false
var town_popup: CanvasLayer = null
var is_town_popup_active: bool = false

# 킬 카운트 영웅 추가
const KILLS_PER_HERO := 5
const AVAILABLE_HEROES := ["roland", "luna", "elena", "shadow", "aria", "gareth"]
var last_hero_kill_threshold: int = 0
#endregion


func _ready() -> void:
	add_to_group("field_hud")
	_init_topbar()
	_init_log_panel()
	_init_party_cards()
	_init_inventory_panel()
	_init_popups()
	_connect_signals()
	update_all()
	_update_trait_display()
	_update_inventory_display()


#region 초기화
func _init_topbar() -> void:
	## TopBar: 배속 버튼 스타일, 킬 라벨 추가
	if speed_button:
		speed_button.visible = false
		var style := _make_flat_style(STYLE.bg_btn, STYLE.border_accent, 3, 2)
		speed_button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate()
		hover.bg_color = Color(0.18, 0.18, 0.22, 0.95)
		speed_button.add_theme_stylebox_override("hover", hover)

	if gold_label:
		var parent := gold_label.get_parent()
		if parent:
			kill_label = Label.new()
			kill_label.name = "KillLabel"
			kill_label.add_theme_font_size_override("font_size", STYLE.font_normal)
			kill_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
			var gold_idx := gold_label.get_index()
			parent.add_child(kill_label)
			parent.move_child(kill_label, gold_idx + 1)
			var current_kills := BattleManager.get_global_kill_count() if BattleManager else 0
			kill_label.text = "💀 %d" % current_kills


func _init_log_panel() -> void:
	## LogPanel: BattleLogUI 컴포넌트 생성
	battle_log = BattleLogUI.new()
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if log_container:
		log_container.add_child(battle_log)


func _init_party_cards() -> void:
	## 하단 파티 카드 씬 인스턴스 생성
	var scene := preload("res://scenes/ui/BottomPartyCards.tscn")
	bottom_party_cards = scene.instantiate() as BottomPartyCards
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(bottom_party_cards)


func _init_inventory_panel() -> void:
	## 인벤토리 패널 초기 설정 및 드롭 타겟 생성
	if not inventory_list:
		return
	if InventoryManager and not InventoryManager.inventory_changed.is_connected(_update_inventory_display):
		InventoryManager.inventory_changed.connect(_update_inventory_display)
	_setup_inventory_drop_target()


func _init_popups() -> void:
	## 팝업 레이어 생성 (원념, 마을)
	grudge_popup = _create_popup_layer("GrudgePopup")
	add_child(grudge_popup)
	town_popup = _create_popup_layer("TownPopup")
	add_child(town_popup)


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
		if not BattleManager.battle_log_received.is_connected(_on_battle_log):
			BattleManager.battle_log_received.connect(_on_battle_log)
		if not BattleManager.party_hp_changed.is_connected(update_party_display):
			BattleManager.party_hp_changed.connect(update_party_display)
		if not BattleManager.loot_animation_requested.is_connected(_on_loot_anim):
			BattleManager.loot_animation_requested.connect(_on_loot_anim)
		if BattleManager.has_signal("global_kill_count_changed"):
			if not BattleManager.global_kill_count_changed.is_connected(_on_kill_count_changed):
				BattleManager.global_kill_count_changed.connect(_on_kill_count_changed)

	if bottom_party_cards:
		if not bottom_party_cards.equipment_dropped.is_connected(_on_equip_dropped):
			bottom_party_cards.equipment_dropped.connect(_on_equip_dropped)
#endregion


#region 스타일 유틸리티
static func _make_flat_style(
	bg: Color, border: Color = Color.TRANSPARENT,
	radius: int = 6, border_w: int = 1
) -> StyleBoxFlat:
	## 일관된 StyleBoxFlat 생성 유틸리티
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


#region 인벤토리 패널
func _setup_inventory_drop_target() -> void:
	if not inventory_panel:
		return
	if inventory_drop_target and is_instance_valid(inventory_drop_target):
		return
	inventory_drop_target = _InventoryDropTarget.new()
	inventory_drop_target.hud_ref = self
	inventory_drop_target.set_anchors_preset(Control.PRESET_FULL_RECT)
	inventory_drop_target.mouse_filter = Control.MOUSE_FILTER_PASS
	inventory_panel.add_child(inventory_drop_target)


func _update_inventory_display() -> void:
	## 인벤토리 UI 전체 갱신
	if not inventory_list:
		return

	for child in inventory_list.get_children():
		child.queue_free()
	inventory_slots.clear()

	var items: Array = InventoryManager.get_all_items() if InventoryManager else []
	var count: int = 0
	for item in items:
		if count >= 10:
			break
		var row := _create_inventory_row(item)
		inventory_list.add_child(row)
		inventory_slots.append(row)
		count += 1


func _create_inventory_row(item: Dictionary) -> Control:
	## 인벤토리 아이템 행 생성 (드래그 + 클릭 장착)
	var row := _DraggableItemRow.new()
	row.item_id = item.id
	row.item_data = item.data
	row.hud_ref = self

	var rarity: String = item.data.get("rarity", "common")
	var rarity_color: Color = InventoryManager.RARITY_COLORS.get(rarity, Color(0.7, 0.7, 0.7))

	var item_type: String = item.data.get("type", "?")
	var icon: String = ITEM_TYPE_ICONS.get(item_type, "?")
	var item_name: String = item.data.get("name", item.id)
	var display_text: String
	if item.quantity > 1:
		display_text = "%s %s x%d" % [icon, item_name, item.quantity]
	else:
		display_text = "%s %s" % [icon, item_name]

	row.setup(display_text, rarity_color, rarity)

	var stats: Dictionary = item.data.get("stats", {})
	var tooltip: String = item_name + "\n"
	tooltip += "희귀도: " + rarity + "\n"
	for stat_key in stats:
		tooltip += "%s: %+d\n" % [stat_key.to_upper(), stats[stat_key]]
	tooltip += "\n[드래그: 영웅에게 장착]\n[클릭: 자동 장착]"
	row.tooltip_text = tooltip

	return row


## 드래그 가능한 인벤토리 아이템 행
class _DraggableItemRow extends Button:
	var item_id: String = ""
	var item_data: Dictionary = {}
	var hud_ref: FieldHUD = null
	var rarity_color: Color = Color.WHITE
	var rarity: String = "common"

	func setup(text: String, color: Color, p_rarity: String) -> void:
		rarity_color = color
		rarity = p_rarity
		self.text = text
		custom_minimum_size = Vector2(100, 18)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		alignment = HORIZONTAL_ALIGNMENT_LEFT

		add_theme_font_size_override("font_size", FieldHUD.STYLE.font_small)
		add_theme_color_override("font_color", color)

		var normal_style := FieldHUD._make_flat_style(
			Color(0.08, 0.08, 0.1, 0.8),
			Color(0.3, 0.3, 0.35, 0.6), 3, 1
		)
		normal_style.content_margin_left = 4
		normal_style.content_margin_right = 4
		add_theme_stylebox_override("normal", normal_style)

		var hover_style := FieldHUD._make_flat_style(
			FieldHUD.STYLE.bg_btn_hover,
			Color(1.0, 0.95, 0.3, 1.0), 3, 2
		)
		hover_style.content_margin_left = 4
		hover_style.content_margin_right = 4
		add_theme_stylebox_override("hover", hover_style)
		add_theme_stylebox_override("pressed", hover_style)

		pressed.connect(_on_pressed)

	func _on_pressed() -> void:
		if hud_ref:
			hud_ref._on_inventory_item_clicked(item_id)

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item_data.get("slot", "").is_empty():
			return null
		var preview := Label.new()
		preview.text = self.text
		preview.add_theme_font_size_override("font_size", 10)
		preview.add_theme_color_override("font_color", rarity_color)
		preview.add_theme_color_override("font_outline_color", Color.BLACK)
		preview.add_theme_constant_override("outline_size", 2)
		preview.modulate.a = 0.9
		set_drag_preview(preview)
		return {"type": "equipment", "item_id": item_id, "item_data": item_data}


## 인벤토리 드롭 타겟 (장비 해제용)
class _InventoryDropTarget extends Control:
	var hud_ref: FieldHUD = null

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not data is Dictionary:
			return false
		return data.get("type", "") == "equipment" and data.get("source", "") == "equipment"

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if not data is Dictionary:
			return
		var hero_index: int = data.get("hero_index", -1)
		var source_slot: String = data.get("source_slot", "")
		if hero_index < 0 or source_slot.is_empty():
			return
		var party: Array = PartyManager.get_party() if PartyManager else []
		if hero_index >= party.size() or party[hero_index] == null:
			return
		var hero: Hero = party[hero_index]
		if InventoryManager and InventoryManager.unequip_item(hero, source_slot):
			if hud_ref:
				hud_ref.update_party_display()
				hud_ref._update_inventory_display()


func _on_inventory_item_clicked(item_id: String) -> void:
	## 인벤토리 아이템 클릭 → 자동 장착
	if not InventoryManager:
		return
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		return
	if InventoryManager.try_auto_equip(item_id):
		add_log("%s 장착!" % item_data.get("name", item_id), STYLE.text_green)
	else:
		add_log("장착할 수 없습니다.", STYLE.text_red)
#endregion


#region 이벤트 핸들러
func _on_speed_pressed() -> void:
	pass


func _on_battle_log(message: String, color: Color) -> void:
	add_log(message, color)


func _on_kill_count_changed(count: int, _danger_level: int) -> void:
	if kill_label:
		kill_label.text = "💀 %d" % count
	# 5킬마다 영웅 추가
	var threshold := (count / KILLS_PER_HERO) * KILLS_PER_HERO
	if threshold > last_hero_kill_threshold and threshold > 0:
		last_hero_kill_threshold = threshold
		_add_random_hero()


func _add_random_hero() -> void:
	if not PartyManager:
		return
	var party: Array = PartyManager.get_party()
	if party.size() >= 4:
		add_log("파티가 가득 찼습니다!", STYLE.text_gold)
		return

	var party_ids: Array = []
	for hero in party:
		if hero:
			party_ids.append(hero.id)

	var available: Array = []
	for hero_id in AVAILABLE_HEROES:
		if hero_id not in party_ids:
			available.append(hero_id)

	if available.is_empty():
		add_log("추가할 수 있는 영웅이 없습니다.", STYLE.text_dim)
		return

	var random_id: String = available[randi() % available.size()]
	if PartyManager.add_hero_by_id(random_id):
		var hero_data: Dictionary = DataManager.get_hero(random_id) if DataManager else {}
		var hero_name: String = hero_data.get("name", random_id)
		add_log("🎉 %s 합류!" % hero_name, Color(0.5, 1.0, 0.8))
		if bottom_party_cards:
			bottom_party_cards.update_display()


func _on_loot_anim(item_id: String, start_pos: Vector2) -> void:
	var target_pos: Vector2
	if inventory_panel and is_instance_valid(inventory_panel):
		target_pos = inventory_panel.global_position + inventory_panel.size / 2
	else:
		target_pos = Vector2(420, 320)

	var loot_anim := LootAnimationUI.new()
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(loot_anim)
	else:
		add_child(loot_anim)
	loot_anim.animation_completed.connect(_on_loot_anim_done)
	loot_anim.setup(item_id, start_pos, target_pos)


func _on_loot_anim_done(_item_id: String) -> void:
	_update_inventory_display()


func _on_equip_dropped(hero_index: int, item_id: String) -> void:
	_update_inventory_display()
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = item_data.get("name", item_id)
	var party: Array = PartyManager.get_party() if PartyManager else []
	var hero_name: String = ""
	if hero_index >= 0 and hero_index < party.size() and party[hero_index] != null:
		hero_name = party[hero_index].hero_name
	if not hero_name.is_empty():
		add_log("%s에게 %s 장착!" % [hero_name, item_name], STYLE.text_green)
	else:
		add_log("%s 장착!" % item_name, STYLE.text_green)
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


#region 특성 표시
func _update_trait_display() -> void:
	## 파티원별 룬/특성 패널 갱신
	if trait_vbox == null:
		return

	for child in trait_vbox.get_children():
		child.queue_free()

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

	# 제목
	var title_label := Label.new()
	title_label.text = "[ 장착 룬 ]"
	title_label.add_theme_font_size_override("font_size", STYLE.font_small)
	title_label.add_theme_color_override("font_color", STYLE.text_dim)
	trait_vbox.add_child(title_label)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	trait_vbox.add_child(sep)

	for hero in heroes_with_runes:
		var rune_data: Dictionary = hero.get_equipped_rune()
		var trait_data: Dictionary = DataManager.get_rune_trait(hero.equipped_rune_id)
		if trait_data.is_empty():
			continue

		var hero_container := VBoxContainer.new()
		hero_container.add_theme_constant_override("separation", 0)
		trait_vbox.add_child(hero_container)

		# 영웅 이름 + 룬 아이콘
		var hero_hbox := HBoxContainer.new()
		hero_hbox.add_theme_constant_override("separation", 4)
		hero_container.add_child(hero_hbox)

		var hero_label := Label.new()
		hero_label.text = hero.hero_name
		hero_label.add_theme_font_size_override("font_size", STYLE.font_small)
		hero_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		hero_hbox.add_child(hero_label)

		var rune_icon := Label.new()
		rune_icon.text = rune_data.get("icon", "")
		rune_icon.add_theme_font_size_override("font_size", 10)
		hero_hbox.add_child(rune_icon)

		# 특성 아이콘 + 이름
		var trait_hbox := HBoxContainer.new()
		trait_hbox.add_theme_constant_override("separation", 4)
		hero_container.add_child(trait_hbox)

		var trait_icon := Label.new()
		trait_icon.text = "  " + trait_data.get("icon", "")
		trait_icon.add_theme_font_size_override("font_size", 10)
		trait_hbox.add_child(trait_icon)

		var trait_name := Label.new()
		trait_name.text = trait_data.get("name", "")
		trait_name.add_theme_font_size_override("font_size", STYLE.font_small)
		trait_name.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		trait_name.add_theme_color_override("font_outline_color", Color.BLACK)
		trait_name.add_theme_constant_override("outline_size", 2)
		trait_hbox.add_child(trait_name)

		# 설명
		var desc_label := Label.new()
		desc_label.text = "    " + trait_data.get("description", "")
		desc_label.add_theme_font_size_override("font_size", STYLE.font_tiny)
		desc_label.add_theme_color_override("font_color", STYLE.text_dim)
		hero_container.add_child(desc_label)


func refresh_traits() -> void:
	_update_trait_display()
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

	# 전체 화면 컨테이너
	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	grudge_popup.add_child(full_screen)

	# 딤 배경
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

	# 제목
	var title := Label.new()
	title.text = "⚠ 원념 %d단계!" % danger_level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", STYLE.font_title)
	title.add_theme_color_override("font_color", STYLE.text_purple)
	vbox.add_child(title)

	# 설명
	var desc := Label.new()
	desc.text = "적이 더 강해집니다.\n계속 원념을 쌓으시겠습니까?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	# 보상 목록
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

	# 버튼
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

	# 힌트
	var hint := Label.new()
	hint.text = "[← →] 선택  [Enter] 결정"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", STYLE.font_small)
	hint.add_theme_color_override("font_color", STYLE.text_dim)
	vbox.add_child(hint)

	# 스타일 복사본 (선택 상태용)
	var go_style_selected := go_style.duplicate()
	var stop_style_selected := stop_style.duplicate()
	stop_style_selected.bg_color = Color(0.6, 0.3, 0.3)
	stop_style_selected.border_width_left = 2
	stop_style_selected.border_width_top = 2
	stop_style_selected.border_width_right = 2
	stop_style_selected.border_width_bottom = 2
	stop_style_selected.border_color = Color.WHITE

	# 입력 처리
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


#region 마을 진입 팝업
func show_town_enter_popup() -> void:
	if is_town_popup_active:
		return

	is_town_popup_active = true
	get_tree().paused = true
	town_popup.visible = true

	for child in town_popup.get_children():
		child.queue_free()

	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	town_popup.add_child(full_screen)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.7)
	full_screen.add_child(dimmer)

	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -180
	center_panel.offset_right = 180
	center_panel.offset_top = -140
	center_panel.offset_bottom = 140
	center_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := _make_flat_style(STYLE.bg_panel, Color(0.4, 0.7, 1.0), 8, 3)
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
	title.text = "🏠 마을로 돌아가시겠습니까?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", STYLE.font_large)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "받지 않은 보상이 있습니다.\n보상을 받고 마을로 들어가시겠습니까?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", STYLE.font_normal)
	desc.add_theme_color_override("font_color", STYLE.text_normal)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	var reward_title := Label.new()
	reward_title.text = "[ 누적 보상 ]"
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
	gold_lbl.add_theme_font_size_override("font_size", STYLE.font_medium)
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

	# 버튼들
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_vbox)

	var claim_style := _make_flat_style(Color(0.2, 0.5, 0.3), Color.WHITE, 4, 2)
	var claim_btn := _make_popup_button("✓ 보상을 받고 마을로", Vector2(200, 35), claim_style)
	var claim_hover := claim_style.duplicate()
	claim_hover.bg_color = Color(0.3, 0.6, 0.4)
	claim_btn.add_theme_stylebox_override("hover", claim_hover)
	claim_btn.pressed.connect(_on_town_claim_and_enter)
	btn_vbox.add_child(claim_btn)

	var skip_style := _make_flat_style(Color(0.25, 0.2, 0.2), Color.TRANSPARENT, 4)
	var skip_btn := _make_popup_button("보상 포기하고 마을로", Vector2(200, 30), skip_style)
	skip_btn.add_theme_font_size_override("font_size", STYLE.font_normal)
	skip_btn.add_theme_color_override("font_color", Color(0.7, 0.6, 0.6))
	skip_btn.pressed.connect(_on_town_skip_and_enter)
	btn_vbox.add_child(skip_btn)

	var cancel_style := _make_flat_style(Color(0.2, 0.2, 0.25), Color.TRANSPARENT, 4)
	var cancel_btn := _make_popup_button("돌아가기", Vector2(200, 28), cancel_style)
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.add_theme_color_override("font_color", STYLE.text_dim)
	cancel_btn.pressed.connect(_on_town_cancel)
	btn_vbox.add_child(cancel_btn)


func _on_town_claim_and_enter() -> void:
	is_town_popup_active = false
	town_popup.visible = false
	get_tree().paused = false
	for child in town_popup.get_children():
		child.queue_free()
	BattleManager.claim_accumulated_rewards()
	BattleManager.battle_log_received.emit("보상을 획득했다!", Color.CYAN)
	town_enter_confirmed.emit(true)


func _on_town_skip_and_enter() -> void:
	is_town_popup_active = false
	town_popup.visible = false
	get_tree().paused = false
	for child in town_popup.get_children():
		child.queue_free()
	BattleManager.reset_accumulated_rewards()
	BattleManager.battle_log_received.emit("보상을 포기했다...", Color.GRAY)
	town_enter_confirmed.emit(false)


func _on_town_cancel() -> void:
	is_town_popup_active = false
	town_popup.visible = false
	get_tree().paused = false
	for child in town_popup.get_children():
		child.queue_free()


func has_unclaimed_rewards() -> bool:
	var rewards: Dictionary = BattleManager.get_accumulated_rewards()
	return rewards.gold > 0 or rewards.items.size() > 0
#endregion
