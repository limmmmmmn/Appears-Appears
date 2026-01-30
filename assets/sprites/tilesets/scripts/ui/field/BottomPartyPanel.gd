extends PanelContainer
class_name BottomPartyPanel
## 하단 중앙 파티 상태 패널
## 페이스칩 + HP바 + ATB바 가로 배치

# 슬롯 데이터 구조체
class SlotUI:
	var container: VBoxContainer
	var face: TextureRect
	var hp_bar: ProgressBar
	var atb_bar: ProgressBar
	var hero_id: String = ""

var slots: Array[SlotUI] = []


func _ready() -> void:
	_setup_slots()
	_connect_signals()
	
	# 초기 업데이트
	call_deferred("update_display")


func _setup_slots() -> void:
	## 4개 슬롯 참조 설정
	var hbox = $HBox
	
	for i in range(4):
		var slot_node = hbox.get_node_or_null("Slot%d" % i)
		if not slot_node:
			continue
		
		var slot = SlotUI.new()
		slot.container = slot_node
		slot.face = slot_node.get_node("Face")
		slot.hp_bar = slot_node.get_node("Bars/HPBar")
		slot.atb_bar = slot_node.get_node("Bars/ATBBar")
		slots.append(slot)
		
		# 초기엔 숨김
		slot.container.visible = false


func _connect_signals() -> void:
	## 시그널 연결
	if BattleManager:
		BattleManager.hero_atb_changed.connect(_on_hero_atb_changed)
		BattleManager.party_hp_changed.connect(update_display)
	
	if PartyManager and PartyManager.has_signal("party_changed"):
		PartyManager.party_changed.connect(update_display)


func update_display() -> void:
	## 파티 상태 업데이트
	var heroes: Array = PartyManager.get_party_heroes()
	
	for i in range(slots.size()):
		var slot = slots[i]
		
		if i >= heroes.size() or heroes[i] == null:
			slot.container.visible = false
			slot.hero_id = ""
			continue
		
		var hero: Hero = heroes[i]
		slot.container.visible = true
		slot.hero_id = hero.id
		
		# 페이스칩
		if SpriteManager:
			slot.face.texture = SpriteManager.get_hero_face_sprite(hero.id)
		
		# HP 바
		var max_hp = hero.get_max_hp()
		slot.hp_bar.max_value = max_hp
		slot.hp_bar.value = hero.current_hp
		_update_hp_color(slot, hero)
		
		# ATB 바
		var atb_value = BattleManager.hero_atb.get(hero.id, 0.0) if BattleManager else 0.0
		slot.atb_bar.value = atb_value * 100.0
		_update_atb_color(slot, atb_value)
		
		# 사망 시 반투명
		if hero.is_dead:
			slot.container.modulate = Color(0.5, 0.5, 0.5, 0.7)
		else:
			slot.container.modulate = Color.WHITE


func _on_hero_atb_changed(hero_id: String, value: float) -> void:
	## 특정 영웅의 ATB만 업데이트
	for slot in slots:
		if slot.hero_id == hero_id:
			slot.atb_bar.value = value * 100.0
			_update_atb_color(slot, value)
			break


func _update_hp_color(slot: SlotUI, hero: Hero) -> void:
	## HP 퍼센트에 따라 색상 변경
	var percent = float(hero.current_hp) / float(hero.get_max_hp())
	var fill_style: StyleBoxFlat = slot.hp_bar.get_theme_stylebox("fill").duplicate()
	
	if percent <= 0.25:
		fill_style.bg_color = Color(0.9, 0.2, 0.2)  # 빨강
	elif percent <= 0.5:
		fill_style.bg_color = Color(0.9, 0.7, 0.2)  # 노랑
	else:
		fill_style.bg_color = Color(0.2, 0.8, 0.2)  # 초록
	
	slot.hp_bar.add_theme_stylebox_override("fill", fill_style)


func _update_atb_color(slot: SlotUI, value: float) -> void:
	## ATB가 거의 찼을 때 색상 변경
	var fill_style: StyleBoxFlat = slot.atb_bar.get_theme_stylebox("fill").duplicate()
	
	if value >= 0.9:
		fill_style.bg_color = Color(1.0, 1.0, 0.5)  # 밝은 노랑
	elif value >= 0.7:
		fill_style.bg_color = Color(1.0, 0.9, 0.3)
	else:
		fill_style.bg_color = Color(1.0, 0.8, 0.2)  # 기본 금색
	
	slot.atb_bar.add_theme_stylebox_override("fill", fill_style)
