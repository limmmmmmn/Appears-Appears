extends Node

## Lightweight prototype telemetry. Listens to game signals and prints a
## run-end summary to the console; no gameplay code needs to know the details.

var _run_number: int = 0
var _run_ended: bool = false
var _field_loops_completed: int = 0
var _enemies_killed: int = 0
var _total_damage_taken: int = 0
var _card_order: Array[StringName] = []
var _card_counts: Dictionary = {}  ## StringName -> int
var _card_names: Dictionary = {}   ## StringName -> String
var _current_loop_number: int = 0
var _current_loop_started_at_msec: int = 0
var _current_loop_gold_start: int = 0
var _current_loop_total_gold_start: int = 0
var _current_loop_battles_started: int = 0
var _current_loop_battles_cleared: int = 0
var _current_loop_enemies_killed: int = 0
var _current_loop_enemy_counts: Dictionary = {}
var _current_loop_damage_dealt: int = 0
var _current_loop_damage_taken: int = 0
var _current_loop_gold_drops: int = 0
var _current_loop_item_drops: int = 0
var _current_loop_level_ups: int = 0
var _last_loop_report_lines: PackedStringArray = []


func _ready() -> void:
	EventBus.field_loop_started.connect(_on_field_loop_started)
	EventBus.field_loop_settled.connect(_on_field_loop_settled)
	EventBus.battle_window_opened.connect(_on_battle_window_opened)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.party_damage_taken.connect(_on_party_damage_taken)
	EventBus.party_member_leveled_up.connect(_on_party_member_leveled_up)
	EventBus.field_gold_drop_requested.connect(_on_field_gold_drop_requested)
	EventBus.field_item_drop_requested.connect(_on_field_item_drop_requested)
	EventBus.card_purchased.connect(_on_card_purchased)
	EventBus.party_wiped.connect(_on_party_wiped)
	EventBus.run_cleared.connect(_on_run_cleared)


func _on_field_loop_started(loop_num: int) -> void:
	if loop_num == 1:
		_begin_run()
	_begin_loop(loop_num)


func _begin_run() -> void:
	_run_number += 1
	_run_ended = false
	_field_loops_completed = 0
	_enemies_killed = 0
	_total_damage_taken = 0
	_card_order.clear()
	_card_counts.clear()
	_card_names.clear()
	for mod: ModifierData in ModifierDB.get_all():
		_card_order.append(mod.id)
		_card_counts[mod.id] = 0
		_card_names[mod.id] = mod.display_name
	_last_loop_report_lines.clear()


func _begin_loop(loop_num: int) -> void:
	_current_loop_number = loop_num
	_current_loop_started_at_msec = Time.get_ticks_msec()
	_current_loop_gold_start = GameState.gold
	_current_loop_total_gold_start = GameState.total_gold_earned
	_current_loop_battles_started = 0
	_current_loop_battles_cleared = 0
	_current_loop_enemies_killed = 0
	_current_loop_enemy_counts.clear()
	_current_loop_damage_dealt = 0
	_current_loop_damage_taken = 0
	_current_loop_gold_drops = 0
	_current_loop_item_drops = 0
	_current_loop_level_ups = 0
	_last_loop_report_lines.clear()


func _on_field_loop_settled(loop_num: int) -> void:
	if loop_num > _field_loops_completed:
		_field_loops_completed = loop_num
	_last_loop_report_lines = _build_loop_report_lines(loop_num)


func _on_battle_window_opened(_window: Node) -> void:
	_current_loop_battles_started += 1


func _on_battle_window_closed(_window: Node) -> void:
	_current_loop_battles_cleared += 1


func _on_enemy_defeated(_enemy: Node, _gold: int, _world_position: Vector2) -> void:
	_enemies_killed += 1
	_current_loop_enemies_killed += 1
	var name := "Enemy"
	var enemy := _enemy as Enemy
	if enemy and enemy.data:
		name = enemy.data.display_name
	_current_loop_enemy_counts[name] = int(_current_loop_enemy_counts.get(name, 0)) + 1


func _on_damage_dealt(target: Node, amount: int, _world_position: Vector2) -> void:
	if target is Enemy:
		_current_loop_damage_dealt += amount


func _on_party_damage_taken(_member_index: int, amount: int) -> void:
	_total_damage_taken += amount
	_current_loop_damage_taken += amount


func _on_party_member_leveled_up(_index: int, _new_level: int) -> void:
	_current_loop_level_ups += 1


func _on_field_gold_drop_requested(amount: int, _world_position: Vector2) -> void:
	_current_loop_gold_drops += maxi(0, amount)


func _on_field_item_drop_requested(_item: ItemData, _world_position: Vector2, _level: int = 1) -> void:
	_current_loop_item_drops += 1


func _on_card_purchased(mod: ModifierData, _cost: int) -> void:
	if mod == null:
		return
	_card_names[mod.id] = mod.display_name
	_card_counts[mod.id] = int(_card_counts.get(mod.id, 0)) + 1


func _on_party_wiped() -> void:
	end_run("Died in %s" % GameState.field_region_name(), "HP depleted")


func _on_run_cleared() -> void:
	end_run("Cleared", "cleared")


func end_run(result: String, cause: String) -> void:
	if _run_ended:
		return
	_run_ended = true
	var lines: PackedStringArray = []
	lines.append("=== Run #%d End ===" % _run_number)
	lines.append("Result: %s" % result)
	lines.append("Field Loops Completed: %d" % _field_loops_completed)
	lines.append("Reached Region: %s" % GameState.field_region_name())
	lines.append("Total Enemies Killed: %d" % _enemies_killed)
	lines.append("Total Gold Earned: %d" % GameState.total_gold_earned)
	lines.append("Total Damage Taken: %d" % _total_damage_taken)
	lines.append("Cards Purchased:")
	for id: StringName in _card_order:
		lines.append("  - %s: %d times" % [_card_names.get(id, str(id)), _card_counts[id]])
	lines.append("Most Bought Card: %s" % _most_bought_card())
	lines.append("Cause of Death: %s" % cause)
	lines.append("Party at End: [%s]" % _party_names())
	lines.append("================")
	print("\n".join(lines))


func _most_bought_card() -> String:
	var best_name := "None"
	var best_count := 0
	for id in _card_counts.keys():
		var count := int(_card_counts[id])
		if count > best_count:
			best_count = count
			best_name = _card_names.get(id, str(id))
	return best_name


func _party_names() -> String:
	var names: PackedStringArray = []
	for i in GameState.party.size():
		var member: CharacterData = GameState.party[i]
		names.append("%s Lv.%d" % [member.display_name, GameState.party_level(i)])
	return ", ".join(names)


func current_field_loop_report_lines() -> PackedStringArray:
	if _last_loop_report_lines.is_empty():
		return _build_loop_report_lines(_current_loop_number)
	return _last_loop_report_lines.duplicate()


func _build_loop_report_lines(loop_num: int) -> PackedStringArray:
	var elapsed_sec: float = float(Time.get_ticks_msec() - _current_loop_started_at_msec) / 1000.0
	var earned_total: int = GameState.total_gold_earned - _current_loop_total_gold_start
	var net_gold: int = GameState.gold - _current_loop_gold_start
	var lines: PackedStringArray = []
	lines.append("Field Loop %d" % loop_num)
	lines.append("Region: %s" % GameState.current_field_region_display_name())
	lines.append("Time: %.1fs" % elapsed_sec)
	lines.append("Battles: %d opened / %d cleared" % [_current_loop_battles_started, _current_loop_battles_cleared])
	lines.append("Enemies defeated: %d%s" % [_current_loop_enemies_killed, _enemy_breakdown_text()])
	lines.append("Damage dealt: %d" % _current_loop_damage_dealt)
	lines.append("Damage taken: %d" % _current_loop_damage_taken)
	lines.append("Level ups: %d" % _current_loop_level_ups)
	lines.append("Gold gained: +%d   Net: %+d" % [earned_total, net_gold])
	lines.append("Drops created: %d gold / %d item" % [_current_loop_gold_drops, _current_loop_item_drops])
	lines.append("Party:")
	for i in GameState.party.size():
		var member: CharacterData = GameState.party[i]
		var hp: int = GameState.party_hp[i] if i < GameState.party_hp.size() else 0
		lines.append("  %s Lv.%d  HP %d/%d  ATK %d AGI %d" % [
			member.display_name,
			GameState.party_level(i),
			hp,
			GameState.effective_max_hp(i),
			GameState.effective_attack(i),
			GameState.effective_agility(i),
		])
	return lines


func _enemy_breakdown_text() -> String:
	if _current_loop_enemy_counts.is_empty():
		return ""
	var parts: PackedStringArray = []
	for enemy_name in _current_loop_enemy_counts.keys():
		parts.append("%s x%d" % [enemy_name, int(_current_loop_enemy_counts[enemy_name])])
	return " (%s)" % ", ".join(parts)
