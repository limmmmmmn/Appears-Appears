extends Control
class_name HeroCard
## 개별 영웅 카드 (씬 인스턴스 방식)
## HeroCard.tscn과 1:1 대응
## 루트=Control(레이아웃용), Panel=PanelContainer(애니메이션 대상)
## [이름 HP 값] + 장비 슬롯 8개 (1열)

const SLOT_ICONS := {
	"main_hand": "⚔", "off_hand": "🛡", "head": "👒",
	"body": "👕", "shoes": "👟", "necklace": "📿", "ring1": "💍", "ring2": "💍",
}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "shoes", "necklace", "ring1", "ring2"]

const HP_COLOR_HIGH := Color(0.25, 0.78, 0.25)
const HP_COLOR_MID  := Color(0.92, 0.72, 0.2)
const HP_COLOR_LOW  := Color(0.92, 0.22, 0.22)

signal equipment_dropped(hero_index: int, item_id: String)
signal field_heal_requested(hero_index: int)

@onready var panel: PanelContainer = %Panel
@onready var name_label: Label = %NameLabel
@onready var skill_label: Label = %SkillLabel
@onready var equip_section: VBoxContainer = %EquipSection

var hero_index: int = -1
var hero_id: String = ""
var is_hovered: bool = false
var equip_rows: Dictionary = {}  # slot_name -> { row: _EquipSlotRow, icon: Label, name: Label }

var _anim_tween: Tween = null
var _stat_popup: PanelContainer = null


func _ready() -> void:
	panel.mouse_entered.connect(_on_mouse_entered)
	panel.mouse_exited.connect(_on_mouse_exited)
	panel.gui_input.connect(_on_gui_input)
	_build_equip_slots()


#region 초기화
func init(p_hero_index: int) -> void:
	hero_index = p_hero_index


func _build_equip_slots() -> void:
	for slot_name in SLOT_ORDER:
		var row := _EquipSlotRow.new()
		row.setup(self, hero_index, slot_name)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 2)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hbox)

		var icon_lbl := Label.new()
		icon_lbl.text = SLOT_ICONS.get(slot_name, "?")
		icon_lbl.add_theme_font_size_override("font_size", 8)
		icon_lbl.add_theme_color_override("font_color", FieldHUD.STYLE.text_dim)
		icon_lbl.custom_minimum_size.x = 12
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon_lbl)

		var name_lbl := Label.new()
		name_lbl.text = "-"
		name_lbl.add_theme_font_size_override("font_size", 8)
		name_lbl.add_theme_color_override("font_color", FieldHUD.STYLE.text_dim)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(name_lbl)

		row.icon_label = icon_lbl
		row.name_label = name_lbl

		equip_section.add_child(row)
		equip_rows[slot_name] = {"row": row, "icon": icon_lbl, "name": name_lbl}
#endregion


#region 호버
func _on_mouse_entered() -> void:
	is_hovered = true
	_kill_anim()

func _on_mouse_exited() -> void:
	is_hovered = false
#endregion


#region 데이터 갱신
func update_from_hero(hero: Hero) -> void:
	if hero == null:
		return
	hero_id = hero.id
	_update_name_hp(hero)
	_update_skill_info(hero)
	_update_equips(hero)


func _update_name_hp(hero: Hero) -> void:
	var hp: int = hero.current_hp
	name_label.text = "%s HP %d" % [hero.hero_name, hp]

	var max_hp := hero.get_max_hp()
	var pct: float = float(hp) / float(max_hp) if max_hp > 0 else 1.0
	var color: Color
	if pct <= 0.25:
		color = HP_COLOR_LOW
	elif pct <= 0.5:
		color = HP_COLOR_MID
	else:
		color = HP_COLOR_HIGH
	name_label.add_theme_color_override("font_color", color)


func _update_skill_info(hero: Hero) -> void:
	var class_name_str: String = hero.hero_class_name
	var skills: Array = hero.get_available_skills()
	var skill_names: Array = []
	for skill_id in skills:
		if skill_id == "basic_attack":
			continue
		var sdata: Dictionary = DataManager.get_skill(skill_id)
		var sname: String = sdata.get("name", skill_id)
		skill_names.append(sname)
	if skill_names.is_empty():
		skill_label.text = class_name_str
	else:
		skill_label.text = "%s %s" % [class_name_str, " ".join(skill_names)]


func _update_equips(hero: Hero) -> void:
	for slot_name in SLOT_ORDER:
		var rd: Dictionary = equip_rows.get(slot_name, {})
		if rd.is_empty():
			continue
		var row: _EquipSlotRow = rd.get("row")
		var icon_lbl: Label = rd.get("icon")
		var name_lbl: Label = rd.get("name")

		var equip_id: String = hero.equipment.get(slot_name, "")
		if row:
			row.item_id = equip_id
			row.hero_index = hero_index

		if equip_id.is_empty():
			icon_lbl.add_theme_color_override("font_color", FieldHUD.STYLE.text_dim)
			name_lbl.text = "-"
			name_lbl.add_theme_color_override("font_color", FieldHUD.STYLE.text_dim)
		else:
			var edata: Dictionary = DataManager.get_equipment(equip_id)
			var rarity: String = edata.get("rarity", "common")
			var rcolor: Color = _get_rarity_color(rarity)
			icon_lbl.add_theme_color_override("font_color", rcolor)
			name_lbl.text = edata.get("name", equip_id)
			name_lbl.add_theme_color_override("font_color", rcolor)


func update_atb(_hero: Hero) -> void:
	pass
#endregion


#region 애니메이션 (panel의 position을 조작 - 레이아웃과 충돌 없음)
func _kill_anim() -> void:
	if _anim_tween and _anim_tween.is_valid():
		_anim_tween.kill()
		_anim_tween = null
	if panel:
		panel.position = Vector2.ZERO


func play_attack_anim() -> void:
	if is_hovered or not panel:
		return
	_kill_anim()
	_anim_tween = create_tween()
	_anim_tween.tween_property(panel, "position:y", -15.0, 0.1).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(panel, "position:y", 0.0, 0.15).set_ease(Tween.EASE_IN)


func play_damage_anim() -> void:
	if is_hovered or not panel:
		return
	_kill_anim()
	_anim_tween = create_tween()
	_anim_tween.tween_property(panel, "position:x", 4.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", -4.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", 3.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", -3.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", 2.0, 0.03)
	_anim_tween.tween_property(panel, "position:x", 0.0, 0.03)
#endregion


#region 필드 힐 (클릭)
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			field_heal_requested.emit(hero_index)
#endregion


#region 능력치 비교 팝업
func show_stat_compare(item_id: String) -> void:
	hide_stat_compare()
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
		return
	var hero: Hero = party[hero_index]
	if not hero.can_equip(item_id):
		return

	var changes: Dictionary = StatCompareUtil.calculate_stat_changes(hero, item_id)
	if changes.is_empty():
		return

	# 변화가 있는 스탯만 필터
	var has_diff := false
	for stat_name in changes:
		if changes[stat_name]["diff"] != 0:
			has_diff = true
			break
	if not has_diff:
		return

	_stat_popup = PanelContainer.new()
	var style := FieldHUD._make_flat_style(
		Color(0.05, 0.05, 0.08, 0.95), Color(0.4, 0.6, 0.9, 0.8), 4, 1
	)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_stat_popup.add_theme_stylebox_override("panel", style)
	_stat_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stat_popup.add_child(vbox)

	for stat_name in changes:
		var data: Dictionary = changes[stat_name]
		var diff: int = data["diff"]
		if diff == 0:
			continue
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 8)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if diff > 0:
			lbl.text = "%s +%d" % [stat_name, diff]
			lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
		else:
			lbl.text = "%s %d" % [stat_name, diff]
			lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		vbox.add_child(lbl)

	add_child(_stat_popup)
	_stat_popup.reset_size()
	var popup_h: float = _stat_popup.get_combined_minimum_size().y
	_stat_popup.position = Vector2(0, -popup_h - 2)


func hide_stat_compare() -> void:
	if _stat_popup and is_instance_valid(_stat_popup):
		_stat_popup.queue_free()
		_stat_popup = null
#endregion


#region 장비 드롭 처리
func handle_equipment_drop(target_slot: String, item_id: String, data: Dictionary) -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
		return
	var hero: Hero = party[hero_index]
	if not hero.can_equip(item_id):
		return

	var source: String = data.get("source", "inventory")

	if source == "equipment":
		# 영웅 → 영웅 장비 이동
		var src_hero_idx: int = data.get("hero_index", -1)
		var src_slot: String = data.get("source_slot", "")
		if src_hero_idx < 0 or src_slot.is_empty():
			return
		if src_hero_idx >= party.size() or party[src_hero_idx] == null:
			return
		var src_hero: Hero = party[src_hero_idx]
		# 같은 영웅, 같은 슬롯이면 무시
		if src_hero_idx == hero_index and src_slot == target_slot:
			return
		# 현재 타겟 슬롯의 장비
		var old_target: String = hero.equipment.get(target_slot, "")
		# 소스에서 해제
		src_hero.unequip_slot(src_slot)
		# 타겟에 기존 장비 있으면 소스로 이동
		if not old_target.is_empty():
			src_hero.equip_item(old_target, src_slot)
		# 새 장비 타겟에 장착
		hero.equip_item(item_id, target_slot)
		PartyManager.party_changed.emit()
	else:
		# 인벤토리 → 영웅 장비 장착
		if not InventoryManager:
			return
		InventoryManager.equip_item(hero, item_id, target_slot)

	equipment_dropped.emit(hero_index, item_id)
#endregion


#region UI 팩토리
static func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.7, 0.7, 0.7)
		"uncommon": return Color(0.4, 0.8, 0.4)
		"magic": return Color(0.4, 0.6, 1.0)
		"rare": return Color(0.8, 0.6, 1.0)
		"epic": return Color(1.0, 0.5, 0.2)
		"legendary": return Color(1.0, 0.8, 0.2)
	return Color.WHITE
#endregion


#region 슬롯 하이라이트
func highlight_slot(p_slot_name: String, equip_id: String = "") -> void:
	if not equip_id.is_empty():
		var party: Array = PartyManager.get_party() if PartyManager else []
		if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
			return
		if not party[hero_index].can_equip(equip_id):
			return
	var rd: Dictionary = equip_rows.get(p_slot_name, {})
	if rd.is_empty():
		return
	var row: _EquipSlotRow = rd.get("row")
	if row:
		row.set_ext_highlight(true)


func clear_slot_highlights() -> void:
	for sn in equip_rows:
		var rd: Dictionary = equip_rows[sn]
		var row: _EquipSlotRow = rd.get("row")
		if row:
			row.set_ext_highlight(false)


static func get_target_slots(item_slot: String) -> Array:
	if item_slot in ["ring", "ring1", "ring2"]:
		return ["ring1", "ring2"]
	return [item_slot]
#endregion


#region 장비 슬롯 드래그앤드롭
class _EquipSlotRow extends PanelContainer:
	var card_ref: HeroCard
	var hero_index: int = -1
	var slot_name: String = ""
	var item_id: String = ""
	var icon_label: Label
	var name_label: Label
	var _normal_style: StyleBoxFlat
	var _hover_style: StyleBoxFlat
	var _self_hovered: bool = false
	var _ext_highlighted: bool = false

	func setup(p_card: HeroCard, p_idx: int, p_slot: String) -> void:
		card_ref = p_card
		hero_index = p_idx
		slot_name = p_slot
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, 14)

		_normal_style = FieldHUD._make_flat_style(
			Color(0.06, 0.06, 0.08, 0.0), Color(0.22, 0.22, 0.28, 0.5), 2, 1
		)
		_normal_style.content_margin_left = 2
		_normal_style.content_margin_right = 2
		add_theme_stylebox_override("panel", _normal_style)

		_hover_style = FieldHUD._make_flat_style(
			FieldHUD.STYLE.bg_btn_hover, Color(1.0, 0.95, 0.3, 1.0), 2, 2
		)
		_hover_style.content_margin_left = 2
		_hover_style.content_margin_right = 2

		mouse_entered.connect(_on_row_mouse_entered)
		mouse_exited.connect(_on_row_mouse_exited)

	func set_ext_highlight(on: bool) -> void:
		_ext_highlighted = on
		_update_style()

	func _on_row_mouse_entered() -> void:
		_self_hovered = true
		_update_style()
		if not item_id.is_empty():
			_highlight_siblings(true)

	func _on_row_mouse_exited() -> void:
		_self_hovered = false
		_update_style()
		if not item_id.is_empty():
			_highlight_siblings(false)

	func _update_style() -> void:
		if _self_hovered or _ext_highlighted:
			add_theme_stylebox_override("panel", _hover_style)
		else:
			add_theme_stylebox_override("panel", _normal_style)

	func _highlight_siblings(on: bool) -> void:
		if not card_ref:
			return
		var container = card_ref.get_parent()
		if not container:
			return
		for child in container.get_children():
			if child is HeroCard and child != card_ref:
				if on:
					child.highlight_slot(slot_name, item_id)
					child.show_stat_compare(item_id)
				else:
					child.clear_slot_highlights()
					child.hide_stat_compare()

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		if not data is Dictionary or data.get("type", "") != "equipment":
			return false
		var iid: String = data.get("item_id", "")
		if iid.is_empty():
			return false
		var party: Array = PartyManager.get_party() if PartyManager else []
		if hero_index < 0 or hero_index >= party.size() or party[hero_index] == null:
			return false
		var hero: Hero = party[hero_index]
		if not hero.can_equip(iid):
			return false
		var edata: Dictionary = DataManager.get_equipment(iid)
		var eslot: String = edata.get("slot", "")
		if eslot.is_empty():
			return false
		if eslot in ["ring", "ring1", "ring2"]:
			return slot_name in ["ring1", "ring2"]
		return eslot == slot_name

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		if data is Dictionary and card_ref:
			var iid: String = data.get("item_id", "")
			if not iid.is_empty():
				card_ref.handle_equipment_drop(slot_name, iid, data)

	func _get_drag_data(_pos: Vector2) -> Variant:
		if item_id.is_empty():
			return null
		var preview := Label.new()
		preview.text = "%s %s" % [SLOT_ICONS.get(slot_name, "?"), name_label.text]
		preview.add_theme_font_size_override("font_size", 9)
		preview.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
		preview.add_theme_color_override("font_outline_color", Color.BLACK)
		preview.add_theme_constant_override("outline_size", 2)
		set_drag_preview(preview)
		return {
			"type": "equipment", "item_id": item_id,
			"source": "equipment", "hero_index": hero_index,
			"source_slot": slot_name,
		}
#endregion
