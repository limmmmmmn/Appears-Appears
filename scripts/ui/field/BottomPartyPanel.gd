extends PanelContainer
## 하단 중앙 파티 상태 패널
## 페이스칩 + HP바 + ATB바 가로 배치
## 페이스칩 이펙트: ATB 금테두리, HP 낮으면 빨간 깜빡임, 공격시 튀어오름

# 슬롯 데이터 구조체
class SlotUI:
	var container: VBoxContainer
	var face: TextureRect
	var hp_bar: ProgressBar
	var atb_bar: ProgressBar
	var hero_id: String = ""
	# 이펙트용
	var glow_panel: Panel = null
	var base_position: Vector2 = Vector2.ZERO
	var is_low_hp: bool = false

var slots: Array[SlotUI] = []

# 이펙트 설정
const GLOW_COLOR_ATB = Color(1.0, 0.85, 0.2, 0.9)  # 금색
const GLOW_COLOR_READY = Color(1.0, 1.0, 0.5, 1.0)  # 밝은 금색 (ATB 풀)
const GLOW_COLOR_LOW_HP = Color(1.0, 0.2, 0.2, 0.8)  # 빨간색
const LOW_HP_THRESHOLD = 0.3  # 30% 이하면 위험

var _blink_time: float = 0.0


func _ready() -> void:
	_setup_slots()
	_connect_signals()
	set_process(true)
	
	# 초기 업데이트
	call_deferred("update_display")


func _process(delta: float) -> void:
	_blink_time += delta * 4.0  # 깜빡임 속도
	_update_low_hp_blink()


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
		slot.base_position = slot.face.position
		
		# Glow 패널 생성 (페이스칩 뒤에)
		_create_glow_panel(slot)
		
		slots.append(slot)
		
		# 초기엔 숨김
		slot.container.visible = false


func _create_glow_panel(slot: SlotUI) -> void:
	## 페이스칩 주변 glow 효과용 패널
	var glow = Panel.new()
	glow.custom_minimum_size = Vector2(38, 38)  # 페이스보다 약간 큼
	glow.position = Vector2(-3, -3)  # 페이스 뒤로
	glow.z_index = -1
	glow.visible = false
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)  # 투명 배경
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = GLOW_COLOR_ATB
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.shadow_color = GLOW_COLOR_ATB
	style.shadow_size = 3
	glow.add_theme_stylebox_override("panel", style)
	
	# Face의 부모에 추가
	slot.face.get_parent().add_child(glow)
	slot.face.get_parent().move_child(glow, 0)  # 맨 뒤로
	slot.glow_panel = glow


func _connect_signals() -> void:
	## 시그널 연결
	if BattleManager:
		BattleManager.hero_atb_changed.connect(_on_hero_atb_changed)
		BattleManager.party_hp_changed.connect(update_display)
		# 공격 시그널 연결 (영웅이 공격할 때)
		if BattleManager.has_signal("hero_attacked"):
			BattleManager.hero_attacked.connect(_on_hero_attacked)
	
	if PartyManager and PartyManager.has_signal("party_changed"):
		PartyManager.party_changed.connect(update_display)


func update_display() -> void:
	## 파티 상태 업데이트
	var heroes: Array = PartyManager.get_party()
	
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
		
		# HP 낮음 체크
		var hp_percent = float(hero.current_hp) / float(max_hp)
		slot.is_low_hp = hp_percent <= LOW_HP_THRESHOLD and not hero.is_dead
		
		# ATB 바
		var atb_value = BattleManager.hero_atb.get(hero.id, 0.0) if BattleManager else 0.0
		slot.atb_bar.value = atb_value * 100.0
		_update_atb_color(slot, atb_value)
		_update_glow(slot, atb_value)
		
		# 사망 시 반투명
		if hero.is_dead:
			slot.container.modulate = Color(0.5, 0.5, 0.5, 0.7)
			slot.glow_panel.visible = false
		else:
			slot.container.modulate = Color.WHITE


func _on_hero_atb_changed(hero_id: String, value: float) -> void:
	## 특정 영웅의 ATB만 업데이트
	for slot in slots:
		if slot.hero_id == hero_id:
			slot.atb_bar.value = value * 100.0
			_update_atb_color(slot, value)
			_update_glow(slot, value)
			break


func _on_hero_attacked(hero_id: String) -> void:
	## 영웅 공격 시 튀어오름 애니메이션
	for slot in slots:
		if slot.hero_id == hero_id:
			_do_attack_bounce(slot)
			break


func _do_attack_bounce(slot: SlotUI) -> void:
	## 페이스칩 튀어오름 애니메이션
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	
	# 위로 튀어오름
	tween.tween_property(slot.face, "position:y", slot.base_position.y - 6, 0.08)
	# 제자리로
	tween.tween_property(slot.face, "position:y", slot.base_position.y, 0.12)


func _update_glow(slot: SlotUI, atb_value: float) -> void:
	## ATB에 따른 glow 효과
	if not slot.glow_panel:
		return
	
	# ATB 70% 이상이면 glow 표시
	if atb_value >= 0.7:
		slot.glow_panel.visible = true
		var style: StyleBoxFlat = slot.glow_panel.get_theme_stylebox("panel").duplicate()
		
		# ATB 풀이면 더 밝게
		if atb_value >= 0.95:
			style.border_color = GLOW_COLOR_READY
			style.shadow_color = GLOW_COLOR_READY
			style.shadow_size = 5
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
		else:
			# 70~95%: 점점 밝아짐
			var intensity = (atb_value - 0.7) / 0.25  # 0~1
			var color = GLOW_COLOR_ATB
			color.a = 0.5 + intensity * 0.4
			style.border_color = color
			style.shadow_color = color
			style.shadow_size = 2 + int(intensity * 2)
		
		slot.glow_panel.add_theme_stylebox_override("panel", style)
	elif not slot.is_low_hp:
		slot.glow_panel.visible = false


func _update_low_hp_blink() -> void:
	## HP 낮은 슬롯 빨간 테두리 깜빡임
	var blink_alpha = (sin(_blink_time) + 1.0) / 2.0  # 0~1 사이클
	
	for slot in slots:
		if slot.is_low_hp and slot.glow_panel:
			slot.glow_panel.visible = true
			var style: StyleBoxFlat = slot.glow_panel.get_theme_stylebox("panel").duplicate()
			
			var color = GLOW_COLOR_LOW_HP
			color.a = 0.4 + blink_alpha * 0.5
			style.border_color = color
			style.shadow_color = color
			style.shadow_size = 2 + int(blink_alpha * 3)
			
			slot.glow_panel.add_theme_stylebox_override("panel", style)


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


func trigger_attack_effect(hero_id: String) -> void:
	## 외부에서 공격 이펙트 트리거 (BattleManager에서 호출)
	_on_hero_attacked(hero_id)
