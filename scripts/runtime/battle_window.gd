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
const BLADE_BUG_DATA: EnemyData = preload("res://data/enemies/blade_bug.tres")

@export var enemy_data: EnemyData
@export var turn_interval: float = 0.5
@export var close_delay: float = 0.85
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
const FUSION_EXTRA_WINDOW_SIZE: Vector2 = Vector2(32.0, 24.0)
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
const ORC_BUMP_DAMAGE_MULTIPLIER: float = 0.5
const HERO_HEAVY_STRIKE_MP_COST: int = 2
const HERO_HOIMI_MP_COST: int = 3
const MAGE_FIREBURST_MP_COST: int = 6
const MAGE_LIGHTNING_MP_COST: int = 4
const PRIEST_PRAYER_MP_COST: int = 4
const PRIEST_HOLY_STRIKE_MP_COST: int = 4
const THIEF_PILFER_MP_COST: int = 2
## Priest only auto-casts Heal when an ally drops below this HP ratio.
## Stops the priest from healing chip damage every turn.
const PRIEST_HEAL_HP_RATIO_THRESHOLD: float = 0.6
const INTRO_MESSAGE_DURATION: float = 0.72
const ATTACK_CALL_DURATION: float = 0.34
const IMPACT_MESSAGE_DELAY: float = 0.16
const RESULT_MESSAGE_DURATION: float = 0.42
const POSTER_DARK_TEXT: Color = Color(0.1, 0.08, 0.07, 1.0)
const POSTER_LIGHT_TEXT: Color = Color(0.94, 1.0, 0.86, 1.0)
const DEFAULT_WINDOW_BG: Color = Color(0.95, 0.78, 0.14, 1.0)
const WINDOW_BG_BY_ENEMY_ID: Dictionary = {
	&"slime": Color(0.1, 0.55, 0.43, 1.0),
	&"slime_chaser": Color(0.2, 0.68, 0.35, 1.0),
	&"bat": Color(0.18, 0.46, 0.72, 1.0),
	&"orc": Color(0.98, 0.66, 0.16, 1.0),
	&"blade_bug": Color(0.72, 0.22, 0.2, 1.0),
}
const ENEMY_TIER_BY_ID: Dictionary = {
	&"slime": 0,
	&"slime_chaser": 1,
	&"bat": 2,
	&"orc": 3,
	&"blade_bug": 3,
}

var _enemies: Array[Enemy] = []
var _turn_queue: Array[Dictionary] = []
var _running: bool = false
var _earned_gold_total: int = 0
var _earned_xp_total: int = 0
var _earned_recovery_orbs: int = 0
var _field_drop_position: Vector2 = Vector2.INF
var _item_drops: Array[ItemData] = []
var _enemy_row_counts: Array[int] = [1]
var _planned_enemy_count: int = 0
var _planned_enemy_data: Array[EnemyData] = []
var _forced_enemy_count: int = 0
var _slide_tween: Tween
var _crash_tween: Tween
var _acting: bool = false


func _ready() -> void:
	_name_label.hide()
	_hp_label.hide()
	_configure_log_label()
	_apply_card_color_chrome()
	_turn_timer.wait_time = turn_interval
	_turn_timer.timeout.connect(_on_turn_tick)
	_spawn_enemy()
	_rebuild_turn_queue()
	EventBus.battle_window_opened.emit(self)
	_running = true
	_play_open_animation()
	# Intro text runs in parallel with the window so the "~가 나타났다!"
	# message rides inside the pop-in. Enemies pop after a tiny breath so
	# the second beat reads as a separate "그리고… 뿅뿅" punch.
	_play_intro_then_start()
	_stagger_enemy_entrance()


## Modern popup entry: window snaps in from a smaller size, overshoots
## past full size, then settles back. Classic Slay-the-Spire / Hades
## "wham!" feel — short, punchy, easy to read. No rotation, no mask.
## Two beats: (1) 와앙 팍 window-with-text, (2) 뿅뿅 enemies.
const OPEN_ANIMATION_DURATION: float = 0.32
const OPEN_ANIMATION_START_SCALE: float = 0.3
## Tiny pause after the window starts to settle before enemies arrive — just
## enough that "window first, enemies second" reads, without ever dragging.
const ENEMY_ENTRANCE_DELAY: float = 0.3
## Gap between consecutive enemy pops — readable as "뿅… 뿅… 뿅" rather than
## a single mob crowd appearing all at once.
const ENEMY_STAGGER: float = 0.13
const ENEMY_POP_DURATION: float = 0.25
const ENEMY_START_SCALE: float = 0.15

func _play_open_animation() -> void:
	# Center pivot so the scale punch radiates from the middle.
	pivot_offset = get_expected_window_size() * 0.5
	scale = Vector2.ONE * OPEN_ANIMATION_START_SCALE
	modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel(true)
	# TRANS_BACK + EASE_OUT lands past 1.0 then snaps back — the "탁!" beat.
	tween.tween_property(self, "scale", Vector2.ONE, OPEN_ANIMATION_DURATION)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	# Fade in finishes well before scale settles so it never looks washed out.
	tween.tween_property(self, "modulate:a", 1.0, OPEN_ANIMATION_DURATION * 0.45)


## Pop each enemy in one at a time. Runs in parallel with intro text and
## also acts as the final gate on the turn timer — once enemies have
## visually landed we re-start the timer so the first action never lands
## before the player can see who's attacking.
func _stagger_enemy_entrance() -> void:
	# Park each enemy as a tiny, transparent dot before the wait kicks in.
	# Done synchronously so the very first frame never shows full-size enemies.
	for enemy: Enemy in _enemies:
		if not is_instance_valid(enemy):
			continue
		enemy.modulate.a = 0.0
		enemy.scale = Vector2.ONE * ENEMY_START_SCALE
	await get_tree().create_timer(ENEMY_ENTRANCE_DELAY).timeout
	for enemy: Enemy in _enemies:
		if not _running or not is_inside_tree():
			return
		if not is_instance_valid(enemy):
			continue
		_pop_in_enemy(enemy)
		await get_tree().create_timer(ENEMY_STAGGER).timeout
	# Wait for the last enemy's overshoot to settle, then re-prime the turn
	# timer. _play_intro_then_start also starts the timer when its messages
	# finish — whichever fires last wins, which is exactly what we want.
	await get_tree().create_timer(ENEMY_POP_DURATION).timeout
	if _running and is_inside_tree():
		_turn_timer.start()


func _pop_in_enemy(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	# Attach the tween to the enemy so it auto-dies if the enemy is freed
	# mid-pop (e.g. instant kill from a passive trigger before turns start).
	var tween: Tween = enemy.create_tween().set_parallel(true)
	tween.tween_property(enemy, "scale", Vector2.ONE, ENEMY_POP_DURATION)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(enemy, "modulate:a", 1.0, ENEMY_POP_DURATION * 0.5)


## Allow spawner to inject data before _ready completes.
func setup(data: EnemyData, field_drop_position: Vector2 = Vector2.INF, enemy_count: int = 0) -> void:
	enemy_data = data
	_field_drop_position = field_drop_position
	_forced_enemy_count = clampi(enemy_count, 0, GameState.BATTLE_WINDOW_MAX_ENEMIES)


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


func claim_recovery_orb_count() -> int:
	var count: int = _earned_recovery_orbs
	_earned_recovery_orbs = 0
	return count


func field_drop_position() -> Vector2:
	return _field_drop_position


func living_enemy_count() -> int:
	return _living_enemies().size()


func absorb_window(other: BattleWindow) -> bool:
	if other == null or other == self or not is_instance_valid(other):
		return false
	var incoming_enemies: Array[Enemy] = other._detach_living_enemies_for_fusion()
	if incoming_enemies.is_empty():
		return false
	_earned_gold_total += other._earned_gold_total
	_earned_xp_total += other.claim_xp_reward()
	_item_drops.append_array(other.claim_item_drops())
	_earned_recovery_orbs += other.claim_recovery_orb_count()
	for enemy: Enemy in incoming_enemies:
		_adopt_enemy_for_fusion(enemy)
	_rebuild_after_fusion()
	other._finish_as_fusion_source()
	_play_crash_flash()
	_log_label.text = "Fusion! %d enemies" % living_enemy_count()
	return true


func _detach_living_enemies_for_fusion() -> Array[Enemy]:
	_running = false
	_turn_timer.stop()
	var detached: Array[Enemy] = []
	for enemy: Enemy in _living_enemies():
		_disconnect_enemy_callbacks(enemy, self)
		detached.append(enemy)
	_enemies.clear()
	return detached


func _adopt_enemy_for_fusion(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	enemy.reparent(_enemy_anchor)
	enemy.hp_changed.connect(_on_enemy_hp_changed)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	_enemies.append(enemy)


func _disconnect_enemy_callbacks(enemy: Enemy, window: BattleWindow) -> void:
	for connection: Dictionary in enemy.hp_changed.get_connections():
		var hp_callable: Callable = connection["callable"]
		if hp_callable.is_valid() and hp_callable.get_object() == window:
			enemy.hp_changed.disconnect(hp_callable)
	for connection: Dictionary in enemy.died.get_connections():
		var died_callable: Callable = connection["callable"]
		if died_callable.is_valid() and died_callable.get_object() == window:
			enemy.died.disconnect(died_callable)


func _rebuild_after_fusion() -> void:
	_enemies = _living_enemies()
	_planned_enemy_count = _enemies.size()
	_planned_enemy_data.clear()
	for enemy: Enemy in _enemies:
		if enemy.data != null:
			_planned_enemy_data.append(enemy.data)
	if not _planned_enemy_data.is_empty():
		enemy_data = _planned_enemy_data.front()
	_apply_enemy_layout(_enemies.size())
	_apply_fusion_size_bonus()
	for i in _enemies.size():
		var enemy: Enemy = _enemies[i]
		if enemy != null and is_instance_valid(enemy):
			enemy.set_battle_slot_position(_enemy_offset(i, _enemies.size()))
	_name_label.text = _encounter_display_name()
	_refresh_hp_label()
	_rebuild_turn_queue()


func _apply_fusion_size_bonus() -> void:
	var fusion_size: Vector2 = size + FUSION_EXTRA_WINDOW_SIZE
	custom_minimum_size = fusion_size
	size = fusion_size
	_enemy_anchor.position = Vector2(
		fusion_size.x * 0.5,
		ENEMY_AREA_TOP + (fusion_size.y - ENEMY_AREA_BOTTOM - ENEMY_AREA_TOP) * 0.5
	)


func _finish_as_fusion_source() -> void:
	_running = false
	_turn_timer.stop()
	if _slide_tween and _slide_tween.is_valid():
		_slide_tween.kill()
	queue_free()


## When `single_target` is true the damage lands on exactly one random
## living enemy inside the window instead of splashing across the whole
## roster. Used by bump_attack so player→window collisions feel more like
## a poke than a screen-clear, while window→window crashes (window_crash)
## keep their original "everyone in the room takes a hit" splash.
func apply_window_collision_damage(ratio: float, log_prefix: String = "Window crash", single_target: bool = false) -> int:
	var total_dealt: int = 0
	var effective_ratio: float = ratio * _window_collision_damage_multiplier(log_prefix)
	var living: Array[Enemy] = _living_enemies()
	if single_target:
		if living.is_empty():
			return 0
		var pick: Enemy = living[randi() % living.size()]
		if pick != null and pick.data != null:
			var damage: int = ceili(float(pick.max_hp) * effective_ratio) + pick.defense
			total_dealt = pick.take_damage(damage, false, null, false)
	else:
		for enemy: Enemy in living:
			if enemy.data == null:
				continue
			var damage: int = ceili(float(enemy.max_hp) * effective_ratio) + enemy.defense
			total_dealt += enemy.take_damage(damage, false, null, false)
	if total_dealt > 0:
		_play_crash_flash()
		_spawn_window_damage_number(total_dealt, _window_damage_label(log_prefix))
		_log_label.text = "%s! -%d" % [log_prefix, total_dealt]
	return total_dealt


func _window_collision_damage_multiplier(log_prefix: String) -> float:
	if log_prefix.to_lower().contains("bump") and has_living_enemy_id(&"orc"):
		return ORC_BUMP_DAMAGE_MULTIPLIER
	return 1.0


func party_bump_counter_damage_ratio() -> float:
	var total_ratio: float = 0.0
	for enemy: Enemy in _living_enemies():
		if enemy.data == null:
			continue
		total_ratio += maxf(0.0, enemy.data.party_bump_counter_damage_ratio)
	return total_ratio


func has_living_enemy_id(enemy_id: StringName) -> bool:
	for enemy: Enemy in _living_enemies():
		if enemy.data != null and enemy.data.id == enemy_id:
			return true
	return false


func show_party_bump_counter_damage(total_amount: int, ratio: float) -> void:
	_log_label.text = "Blade counter! Party -%d%% (%d)" % [int(round(ratio * 100.0)), total_amount]


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


func _configure_log_label() -> void:
	_log_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_log_label.clip_text = true
	_log_label.max_lines_visible = 1
	var settings: LabelSettings = _log_label.label_settings.duplicate()
	settings.font_size = 7
	_log_label.label_settings = settings


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


func _play_intro_then_start() -> void:
	_turn_timer.stop()
	for message: String in _encounter_intro_messages():
		if not _running or not is_inside_tree():
			return
		_log_label.text = message
		await _battle_pause(INTRO_MESSAGE_DURATION)
	if _running and is_inside_tree():
		_turn_timer.start()


func _ensure_enemy_plan() -> void:
	if _planned_enemy_count > 0:
		return
	_planned_enemy_count = _roll_enemy_count_for_window()
	_planned_enemy_data = _plan_enemy_mix(_planned_enemy_count)


func _ensure_enemy_count_planned() -> void:
	_ensure_enemy_plan()


func _max_enemies_per_window() -> int:
	return GameState.BATTLE_WINDOW_MAX_ENEMIES


func _roll_enemy_count_for_window() -> int:
	if _forced_enemy_count > 0:
		return _forced_enemy_count
	return GameState.roll_battle_window_enemy_count()


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
	# Drive the support pool off the *effective* stage so the time-based
	# difficulty bumps also unlock new species in battle window mixes.
	var stage: int = GameState.effective_stage()
	var out: Array[EnemyData] = [SLIME_DATA]
	if stage >= 2:
		out.append(SLIME_CHASER_DATA)
	if stage >= 3:
		out.append(BAT_DATA)
	if stage >= 5:
		out.append(BLADE_BUG_DATA)
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


func _encounter_intro_messages() -> Array[String]:
	var counts: Dictionary = {}
	var names: Dictionary = {}
	for data: EnemyData in _planned_enemy_data:
		if data == null:
			continue
		counts[data.id] = int(counts.get(data.id, 0)) + 1
		names[data.id] = data.display_name
	var messages: Array[String] = []
	var ordered_ids: Array = counts.keys()
	ordered_ids.sort()
	if enemy_data and counts.has(enemy_data.id):
		ordered_ids.erase(enemy_data.id)
		ordered_ids.push_front(enemy_data.id)
	for id in ordered_ids:
		var count: int = int(counts[id])
		var name: String = str(names[id])
		var label: String = name if count == 1 else "%s x%d" % [name, count]
		messages.append("%s%s 나타났다!" % [label, _subject_particle(label)])
	return messages


func _battle_pause(duration: float) -> void:
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout


func _subject_particle(text: String) -> String:
	if text.is_empty():
		return "가"
	var last_code: int = text.unicode_at(text.length() - 1)
	if last_code < 0xAC00 or last_code > 0xD7A3:
		return "가"
	return "이" if (last_code - 0xAC00) % 28 > 0 else "가"


func _object_particle(text: String) -> String:
	if text.is_empty():
		return "를"
	var last_code: int = text.unicode_at(text.length() - 1)
	if last_code < 0xAC00 or last_code > 0xD7A3:
		return "를"
	return "을" if (last_code - 0xAC00) % 28 > 0 else "를"


# ─── Turn loop ────────────────────────────────────────────────────────
func _on_turn_tick() -> void:
	if not _running or _acting:
		return
	if _living_enemies().is_empty() or GameState.is_party_wiped():
		return
	var actor: Dictionary = _next_actor()
	if actor.is_empty():
		return
	_acting = true
	if int(actor["type"]) == ACTOR_PARTY:
		await _party_attack(int(actor["party_index"]))
	else:
		await _enemy_attack(actor["enemy"])
	_acting = false


func _party_attack(attacker_index: int) -> void:
	var target_enemy := _first_living_enemy()
	if target_enemy == null:
		return
	var member: CharacterData = GameState.party[attacker_index]
	match member.id:
		&"hero":
			# Priority: heal a wounded ally with Hoimi > Heavy Strike > basic attack.
			if GameState.hero_hoimi_amount(attacker_index) > 0 and _heal_target_index() != -1 and GameState.spend_mp(attacker_index, HERO_HOIMI_MP_COST):
				await _hero_hoimi_spell(attacker_index)
			else:
				var damage_mult: float = GameState.hero_attack_multiplier()
				if damage_mult > 1.0 and not GameState.spend_mp(attacker_index, HERO_HEAVY_STRIKE_MP_COST):
					damage_mult = 1.0
				await _basic_party_attack(attacker_index, target_enemy, damage_mult)
		&"mage":
			# Lightning Bolt (single + chain) takes priority over the broader
			# Firewall when both are learned, since it's the cheaper option.
			if GameState.mage_lightning_damage(attacker_index) > 0 and GameState.spend_mp(attacker_index, MAGE_LIGHTNING_MP_COST):
				await _mage_lightning_attack(attacker_index, target_enemy)
			elif GameState.mage_firewall_unlocked(attacker_index) and GameState.spend_mp(attacker_index, MAGE_FIREBURST_MP_COST):
				await _mage_firewall_attack(attacker_index)
			else:
				await _basic_party_attack(attacker_index, target_enemy)
		&"priest":
			if GameState.priest_heal_amount() > 0 and _heal_target_index() != -1 and GameState.spend_mp(attacker_index, PRIEST_PRAYER_MP_COST):
				await _priest_heal_spell(attacker_index)
			elif GameState.priest_holy_damage(attacker_index) > 0 and GameState.spend_mp(attacker_index, PRIEST_HOLY_STRIKE_MP_COST):
				await _priest_holy_strike(attacker_index, target_enemy)
			else:
				await _basic_party_attack(attacker_index, target_enemy)
		&"thief":
			var can_pilfer: bool = GameState.thief_steal_chance() > 0.0 and GameState.spend_mp(attacker_index, THIEF_PILFER_MP_COST)
			if can_pilfer:
				await _thief_attack(attacker_index, target_enemy)
			else:
				await _basic_party_attack(attacker_index, target_enemy)
		_:
			await _basic_party_attack(attacker_index, target_enemy)


func _basic_party_attack(attacker_index: int, target_enemy: Enemy, damage_mult: float = 1.0):
	if not _running or not is_instance_valid(target_enemy) or not target_enemy.is_alive():
		return 0
	var member: CharacterData = GameState.party[attacker_index]
	_log_label.text = "%s의 공격!" % member.display_name
	await _battle_pause(ATTACK_CALL_DURATION)
	if not _running or not is_instance_valid(target_enemy) or not target_enemy.is_alive():
		return 0
	var atk: int = GameState.effective_attack(attacker_index)
	var crit: Dictionary = GameState.roll_crit()
	var damage: int = int(round(float(atk) * damage_mult * float(crit["mult"])))
	# Plain attacks (damage_mult == 1.0) land with no FX — just a thud. Only
	# the heavy_strike multiplier promotes the swing into a full slash effect.
	var fx: Texture2D = member.attack_effect if damage_mult > 1.0 else null
	if damage_mult > 1.0:
		EventBus.party_skill_activated.emit(attacker_index, &"heavy_strike")
	var dealt: int = target_enemy.take_damage(damage, crit["is_crit"], fx)
	var target_name: String = target_enemy.data.display_name if target_enemy.data else "Enemy"
	await _battle_pause(IMPACT_MESSAGE_DELAY)
	var tag: String = "%s에게 %d포인트 데미지!!" % [target_name, dealt]
	if crit["is_crit"]:
		tag = "회심의 일격! " + tag
	_log_label.text = tag
	await _battle_pause(RESULT_MESSAGE_DURATION)
	return dealt


func _mage_firewall_attack(attacker_index: int) -> void:
	var member: CharacterData = GameState.party[attacker_index]
	var targets: Array[Enemy] = _living_enemies()
	var target_count: int = targets.size()
	if target_count <= 0:
		return
	EventBus.party_skill_activated.emit(attacker_index, &"fireburst")
	_log_label.text = "%s's Firewall!" % member.display_name
	await _battle_pause(ATTACK_CALL_DURATION)
	var crit: Dictionary = GameState.roll_crit()
	var damage: int = int(round(float(GameState.mage_firewall_damage(attacker_index)) * float(crit["mult"])))
	var total_dealt: int = 0
	for i in target_count:
		if is_instance_valid(targets[i]) and targets[i].is_alive():
			total_dealt += targets[i].take_damage(damage, crit["is_crit"], member.attack_effect)
	await _battle_pause(IMPACT_MESSAGE_DELAY)
	var tag: String = "%d마리에게 %d포인트 데미지!!" % [target_count, total_dealt]
	if crit["is_crit"]:
		tag = "회심의 일격! " + tag
	_log_label.text = tag
	await _battle_pause(RESULT_MESSAGE_DURATION)


func _priest_heal_spell(attacker_index: int) -> void:
	var heal_target: int = _heal_target_index()
	if heal_target == -1:
		heal_target = _lowest_wounded_party_index()
	if heal_target == -1:
		return
	var member: CharacterData = GameState.party[attacker_index]
	var target: CharacterData = GameState.party[heal_target]
	EventBus.party_skill_activated.emit(attacker_index, &"battle_prayer")
	_log_label.text = "%s's Heal!" % member.display_name
	await _battle_pause(ATTACK_CALL_DURATION)
	var before_hp: int = GameState.party_hp[heal_target]
	GameState.heal_party_member(heal_target, GameState.priest_heal_amount())
	var healed: int = GameState.party_hp[heal_target] - before_hp
	_log_label.text = "%s의 HP가 %d 회복됐다!" % [target.display_name, healed]
	await _battle_pause(RESULT_MESSAGE_DURATION)


## Hero's Hoimi: small targeted heal on the most wounded ally. Mirrors the
## priest heal pipeline but draws from a separate effect key so the two
## can stack without conflict.
func _hero_hoimi_spell(attacker_index: int) -> void:
	var heal_target: int = _heal_target_index()
	if heal_target == -1:
		heal_target = _lowest_wounded_party_index()
	if heal_target == -1:
		return
	var member: CharacterData = GameState.party[attacker_index]
	var target: CharacterData = GameState.party[heal_target]
	EventBus.party_skill_activated.emit(attacker_index, &"hoimi")
	_log_label.text = "%s's Hoimi!" % member.display_name
	await _battle_pause(ATTACK_CALL_DURATION)
	var before_hp: int = GameState.party_hp[heal_target]
	GameState.heal_party_member(heal_target, GameState.hero_hoimi_amount(attacker_index))
	var healed: int = GameState.party_hp[heal_target] - before_hp
	_log_label.text = "%s의 HP가 %d 회복됐다!" % [target.display_name, healed]
	await _battle_pause(RESULT_MESSAGE_DURATION)


## Mage's Lightning Bolt: deal full damage to the primary target, then with
## chain_chance roll, hit one extra living enemy for half damage. Uses the
## fire FX for now since it's the closest existing texture.
func _mage_lightning_attack(attacker_index: int, target_enemy: Enemy) -> void:
	if not is_instance_valid(target_enemy) or not target_enemy.is_alive():
		return
	var member: CharacterData = GameState.party[attacker_index]
	EventBus.party_skill_activated.emit(attacker_index, &"lightning_bolt")
	_log_label.text = "%s's Lightning Bolt!" % member.display_name
	await _battle_pause(ATTACK_CALL_DURATION)
	var base_damage: int = GameState.mage_lightning_damage(attacker_index)
	var crit: Dictionary = GameState.roll_crit()
	var primary_damage: int = int(round(float(base_damage) * float(crit["mult"])))
	var total_dealt: int = target_enemy.take_damage(primary_damage, crit["is_crit"], member.attack_effect)
	var primary_name: String = target_enemy.data.display_name if target_enemy.data else "Enemy"
	# Chain to one adjacent living enemy at half damage.
	var chained_to: Enemy = null
	if GameState.mage_lightning_chain_chance(attacker_index) > 0.0 and randf() < GameState.mage_lightning_chain_chance(attacker_index):
		for other: Enemy in _living_enemies():
			if other == target_enemy or not is_instance_valid(other) or not other.is_alive():
				continue
			chained_to = other
			break
	if chained_to != null:
		var chain_damage: int = maxi(1, int(round(float(primary_damage) * 0.5)))
		total_dealt += chained_to.take_damage(chain_damage, false, member.attack_effect)
	await _battle_pause(IMPACT_MESSAGE_DELAY)
	var tag: String = "%s에게 %d포인트 데미지!!" % [primary_name, total_dealt]
	if chained_to != null:
		tag = "체인! " + tag
	if crit["is_crit"]:
		tag = "회심의 일격! " + tag
	_log_label.text = tag
	await _battle_pause(RESULT_MESSAGE_DURATION)


## Priest's Holy Strike: chip damage to one enemy that also tops the
## priest up for a smaller amount. The dual nature lets it pull double
## duty as both attack and emergency heal when the main Heal is overkill.
func _priest_holy_strike(attacker_index: int, target_enemy: Enemy) -> void:
	if not is_instance_valid(target_enemy) or not target_enemy.is_alive():
		return
	var member: CharacterData = GameState.party[attacker_index]
	EventBus.party_skill_activated.emit(attacker_index, &"holy_strike")
	_log_label.text = "%s's Holy Strike!" % member.display_name
	await _battle_pause(ATTACK_CALL_DURATION)
	var damage: int = GameState.priest_holy_damage(attacker_index)
	var crit: Dictionary = GameState.roll_crit()
	var final_damage: int = int(round(float(damage) * float(crit["mult"])))
	var dealt: int = target_enemy.take_damage(final_damage, crit["is_crit"], member.attack_effect)
	var target_name: String = target_enemy.data.display_name if target_enemy.data else "Enemy"
	# Self-heal rider — does nothing if priest is already at full HP.
	var heal_amount: int = GameState.priest_holy_self_heal(attacker_index)
	var before_hp: int = GameState.party_hp[attacker_index]
	if heal_amount > 0:
		GameState.heal_party_member(attacker_index, heal_amount)
	var healed: int = GameState.party_hp[attacker_index] - before_hp
	await _battle_pause(IMPACT_MESSAGE_DELAY)
	var tag: String = "%s에게 %d데미지!" % [target_name, dealt]
	if healed > 0:
		tag += " (%s HP +%d)" % [member.display_name, healed]
	if crit["is_crit"]:
		tag = "회심의 일격! " + tag
	_log_label.text = tag
	await _battle_pause(RESULT_MESSAGE_DURATION)


func _priest_heal_attack(attacker_index: int, target_enemy: Enemy) -> void:
	var dealt: int = await _basic_party_attack(attacker_index, target_enemy, GameState.priest_attack_multiplier())
	var heal_target: int = _lowest_wounded_party_index()
	if heal_target == -1:
		return
	var before_hp: int = GameState.party_hp[heal_target]
	GameState.heal_party_member(heal_target, GameState.priest_heal_amount())
	var healed: int = GameState.party_hp[heal_target] - before_hp
	if healed > 0:
		_log_label.text = "%s의 HP가 %d 회복됐다!" % [GameState.party[heal_target].display_name, healed]
		await _battle_pause(RESULT_MESSAGE_DURATION)


func _thief_attack(attacker_index: int, target_enemy: Enemy) -> void:
	EventBus.party_skill_activated.emit(attacker_index, &"pilfer")
	await _basic_party_attack(attacker_index, target_enemy)
	var stolen: int = target_enemy.try_steal_gold(GameState.thief_steal_chance(), GameState.thief_steal_gold_amount())
	if stolen <= 0:
		return
	GameState.add_gold(stolen)
	_log_label.text = "%s는 %dG를 훔쳤다!" % [GameState.party[attacker_index].display_name, stolen]
	await _battle_pause(RESULT_MESSAGE_DURATION)


func _enemy_attack(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return
	EventBus.battle_window_enemy_attack_started.emit(self)
	var alive_indices: Array[int] = []
	for i in GameState.party_size():
		if GameState.is_alive(i):
			alive_indices.append(i)
	if alive_indices.is_empty():
		return
	var target_index: int = alive_indices.pick_random()
	var target: CharacterData = GameState.party[target_index]
	var attacker_name: String = enemy.data.display_name if enemy.data else "Enemy"
	_log_label.text = "%s의 공격!" % attacker_name
	await _battle_pause(ATTACK_CALL_DURATION)
	if not _running or not is_instance_valid(enemy) or not enemy.is_alive() or not GameState.is_alive(target_index):
		return
	if GameState.roll_evade(target_index):
		enemy.play_attack_lunge()
		await _battle_pause(IMPACT_MESSAGE_DELAY)
		if not _running:
			return
		_log_label.text = "%s는 몸을 피했다!" % target.display_name
		await _battle_pause(RESULT_MESSAGE_DURATION)
		return
	var dealt: int = max(1, enemy.attack - GameState.effective_defense(target_index))
	enemy.play_attack_lunge()
	GameState.damage_party_member(target_index, dealt)
	await _battle_pause(IMPACT_MESSAGE_DELAY)
	if not _running:
		return
	_log_label.text = "%s에게 %d포인트 데미지!!" % [target.display_name, dealt]
	await _battle_pause(RESULT_MESSAGE_DURATION)


# ─── Enemy callbacks ──────────────────────────────────────────────────
func _on_enemy_hp_changed(_current: int, _max_hp: int) -> void:
	_refresh_hp_label()


func _on_enemy_died(_enemy: Enemy) -> void:
	var reward: int = GameState.modify_gold_reward(_enemy.gold_reward)
	GameState.add_gold(reward)
	_earned_gold_total += reward
	_earned_recovery_orbs += 1
	if _enemy.data:
		_earned_xp_total += GameState.scaled_enemy_xp_reward(_enemy.data)
		_roll_item_drop()
	_refresh_hp_label()
	if not _living_enemies().is_empty():
		var defeated_name: String = _enemy.data.display_name if _enemy.data else "Enemy"
		_log_label.text = "%s%s 쓰러뜨렸다! +%dG" % [defeated_name, _object_particle(defeated_name), reward]
		return
	_running = false
	_turn_timer.stop()
	_log_label.text = "몬스터를 모두 쓰러뜨렸다! +%dG" % _earned_gold_total
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


## Returns the most wounded ally only if they are below the heal threshold.
## Used to gate priest auto-casting so chip damage doesn't trigger heal spam.
func _heal_target_index() -> int:
	var candidate: int = _lowest_wounded_party_index()
	if candidate == -1:
		return -1
	var max_hp: int = GameState.effective_max_hp(candidate)
	if max_hp <= 0:
		return -1
	var ratio: float = float(GameState.party_hp[candidate]) / float(max_hp)
	if ratio > PRIEST_HEAL_HP_RATIO_THRESHOLD:
		return -1
	return candidate


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
		var current_row_count: int = _enemy_row_counts[row_index]
		if index < row_start + current_row_count:
			row = row_index
			break
		row_start += current_row_count
	var selected_row_count: int = _enemy_row_counts[row]
	var column: int = index - row_start
	var width: float = float(selected_row_count - 1) * spacing.x
	var height: float = float(rows - 1) * spacing.y
	return Vector2(
		float(column) * spacing.x - width * 0.5,
		float(row) * spacing.y - height * 0.5
	)
