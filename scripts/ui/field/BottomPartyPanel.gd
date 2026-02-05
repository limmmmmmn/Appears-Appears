extends PanelContainer
class_name BottomPartyPanel
## 하단 파티 패널 - 새 레이아웃
## Face(40x40) + ATB바 + 장비 그리드(3x2)

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
	var atb_bar: ProgressBar  # ATB 바
	var equip_grid: GridContainer
	var equip_labels: Dictionary = {}  # slot_name -> Label
	var hero_index: int = -1
	var hero_id: String = ""

var slots: Array[SlotUI] = []
var main_hbox: HBoxContainer


func _ready() -> void:
	_build_ui()
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

	# ATB 바 (페이스 아래)
	slot.atb_bar = ProgressBar.new()
	slot.atb_bar.custom_minimum_size = Vector2(FACE_SIZE, 6)
	slot.atb_bar.max_value = 100.0
	slot.atb_bar.value = 0.0
	slot.atb_bar.show_percentage = false
	slot.atb_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ATB 바 스타일
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

	slot.container.add_child(slot.atb_bar)

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

	# ATB 업데이트 연결
	if ATBManager and ATBManager.has_signal("atb_updated"):
		if not ATBManager.atb_updated.is_connected(_on_atb_updated):
			ATBManager.atb_updated.connect(_on_atb_updated)

	# 자동 장착 알림 연결
	if InventoryManager and InventoryManager.has_signal("item_auto_equipped"):
		if not InventoryManager.item_auto_equipped.is_connected(_on_item_auto_equipped):
			InventoryManager.item_auto_equipped.connect(_on_item_auto_equipped)


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


func _update_equip_grid(slot: SlotUI, hero: Hero) -> void:
	for slot_name in SLOT_ORDER:
		var equip_lbl: Label = slot.equip_labels.get(slot_name)
		if not equip_lbl:
			continue

		var equip_id: String = hero.equipment.get(slot_name, "")
		if equip_id.is_empty():
			equip_lbl.text = SLOT_ICONS.get(slot_name, "?")
			equip_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
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


func _on_atb_updated() -> void:
	## ATB 업데이트 시 바 갱신
	for slot in slots:
		if slot.hero_id.is_empty() or slot.atb_bar == null:
			continue

		var atb_percent: float = ATBManager.get_hero_atb_percent(slot.hero_id)
		slot.atb_bar.value = atb_percent * 100.0

		# ATB 100% 도달 시 색상 변경 (준비 완료)
		if atb_percent >= 1.0:
			var ready_fill := StyleBoxFlat.new()
			ready_fill.bg_color = Color(1.0, 0.8, 0.2)  # 금색
			ready_fill.corner_radius_top_left = 2
			ready_fill.corner_radius_top_right = 2
			ready_fill.corner_radius_bottom_left = 2
			ready_fill.corner_radius_bottom_right = 2
			slot.atb_bar.add_theme_stylebox_override("fill", ready_fill)
		else:
			var normal_fill := StyleBoxFlat.new()
			normal_fill.bg_color = Color(0.3, 0.7, 1.0)  # 파란색
			normal_fill.corner_radius_top_left = 2
			normal_fill.corner_radius_top_right = 2
			normal_fill.corner_radius_bottom_left = 2
			normal_fill.corner_radius_bottom_right = 2
			slot.atb_bar.add_theme_stylebox_override("fill", normal_fill)


func _on_item_auto_equipped(hero_name: String, item_id: String, slot: String, replaced_id: String) -> void:
	## 아이템 자동 장착 시 알림 표시
	var item_data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = item_data.get("name", item_id)
	var rarity: String = item_data.get("rarity", "common")

	# 알림 패널 생성
	var notify := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_bottom = 2
	style.border_color = InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	notify.add_theme_stylebox_override("panel", style)

	# 내용
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	notify.add_child(vbox)

	# 영웅 이름
	var hero_label := Label.new()
	hero_label.text = hero_name
	hero_label.add_theme_font_size_override("font_size", 10)
	hero_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hero_label)

	# 아이템 이름
	var item_label := Label.new()
	item_label.text = item_name
	item_label.add_theme_font_size_override("font_size", 11)
	item_label.add_theme_color_override("font_color", InventoryManager.RARITY_COLORS.get(rarity, Color.WHITE))
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(item_label)

	# 교체 정보
	if not replaced_id.is_empty():
		var old_data: Dictionary = DataManager.get_equipment(replaced_id)
		var old_name: String = old_data.get("name", replaced_id)
		var replace_label := Label.new()
		replace_label.text = "← " + old_name
		replace_label.add_theme_font_size_override("font_size", 9)
		replace_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		replace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(replace_label)

	# 부모에 추가 (파티패널 위쪽)
	add_child(notify)
	notify.position = Vector2(0, -notify.size.y - 8)

	# 애니메이션 후 제거
	notify.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(notify, "modulate:a", 1.0, 0.15)
	tween.tween_property(notify, "position:y", notify.position.y - 10, 0.15)
	tween.tween_interval(1.5)
	tween.tween_property(notify, "modulate:a", 0.0, 0.3)
	tween.tween_callback(notify.queue_free)

	# 사운드
	if SoundManager:
		SoundManager.play_equip()
#endregion


