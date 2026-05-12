class_name BattleWindow
extends Control

## A single auto-battle window. Self-contained: spawned, ticks turns, closes itself.
## Runs in parallel with up to 100 sibling windows — must stay independent.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")
const SLIME_CHASER_DATA: EnemyData = preload("res://data/enemies/slime_chaser.tres")
const BAT_DATA: EnemyData = preload("res://data/enemies/bat.tres")
const ORC_DATA: EnemyData = preload("res://data/enemies/orc.tres")

@export var enemy_data: EnemyData
@export var turn_interval: float = 0.5
@export var close_delay: float = 0.4
@export_range(0.0, 1.0, 0.05) var item_drop_chance: float = 0.5

## How long to linger at spawn center before sliding to the assigned slot.
@export var slide_delay: float = 0.3
@export var slide_duration: float = 0.3

@onready var _name_label: Label = %NameLabel
@onready var _hp_label: Label = %HPLabel
@onready var _log_label: Label = %LogLabel
@onready var _enemy_anchor: Node2D = %EnemyAnchor
@onready var _turn_timer: Timer = $TurnTimer
@onready var _background: Panel = $Background
@onready var _log_panel: Panel = $LogPanel

const ACTOR_PARTY: int = 0
const ACTOR_ENEMY: int = 1

const BASE_WINDOW_SIZE: Vector2 = Vector2(96.0, 72.0)
const ENEMY_SPRITE_SIZE: Vector2 = Vector2(16.0, 16.0)
const ENEMY_SPACING_X_MIN: float = 18.0
const ENEMY_SPACING_X_MAX: float = 34.0
const ENEMY_ROW_HEIGHT_MIN: float = 22.0
const ENEMY_ROW_HEIGHT_MAX: float = 30.0
const ENEMY_SIDE_PADDING: float = 12.0
const ENEMY_AREA_TOP: float = 8.0
const ENEMY_AREA_BOTTOM: float = 32.0
const TARGET_WINDOW_RATIO: float = 4.0 / 3.0
const DIAMOND_EDGE_WEIGHT: float = 0.5
const CRASH_FLASH_COLOR: Color = Color(1.0, 0.48, 0.12, 1.0)
const WINDOW_FLASH_HOLD_DURATION: float = 0.16
const WINDOW_FLASH_FADE_DURATION: float = 0.42
const BASE_ENEMY_REPEAT_CHANCE: float = 0.68
const STRONGER_SUPPORT_CHANCE: float = 0.06
const POSTER_DARK_TEXT: Color = Color(0.1, 0.08, 0.07, 1.0)
const POSTER_LIGHT_TEXT: Color = Color(0.94, 1.0, 0.86, 1.0)
const DEFAULT_WINDOW_BG: Color = Color(0.95, 0.78, 0.14, 1.0)
const WINDOW_BG_BY_ENEMY_ID: Dictionary = {
	&"slime": Color(0.1, 0.55, 0.43, 1.0),
	&"slime_chaser": Color(0.2, 0.68, 0.35, 1.0),
	&"bat": Color(0.18, 0.46, 0.72, 1.0),
	&"orc": Color(0.98, 0.66, 0.16, 1.0),
}
const ENEMY_TIER_BY_ID: Dictionary = {
	&"slime": 0,
	&"slime_chaser": 1,
	&"bat": 2,
	&"orc": 3,
}

var _enemies: Array[Enemy] = []
var _turn_queue: Array[Dictionary] = []
var _running: bool = false
var _earned_gold_total: int = 0
var _earned_xp_total: int = 0
var _field_drop_position: Vector2 = Vector2.INF
var _item_drops: Array[ItemData] = []
var _enemy_row_counts: Array[int] = [1]
var _planned_enemy_count: int = 0
var _planned_enemy_data: Array[EnemyData] = []
var _slide_tween: Tween
var _crash_tween: Tween


func _ready() -> void:
	_name_label.hide()
	_hp_label.hide()
	_apply_card_color_chrome()
	_turn_timer.wait_time = turn_interval
	_turn_timer.timeout.connect(_on_turn_tick)
	_spawn_enemy()
	_rebuild_turn_queue()
	EventBus.battle_window_opened.emit(self)
	_running = true
	_turn_timer.start()


## Allow spawner to inject data before _ready completes.
func setup(data: EnemyData, field_drop_position: Vector2 = Vector2.INF) -> void:
	enemy_data = data
	_field_drop_position = field_drop_position


func get_expected_window_size() -> Vector2:
	_ensure_enemy_count_planned()
	return _layout_size_for_enemy_count(_planned_enemy_count)


## Slide from spawn position to the assigned slot. Caller decides target.
## Linger at spawn for `slide_delay`, then ease into `target` over `slide_duration`.
func slide_to(target: Vector2) -> void:
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	var tween: Tween = create_tween()
	_slide_tween = tween
	tween.tween_interval(slide_delay)
	tween.tween_property(self, "position", target, slide_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)


func settle_to(target: Vector2, duration: float = 0.22) -> void:
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.tween_property(self, "position", target, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT)


func push_to(target: Vector2) -> void:
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	position = target


func claim_xp_reward() -> int:
	var xp: int = _earned_xp_total
	_earned_xp_total = 0
	return xp


func claim_item_drops() -> Array[ItemData]:
	var drops: Array[ItemData] = _item_drops.duplicate()
	_item_drops.clear()
	return drops


func field_drop_position() -> Vector2:
	return _field_drop_position


func apply_window_collision_damage(ratio: float, log_prefix: String = "Window crash") -> int:
	var total_dealt: int = 0
	for enemy: Enemy in _living_enemies():
		if enemy.data == null:
			continue
		var damage: int = ceili(float(enemy.max_hp) * ratio) + enemy.defense
		total_dealt += enemy.take_damage(damage, false, null, false)
	if total_dealt > 0:
		_play_crash_flash()
		_spawn_window_damage_number(total_dealt, _window_damage_label(log_prefix))
		_log_label.text = "%s! -%d" % [log_prefix, total_dealt]
	return total_dealt


func show_window_collision_heal(member_name: String, amount: int) -> void:
	_log_label.text = "Bump blessing! %s +%d" % [member_name, amount]


func _play_crash_flash() -> void:
	_play_window_color_flash(CRASH_FLASH_COLOR)


func _play_window_color_flash(flash_color: Color) -> void:
	if _background == null or _log_panel == null:
		return
	if _crash_tween and _crash_tween.is_valid():
		_crash_tween.kill()
	var base_bg: Color = _window_bg_color()
	var base_border: Color = base_bg.darkened(0.42)
	var base_log_bg: Color = _log_bg_color(base_bg)
	var base_log_border: Color = base_border
	var flash_log_bg: Color = flash_color.lightened(0.22)
	var flash_style := _flat_panel_style(flash_color, flash_color.darkened(0.4))
	var flash_log_style := _flat_panel_style(flash_log_bg, flash_color.darkened(0.18))
	_background.add_theme_stylebox_override("panel", flash_style)
	_log_panel.add_theme_stylebox_override("panel", flash_log_style)
	_apply_label_color(_log_label, POSTER_DARK_TEXT)
	_crash_tween = create_tween()
	_crash_tween.tween_interval(WINDOW_FLASH_HOLD_DURATION)
	_crash_tween.tween_property(flash_style, "bg_color", base_bg, WINDOW_FLASH_FADE_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_crash_tween.parallel().tween_property(flash_style, "border_color", base_border, WINDOW_FLASH_FADE_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_crash_tween.parallel().tween_property(flash_log_style, "bg_color", base_log_bg, WINDOW_FLASH_FADE_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_crash_tween.parallel().tween_property(flash_log_style, "border_color", base_log_border, WINDOW_FLASH_FADE_DURATION)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	_crash_tween.tween_callback(_apply_card_color_chrome)


func _apply_card_color_chrome() -> void:
	var bg: Color = _window_bg_color()
	var border: Color = bg.darkened(0.42)
	var log_bg: Color = _log_bg_color(bg)
	var text_color: Color = POSTER_LIGHT_TEXT if log_bg.get_luminance() < 0.42 else POSTER_DARK_TEXT
	_background.add_theme_stylebox_override("panel", _flat_panel_style(bg, border))
	_log_panel.add_theme_stylebox_override("panel", _flat_panel_style(log_bg, border))
	_apply_label_color(_log_label, text_color)
	_apply_label_color(_name_label, text_color)
	_apply_label_color(_hp_label, text_color)


func _flat_panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.anti_aliasing = false
	return style


func _apply_label_color(label: Label, color: Color) -> void:
	if label == null:
		return
	var settings: LabelSettings = label.label_settings.duplicate()
	settings.font_color = color
	label.label_settings = settings


func _window_bg_color() -> Color:
	if enemy_data == null:
		return DEFAULT_WINDOW_BG
	return WINDOW_BG_BY_ENEMY_ID.get(enemy_data.id, DEFAULT_WINDOW_BG)


func _log_bg_color(bg: Color) -> Color:
	return bg.lightened(0.34 if bg.get_luminance() < 0.42 else 0.14)


func _spawn_window_damage_number(amount: int, label_prefix: String) -> void:
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	add_child(num)
	num.position = Vector2(size.x * 0.5 + randf_range(-18.0, 18.0), 10.0 + randf_range(-2.0, 4.0))
	num.z_index = 20
	num.setup_window_damage(amount, label_prefix)


func _window_damage_label(log_prefix: String) -> String:
	if log_prefix.to_lower().contains("bump"):
		return "BUMP"
	return "CRASH"


func _spawn_enemy() -> void:
	if enemy_data == null:
		push_warning("[BattleWindow] no enemy_data set")
		return
	_ensure_enemy_plan()
	var enemy_count: int = _planned_enemy_data.size()
	_apply_enemy_layout(enemy_count)
	for i in enemy_count:
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		enemy.setup(_planned_enemy_data[i])
		enemy.position = _enemy_offset(i, enemy_count)
		_enemy_anchor.add_child(enemy)
		enemy.hp_changed.connect(_on_enemy_hp_changed)
		enemy.died.connect(_on_enemy_died.bind(enemy))
		_enemies.append(enemy)
	_name_label.text = _encounter_display_name()
	_refresh_hp_label()
	_log_label.text = "%s appears!" % _name_label.text


func _ensure_enemy_plan() -> void:
	if _planned_enemy_count > 0:
		return
	_planned_enemy_count = randi_range(1, _max_enemies_per_window())
	_planned_enemy_data = _plan_enemy_mix(_planned_enemy_count)


func _ensure_enemy_count_planned() -> void:
	_ensure_enemy_plan()


func _max_enemies_per_window() -> int:
	return maxi(1, GameState.party_size() + 1)


func _plan_enemy_mix(total: int) -> Array[EnemyData]:
	var planned: Array[EnemyData] = []
	for i in total:
		if i == 0 or randf() < BASE_ENEMY_REPEAT_CHANCE:
			planned.append(enemy_data)
		else:
			planned.append(_pick_support_enemy())
	planned.shuffle()
	return planned


func _pick_support_enemy() -> EnemyData:
	var pool: Array[EnemyData] = _support_enemy_pool()
	return enemy_data if pool.is_empty() else pool.pick_random()


func _support_enemy_pool() -> Array[EnemyData]:
	var pool: Array[EnemyData] = []
	var base_tier: int = _enemy_tier(enemy_data)
	for candidate: EnemyData in _available_support_enemies():
		if candidate == enemy_data:
			continue
		var candidate_tier: int = _enemy_tier(candidate)
		if candidate_tier <= base_tier or randf() < STRONGER_SUPPORT_CHANCE:
			pool.append(candidate)
	return pool


func _available_support_enemies() -> Array[EnemyData]:
	var out: Array[EnemyData] = [SLIME_DATA]
	if GameState.current_stage >= 2:
		out.append(SLIME_CHASER_DATA)
	if GameState.current_stage >= 3:
		out.append(BAT_DATA)
	if GameState.current_stage >= 5:
		out.append(ORC_DATA)
	return out


func _enemy_tier(data: EnemyData) -> int:
	if data == null:
		return 0
	return int(ENEMY_TIER_BY_ID.get(data.id, 0))


func _encounter_display_name() -> String:
	var counts: Dictionary = {}
	var names: Dictionary = {}
	for data: EnemyData in _planned_enemy_data:
		if data == null:
			continue
		counts[data.id] = int(counts.get(data.id, 0)) + 1
		names[data.id] = data.display_name
	var parts: PackedStringArray = []
	var ordered_ids: Array = counts.keys()
	ordered_ids.sort()
	if enemy_data and counts.has(enemy_data.id):
		ordered_ids.erase(enemy_data.id)
		ordered_ids.push_front(enemy_data.id)
	for id in ordered_ids:
		var count: int = int(counts[id])
		var name: String = str(names[id])
		parts.append(name if count == 1 else "%s x%d" % [name, count])
	return " / ".join(parts)


# ─── Turn loop ────────────────────────────────────────────────────────
func _on_turn_tick() -> void:
	if not _running:
		return
	if _living_enemies().is_empty() or GameState.is_party_wiped():
		return
	var actor: Dictionary = _next_actor()
	if actor.is_empty():
		return
	if int(actor["type"]) == ACTOR_PARTY:
		_party_attack(int(actor["party_index"]))
	else:
		_enemy_attack(actor["enemy"])


func _party_attack(attacker_index: int) -> void:
	var target_enemy := _first_living_enemy()
	if target_enemy == null:
		return
	var member: CharacterData = GameState.party[attacker_index]
	match member.id:
		&"hero":
			_basic_party_attack(attacker_index, target_enemy, GameState.hero_attack_multiplier())
		&"mage":
			if GameState.mage_splash_extra_targets() > 0:
				_mage_splash_attack(attacker_index)
			else:
				_basic_party_attack(attacker_index, target_enemy)
		&"priest":
			if GameState.priest_heal_amount() > 0:
				_priest_heal_attack(attacker_index, target_enemy)
			else:
				_basic_party_attack(attacker_index, target_enemy)
		&"thief":
			_thief_attack(attacker_index, target_enemy)
		_:
			_basic_party_attack(attacker_index, target_enemy)


func _basic_party_attack(attacker_index: int, target_enemy: Enemy, damage_mult: float = 1.0) -> int:
	var member: CharacterData = GameState.party[attacker_index]
	var atk: int = GameState.effective_attack(attacker_index)
	var crit: Dictionary = GameState.roll_crit()
	var damage: int = int(round(float(atk) * damage_mult * float(crit["mult"])))
	var dealt: int = target_enemy.take_damage(damage, crit["is_crit"], member.attack_effect)
	var target_name: String = target_enemy.data.display_name if target_enemy.data else "Enemy"
	var tag: String = "%s hits %s -%d" % [member.display_name, target_name, dealt]
	if crit["is_crit"]:
		tag += "!"
	_log_label.text = tag
	return dealt


func _mage_splash_attack(attacker_index: int) -> void:
	var member: CharacterData = GameState.party[attacker_index]
	var targets: Array[Enemy] = _living_enemies()
	var target_count: int = mini(targets.size(), 1 + GameState.mage_splash_extra_targets())
	var atk: int = GameState.effective_attack(attacker_index)
	var crit: Dictionary = GameState.roll_crit()
	var damage: int = int(round(float(atk) * GameState.mage_splash_damage_multiplier() * float(crit["mult"])))
	var total_dealt: int = 0
	for i in target_count:
		total_dealt += targets[i].take_damage(damage, crit["is_crit"], member.attack_effect)
	var suffix := "!" if crit["is_crit"] else ""
	_log_label.text = "%s scorches x%d -%d%s" % [member.display_name, target_count, total_dealt, suffix]


func _priest_heal_attack(attacker_index: int, target_enemy: Enemy) -> void:
	var dealt: int = _basic_party_attack(attacker_index, target_enemy, GameState.priest_attack_multiplier())
	var heal_target: int = _lowest_wounded_party_index()
	if heal_target == -1:
		return
	var before_hp: int = GameState.party_hp[heal_target]
	GameState.heal_party_member(heal_target, GameState.priest_heal_amount())
	var healed: int = GameState.party_hp[heal_target] - before_hp
	if healed > 0:
		_log_label.text = "%s -%d / %s +%d" % [
			GameState.party[attacker_index].display_name,
			dealt,
			GameState.party[heal_target].display_name,
			healed,
		]


func _thief_attack(attacker_index: int, target_enemy: Enemy) -> void:
	var dealt: int = _basic_party_attack(attacker_index, target_enemy)
	var stolen: int = target_enemy.try_steal_gold(GameState.thief_steal_chance(), GameState.thief_steal_gold_amount())
	if stolen <= 0:
		return
	GameState.add_gold(stolen)
	_log_label.text = "%s -%d / stole %dG" % [GameState.party[attacker_index].display_name, dealt, stolen]


func _enemy_attack(enemy: Enemy) -> void:
	var alive_indices: Array[int] = []
	for i in GameState.party_size():
		if GameState.is_alive(i):
			alive_indices.append(i)
	if alive_indices.is_empty():
		return
	var target_index: int = alive_indices.pick_random()
	var target: CharacterData = GameState.party[target_index]
	var attacker_name: String = enemy.data.display_name if enemy.data else "Enemy"
	if GameState.roll_evade(target_index):
		enemy.play_attack_lunge()
		_log_label.text = "%s dodges %s!" % [target.display_name, attacker_name]
		return
	var dealt: int = max(1, enemy.attack - GameState.effective_defense(target_index))
	enemy.play_attack_lunge()
	GameState.damage_party_member(target_index, dealt)
	_log_label.text = "%s hits %s -%d" % [attacker_name, target.display_name, dealt]


# ─── Enemy callbacks ──────────────────────────────────────────────────
func _on_enemy_hp_changed(_current: int, _max_hp: int) -> void:
	_refresh_hp_label()


func _on_enemy_died(_enemy: Enemy) -> void:
	var reward: int = GameState.modify_gold_reward(_enemy.gold_reward)
	GameState.add_gold(reward)
	_earned_gold_total += reward
	if _enemy.data:
		_earned_xp_total += GameState.scaled_enemy_xp_reward(_enemy.data)
		_roll_item_drop()
	_refresh_hp_label()
	if not _living_enemies().is_empty():
		var defeated_name: String = _enemy.data.display_name if _enemy.data else "Enemy"
		_log_label.text = "%s defeated! +%d gold" % [defeated_name, reward]
		return
	_running = false
	_turn_timer.stop()
	_log_label.text = "All defeated! +%d gold" % _earned_gold_total
	await get_tree().create_timer(close_delay).timeout
	EventBus.battle_window_closed.emit(self)
	queue_free()


func _roll_item_drop() -> void:
	if randf() > item_drop_chance:
		return
	var item: ItemData = ItemDB.random_drop()
	if item:
		_item_drops.append(item)


func _refresh_hp_label() -> void:
	var current_total: int = 0
	var max_total: int = 0
	for enemy: Enemy in _enemies:
		if not is_instance_valid(enemy):
			continue
		current_total += enemy.current_hp
		max_total += enemy.max_hp
	_hp_label.text = "HP %d/%d" % [current_total, max_total]


func _living_enemies() -> Array[Enemy]:
	var living: Array[Enemy] = []
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			living.append(enemy)
	return living


func _first_living_enemy() -> Enemy:
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			return enemy
	return null


func _lowest_wounded_party_index() -> int:
	var best_index: int = -1
	var best_ratio: float = 1.1
	for i in GameState.party_size():
		if not GameState.is_alive(i):
			continue
		var max_hp: int = GameState.effective_max_hp(i)
		if max_hp <= 0 or GameState.party_hp[i] >= max_hp:
			continue
		var ratio: float = float(GameState.party_hp[i]) / float(max_hp)
		if ratio < best_ratio:
			best_ratio = ratio
			best_index = i
	return best_index


func _next_actor() -> Dictionary:
	while true:
		if _turn_queue.is_empty():
			_rebuild_turn_queue()
			if _turn_queue.is_empty():
				return {}
		var actor: Dictionary = _turn_queue.pop_front()
		if _is_actor_alive(actor):
			return actor
	return {}


func _rebuild_turn_queue() -> void:
	_turn_queue.clear()
	for i in GameState.party_size():
		if GameState.is_alive(i):
			_turn_queue.append({
				"type": ACTOR_PARTY,
				"party_index": i,
				"agility": GameState.effective_agility(i),
				"tie_break": randf(),
			})
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			_turn_queue.append({
				"type": ACTOR_ENEMY,
				"enemy": enemy,
				"agility": enemy.agility,
				"tie_break": randf(),
			})
	_turn_queue.sort_custom(_compare_turn_actors)


func _compare_turn_actors(a: Dictionary, b: Dictionary) -> bool:
	var agility_a: int = int(a["agility"])
	var agility_b: int = int(b["agility"])
	if agility_a == agility_b:
		return float(a["tie_break"]) < float(b["tie_break"])
	return agility_a > agility_b


func _is_actor_alive(actor: Dictionary) -> bool:
	if int(actor["type"]) == ACTOR_PARTY:
		return GameState.is_alive(int(actor["party_index"]))
	var enemy := actor["enemy"] as Enemy
	return enemy != null and is_instance_valid(enemy) and enemy.is_alive()


func _apply_enemy_layout(total: int) -> void:
	_enemy_row_counts = _row_counts_for_enemy_count(total)
	var next_size := _layout_size_for_enemy_count(total)
	custom_minimum_size = next_size
	size = next_size
	_enemy_anchor.position = Vector2(
		next_size.x * 0.5,
		ENEMY_AREA_TOP + (next_size.y - ENEMY_AREA_BOTTOM - ENEMY_AREA_TOP) * 0.5
	)


func _layout_size_for_enemy_count(total: int) -> Vector2:
	return _layout_size_for_rows(_row_counts_for_enemy_count(total))


func _layout_size_for_rows(row_counts: Array[int]) -> Vector2:
	var rows: int = row_counts.size()
	var widest_row: int = 1
	for row_count: int in row_counts:
		widest_row = maxi(widest_row, row_count)
	var spacing: Vector2 = _enemy_spacing_for_count(_row_enemy_count(row_counts))
	var grid_width: float = ENEMY_SPRITE_SIZE.x + float(widest_row - 1) * spacing.x
	var content_size := Vector2(
		maxf(BASE_WINDOW_SIZE.x, grid_width + ENEMY_SIDE_PADDING * 2.0),
		maxf(BASE_WINDOW_SIZE.y, ENEMY_AREA_TOP + _diamond_content_height(rows, spacing.y) + ENEMY_AREA_BOTTOM)
	)
	return _fit_to_target_ratio(content_size)


func _fit_to_target_ratio(content_size: Vector2) -> Vector2:
	var ratio: float = content_size.x / content_size.y
	if ratio > TARGET_WINDOW_RATIO:
		content_size.y = content_size.x / TARGET_WINDOW_RATIO
	elif ratio < TARGET_WINDOW_RATIO:
		content_size.x = content_size.y * TARGET_WINDOW_RATIO
	return content_size


func _row_counts_for_enemy_count(total: int) -> Array[int]:
	if total <= 1:
		return [1]
	var max_rows: int = _max_rows_for_enemy_count(total)
	var best_rows: Array[int] = [total]
	var best_score: float = INF
	for rows in range(1, max_rows + 1):
		var row_counts: Array[int] = _diamond_row_counts(total, rows)
		var size: Vector2 = _raw_layout_size_for_rows(row_counts)
		var ratio: float = size.x / size.y
		var score: float = absf(ratio - TARGET_WINDOW_RATIO)
		score += absf(float(_widest_row_count(row_counts)) - float(rows) * TARGET_WINDOW_RATIO) * 0.015
		if score < best_score:
			best_score = score
			best_rows = row_counts
	return best_rows


func _max_rows_for_enemy_count(total: int) -> int:
	return maxi(1, ceili(sqrt(float(total)) * 1.6))


func _diamond_row_counts(total: int, rows: int) -> Array[int]:
	var counts: Array[int] = []
	for i in rows:
		counts.append(1)
	var remaining: int = total - rows
	if remaining <= 0:
		return counts
	var weights: Array[float] = []
	var fractions: Array[Dictionary] = []
	var weight_sum: float = 0.0
	var center: float = float(rows - 1) * 0.5
	var max_distance: float = maxf(center, float(rows - 1) - center)
	if max_distance <= 0.0:
		max_distance = 1.0
	for row in rows:
		var distance_ratio: float = absf(float(row) - center) / max_distance
		var weight: float = lerpf(1.0, DIAMOND_EDGE_WEIGHT, distance_ratio)
		weights.append(weight)
		weight_sum += weight
	for row in rows:
		var exact: float = float(remaining) * weights[row] / weight_sum
		var add: int = int(floor(exact))
		counts[row] += add
		remaining -= add
		fractions.append({
			"row": row,
			"fraction": exact - float(add),
			"center_distance": absf(float(row) - center),
		})
	fractions.sort_custom(_compare_diamond_fraction)
	var fraction_index: int = 0
	while remaining > 0:
		var entry: Dictionary = fractions[fraction_index % fractions.size()]
		counts[int(entry["row"])] += 1
		remaining -= 1
		fraction_index += 1
	return counts


func _compare_diamond_fraction(a: Dictionary, b: Dictionary) -> bool:
	var fraction_a: float = float(a["fraction"])
	var fraction_b: float = float(b["fraction"])
	if is_equal_approx(fraction_a, fraction_b):
		return float(a["center_distance"]) < float(b["center_distance"])
	return fraction_a > fraction_b


func _diamond_content_height(rows: int, row_height: float) -> float:
	return ENEMY_SPRITE_SIZE.y + float(rows - 1) * row_height


func _raw_layout_size_for_rows(row_counts: Array[int]) -> Vector2:
	var widest_row: int = _widest_row_count(row_counts)
	var spacing: Vector2 = _enemy_spacing_for_count(_row_enemy_count(row_counts))
	return Vector2(
		maxf(BASE_WINDOW_SIZE.x, ENEMY_SPRITE_SIZE.x + float(widest_row - 1) * spacing.x + ENEMY_SIDE_PADDING * 2.0),
		maxf(BASE_WINDOW_SIZE.y, ENEMY_AREA_TOP + _diamond_content_height(row_counts.size(), spacing.y) + ENEMY_AREA_BOTTOM)
	)


func _widest_row_count(row_counts: Array[int]) -> int:
	var widest_row: int = 1
	for row_count: int in row_counts:
		widest_row = maxi(widest_row, row_count)
	return widest_row


func _row_enemy_count(row_counts: Array[int]) -> int:
	var total: int = 0
	for row_count: int in row_counts:
		total += row_count
	return total


func _enemy_spacing_for_count(total: int) -> Vector2:
	var crowding: float = clampf(float(maxi(0, total - 1)) / 19.0, 0.0, 1.0)
	return Vector2(
		lerpf(ENEMY_SPACING_X_MAX, ENEMY_SPACING_X_MIN, crowding),
		lerpf(ENEMY_ROW_HEIGHT_MAX, ENEMY_ROW_HEIGHT_MIN, crowding)
	)


func _enemy_offset(index: int, total: int) -> Vector2:
	if total <= 1:
		return Vector2.ZERO
	var spacing: Vector2 = _enemy_spacing_for_count(total)
	var rows: int = _enemy_row_counts.size()
	var row: int = 0
	var row_start: int = 0
	for row_index in rows:
		var row_count: int = _enemy_row_counts[row_index]
		if index < row_start + row_count:
			row = row_index
			break
		row_start += row_count
	var row_count: int = _enemy_row_counts[row]
	var column: int = index - row_start
	var width: float = float(row_count - 1) * spacing.x
	var height: float = float(rows - 1) * spacing.y
	return Vector2(
		float(column) * spacing.x - width * 0.5,
		float(row) * spacing.y - height * 0.5
	)
