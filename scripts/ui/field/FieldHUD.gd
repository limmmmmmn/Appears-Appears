extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## 구성:
##   TopBar     - 스테이지, 골드, 킬, 배속, 메뉴 (상단)
##   PartyCards - 파티 카드 (하단 중앙)
##   TraitPanel - 룬/특성 (우측 중앙)
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
var kill_label: Label = null

# BottomPartyCards
var bottom_party_cards: BottomPartyCards = null

# TraitPanel
@onready var trait_panel: PanelContainer = %TraitPanel
@onready var trait_vbox: VBoxContainer = %TraitVBox
#endregion


#region 내부 상태
# 팝업
var grudge_popup: CanvasLayer = null
var is_grudge_popup_active: bool = false

# 킬 카운트 영웅 추가
const KILLS_PER_HERO := 5
const AVAILABLE_HEROES := ["roland", "luna", "elena", "shadow", "aria", "gareth"]
var last_hero_kill_threshold: int = 0
#endregion


func _ready() -> void:
	add_to_group("field_hud")
	_init_topbar()
	_init_party_cards()
	_init_popups()
	_connect_signals()
	update_all()
	_update_trait_display()


#region 초기화
func _init_topbar() -> void:
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
			var current_kills: int = BattleManager.get_global_kill_count() if BattleManager else 0
			kill_label.text = "💀 %d" % current_kills


func _init_party_cards() -> void:
	var scene := preload("res://scenes/ui/BottomPartyCards.tscn")
	bottom_party_cards = scene.instantiate() as BottomPartyCards
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(bottom_party_cards)


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


func _on_kill_count_changed(count: int, _danger_level: int) -> void:
	if kill_label:
		kill_label.text = "💀 %d" % count
	var threshold := (count / KILLS_PER_HERO) * KILLS_PER_HERO
	if threshold > last_hero_kill_threshold and threshold > 0:
		last_hero_kill_threshold = threshold
		_add_random_hero()


func _add_random_hero() -> void:
	if not PartyManager:
		return
	var party: Array = PartyManager.get_party()
	if party.size() >= 4:
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
		return

	var random_id: String = available[randi() % available.size()]
	if PartyManager.add_hero_by_id(random_id):
		if bottom_party_cards:
			bottom_party_cards.update_display()


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


#region 특성 표시
func _update_trait_display() -> void:
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


