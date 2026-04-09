extends Node
## GameManager: 전역 게임 상태 (HP/MP/골드/여정 진행).

signal party_hp_changed(current_hp: int, max_hp: int)
signal party_mp_changed(current_mp: int, max_mp: int)
signal gold_changed(amount: int)
signal game_over
signal journey_node_changed(node_index: int)
signal encounter_count_changed(count: int)

var party_hp: int = 100
var party_max_hp: int = 100
var party_mp: int = 30
var party_max_mp: int = 30
var gold: int = 0
var encounter_count: int = 0

var party_members: Array = []
var current_journey: Dictionary = {}
var current_node_index: int = 0

var is_moving: bool = true
var move_speed: float = 60.0
var _game_over_emitted: bool = false

func _ready() -> void:
	_load_default_party()

func _load_default_party() -> void:
	party_members.clear()
	var ids := ["hero", "warrior", "mage", "healer"]
	var total_hp := 0
	var total_mp := 0
	for id in ids:
		var ch: Dictionary = DataLoader.load_character(id)
		if ch.is_empty():
			continue
		party_members.append(ch)
		total_hp += int(ch.get("base_hp", 0))
		total_mp += int(ch.get("base_mp", 0))
	if total_hp > 0:
		party_max_hp = total_hp
		party_hp = total_hp
	if total_mp > 0:
		party_max_mp = total_mp
		party_mp = total_mp

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	party_hp = maxi(0, party_hp - amount)
	party_hp_changed.emit(party_hp, party_max_hp)
	if party_hp <= 0 and not _game_over_emitted:
		_game_over_emitted = true
		game_over.emit()

func heal(amount: int) -> void:
	if amount <= 0:
		return
	party_hp = mini(party_max_hp, party_hp + amount)
	party_hp_changed.emit(party_hp, party_max_hp)

func heal_full() -> void:
	party_hp = party_max_hp
	party_mp = party_max_mp
	party_hp_changed.emit(party_hp, party_max_hp)
	party_mp_changed.emit(party_mp, party_max_mp)

func use_mp(amount: int) -> bool:
	if amount <= 0:
		return true
	if party_mp < amount:
		return false
	party_mp -= amount
	party_mp_changed.emit(party_mp, party_max_mp)
	return true

func restore_mp(amount: int) -> void:
	if amount <= 0:
		return
	party_mp = mini(party_max_mp, party_mp + amount)
	party_mp_changed.emit(party_mp, party_max_mp)

func add_gold(amount: int) -> void:
	if amount == 0:
		return
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

func increment_encounter_count() -> void:
	encounter_count += 1
	encounter_count_changed.emit(encounter_count)

func start_new_journey(journey_data: Dictionary) -> void:
	current_journey = journey_data
	current_node_index = 0
	_game_over_emitted = false
	journey_node_changed.emit(current_node_index)

func advance_to_next_node() -> void:
	current_node_index += 1
	journey_node_changed.emit(current_node_index)

func get_current_node_data() -> Dictionary:
	if current_journey.is_empty():
		return {}
	var nodes: Array = current_journey.get("nodes", [])
	if current_node_index < 0 or current_node_index >= nodes.size():
		return {}
	return nodes[current_node_index]

func get_journey_nodes() -> Array:
	return current_journey.get("nodes", []) if not current_journey.is_empty() else []

func is_journey_complete() -> bool:
	var nodes := get_journey_nodes()
	return current_node_index >= nodes.size()

func toggle_movement() -> void:
	is_moving = not is_moving

func reset() -> void:
	party_hp = party_max_hp
	party_mp = party_max_mp
	gold = 0
	encounter_count = 0
	current_node_index = 0
	is_moving = true
	_game_over_emitted = false
	party_hp_changed.emit(party_hp, party_max_hp)
	party_mp_changed.emit(party_mp, party_max_mp)
	gold_changed.emit(gold)
	encounter_count_changed.emit(encounter_count)
