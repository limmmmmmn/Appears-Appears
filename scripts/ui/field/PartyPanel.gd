extends Control
class_name PartyPanel
## 파티 패널 — 화면 좌측, 세로 배치
## 히어로 박스 4개를 좌측에 세로 중앙 정렬
## 하단에 HP/MP 포션 오브 인벤토리 표시

const HeroCardScene := preload("res://scenes/ui/HeroCard.tscn")

# 레이아웃 (인스펙터에서 조정 가능)
@export var card_gap: int = 3        ## 카드 사이 간격
@export var card_height: int = 60    ## 각 카드 높이
@export var panel_width: int = 160   ## 패널 가로 폭

signal equipment_dropped(hero_index: int, item_id: String)
signal hero_selected(hero_index: int)
signal hero_hovered(hero_index: int, is_hovered: bool)

var cards: Array[HeroCard] = []
var selected_hero_index: int = -1
var selection_enabled: bool = true


# === 포션 시스템 ===
# 칸 = 포션 1개, 오브 3개 모으면 칸 1개 가득 참
const POTION_SLOTS: int = 10           ## 포션 칸 수 (가로)
const ORBS_PER_SLOT: int = 3           ## 칸 1개 = 오브 3개로 충전
const MAX_HP_ORBS: int = 30            ## HP 오브 최대 (10칸 × 3)
const HP_PER_POTION: int = 30          ## 포션 1개 회복량

# 레이아웃
const POTION_SLOT_W: float = 11.0      ## 포션 칸 가로 크기
const POTION_SLOT_H: float = 11.0      ## 포션 칸 세로 크기
const POTION_SLOT_GAP: float = 1.0     ## 칸 사이 간격
const POTION_GRID_PAD: float = 4.0     ## 그리드 내부 패딩
const POTION_ROW_GAP: float = 3.0      ## (레거시 — 사용 안 함)
const POTION_GRID_TOP_GAP: float = 6.0 ## 카드 아래 ~ 포션그리드 사이 간격

# 포션 색상
const HP_FILL_COLOR := Color(0.85, 0.15, 0.15, 1.0)    ## HP 포션 내용물
const HP_BG_COLOR   := Color(0.2, 0.08, 0.08, 0.5)      ## HP 빈 칸 배경
# 오브 보유량 (오브 단위, 칸이 아님)
var hp_orb_count: int = 3    ## 현재 HP 오브 (초기 3개 = 포션 1칸 가득)

# 포션 그리드 UI 노드
var _potion_grid_panel: Control = null
var _hp_slot_bgs: Array[ColorRect] = []    ## 칸 배경 (빈 칸)
var _hp_slot_fills: Array[ColorRect] = []  ## 칸 내용물 (아래서 위로 채워짐)
var _hp_count_label: Label = null


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_connect_signals()
	call_deferred("_initial_setup")
	set_process(true)


func _process(_delta: float) -> void:
	_update_realtime_bars()
	_update_potion_button_states()


func _initial_setup() -> void:
	update_display()
	_create_potion_grid()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout_cards()
		_layout_potion_grid()


#region 시그널
func _connect_signals() -> void:
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(_on_party_changed):
			PartyManager.party_changed.connect(_on_party_changed)

	if BattleManager:
		if BattleManager.has_signal("party_hp_changed"):
			if not BattleManager.party_hp_changed.is_connected(update_display):
				BattleManager.party_hp_changed.connect(update_display)
		if BattleManager.has_signal("hero_attacked"):
			if not BattleManager.hero_attacked.is_connected(_on_hero_attacked):
				BattleManager.hero_attacked.connect(_on_hero_attacked)
		if BattleManager.has_signal("hero_damaged"):
			if not BattleManager.hero_damaged.is_connected(_on_hero_damaged):
				BattleManager.hero_damaged.connect(_on_hero_damaged)
#endregion


func _on_party_changed() -> void:
	update_display()


#region 카드 관리
func _rebuild_cards() -> void:
	cards.clear()
	# 포션 그리드는 보존
	for child in get_children():
		if child == _potion_grid_panel:
			continue
		remove_child(child)
		child.queue_free()

	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		if party[i] == null:
			continue
		var card: HeroCard = HeroCardScene.instantiate()
		card.init(i)
		card.equipment_dropped.connect(_on_card_equip_dropped)
		card.field_heal_requested.connect(_on_field_heal_requested)
		card.card_selected.connect(_on_card_selected)
		card.card_hovered.connect(_on_card_hovered)
		card.face_chip_clicked.connect(_on_face_chip_clicked)
		add_child(card)
		cards.append(card)
	_relayout_cards()
	_update_selection_visuals()


func _relayout_cards() -> void:
	## 카드를 세로 중앙 정렬 — @export 값 기반 (포션 그리드 공간 고려)
	if cards.is_empty():
		return
	var card_count: int = cards.size()
	var card_w: float = float(panel_width)
	var card_h: float = float(card_height)
	var potion_h: float = _get_potion_grid_height()
	var total_h: float = card_h * float(card_count) + float(card_gap) * float(maxi(0, card_count - 1)) + POTION_GRID_TOP_GAP + potion_h
	var panel_h: float = size.y
	if panel_h <= 0:
		var vp := get_viewport_rect().size
		panel_h = vp.y if vp.y > 0 else 540.0
	var start_y: float = floorf((panel_h - total_h) * 0.5)
	for i in range(card_count):
		var card: HeroCard = cards[i]
		var y: float = start_y + float(i) * (card_h + float(card_gap))
		card.position = Vector2(0, y)
		card.size = Vector2(card_w, card_h)
	_layout_potion_grid()


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	if cards.size() != party.size():
		_rebuild_cards()

	for i in range(cards.size()):
		if i >= party.size() or party[i] == null:
			continue
		cards[i].update_from_hero(party[i])
	_update_selection_visuals()
	_refresh_orb_visuals()
#endregion


#region 패널 레벨 API
func init_party(heroes: Array) -> void:
	cards.clear()
	for child in get_children():
		if child == _potion_grid_panel:
			continue
		remove_child(child)
		child.queue_free()
	for i in range(heroes.size()):
		if heroes[i] == null:
			continue
		var card: HeroCard = HeroCardScene.instantiate()
		card.init(i)
		card.equipment_dropped.connect(_on_card_equip_dropped)
		card.field_heal_requested.connect(_on_field_heal_requested)
		card.card_selected.connect(_on_card_selected)
		card.card_hovered.connect(_on_card_hovered)
		card.face_chip_clicked.connect(_on_face_chip_clicked)
		add_child(card)
		cards.append(card)
		card.update_from_hero(heroes[i])
	_relayout_cards()
	_update_selection_visuals()


func update_hp(index: int, current: int, max_hp: int) -> void:
	if index >= 0 and index < cards.size():
		cards[index].update_hp(current, max_hp)


func set_dead(index: int, is_dead: bool) -> void:
	if index >= 0 and index < cards.size():
		cards[index].set_dead(is_dead)


func set_portrait(index: int, texture: Texture2D) -> void:
	if index >= 0 and index < cards.size():
		cards[index].set_portrait(texture)


func shake(index: int) -> void:
	if index >= 0 and index < cards.size():
		cards[index].shake()


## 패널 폭 반환 (전투창 배치 영역 제한용)
func get_panel_width() -> float:
	return panel_width
#endregion


#region 실시간 갱신
func _update_realtime_bars() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(cards.size()):
		if i >= party.size():
			continue
		var hero: Hero = party[i]
		if hero == null:
			continue
		var card: HeroCard = cards[i]
		if not hero.is_dead:
			card.update_level(hero.level)
		card.update_hp(hero.current_hp, hero.get_max_hp())
		card.update_mp(hero)
		card.update_skill_atb_bars(hero)
#endregion


#region 애니메이션 포워딩
func _find_card_by_hero_id(p_hero_id: String) -> HeroCard:
	for card in cards:
		if card.hero_id == p_hero_id:
			return card
	return null


func _on_hero_attacked(p_hero_id: String) -> void:
	var card := _find_card_by_hero_id(p_hero_id)
	if card:
		card.play_attack_anim()


func _on_hero_damaged(p_hero_id: String) -> void:
	var card := _find_card_by_hero_id(p_hero_id)
	if card:
		card.play_damage_anim()
#endregion


#region 이벤트 포워딩
func _on_card_equip_dropped(hero_index: int, item_id: String) -> void:
	equipment_dropped.emit(hero_index, item_id)


func _on_field_heal_requested(hero_index: int) -> void:
	_try_field_heal(hero_index)


func _on_card_hovered(hero_index: int, is_hovered: bool) -> void:
	hero_hovered.emit(hero_index, is_hovered)


func _on_card_selected(hero_index: int) -> void:
	if not selection_enabled:
		return
	if hero_index < 0:
		return
	selected_hero_index = hero_index
	_update_selection_visuals()
	hero_selected.emit(hero_index)


func _on_item_equipped(_hero_name: String, _item_id: String, _slot: String, _replaced_id: String) -> void:
	pass
#endregion


func get_hero_slot_global_center(_hero_name: String, _slot: String) -> Vector2:
	return Vector2.ZERO


func _update_selection_visuals() -> void:
	if cards.is_empty():
		return
	if selected_hero_index >= cards.size():
		selected_hero_index = cards.size() - 1
	if selected_hero_index < -1:
		selected_hero_index = -1
	for i in range(cards.size()):
		cards[i].set_selected(i == selected_hero_index)


func get_selected_hero_index() -> int:
	return selected_hero_index


func set_selection_enabled(enabled: bool) -> void:
	selection_enabled = enabled
	if not enabled:
		selected_hero_index = -1
	_update_selection_visuals()


func set_selected_hero_index(index: int, emit_signal: bool = false) -> void:
	if cards.is_empty():
		selected_hero_index = -1
		return
	if index < 0:
		selected_hero_index = -1
	else:
		selected_hero_index = clampi(index, 0, cards.size() - 1)
	_update_selection_visuals()
	if emit_signal and selected_hero_index >= 0:
		hero_selected.emit(selected_hero_index)


#region 유틸
func _find_hero_by_id(p_hero_id: String) -> Hero:
	if not PartyManager:
		return null
	for h in PartyManager.get_party():
		if h != null and h.id == p_hero_id:
			return h
	return null
#endregion


#region 필드 힐
func _try_field_heal(hero_index: int) -> void:
	if BattleManager and BattleManager.get_active_battle_count() > 0:
		return

	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return

	var target: Hero = party[hero_index]
	if target == null or target.is_dead:
		return
	if target.current_hp >= target.get_max_hp():
		return

	var healer := _find_available_healer()
	if healer == null:
		return

	_execute_field_heal(healer, target)


func _find_available_healer() -> Hero:
	var party: Array = PartyManager.get_party() if PartyManager else []
	for hero in party:
		if hero == null or hero.is_dead:
			continue
		if hero.class_id != "cleric":
			continue
		# 힐 스킬 ATB 확인
		if not hero.is_skill_atb_ready("heal"):
			continue
		return hero
	return null


func _execute_field_heal(healer: Hero, target: Hero) -> void:
	var skill_data: Dictionary = DataManager.get_skill("heal")

	var base_value: int = int(skill_data.get("base_damage", 25))
	var scaling: float = skill_data.get("scaling", 1.2)
	var int_stat: int = healer.get_int()
	var heal_amount: int = int(base_value + int_stat * scaling)

	var actual_heal := target.heal(heal_amount)

	# 힐 스킬 ATB 리셋
	healer.reset_skill_atb("heal")

	if SoundManager:
		SoundManager.play_heal()

	update_display()

	if BattleManager:
		BattleManager.battle_log_received.emit(
			"[필드] %s → %s HP +%d" % [healer.hero_name, target.hero_name, actual_heal],
			Color.LIGHT_GREEN
		)
#endregion


# =====================================================================
#region 포션 오브 그리드 (파티 패널 아래)
# =====================================================================

func _get_potion_grid_height() -> float:
	return POTION_GRID_PAD * 2.0 + POTION_SLOT_H + 10.0


func _create_potion_grid() -> void:
	## 포션 그리드 생성 — 각 칸 = 배경(빈) + 내용물(아래서 위로 채워짐)
	if _potion_grid_panel != null:
		return

	_potion_grid_panel = Control.new()
	_potion_grid_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potion_grid_panel.clip_contents = false
	add_child(_potion_grid_panel)

	# HP 포션 10칸
	_hp_slot_bgs.clear()
	_hp_slot_fills.clear()
	for i in range(POTION_SLOTS):
		var bg := ColorRect.new()
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.color = HP_BG_COLOR
		_potion_grid_panel.add_child(bg)
		_hp_slot_bgs.append(bg)
		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.color = HP_FILL_COLOR
		fill.clip_contents = true
		_potion_grid_panel.add_child(fill)
		_hp_slot_fills.append(fill)

	# HP 라벨
	_hp_count_label = Label.new()
	_hp_count_label.add_theme_font_size_override("font_size", 7)
	_hp_count_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 0.9))
	_hp_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potion_grid_panel.add_child(_hp_count_label)

	_layout_potion_grid()
	_refresh_orb_visuals()


func _layout_potion_grid() -> void:
	if _potion_grid_panel == null or cards.is_empty():
		return

	var last_card: HeroCard = cards[cards.size() - 1]
	var grid_y: float = last_card.position.y + last_card.size.y + POTION_GRID_TOP_GAP
	var grid_w: float = float(panel_width)
	var grid_h: float = _get_potion_grid_height()
	_potion_grid_panel.position = Vector2(0, grid_y)
	_potion_grid_panel.size = Vector2(grid_w, grid_h)

	var total_w: float = POTION_SLOT_W * float(POTION_SLOTS) + POTION_SLOT_GAP * float(POTION_SLOTS - 1)
	var start_x: float = floorf((grid_w - total_w) * 0.5)
	var hp_row_y: float = POTION_GRID_PAD

	for i in range(POTION_SLOTS):
		var x: float = start_x + float(i) * (POTION_SLOT_W + POTION_SLOT_GAP)
		# HP
		if i < _hp_slot_bgs.size():
			_hp_slot_bgs[i].position = Vector2(x, hp_row_y)
			_hp_slot_bgs[i].size = Vector2(POTION_SLOT_W, POTION_SLOT_H)
		if i < _hp_slot_fills.size():
			_hp_slot_fills[i].position = Vector2(x, hp_row_y)
			# fill 높이는 _refresh에서 설정

	var label_y: float = hp_row_y + POTION_SLOT_H + 1.0
	if _hp_count_label:
		_hp_count_label.position = Vector2(start_x, label_y)
		_hp_count_label.size = Vector2(total_w, 10)

	_refresh_orb_visuals()


func _refresh_orb_visuals() -> void:
	## 각 포션 칸의 fill 높이를 오브 보유량에 따라 갱신
	## 칸 i의 오브 = slot_orbs (0~3), fill ratio = slot_orbs / 3
	_refresh_row(hp_orb_count, _hp_slot_bgs, _hp_slot_fills, HP_FILL_COLOR, HP_BG_COLOR)

	var hp_full_potions: int = hp_orb_count / ORBS_PER_SLOT
	if _hp_count_label:
		_hp_count_label.text = "HP ×%d" % hp_full_potions


func _refresh_row(orb_total: int, bgs: Array[ColorRect], fills: Array[ColorRect], fill_color: Color, bg_color: Color) -> void:
	for i in range(POTION_SLOTS):
		# 왼쪽부터 채움 (i=0 이 가장 왼쪽)
		var slot_orbs: int = clampi(orb_total - i * ORBS_PER_SLOT, 0, ORBS_PER_SLOT)
		var ratio: float = float(slot_orbs) / float(ORBS_PER_SLOT)

		if i < bgs.size():
			bgs[i].color = bg_color

		if i < fills.size():
			var fill: ColorRect = fills[i]
			if ratio <= 0.0:
				fill.size = Vector2(POTION_SLOT_W, 0)
				fill.visible = false
			else:
				fill.visible = true
				# 아래서 위로 채워짐 (물약 느낌)
				var fill_h: float = POTION_SLOT_H * ratio
				fill.size = Vector2(POTION_SLOT_W, fill_h)
				# position.y = 칸 상단 + 빈 부분
				var bg_pos_y: float = bgs[i].position.y if i < bgs.size() else 0.0
				fill.position.y = bg_pos_y + (POTION_SLOT_H - fill_h)
				fill.color = fill_color


func _update_potion_button_states() -> void:
	## 포션 버튼 제거됨 — 페이스칩 클릭으로 대체
	pass
#endregion


#region 포션 사용 로직
func _on_face_chip_clicked(hero_index: int) -> void:
	## 페이스칩 클릭 → HP 포션 사용
	_on_hp_potion_requested(hero_index)


func _on_hp_potion_requested(hero_index: int) -> void:
	## HP 포션 사용 (가득 찬 칸 1개 소모 → HP 30 회복)
	if hp_orb_count < ORBS_PER_SLOT:
		return
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index < 0 or hero_index >= party.size():
		return
	var hero: Hero = party[hero_index]
	if hero == null or hero.is_dead:
		return
	if hero.current_hp >= hero.get_max_hp():
		return

	# 왼쪽부터 소모: 첫 번째 꽉 찬 칸 찾기
	var consumed_slot: int = _find_first_full_slot(hp_orb_count)
	var actual: int = hero.heal(HP_PER_POTION)
	# 해당 칸의 오브만 제거 (왼쪽 칸부터)
	_consume_slot_orbs(true, consumed_slot)
	_refresh_orb_visuals()
	update_display()

	if SoundManager and SoundManager.has_method("play_heal"):
		SoundManager.play_heal()

	if BattleManager and actual > 0:
		BattleManager.battle_log_received.emit(
			"%s: HP 포션 사용! HP +%d" % [hero.hero_name, actual],
			Color(1.0, 0.6, 0.6)
		)

	_flash_potion_slot(true, consumed_slot)


func _on_mp_potion_requested(_hero_index: int) -> void:
	## MP 시스템 삭제됨 — 아무 동작 없음
	pass


func _find_first_full_slot(orb_count: int) -> int:
	## 왼쪽부터 탐색하여 가득 찬(오브 3개) 첫 번째 칸 인덱스 반환
	for i in range(POTION_SLOTS):
		var slot_orbs: int = clampi(orb_count - i * ORBS_PER_SLOT, 0, ORBS_PER_SLOT)
		if slot_orbs >= ORBS_PER_SLOT:
			return i
	return 0


func _consume_slot_orbs(is_hp: bool, slot_index: int) -> void:
	## 지정된 칸의 오브(ORBS_PER_SLOT)를 제거
	if is_hp:
		hp_orb_count = maxi(0, hp_orb_count - ORBS_PER_SLOT)


func _flash_potion_slot(is_hp: bool, slot_index: int = 0) -> void:
	## 포션 사용 시 소진된 칸 반짝 연출
	var bgs: Array[ColorRect] = _hp_slot_bgs
	var bg_color: Color = HP_BG_COLOR
	var flash_color := Color(1.0, 0.85, 0.5, 1.0)
	if slot_index >= 0 and slot_index < bgs.size():
		var target_bg: ColorRect = bgs[slot_index]
		var tw := create_tween()
		tw.tween_property(target_bg, "color", flash_color, 0.06)
		tw.tween_property(target_bg, "color", bg_color, 0.2)


## 외부에서 오브 충전 (전투 보상, 상점 등)
func add_hp_orbs(amount: int) -> void:
	hp_orb_count = mini(hp_orb_count + amount, MAX_HP_ORBS)
	_refresh_orb_visuals()


func get_hp_orb_count() -> int:
	return hp_orb_count
#endregion
