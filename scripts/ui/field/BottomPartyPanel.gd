extends PanelContainer
class_name BottomPartyPanel
## 하단 파티 패널 - 새 레이아웃
## Face(40x40) + MP바 + 작전 패널 + 장비 그리드(3x2)

signal tactic_changed(hero_index: int, tactic_id: String)

## 작전 정의 (드래곤퀘스트 스타일)
const TACTICS := {
	"all_out": {"name": "전력으로 싸워라", "icon": "⚔️"},
	"no_mp": {"name": "MP 사용 금지", "icon": "🚫"},
	"heal_first": {"name": "회복 우선", "icon": "💚"},
	"conserve_mp": {"name": "MP 아껴라", "icon": "💧"},
	"defend": {"name": "방어 집중", "icon": "🛡️"}
}
const TACTIC_ORDER := ["all_out", "no_mp", "heal_first", "conserve_mp", "defend"]

const FACE_SIZE := 40
const SLOT_ICONS := {"main_hand": "⚔", "off_hand": "🛡", "head": "👒", "body": "👕", "acc1": "💍", "acc2": "💍"}
const SLOT_ORDER := ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

# 색상
const HP_COLOR_HIGH := Color(0.2, 0.75, 0.2)
const HP_COLOR_MID := Color(0.9, 0.7, 0.2)
const HP_COLOR_LOW := Color(0.9, 0.2, 0.2)

# 클래스별 공격 아이콘
const CLASS_ATTACK_ICONS := {
	"warrior": "⚔️",
	"knight": "🗡️",
	"thief": "🔪",
	"archer": "🏹",
	"mage": "✨",
	"cleric": "✝️"
}

# 슬롯 데이터
class SlotUI:
	var container: VBoxContainer
	var face_container: Control
	var face: TextureRect
	var damage_overlay: ColorRect
	var hp_label: Label
	var attack_icon: Label
	var tactic_btn: Button
	var equip_grid: GridContainer
	var equip_labels: Dictionary = {}  # slot_name -> Label
	var hero_index: int = -1
	var current_tactic: String = "all_out"
	var hero_id: String = ""

var slots: Array[SlotUI] = []
var tactic_popup: PopupMenu
var active_slot_index: int = -1
var main_hbox: HBoxContainer


func _ready() -> void:
	_build_ui()
	_setup_tactic_popup()
	_connect_signals()
	update_display()


func _build_ui() -> void:
	# 기존 자식 제거
	for child in get_children():
		child.queue_free()

	main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 6)
	add_child(main_hbox)

	# 4명의 파티원 슬롯 생성
	for i in range(4):
		var slot := _create_slot(i)
		slots.append(slot)
		main_hbox.add_child(slot.container)


func _create_slot(index: int) -> SlotUI:
	var slot := SlotUI.new()
	slot.hero_index = index

	# 메인 컨테이너
	slot.container = VBoxContainer.new()
	slot.container.add_theme_constant_override("separation", 2)
	slot.container.visible = false

	# 페이스 컨테이너 (40x40)
	slot.face_container = Control.new()
	slot.face_container.custom_minimum_size = Vector2(FACE_SIZE, FACE_SIZE)
	slot.face_container.clip_contents = false  # 아이콘이 위로 나올 수 있도록
	slot.container.add_child(slot.face_container)

	# 페이스 이미지
	slot.face = TextureRect.new()
	slot.face.custom_minimum_size = Vector2(FACE_SIZE, FACE_SIZE)
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

	# 공격 아이콘 (페이스 위에 표시)
	slot.attack_icon = Label.new()
	slot.attack_icon.text = "⚔️"
	slot.attack_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.attack_icon.add_theme_font_size_override("font_size", 14)
	slot.attack_icon.position = Vector2(FACE_SIZE / 2 - 8, -20)
	slot.attack_icon.z_index = 10
	slot.attack_icon.visible = false
	slot.attack_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.face_container.add_child(slot.attack_icon)

	# 작전 버튼 (페이스 폭과 동일)
	slot.tactic_btn = Button.new()
	slot.tactic_btn.custom_minimum_size = Vector2(FACE_SIZE, 16)
	slot.tactic_btn.add_theme_font_size_override("font_size", 7)
	slot.tactic_btn.clip_text = true
	slot.tactic_btn.text = "전력"
	var tactic_style := StyleBoxFlat.new()
	tactic_style.bg_color = Color(0.15, 0.15, 0.2)
	tactic_style.border_width_bottom = 1
	tactic_style.border_color = Color(0.3, 0.3, 0.4)
	slot.tactic_btn.add_theme_stylebox_override("normal", tactic_style)
	slot.tactic_btn.pressed.connect(_on_tactic_btn_pressed.bind(index))
	slot.container.add_child(slot.tactic_btn)

	# 장비 그리드 (3x2)
	slot.equip_grid = GridContainer.new()
	slot.equip_grid.columns = 3
	slot.equip_grid.add_theme_constant_override("h_separation", 1)
	slot.equip_grid.add_theme_constant_override("v_separation", 1)
	slot.container.add_child(slot.equip_grid)

	# 6개의 장비 슬롯 생성
	for slot_name in SLOT_ORDER:
		var equip_lbl := Label.new()
		equip_lbl.custom_minimum_size = Vector2(13, 12)
		equip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		equip_lbl.add_theme_font_size_override("font_size", 9)
		equip_lbl.text = SLOT_ICONS.get(slot_name, "?")
		equip_lbl.tooltip_text = _get_slot_display_name(slot_name)
		equip_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		slot.equip_grid.add_child(equip_lbl)
		slot.equip_labels[slot_name] = equip_lbl

	return slot


func _get_slot_display_name(slot_name: String) -> String:
	match slot_name:
		"main_hand": return "주무기"
		"off_hand": return "보조"
		"head": return "머리"
		"body": return "몸통"
		"acc1": return "악세1"
		"acc2": return "악세2"
	return slot_name


func _setup_tactic_popup() -> void:
	tactic_popup = PopupMenu.new()
	add_child(tactic_popup)

	for tactic_id in TACTIC_ORDER:
		var tactic: Dictionary = TACTICS[tactic_id]
		tactic_popup.add_item("%s %s" % [tactic.icon, tactic.name])
		tactic_popup.set_item_metadata(tactic_popup.item_count - 1, tactic_id)

	tactic_popup.id_pressed.connect(_on_tactic_selected)


func _connect_signals() -> void:
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(update_display):
			PartyManager.party_changed.connect(update_display)

	if BattleManager:
		if BattleManager.has_signal("party_hp_changed"):
			if not BattleManager.party_hp_changed.is_connected(_on_party_hp_changed):
				BattleManager.party_hp_changed.connect(_on_party_hp_changed)
		if BattleManager.has_signal("hero_attacked"):
			if not BattleManager.hero_attacked.is_connected(_on_hero_attacked):
				BattleManager.hero_attacked.connect(_on_hero_attacked)


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(slots.size()):
		var slot := slots[i]

		if i < party.size() and party[i] != null:
			var hero: Hero = party[i]
			slot.container.visible = true
			slot.hero_id = hero.id

			# 페이스 업데이트
			if SpriteManager and slot.face:
				slot.face.texture = SpriteManager.get_hero_face_sprite(hero.id)

			# 공격 아이콘 설정
			slot.attack_icon.text = CLASS_ATTACK_ICONS.get(hero.class_id, "⚔️")

			# HP 오버레이 업데이트
			var max_hp := hero.get_max_hp()
			var hp_percent: float = float(hero.current_hp) / float(max_hp) if max_hp > 0 else 1.0
			_update_damage_overlay(slot, hp_percent)
			_update_hp_label(slot, hero.current_hp, max_hp)

			# 작전 버튼 업데이트
			_update_tactic_button(slot)

			# 장비 그리드 업데이트
			_update_equip_grid(slot, hero)
		else:
			slot.container.visible = false


func _update_damage_overlay(slot: SlotUI, hp_percent: float) -> void:
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


func _update_hp_label(slot: SlotUI, current_hp: int, max_hp: int) -> void:
	if not slot.hp_label:
		return

	slot.hp_label.text = "%d/%d" % [current_hp, max_hp]

	var hp_percent: float = float(current_hp) / float(max_hp) if max_hp > 0 else 1.0
	if hp_percent <= 0.25:
		slot.hp_label.add_theme_color_override("font_color", HP_COLOR_LOW)
	elif hp_percent <= 0.5:
		slot.hp_label.add_theme_color_override("font_color", HP_COLOR_MID)
	else:
		slot.hp_label.add_theme_color_override("font_color", Color.WHITE)


func _update_tactic_button(slot: SlotUI) -> void:
	if not slot.tactic_btn:
		return

	var tactic_data: Dictionary = TACTICS.get(slot.current_tactic, TACTICS["all_out"])
	# 짧은 이름으로 표시
	var short_name: String = tactic_data.name
	if short_name.length() > 4:
		short_name = short_name.substr(0, 4)
	slot.tactic_btn.text = short_name
	slot.tactic_btn.tooltip_text = tactic_data.name


func _update_equip_grid(slot: SlotUI, hero: Hero) -> void:
	for slot_name in SLOT_ORDER:
		var equip_lbl: Label = slot.equip_labels.get(slot_name)
		if not equip_lbl:
			continue

		var equip_id: String = hero.equipment.get(slot_name, "")
		if equip_id.is_empty():
			equip_lbl.text = SLOT_ICONS.get(slot_name, "?")
			equip_lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
			equip_lbl.tooltip_text = _get_slot_display_name(slot_name) + " (비어있음)"
		else:
			var equip_data: Dictionary = DataManager.get_equipment(equip_id)
			equip_lbl.text = SLOT_ICONS.get(slot_name, "?")
			var rarity: String = equip_data.get("rarity", "common")
			equip_lbl.add_theme_color_override("font_color", _get_rarity_color(rarity))
			equip_lbl.tooltip_text = equip_data.get("name", equip_id)


func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.7, 0.7, 0.7)
		"uncommon": return Color(0.4, 0.8, 0.4)
		"magic": return Color(0.4, 0.6, 1.0)
		"rare": return Color(0.8, 0.6, 1.0)
		"epic": return Color(1.0, 0.5, 0.2)
		"legendary": return Color(1.0, 0.8, 0.2)
	return Color.WHITE


func _on_tactic_btn_pressed(hero_index: int) -> void:
	if hero_index < 0 or hero_index >= slots.size():
		return

	active_slot_index = hero_index
	var slot := slots[hero_index]

	# 현재 선택된 작전 체크
	for i in range(tactic_popup.item_count):
		var item_tactic: String = tactic_popup.get_item_metadata(i)
		tactic_popup.set_item_checked(i, item_tactic == slot.current_tactic)

	# 팝업 위치
	var btn_pos := slot.tactic_btn.global_position
	tactic_popup.position = Vector2i(int(btn_pos.x), int(btn_pos.y - tactic_popup.size.y - 4))
	tactic_popup.popup()


func _on_tactic_selected(index: int) -> void:
	if active_slot_index < 0 or active_slot_index >= slots.size():
		return

	var tactic_id: String = tactic_popup.get_item_metadata(index)
	var slot := slots[active_slot_index]
	slot.current_tactic = tactic_id

	_update_tactic_button(slot)

	if SoundManager != null:
		SoundManager.play_select()

	tactic_changed.emit(active_slot_index, tactic_id)
	active_slot_index = -1


func get_hero_tactic(hero_index: int) -> String:
	if hero_index >= 0 and hero_index < slots.size():
		return slots[hero_index].current_tactic
	return "all_out"


func set_hero_tactic(hero_index: int, tactic_id: String) -> void:
	if hero_index >= 0 and hero_index < slots.size():
		if TACTICS.has(tactic_id):
			slots[hero_index].current_tactic = tactic_id
			_update_tactic_button(slots[hero_index])


func get_tactic_data(tactic_id: String) -> Dictionary:
	return TACTICS.get(tactic_id, TACTICS["all_out"])


#region 전투 이펙트
var _prev_hp: Dictionary = {}  # hero_id -> prev_hp

func _on_party_hp_changed() -> void:
	## HP 변경 감지하여 피격 시 반짝임
	var party: Array = PartyManager.get_party() if PartyManager else []

	for i in range(slots.size()):
		if i >= party.size() or party[i] == null:
			continue

		var hero: Hero = party[i]
		var prev: int = _prev_hp.get(hero.id, hero.current_hp)

		# HP 감소 = 피격
		if hero.current_hp < prev:
			_play_hit_flash(slots[i])

		_prev_hp[hero.id] = hero.current_hp

	update_display()


func _on_hero_attacked(hero_id: String) -> void:
	## 영웅 공격 시 아이콘 표시
	for slot in slots:
		if slot.hero_id == hero_id:
			_play_attack_icon(slot)
			break


func _play_attack_icon(slot: SlotUI) -> void:
	## 공격 아이콘 살짝 떠오르는 애니메이션
	if not slot.attack_icon:
		return

	slot.attack_icon.visible = true
	slot.attack_icon.modulate = Color.WHITE
	slot.attack_icon.position.y = -16

	var tween := create_tween()
	tween.tween_property(slot.attack_icon, "position:y", -26, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(slot.attack_icon, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): slot.attack_icon.visible = false)


func _play_hit_flash(slot: SlotUI) -> void:
	## 피격 시 페이스 반짝임
	if not slot.face:
		return

	var tween := create_tween()
	tween.tween_property(slot.face, "modulate", Color(1.0, 0.3, 0.3), 0.05)
	tween.tween_property(slot.face, "modulate", Color.WHITE, 0.1)
	tween.tween_property(slot.face, "modulate", Color(1.0, 0.5, 0.5), 0.05)
	tween.tween_property(slot.face, "modulate", Color.WHITE, 0.1)
#endregion


