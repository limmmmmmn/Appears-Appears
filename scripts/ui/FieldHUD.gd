extends CanvasLayer
class_name FieldHUD
## 필드 HUD: 상단바 + 우측 패널 (미니맵, 파티, 로그)

signal menu_pressed

# 상단 바
@onready var stage_label: Label = %StageLabel
@onready var gold_label: Label = %GoldLabel
@onready var menu_button: Button = %MenuButton

# 우측 패널
@onready var minimap_panel: PanelContainer = %MinimapPanel
@onready var party_container: VBoxContainer = %PartyContainer
@onready var log_container: VBoxContainer = %LogContainer
@onready var log_scroll: ScrollContainer = %LogScroll

# 파티 슬롯 참조
var party_slots: Array[Control] = []

# 로그 설정
const MAX_LOG_LINES: int = 50
const LOG_FADE_TIME: float = 5.0


func _ready() -> void:
	_setup_party_slots()
	_connect_signals()
	update_all()


func _setup_party_slots() -> void:
	# 파티 슬롯 4개 생성
	for i in range(4):
		var slot := _create_party_slot(i)
		party_container.add_child(slot)
		party_slots.append(slot)


func _create_party_slot(index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PartySlot%d" % index
	panel.custom_minimum_size = Vector2(140, 50)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	margin.add_child(hbox)
	
	# 페이스칩
	var face := TextureRect.new()
	face.name = "Face"
	face.custom_minimum_size = Vector2(32, 32)
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hbox.add_child(face)
	
	# 정보 영역
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	# 이름
	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)
	
	# HP 바
	var hp_bar := _create_stat_bar("HP", Color(0.2, 0.8, 0.2))
	hp_bar.name = "HPBar"
	vbox.add_child(hp_bar)
	
	# MP 바
	var mp_bar := _create_stat_bar("MP", Color(0.2, 0.4, 0.9))
	mp_bar.name = "MPBar"
	vbox.add_child(mp_bar)
	
	# 초기에는 숨김
	panel.visible = false
	
	return panel


func _create_stat_bar(label_text: String, color: Color) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 20
	label.add_theme_font_size_override("font_size", 9)
	hbox.add_child(label)
	
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(60, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.show_percentage = false
	bar.value = 100
	
	# 색상 설정
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", style)
	
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("background", bg_style)
	
	hbox.add_child(bar)
	
	# 숫자 표시
	var value_label := Label.new()
	value_label.name = "ValueLabel"
	value_label.custom_minimum_size.x = 45
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 9)
	hbox.add_child(value_label)
	
	return hbox


func _connect_signals() -> void:
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	
	if GameManager:
		GameManager.gold_changed.connect(_on_gold_changed)
	
	if PartyManager:
		if PartyManager.has_signal("party_changed"):
			PartyManager.party_changed.connect(_on_party_changed)


#region 업데이트 함수
func update_all() -> void:
	update_top_bar()
	update_party_display()


func update_top_bar() -> void:
	if stage_label and FieldManager:
		stage_label.text = FieldManager.get_display_name() + ": " + FieldManager.get_current_field_name()
	
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold


func update_party_display() -> void:
	var party: Array = []
	if PartyManager:
		party = PartyManager.get_party()
	
	for i in range(4):
		if i < party.size():
			_update_party_slot(i, party[i])
			party_slots[i].visible = true
		else:
			party_slots[i].visible = false


func _update_party_slot(index: int, hero: RefCounted) -> void:
	var slot: Control = party_slots[index]
	
	# 이름
	var name_label: Label = slot.find_child("NameLabel", true, false)
	if name_label:
		name_label.text = hero.hero_name
	
	# 페이스칩
	var face: TextureRect = slot.find_child("Face", true, false)
	if face and SpriteManager:
		face.texture = SpriteManager.get_hero_face_sprite(hero.id)
	
	# HP 바
	var hp_container: HBoxContainer = slot.find_child("HPBar", true, false)
	if hp_container:
		var hp_bar: ProgressBar = hp_container.find_child("Bar", true, false)
		var hp_label: Label = hp_container.find_child("ValueLabel", true, false)
		var max_hp: int = hero.get_max_hp()
		var current_hp: int = hero.current_hp
		if hp_bar:
			hp_bar.max_value = max_hp
			hp_bar.value = current_hp
		if hp_label:
			hp_label.text = "%d/%d" % [current_hp, max_hp]
	
	# MP 바
	var mp_container: HBoxContainer = slot.find_child("MPBar", true, false)
	if mp_container:
		var mp_bar: ProgressBar = mp_container.find_child("Bar", true, false)
		var mp_label: Label = mp_container.find_child("ValueLabel", true, false)
		var max_mp: int = hero.get_max_mp()
		var current_mp: int = hero.current_mp
		if mp_bar:
			mp_bar.max_value = max_mp
			mp_bar.value = current_mp
		if mp_label:
			mp_label.text = "%d/%d" % [current_mp, max_mp]


func update_hero_hp(hero_id: String) -> void:
	## 특정 영웅 HP만 업데이트
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		if party[i].id == hero_id:
			_update_party_slot(i, party[i])
			break
#endregion


#region 로그 시스템
func add_log(message: String, color: Color = Color.WHITE) -> void:
	## 로그 메시지 추가
	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	log_container.add_child(label)
	
	# 최대 라인 수 초과 시 오래된 것 삭제
	while log_container.get_child_count() > MAX_LOG_LINES:
		var old: Node = log_container.get_child(0)
		old.queue_free()
	
	# 스크롤 맨 아래로
	await get_tree().process_frame
	if log_scroll:
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func add_battle_log(message: String) -> void:
	## 전투 로그 (흰색)
	add_log(message, Color.WHITE)


func add_damage_log(attacker: String, target: String, damage: int, is_crit: bool = false) -> void:
	## 데미지 로그
	var msg: String
	if is_crit:
		msg = "💥 %s → %s 크리티컬 %d 데미지!" % [attacker, target, damage]
		add_log(msg, Color.YELLOW)
	else:
		msg = "⚔️ %s → %s %d 데미지" % [attacker, target, damage]
		add_log(msg, Color.WHITE)


func add_heal_log(healer: String, target: String, amount: int) -> void:
	## 힐 로그
	var msg := "💚 %s → %s %d 회복" % [healer, target, amount]
	add_log(msg, Color.GREEN)


func add_defeat_log(target: String) -> void:
	## 처치 로그
	var msg := "💀 %s 쓰러졌다!" % target
	add_log(msg, Color.ORANGE_RED)


func add_exp_log(exp: int) -> void:
	## 경험치 로그
	var msg := "✨ %d EXP 획득!" % exp
	add_log(msg, Color.CYAN)


func add_gold_log(gold: int) -> void:
	## 골드 로그
	var msg := "💰 %d G 획득!" % gold
	add_log(msg, Color.GOLD)


func add_item_log(item_name: String) -> void:
	## 아이템 획득 로그
	var msg := "📦 %s 획득!" % item_name
	add_log(msg, Color.MEDIUM_PURPLE)


func add_system_log(message: String) -> void:
	## 시스템 로그 (회색)
	add_log(message, Color.GRAY)


func add_stat_description(stat_name: String, description: String) -> void:
	## 스탯 설명 로그
	var msg := "[%s] %s" % [stat_name, description]
	add_log(msg, Color.LIGHT_BLUE)


func clear_logs() -> void:
	## 로그 클리어
	for child in log_container.get_children():
		child.queue_free()
#endregion


#region 시그널 핸들러
func _on_menu_pressed() -> void:
	menu_pressed.emit()


func _on_gold_changed(_new_gold: int) -> void:
	update_top_bar()


func _on_party_changed() -> void:
	update_party_display()
#endregion
