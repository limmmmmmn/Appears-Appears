extends Control
class_name PartyPanel
## 파티 초상화 패널 (좌측 상단, 세로 배치)
## HeroCard.tscn을 인스턴스하여 파티원별 초상화를 표시

const HeroCardScene := preload("res://scenes/ui/HeroCard.tscn")

signal equipment_dropped(hero_index: int, item_id: String)
signal hero_selected(hero_index: int)

@onready var cards_container: VBoxContainer = %CardsContainer

var cards: Array[HeroCard] = []
var selected_hero_index: int = -1
var selection_enabled: bool = true


func _ready() -> void:
	_connect_signals()
	call_deferred("_initial_setup")
	set_process(true)


func _process(_delta: float) -> void:
	# Will/EXP 바를 매 프레임 갱신 (Will은 전투 밖에서도 항상 충전)
	_update_realtime_bars()


func _initial_setup() -> void:
	if cards_container:
		update_display()


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
	if cards_container:
		for child in cards_container.get_children():
			cards_container.remove_child(child)
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
		cards_container.add_child(card)
		cards.append(card)
	_update_selection_visuals()


func update_display() -> void:
	var party: Array = PartyManager.get_party() if PartyManager else []

	if cards.size() != party.size():
		_rebuild_cards()

	for i in range(cards.size()):
		if i >= party.size() or party[i] == null:
			continue
		cards[i].update_from_hero(party[i])
	_update_selection_visuals()
#endregion


#region 패널 레벨 API
func init_party(heroes: Array) -> void:
	## 파티 데이터로 초기화. 각 영웅의 max_hp에 따라 바 길이 자동 계산
	cards.clear()
	if cards_container:
		for child in cards_container.get_children():
			cards_container.remove_child(child)
			child.queue_free()
	for i in range(heroes.size()):
		if heroes[i] == null:
			continue
		var card: HeroCard = HeroCardScene.instantiate()
		card.init(i)
		card.equipment_dropped.connect(_on_card_equip_dropped)
		card.field_heal_requested.connect(_on_field_heal_requested)
		card.card_selected.connect(_on_card_selected)
		cards_container.add_child(card)
		cards.append(card)
		card.update_from_hero(heroes[i])
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
#endregion


#region EXP 실시간 갱신
func _update_realtime_bars() -> void:
	## EXP 바만 경량 갱신
	var party: Array = PartyManager.get_party() if PartyManager else []
	for i in range(cards.size()):
		if i >= party.size():
			continue
		var hero: Hero = party[i]
		if hero == null:
			continue
		var card: HeroCard = cards[i]
		if not hero.is_dead:
			card.update_exp(hero.get_exp_ratio())
			card.update_level(hero.level)
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


func _on_card_accordion_toggle(hero_index: int) -> void:
	pass


func _on_card_selected(hero_index: int) -> void:
	if not selection_enabled:
		return
	if hero_index < 0:
		return
	selected_hero_index = hero_index
	_update_selection_visuals()
	hero_selected.emit(hero_index)


func _on_item_equipped(hero_name: String, item_id: String, slot: String, _replaced_id: String) -> void:
	pass
#endregion


func get_hero_slot_global_center(hero_name: String, slot: String) -> Vector2:
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
		if CooldownManager and not CooldownManager.is_skill_ready(hero.id, "heal"):
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

	if CooldownManager:
		CooldownManager.start_cooldown(healer.id, "heal")
	if SoundManager:
		SoundManager.play_heal()

	update_display()

	if BattleManager:
		BattleManager.battle_log_received.emit(
			"[필드] %s → %s HP +%d" % [healer.hero_name, target.hero_name, actual_heal],
			Color.LIGHT_GREEN
		)
#endregion
