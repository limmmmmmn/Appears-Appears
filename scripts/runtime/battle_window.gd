class_name BattleWindow
extends Control

## A single auto-battle window. Self-contained: spawned, ticks turns, closes itself.
## Runs in parallel with up to 100 sibling windows — must stay independent.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

@export var enemy_data: EnemyData
@export var turn_interval: float = 0.5
@export var close_delay: float = 0.35

## How long to linger at spawn center before sliding to the assigned slot.
@export var slide_delay: float = 0.3
@export var slide_duration: float = 0.3
## "쭈욱" intro: window erupts from the encounter point and pops out to its slot.
@export var open_duration: float = 0.24

@onready var _name_label: Label = %NameLabel
@onready var _hp_label: Label = %HPLabel
@onready var _log_label: Label = %LogLabel
@onready var _enemy_anchor: Node2D = %EnemyAnchor
@onready var _turn_timer: Timer = $TurnTimer
@onready var _background: Panel = $Background
@onready var _background_image: TextureRect = %BackgroundImage
@onready var _log_panel: Panel = $LogPanel

const ACTOR_PARTY: int = 0
const ACTOR_ENEMY: int = 1

## Min window size (ratio-fit floor). Was bumped to 176×132 for the (now removed)
## manual-combat command row; restored to the compact 4:3 the field was tuned for.
const BASE_WINDOW_SIZE: Vector2 = Vector2(104.0, 78.0)  ## ~20% smaller — compact, dice-like card
## Manual combat (before the 자동 전투 upgrade) reuses the auto window's bottom log-box
## strip for the command row — SAME window size as auto. Matches LogPanel's top inset
## in battle_window.tscn so the buttons land exactly where the log text was.
const COMMAND_STRIP_OFFSET_TOP: float = -34.0
const ENEMY_SPRITE_SIZE: Vector2 = Vector2(16.0, 16.0)
const ENEMY_SPACING_X_MIN: float = 18.0
const ENEMY_SPACING_X_MAX: float = 34.0
const ENEMY_ROW_HEIGHT_MIN: float = 22.0
const ENEMY_ROW_HEIGHT_MAX: float = 30.0
const ENEMY_SIDE_PADDING: float = 12.0
const ENEMY_AREA_TOP: float = 8.0
const ENEMY_AREA_BOTTOM: float = 40.0
const TARGET_WINDOW_RATIO: float = 4.0 / 3.0
const DIAMOND_EDGE_WEIGHT: float = 0.5
const CRASH_FLASH_COLOR: Color = Color(1.0, 0.48, 0.12, 1.0)
const WINDOW_FLASH_HOLD_DURATION: float = 0.16
const WINDOW_FLASH_FADE_DURATION: float = 0.42
const ORC_BUMP_DAMAGE_MULTIPLIER: float = 0.5
const POSTER_DARK_TEXT: Color = Color(0.1, 0.08, 0.07, 1.0)
const DEFAULT_WINDOW_BG: Color = Color(0.3529412, 0.70980394, 0.32156864, 1.0)  ## = field green
const DQ_WINDOW_BG: Color = Color(0.3529412, 0.70980394, 0.32156864, 1.0)
const DQ_WINDOW_BORDER: Color = Color(0, 0, 0, 1.0)              ## black window edge (retro)
const DQ_WINDOW_TEXT: Color = Color(1.0, 1.0, 1.0, 1.0)
## Classic Dragon-Quest battle screen: pure black with crisp white-bordered windows.
const DQ_BATTLE_BG: Color = Color(0.0, 0.0, 0.0, 1.0)
const DQ_BATTLE_BORDER: Color = Color(1.0, 1.0, 1.0, 1.0)

# ─── Reward-color system: the card's COLOR = its reward type (shown from spawn) ──
enum Reward { WEAPON, GOLD, HP, XP, RANDOM, OBJET }
const REWARD_LABEL: Dictionary = {
	Reward.WEAPON: "무기", Reward.GOLD: "골드", Reward.HP: "회복", Reward.XP: "경험치", Reward.RANDOM: "?", Reward.OBJET: "획득!",
}
const REWARD_COLOR: Dictionary = {
	Reward.WEAPON: Color(0.85, 0.24, 0.24, 1.0),   ## 빨강
	Reward.GOLD: Color(0.93, 0.60, 0.26, 1.0),     ## 주황
	Reward.HP: Color(0.16, 0.52, 0.28, 1.0),       ## 진한 녹색
	Reward.XP: Color(0.29, 0.41, 0.72, 1.0),       ## 파랑
	Reward.RANDOM: Color(0.55, 0.36, 0.74, 1.0),   ## 보라
	Reward.OBJET: Color(0.16, 0.55, 0.62, 1.0),    ## 청록 — 특별한 오브제 드롭
}
## Spawn weighting (gold most common; weapon/hp/random rarer). OBJET is NOT in the
## weighted roll — it's special-cased one-time (see _roll_reward_type).
const REWARD_WEIGHT: Dictionary = {Reward.WEAPON: 16, Reward.GOLD: 32, Reward.HP: 14, Reward.XP: 20, Reward.RANDOM: 14}
## Per-card chance to surface an un-acquired objet instead of a normal reward.
const OBJET_DROP_CHANCE: float = 0.22
## Objet sprites by id (shown big in the card center). Acquired in this order.
const OBJET_TEX: Dictionary = {
	&"village": preload("res://assets/sprites/objects/village.png"),
	&"campfire": preload("res://assets/sprites/objects/bonfire.png"),
}
## Drop order: each un-acquired objet surfaces in turn (village → campfire → …).
const OBJET_ORDER: Array[StringName] = [&"village", &"campfire"]
const HEAL_PER_CARD: int = 14
var _reward_type: int = Reward.GOLD
## When _reward_type == OBJET, which objet this card grants (e.g. &"village").
var _objet_id: StringName = &""
var _mult: int = 1
var _mult_label: Label
var _face_overlay: Control

const LOG_STEP_DURATION: float = 0.46
## Dragon-Quest manual-attack beats: "○○의 공격!" → (이펙트) → "△△에게 N 데미지!".
const ATTACK_TEXT_DELAY: float = 0.38   ## hold on the attack declaration
const ATTACK_EFFECT_DELAY: float = 0.38 ## hit lands (flash + number) before the result
const DAMAGE_TEXT_DELAY: float = 0.48   ## hold on the damage result

# ─── Chest reward state (post-victory) ────────────────────────────────
## How long the player must hover before the chest pops open.
const CHEST_HOVER_DURATION: float = 1.0
## Chest stays the same size as the battle window (they share one size now), so no
## shrink — keeping this at 1.0 leaves the reward card at scale 1 for crisp nearest
## text. (Was 0.7; the downscale mangled the vector font.)
const CHEST_SCALE: float = 1.0
const CHEST_SHRINK_DURATION: float = 0.3
const CHEST_OPEN_DURATION: float = 0.22
const CHEST_REVEAL_LINGER: float = 1.2
const CHEST_CLOSE_FADE: float = 0.32
## Flip-to-claim card: how long the revealed reward lingers before the card fades.
const CARD_REVEAL_LINGER: float = 0.95
const CARD_BACK_BG: Color = Color(0.16, 0.12, 0.05, 1.0)  ## fancy dark-gold card back
## How many bonus gold the victory itself grants on top of enemy drops.
const VICTORY_GOLD_BONUS: int = 1
const GOLD_ICON: Texture2D = preload("res://assets/sprites/icons/gold.png")
## Reward chests float above active battle windows (which sit at z_index 0) so a
## freshly spawned fight can never bury the box the player needs to claim.
const CHEST_Z_INDEX: int = 50
## Extra pixels of forgiveness around the chest box for hover detection.
const CHEST_HOVER_PADDING: float = 6.0
## When a party member is downed by THIS window's enemy, the fight collapses:
## progress lost, no chest. This is the shatter/vanish animation length.
const COLLAPSE_DURATION: float = 0.34

enum ChestState { NONE, CLOSED, OPENING, REVEALED, CLOSING }

var _enemies: Array[Enemy] = []
var _turn_queue: Array[Dictionary] = []
var _running: bool = false
var _earned_xp_total: int = 0
var _gold_drops_total: int = 0
var _field_drop_position: Vector2 = Vector2.INF
var _item_drops: Array[ItemData] = []
var _enemy_row_counts: Array[int] = [1]
var _planned_enemy_count: int = 0
var _planned_enemy_data: Array[EnemyData] = []
var _window_size_multiplier: float = 1.0
## Chips = monster gold, accrued kill-by-kill (the score panel counts it up). After
## the fight this is the window's final chip value (used by the stack 족보).
var _accumulated_chips: int = 0
## Top score panel: "칩 × 배수". Alone → ×1 grey; the stack manager can override it.
var _score_readout: RichTextLabel
var _stack_chips: int = -1   ## ≥0 when a stack has set a combined readout on this (top) card
var _stack_mult: float = 1.0
var _stack_melds: Array = []  ## 족보 dicts ({name, mult}) of the current stack
var _stack_count: int = 1     ## 전투창 수 in the current stack
var _slide_tween: Tween
var _crash_tween: Tween
var _log_queue: Array[String] = []
var _pending_defeat_logs: Array[String] = []
var _log_sequence_running: bool = false
var _close_started: bool = false
var _opening: bool = false
var _open_tween: Tween

# Chest state (replaces the immediate "close-after-logs" path).
var _pending_chest: bool = false
var _chest_state: int = ChestState.NONE
## Flip-to-claim card state (post-victory).
var _flippable: bool = false
var _flipping: bool = false
var _flip_hint: Label
var _chain_ready: bool = false  ## TOP of a fully-resolved stack → clickable
var _card_back: Control

## The player pressed this card → BattleManager owns the gesture from here: a
## release without movement = click (open the stack), a drag = move the whole stack.
signal grab_started(window: BattleWindow, screen_pos: Vector2)
## Keyboard Enter on the openable top card → BattleManager opens the stack (no mouse).
signal flip_requested(window: BattleWindow)
var _chest_root: Control
var _chest_hover_progress: float = 0.0
var _chest_hover_bar: ProgressBar
var _chest_tween: Tween
## DQ1-style initiative for this fight: +1 선공 (party first), -1 피습 (enemies
## first), 0 보통 (by agility). Applied to the FIRST turn-queue build only.
var _initiative: int = 0
var _initiative_pending: bool = true
## Battle formation gate. When false, the window opens and shows its enemy but does
## NOT tick turns (the foe waits) until arm_combat() is called. Default true keeps
## the classic "fight starts immediately" behavior for modal / non-formation spawns.
var _combat_armed: bool = true

# ─── Manual combat (pre 자동 전투 upgrade) ──────────────────────────────
## The bottom command box ("도윤" titled, Fight/Skill/Item/Run) + target picking.
var _command_panel: Panel
var _command_title: Label
var _command_row: HBoxContainer
## Keyboard command navigation: the enabled buttons (Fight, Run) + which one is picked.
var _cmd_buttons: Array[Button] = []
var _cmd_callables: Array[Callable] = []
var _command_sel: int = 0
var _target_layer: Control
## True while a party member's turn is paused waiting for the player's command.
var _awaiting_command: bool = false
var _command_party_index: int = -1
## True while the Fight target picker is up.
var _selecting_target: bool = false
## Keyboard target picking: the living enemies offered, the highlighted index, and
## the per-enemy highlight visuals (arrow + box) so Enter/arrows drive selection.
var _target_enemies: Array[Enemy] = []
var _target_index: int = 0
var _target_arrows: Array[Label] = []
var _target_boxes: Array[Panel] = []

func _ready() -> void:
	_name_label.show()  # enemy name = the window's small title
	_hp_label.hide()
	_log_label.add_theme_font_size_override("font_size", UITheme.FONT_BATTLE_LOG)
	# LabelSettings overrides the theme font_size + line_spacing, so set BIG font with a
	# very tight (near-touching) line gap so the 2-line "○○의 공격! / N 데미지!" both fit.
	if _log_label.label_settings != null:
		var ls: LabelSettings = _log_label.label_settings.duplicate()
		ls.font_size = 8
		ls.line_spacing = -2   # 행간 살짝 좁힘 (붙지 않게)
		_log_label.label_settings = ls
	_log_label.add_theme_constant_override("line_spacing", -2)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_OFF  # \n controls the 2 lines, no wrap
	_reward_type = _roll_reward_type()  # the card's color = its reward type
	_apply_card_color_chrome()
	# The card root catches mouse (drag to move/stack, click to flip); its children
	# pass through so the root owns the gesture.
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child: Node in [_background, _background_image, _name_label, _hp_label, _log_panel, _log_label]:
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui_input.connect(_on_window_gui_input)
	_turn_timer.wait_time = turn_interval * GameState.battle_turn_interval_multiplier()
	_turn_timer.timeout.connect(_on_turn_tick)
	_spawn_enemy()
	_roll_initiative()
	_rebuild_turn_queue()
	_build_score_readout()
	EventBus.battle_window_opened.emit(self)
	# Weapon (SPEED) and armor (survival) equips both surface "○○ 장착!" in any
	# live fight + a quick celebratory pop.
	EventBus.weapon_equipped.connect(_on_weapon_equipped)
	EventBus.armor_equipped.connect(_on_weapon_equipped)
	_running = true
	# Manual combat (before 자동 전투): strip the card down to enemy + HP bar and put a
	# command box at the bottom. The turn loop pauses on each party member for input.
	if _is_manual_combat():
		_enter_manual_mode()
	# Battle formation: a disarmed window shows its enemy but holds its turns — the
	# foe just WAITS until the hero reaches formation and BattleManager arms it.
	if _combat_armed:
		_turn_timer.start()


func _on_weapon_equipped(weapon_name: String) -> void:
	if not _running or is_chest_active():
		return
	_queue_log("%s 장착!" % weapon_name)
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_QUAD)
	pop.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD)


## Allow spawner to inject data before _ready completes.
func setup(data: EnemyData, field_drop_position: Vector2 = Vector2.INF, window_size_multiplier: float = 1.0) -> void:
	enemy_data = data
	_field_drop_position = field_drop_position
	_window_size_multiplier = maxf(1.0, window_size_multiplier)


func get_expected_window_size() -> Vector2:
	_ensure_enemy_count_planned()
	return _layout_size_for_enemy_count(_planned_enemy_count)


## True while the open intro is animating — the spawner skips drift/push on us
## so the "쭈욱" reveal isn't fought by the window-separation forces.
func is_opening() -> bool:
	return _opening


## Erupt from the encounter point: start as a near-zero dot centered on where the
## enemy was, then pop+travel out to the resting slot the spawner already set on
## `position`. Center pivot keeps the growth anchored to the travelling center.
## Spawn this window in "waiting" mode — enemy visible, no turns. Call BEFORE the
## window enters the tree (before add_child) so _ready respects it.
func disarm_combat() -> void:
	_combat_armed = false


## Begin the fight (battle formation: the hero has reached its spot). Idempotent.
func arm_combat() -> void:
	if _combat_armed:
		return
	_combat_armed = true
	if _running and is_instance_valid(_turn_timer) and _turn_timer.is_stopped():
		_turn_timer.start()
	# Juice: a punch-scale the instant the fight kicks off.
	pivot_offset = size * 0.5
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.12, 1.12), 0.07).set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_open_intro() -> void:
	var rest_position: Vector2 = position
	pivot_offset = size * 0.5
	# Pop open in place at the assigned grid slot (the spawner placed `position`).
	var origin: Vector2 = rest_position + size * 0.5
	position = origin - size * 0.5
	scale = Vector2(0.1, 0.1)
	modulate.a = 0.0
	_opening = true
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(self, "position", rest_position, open_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(self, "scale", Vector2.ONE, open_duration)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(self, "modulate:a", 1.0, open_duration * 0.55)
	_open_tween.chain().tween_callback(_finish_open_intro)


func _finish_open_intro() -> void:
	_opening = false
	scale = Vector2.ONE


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


func claim_gold_drops() -> int:
	var amount: int = _gold_drops_total
	_gold_drops_total = 0
	return amount


func claim_item_drops() -> Array[ItemData]:
	var drops: Array[ItemData] = _item_drops.duplicate()
	_item_drops.clear()
	return drops


func field_drop_position() -> Vector2:
	return _field_drop_position


func apply_window_collision_damage(ratio: float, log_prefix: String = "Window crash", silent_log: bool = false) -> int:
	var total_dealt: int = 0
	var effective_ratio: float = ratio * _window_collision_damage_multiplier(log_prefix)
	for enemy: Enemy in _living_enemies():
		if enemy.data == null:
			continue
		var damage: int = ceili(float(enemy.max_hp) * effective_ratio)
		total_dealt += enemy.take_damage(damage, false, null, false)
	if total_dealt > 0:
		_play_crash_flash()
		_spawn_window_damage_number(total_dealt, _window_damage_label(log_prefix))
		# Bump / window-crash damage skips the text log — the floating damage
		# number + crash flash are enough feedback for ambient collisions.
		# Explicit skills (combo attack) still log so the player understands
		# what they triggered.
		if not silent_log:
			_queue_log("%s!\nEnemies take %d damage." % [log_prefix, total_dealt])
		_flush_pending_defeat_logs()
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


func show_party_bump_counter_damage(_total_amount: int, _ratio: float) -> void:
	# Bump-related: log suppressed. Party damage is already visible via the
	# party HP bars + damage numbers spawned on the party member.
	pass


func show_window_collision_heal(_member_name: String, _amount: int) -> void:
	# Bump-related: log suppressed. The heal still applies in GameState and
	# pops up on the party member box via the existing HP-change feedback.
	pass


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
	if _background_image:
		_background_image.modulate = flash_color.lightened(0.25)
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
	if _background_image:
		_crash_tween.parallel().tween_property(_background_image, "modulate", Color.WHITE, WINDOW_FLASH_FADE_DURATION)\
			.set_trans(Tween.TRANS_QUAD)\
			.set_ease(Tween.EASE_OUT)
	_crash_tween.tween_callback(_apply_card_color_chrome)


func _apply_card_color_chrome() -> void:
	var col: Color = _reward_color()
	_background.add_theme_stylebox_override("panel", _flat_panel_style(col, DQ_WINDOW_BORDER))
	_log_panel.add_theme_stylebox_override("panel", _flat_panel_style(col.darkened(0.28), DQ_WINDOW_BORDER))
	if _background_image:
		_background_image.visible = false
	_apply_label_color(_log_label, DQ_WINDOW_TEXT)
	_apply_label_color(_name_label, DQ_WINDOW_TEXT)
	_apply_label_color(_hp_label, DQ_WINDOW_TEXT)


func _flat_panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.set_corner_radius_all(0)  # 사각형 — retro, no rounded corners
	style.anti_aliasing = false
	return style


func _apply_label_color(label: Label, color: Color) -> void:
	if label == null:
		return
	var settings: LabelSettings = label.label_settings.duplicate()
	settings.font_color = color
	label.label_settings = settings


func _window_bg_color() -> Color:
	return DEFAULT_WINDOW_BG


func _log_bg_color(_bg: Color) -> Color:
	return DQ_WINDOW_BG


func _spawn_window_damage_number(amount: int, label_prefix: String) -> void:
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	add_child(num)
	num.position = Vector2(size.x * 0.5 + randf_range(-18.0, 18.0), 10.0 + randf_range(-2.0, 4.0))
	# z 0 (relative) → stays inside this window's layer; added last so it's on top here.
	num.setup_window_damage(amount, label_prefix)


func _window_damage_label(log_prefix: String) -> String:
	if log_prefix.to_lower().contains("combo"):
		return "COMBO"
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
	_set_log("%s appears!" % _name_label.text)


func _ensure_enemy_plan() -> void:
	if _planned_enemy_count > 0:
		return
	_planned_enemy_count = _enemies_per_window()
	_planned_enemy_data = _plan_enemy_mix(_planned_enemy_count)


func _ensure_enemy_count_planned() -> void:
	_ensure_enemy_plan()


func _enemies_per_window() -> int:
	# System 1 + 랜덤 마릿수: the tier's level-based count (1→5, capped in Balance)
	# plus any legacy skill bonus sets the CEILING; the actual headcount is a
	# random 1..ceiling. A Lv4 slime window is now 1~4 bodies, not always 4.
	var tier_id: StringName = GameState.tier_id_for_enemy_data(enemy_data)
	var ceiling: int = maxi(1, GameState.enemy_spawn_count(tier_id) + GameState.enemies_per_window_bonus())
	return randi_range(1, ceiling)


func _plan_enemy_mix(total: int) -> Array[EnemyData]:
	# 종류 섞임: when 2+ enemy types are unlocked ("On"), a fight may blend in
	# other types as 양념. Hard rule — the BASE enemy (the one the player met)
	# must stay numerically dominant: every other type's count ≤ base count, so
	# the fight keeps the base's identity (e.g. base=슬라임 → 슬박오 ✓, 슬슬박 ✓,
	# 슬박박 ✗). With one type unlocked it degrades to a homogeneous pile.
	var others: Array[EnemyData] = _mixable_enemy_pool()
	others.shuffle()

	# How many DISTINCT other types to season this fight with (0 = pure base).
	var max_extra: int = mini(others.size(), maxi(0, total - 1))
	var extra_types: Array[EnemyData] = others.slice(0, randi_range(0, max_extra))
	var k: int = extra_types.size()
	if k == 0:
		var pure: Array[EnemyData] = []
		for i in total:
			pure.append(enemy_data)
		return pure

	# Pick the base count `b` so the rest (total-b) can be split among the k
	# others with each share in [1, b] (1 ⇒ every chosen type appears, b ⇒ ties
	# allowed). Feasible range: b ∈ [ceil(total/(k+1)), total-k].
	var b_min: int = int(ceil(float(total) / float(k + 1)))
	var b_max: int = total - k
	var base_count: int = randi_range(b_min, maxi(b_min, b_max))

	# Seed each chosen type with 1, then scatter the remainder, never letting any
	# other type's count exceed `base_count`.
	var other_counts: Array[int] = []
	other_counts.resize(k)
	other_counts.fill(1)
	var remaining: int = total - base_count - k
	while remaining > 0:
		var growable: Array[int] = []
		for i in k:
			if other_counts[i] < base_count:
				growable.append(i)
		if growable.is_empty():
			break  # everything capped at base_count; leftover stays with base
		other_counts[growable[randi() % growable.size()]] += 1
		remaining -= 1

	var planned: Array[EnemyData] = []
	for i in base_count + remaining:
		planned.append(enemy_data)
	for i in k:
		for j in other_counts[i]:
			planned.append(extra_types[i])
	planned.shuffle()
	return planned


## Other unlocked ("On") enemy types available to season a fight, excluding the
## base type. Empty when only the base type is unlocked.
func _mixable_enemy_pool() -> Array[EnemyData]:
	var base_id: StringName = GameState.tier_id_for_enemy_data(enemy_data)
	var out: Array[EnemyData] = []
	for id: StringName in GameState.unlocked_tier_ids:
		if id == base_id:
			continue
		var ed: EnemyData = GameState.tier_enemy_data(id)
		if ed != null:
			out.append(ed)
	return out


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


# ─── Turn loop ─────────────────────────────────────────────────────────
## Auto once 자동 전투 is bought; until then party turns pause for the command box.
func _on_turn_tick() -> void:
	if not _running:
		return
	if _awaiting_command:  # holding for the player's manual pick — timer is stopped anyway
		return
	if _is_log_busy():
		return
	if _living_enemies().is_empty() or GameState.is_party_wiped():
		return
	var actor: Dictionary = _next_actor()
	if actor.is_empty():
		return
	if int(actor["type"]) == ACTOR_PARTY:
		if _is_manual_combat():
			_begin_manual_command(actor)
			return
		_party_attack(int(actor["party_index"]))
	else:
		_enemy_attack(actor["enemy"])


func _party_attack(attacker_index: int, target_override: Enemy = null) -> void:
	var target_enemy: Enemy = target_override if (target_override != null and is_instance_valid(target_override) and target_override.is_alive()) else _first_living_enemy()
	if target_enemy == null:
		return
	# Juice: the formation avatar for this member lunges forward on its attack turn.
	EventBus.party_member_attacked.emit(attacker_index)
	var member: CharacterData = GameState.party[attacker_index]
	# Behavior keys off the member's innate TRAIT, not their id — so future
	# variants of the same class can act differently.
	match Balance.character_trait(member.id):
		&"aoe":
			_mage_splash_attack(attacker_index)
		&"support":
			_priest_heal_attack(attacker_index, target_enemy)
		&"single":
			_basic_party_attack(attacker_index, target_enemy, GameState.hero_attack_multiplier())
		_:
			# &"gold" (도적, gold is passive) and any other trait → basic attack.
			_basic_party_attack(attacker_index, target_enemy)


func _basic_party_attack(attacker_index: int, target_enemy: Enemy, damage_mult: float = 1.0) -> int:
	var member: CharacterData = GameState.party[attacker_index]
	var atk: int = GameState.effective_attack(attacker_index)
	var crit: Dictionary = GameState.roll_crit()
	# The attacker's WEAPON-TYPE multiplier scales damage here (per-member SPEED
	# component of the gold/sec formula); base stat stays clean.
	var damage: int = int(round(float(atk) * damage_mult * float(crit["mult"]) * GameState.member_weapon_multiplier(attacker_index)))
	# Manual = Dragon-Quest beats: 공격 텍스트 → 이펙트 → 데미지 텍스트 (staggered).
	if _is_manual_combat():
		return await _play_party_attack_seq(member, target_enemy, damage, bool(crit["is_crit"]))
	# Auto = fast combined message (the card-game pace must stay snappy).
	var dealt: int = target_enemy.take_damage(damage, crit["is_crit"], member.attack_effect)
	_spawn_window_damage_number(dealt, "")
	var enemy_name: String = target_enemy.data.display_name if target_enemy.data else "적"
	var crit_text := "  회심의 일격!" if crit["is_crit"] else ""
	_queue_log("%s의 공격!\n%s에게 %d의 데미지!%s" % [member.display_name, enemy_name, dealt, crit_text])
	_flush_pending_defeat_logs()
	return dealt


## DQ-style 3-beat attack. Holds the log "busy" (the turn loop waits on _is_log_busy)
## so the next turn doesn't barge in mid-narration.
func _play_party_attack_seq(member: CharacterData, target_enemy: Enemy, damage: int, is_crit: bool) -> int:
	_log_sequence_running = true
	# 1) 공격 텍스트
	_set_log("%s의 공격!" % member.display_name)
	await get_tree().create_timer(ATTACK_TEXT_DELAY).timeout
	if not is_inside_tree() or not is_instance_valid(target_enemy):
		_log_sequence_running = false
		return 0
	# 2) 공격 이펙트 — 피격 적용 + 떠오르는 데미지 숫자
	var dealt: int = target_enemy.take_damage(damage, is_crit, member.attack_effect)
	_spawn_window_damage_number(dealt, "")
	await get_tree().create_timer(ATTACK_EFFECT_DELAY).timeout
	if not is_inside_tree():
		_log_sequence_running = false
		return dealt
	# 3) 데미지 텍스트
	var enemy_name: String = target_enemy.data.display_name if (is_instance_valid(target_enemy) and target_enemy.data) else "적"
	var crit_text := "  회심의 일격!" if is_crit else ""
	_set_log("%s의 공격!\n%s에게 %d의 데미지!%s" % [member.display_name, enemy_name, dealt, crit_text])
	await get_tree().create_timer(DAMAGE_TEXT_DELAY).timeout
	# 4) 마무리: busy 해제 → 대기 중인 "쓰러뜨렸다!"/체스트 처리
	_log_sequence_running = false
	_flush_pending_defeat_logs()
	if not _log_queue.is_empty():
		_drain_log_queue()
	elif _pending_chest and _chest_state == ChestState.NONE:
		_pending_chest = false
		_enter_flip_card_state()
	return dealt


func _mage_splash_attack(attacker_index: int) -> void:
	var member: CharacterData = GameState.party[attacker_index]
	var targets: Array[Enemy] = _living_enemies()
	var target_count: int = mini(targets.size(), 1 + GameState.member_aoe_extra_targets(attacker_index))
	var atk: int = GameState.effective_attack(attacker_index)
	var crit: Dictionary = GameState.roll_crit()
	var damage: int = int(round(float(atk) * GameState.member_aoe_damage_mult(attacker_index) * float(crit["mult"]) * GameState.member_weapon_multiplier(attacker_index)))
	var total_dealt: int = 0
	for i in target_count:
		total_dealt += targets[i].take_damage(damage, crit["is_crit"], member.attack_effect)
	var weapon: String = GameState.current_weapon_name(Balance.character_weapon_type(member.id))
	var crit_text := "  치명타!" if crit["is_crit"] else ""
	_queue_log("%s의 %s 마법!\nx%d  %d 데미지!%s" % [member.display_name, weapon, target_count, total_dealt, crit_text])
	_flush_pending_defeat_logs()


func _priest_heal_attack(attacker_index: int, target_enemy: Enemy) -> void:
	await _basic_party_attack(attacker_index, target_enemy, GameState.priest_attack_multiplier())
	if not _running or not is_inside_tree():
		return
	var heal_target: int = _lowest_wounded_party_index()
	if heal_target == -1:
		return
	var before_hp: int = GameState.party_hp[heal_target]
	GameState.heal_party_member(heal_target, GameState.member_heal_amount(attacker_index))
	var healed: int = GameState.party_hp[heal_target] - before_hp
	if healed > 0:
		_queue_log("%s의 기도!\n%s의 HP가 %d 회복!" % [
			GameState.party[attacker_index].display_name,
			GameState.party[heal_target].display_name,
			healed,
		])


func _thief_attack(attacker_index: int, target_enemy: Enemy) -> void:
	await _basic_party_attack(attacker_index, target_enemy)
	if not _running or not is_inside_tree():
		return
	var stolen: int = target_enemy.try_steal_gold(GameState.thief_steal_chance(), GameState.thief_steal_gold_amount())
	if stolen <= 0:
		return
	GameState.add_gold(stolen)
	_queue_log("%s이(가) %dG 훔쳤다!" % [GameState.party[attacker_index].display_name, stolen])


func _enemy_attack(enemy: Enemy) -> void:
	var alive_indices: Array[int] = []
	for i in GameState.party_size():
		if GameState.is_combat_ready(i):
			alive_indices.append(i)
	if alive_indices.is_empty():
		return
	var target_index: int = alive_indices.pick_random()
	var target: CharacterData = GameState.party[target_index]
	var attacker_name: String = enemy.data.display_name if enemy.data else "Enemy"
	if GameState.roll_evade(target_index):
		enemy.play_attack_lunge()
		_queue_log("%s의 공격!\n%s은(는) 잽싸게 피했다!" % [attacker_name, target.display_name])
		return
	var dealt: int = max(1, enemy.attack)
	enemy.play_attack_lunge()
	GameState.damage_party_member(target_index, dealt)
	_queue_log("%s의 공격!\n%s에게 %d의 데미지!" % [attacker_name, target.display_name, dealt])
	# A single down no longer collapses the fight — the window keeps rolling with the
	# remaining members. Only a FULL party wipe closes windows (BattleManager._on_party
	# _collapsed). The downed member just trails the party until everyone recovers.
	if GameState.is_downed(target_index):
		_queue_log("%s은(는) 쓰러졌다!" % target.display_name)


# ─── Manual combat ─────────────────────────────────────────────────────
## Until 자동 전투 is purchased, the player drives each party member's turn by hand.
func _is_manual_combat() -> bool:
	return not GameState.auto_battle_unlocked


## Strip the card to enemy + HP bar (hide name / score / log / 적 Lv) and build the
## bottom command box. Called once at spawn when starting in manual mode.
func _enter_manual_mode() -> void:
	_name_label.hide()
	# Log stays available: the bottom strip toggles between the command box (player's
	# turn) and the combat log (attacks resolving) — see _begin_manual_command /
	# _on_target_chosen. So the "○○의 공격! N 데미지!" play-by-play is visible.
	if _score_readout != null:
		_score_readout.hide()
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.set_level_label_visible(false)
	_build_command_panel()


## A party member's turn came up in manual mode → stop the clock and ask the player.
func _begin_manual_command(actor: Dictionary) -> void:
	_awaiting_command = true
	_command_party_index = int(actor["party_index"])
	_turn_timer.stop()
	_selecting_target = false
	_clear_target_markers()
	if _command_panel == null:
		_build_command_panel()
	if _log_panel != null:
		_log_panel.hide()   # player's turn → swap the log for the command box
	_command_title.text = GameState.party[_command_party_index].display_name
	_command_sel = 0
	_highlight_command()
	_command_row.show()
	_command_panel.show()


## DQ cursor: the picked command lights up brighter than the rest.
func _highlight_command() -> void:
	for i in _cmd_buttons.size():
		var b: Button = _cmd_buttons[i]
		if not is_instance_valid(b):
			continue
		var col: Color = _reward_color().lightened(0.4) if i == _command_sel else _reward_color()
		b.add_theme_stylebox_override("normal", _flat_panel_style(col, DQ_WINDOW_BORDER))


func _move_command_sel(dir: int) -> void:
	if _cmd_buttons.is_empty():
		return
	_command_sel = wrapi(_command_sel + dir, 0, _cmd_buttons.size())
	_highlight_command()


func _activate_command() -> void:
	if _command_sel >= 0 and _command_sel < _cmd_callables.size():
		_cmd_callables[_command_sel].call()


func _on_fight_pressed() -> void:
	if not _awaiting_command or _selecting_target:
		return
	var living: Array[Enemy] = _living_enemies()
	if living.is_empty():
		return
	_selecting_target = true
	_command_row.hide()
	_command_title.text = "적 선택 ▶"
	_build_target_markers(living)


func _on_run_pressed() -> void:
	if not _awaiting_command:
		return
	_flee()


## Target chosen → resolve that member's attack on it and resume the turn order.
func _on_target_chosen(enemy: Enemy) -> void:
	if not _awaiting_command or enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
		return
	_clear_target_markers()
	_selecting_target = false
	_awaiting_command = false
	var index: int = _command_party_index
	_command_party_index = -1
	_hide_command_panel()
	if _log_panel != null:
		_log_panel.show()   # action resolving → show the combat log (attack + replies)
	_party_attack(index, enemy)
	# Let the enemies (and any further party members) take their turns automatically.
	if _running and not _close_started:
		_turn_timer.start()


## Player backed out of target picking → restore the command buttons.
func _on_target_cancel() -> void:
	if not _selecting_target:
		return
	_clear_target_markers()
	_selecting_target = false
	if _awaiting_command and _command_party_index >= 0:
		_command_title.text = GameState.party[_command_party_index].display_name
		_highlight_command()
		_command_row.show()


func _hide_command_panel() -> void:
	if _command_panel != null:
		_command_panel.hide()
	_clear_target_markers()


func _clear_target_markers() -> void:
	if _target_layer != null and is_instance_valid(_target_layer):
		_target_layer.queue_free()
	_target_layer = null
	_target_enemies.clear()
	_target_arrows.clear()
	_target_boxes.clear()
	_target_index = 0


# ─── Manual-combat UI ──────────────────────────────────────────────────
func _build_command_panel() -> void:
	# Lives in the bottom log-box strip — same footprint as the auto window's LogPanel,
	# so the manual card is exactly the same size as an auto card.
	_command_panel = Panel.new()
	_command_panel.add_theme_stylebox_override("panel", _flat_panel_style(_reward_color().darkened(0.28), DQ_WINDOW_BORDER))
	_command_panel.anchor_left = 0.0
	_command_panel.anchor_top = 1.0
	_command_panel.anchor_right = 1.0
	_command_panel.anchor_bottom = 1.0
	_command_panel.offset_left = 4.0
	_command_panel.offset_top = COMMAND_STRIP_OFFSET_TOP
	_command_panel.offset_right = -4.0
	_command_panel.offset_bottom = -4.0
	_command_panel.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks so the card isn't dragged
	_command_panel.hide()
	add_child(_command_panel)
	# Buttons fill the strip (tiny, four across); the member-name title floats on the
	# strip's top border above them.
	_command_row = HBoxContainer.new()
	_command_row.anchor_right = 1.0
	_command_row.anchor_bottom = 1.0
	_command_row.offset_left = 2.0
	_command_row.offset_top = 2.0
	_command_row.offset_right = -2.0
	_command_row.offset_bottom = -2.0
	_command_row.add_theme_constant_override("separation", 1)
	_command_panel.add_child(_command_row)
	var fight_btn := _make_command_button("Fight", _on_fight_pressed, true)
	_make_command_button("Skill", Callable(), false)  # not ready yet
	_make_command_button("Item", Callable(), false)   # not ready yet
	var run_btn := _make_command_button("Run", _on_run_pressed, true)
	# Keyboard nav targets: only the enabled commands. Left/Right cycles, Enter picks.
	_cmd_buttons = [fight_btn, run_btn]
	_cmd_callables = [_on_fight_pressed, _on_run_pressed]
	_command_sel = 0
	# Member-name title sitting on the box's top-left border (its bg breaks the line).
	# Uses the theme font (Korean-capable) — member names are Korean (e.g. "도윤").
	_command_title = Label.new()
	_command_title.add_theme_font_size_override("font_size", 7)
	_command_title.add_theme_color_override("font_color", DQ_WINDOW_TEXT)
	var title_bg := PanelContainer.new()
	title_bg.add_theme_stylebox_override("panel", _flat_panel_style(_reward_color(), _reward_color()))
	title_bg.position = Vector2(7.0, -6.0)
	title_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bg.add_child(_command_title)
	_command_panel.add_child(title_bg)


func _make_command_button(text: String, on_press: Callable, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 6)
	b.add_theme_constant_override("h_separation", 0)
	# Retro cell look: card-color fill, black 1px border, white text (matches the card).
	var base: Color = _reward_color()
	b.add_theme_stylebox_override("normal", _flat_panel_style(base, DQ_WINDOW_BORDER))
	b.add_theme_stylebox_override("hover", _flat_panel_style(base.lightened(0.12), DQ_WINDOW_BORDER))
	b.add_theme_stylebox_override("pressed", _flat_panel_style(base.darkened(0.2), DQ_WINDOW_BORDER))
	b.add_theme_stylebox_override("disabled", _flat_panel_style(base.darkened(0.34), Color(0.32, 0.32, 0.34, 1.0)))
	b.add_theme_color_override("font_color", DQ_WINDOW_TEXT)
	b.add_theme_color_override("font_hover_color", DQ_WINDOW_TEXT)
	b.add_theme_color_override("font_pressed_color", DQ_WINDOW_TEXT)
	b.add_theme_color_override("font_disabled_color", Color(0.56, 0.56, 0.6, 1.0))
	b.disabled = not enabled
	if enabled and on_press.is_valid():
		b.pressed.connect(on_press)
	_command_row.add_child(b)
	return b


## A clickable marker + highlight (arrow ▼ and box) over each living enemy, plus a
## full-card cancel behind them. Mouse clicks a marker; Enter/arrows drive it too.
func _build_target_markers(living: Array[Enemy]) -> void:
	_clear_target_markers()
	_target_layer = Control.new()
	_target_layer.anchor_right = 1.0
	_target_layer.anchor_bottom = 1.0
	_target_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_target_layer)
	# Behind the markers: clicking empty space cancels back to the command buttons.
	var cancel_bg := Button.new()
	cancel_bg.flat = true
	cancel_bg.focus_mode = Control.FOCUS_NONE
	cancel_bg.anchor_right = 1.0
	cancel_bg.anchor_bottom = 1.0
	cancel_bg.pressed.connect(_on_target_cancel)
	_target_layer.add_child(cancel_bg)
	for enemy: Enemy in living:
		if enemy == null or not is_instance_valid(enemy):
			continue
		_target_enemies.append(enemy)
		var local: Vector2 = _enemy_anchor.position + enemy.position
		# Highlight box around the selected enemy (shown only on the current target).
		var box := Panel.new()
		box.add_theme_stylebox_override("panel", _flat_panel_style(Color(0, 0, 0, 0), Color(1.0, 0.95, 0.4, 1.0)))
		var box_size := Vector2(ENEMY_SPRITE_SIZE.x + 8.0, ENEMY_SPRITE_SIZE.y + 8.0)
		box.size = box_size
		box.position = local - box_size * 0.5
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_target_layer.add_child(box)
		_target_boxes.append(box)
		var marker := Button.new()
		marker.flat = true
		marker.focus_mode = Control.FOCUS_NONE
		var marker_size := Vector2(24.0, 24.0)
		marker.size = marker_size
		marker.position = local - marker_size * 0.5
		marker.pressed.connect(_on_target_chosen.bind(enemy))
		_target_layer.add_child(marker)
		var arrow := Label.new()
		arrow.text = "▼"
		arrow.add_theme_font_size_override("font_size", 10)
		arrow.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4, 1.0))
		arrow.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		arrow.add_theme_constant_override("shadow_offset_x", 1)
		arrow.add_theme_constant_override("shadow_offset_y", 1)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.position = local + Vector2(-5.0, -ENEMY_SPRITE_SIZE.y * 0.5 - 12.0)
		_target_layer.add_child(arrow)
		_target_arrows.append(arrow)
	_target_index = 0
	_update_target_highlight()


## Show the arrow + box only on the currently-highlighted target.
func _update_target_highlight() -> void:
	for i in _target_arrows.size():
		var selected: bool = (i == _target_index)
		if i < _target_arrows.size() and is_instance_valid(_target_arrows[i]):
			_target_arrows[i].visible = selected
		if i < _target_boxes.size() and is_instance_valid(_target_boxes[i]):
			_target_boxes[i].visible = selected


## Arrow keys cycle the highlighted enemy (wraps). dir +1 = next, -1 = previous.
func _move_target_highlight(dir: int) -> void:
	if _target_enemies.is_empty():
		return
	_target_index = wrapi(_target_index + dir, 0, _target_enemies.size())
	_update_target_highlight()


## Enter while picking → attack the highlighted enemy.
func _confirm_target_selection() -> void:
	if _target_index < 0 or _target_index >= _target_enemies.size():
		return
	_on_target_chosen(_target_enemies[_target_index])


# ─── Keyboard control (manual combat) ──────────────────────────────────
## Enter drives the fight (연타): in the command box it presses Fight; while picking a
## target it attacks the highlighted enemy. Arrows move the target highlight.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var is_enter: bool = key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
	# Reward card: Enter flips the openable TOP of a resolved stack (까기) — no mouse.
	if _chain_ready and not _flipping and is_enter:
		flip_requested.emit(self)
		get_viewport().set_input_as_handled()
		return
	if not _awaiting_command:
		return
	if not _selecting_target:
		# Command box: ←/→ (or ↑/↓) move between Fight/Run, Enter picks.
		match key.keycode:
			KEY_LEFT, KEY_UP:
				_move_command_sel(-1)
				get_viewport().set_input_as_handled()
			KEY_RIGHT, KEY_DOWN:
				_move_command_sel(1)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				_activate_command()
				get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_confirm_target_selection()
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_DOWN:
			_move_target_highlight(1)
			get_viewport().set_input_as_handled()
		KEY_LEFT, KEY_UP:
			_move_target_highlight(-1)
			get_viewport().set_input_as_handled()


## Run: flee this fight. No reward; the field repopulates the escaped enemy through
## its normal spawn maintenance. Releases the modal pause / window-cap slot.
func _flee() -> void:
	if _close_started or _chest_state != ChestState.NONE:
		return
	_close_started = true
	_running = false
	_pending_chest = false
	_awaiting_command = false
	_selecting_target = false
	_turn_timer.stop()
	_hide_command_panel()
	_gold_drops_total = 0
	_earned_xp_total = 0
	_item_drops.clear()
	EventBus.battle_window_resolved.emit(self)
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position", position + Vector2(0.0, 12.0), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(_finish_flee)


func _finish_flee() -> void:
	if not is_inside_tree():
		return
	EventBus.battle_window_closed.emit(self)
	queue_free()


# ─── Enemy callbacks ──────────────────────────────────────────────────
func _on_enemy_hp_changed(_current: int, _max_hp: int) -> void:
	_refresh_hp_label()


func _on_enemy_died(_enemy: Enemy) -> void:
	# System 1: every kill grows that enemy tier's level (more spawns + more
	# gold over time). Recorded before reading the reward so the count is live.
	if _enemy.data:
		GameState.record_enemy_kill(GameState.tier_id_for_enemy_data(_enemy.data))
	# Kill gold is paid IMMEDIATELY (GameState._on_enemy_defeated). We still tally it
	# here as the pool the 🟧 GOLD reward card pays AGAIN as a bonus on flip.
	var drop_reward: int = _enemy.gold_reward
	_gold_drops_total += drop_reward
	# Score panel: this kill's gold counts up onto the chip total (with a pop).
	_accumulated_chips += maxi(0, drop_reward)
	_update_score_readout()
	_pop_score_readout()
	if _enemy.data:
		_earned_xp_total += GameState.scaled_enemy_xp_reward(_enemy.data)
	_refresh_hp_label()
	var defeated_name: String = _enemy.data.display_name if _enemy.data else "Enemy"
	if not _living_enemies().is_empty():
		if drop_reward > 0:
			_pending_defeat_logs.append("%s을(를) 쓰러뜨렸다!\n%dG 획득!" % [defeated_name, drop_reward])
		else:
			_pending_defeat_logs.append("%s을(를) 쓰러뜨렸다!" % defeated_name)
		call_deferred("_flush_pending_defeat_logs")
		return
	_running = false
	_turn_timer.stop()
	_add_window_item_drop()
	# Rewards no longer drop onto the field — they're locked inside the chest
	# the window transforms into. Total chest gold = enemy drops + the flat
	# victory bonus (kept so trivial wins still pay something).
	_gold_drops_total += VICTORY_GOLD_BONUS
	_pending_defeat_logs.append("%s을(를) 쓰러뜨렸다!" % defeated_name)
	_pending_chest = true
	call_deferred("_flush_pending_defeat_logs")


func _set_log(text: String) -> void:
	_log_label.text = text


func _queue_log(text: String) -> void:
	if text.is_empty():
		return
	_log_queue.append(text)
	if not _log_sequence_running:
		_drain_log_queue()


func _is_log_busy() -> bool:
	return _log_sequence_running or not _log_queue.is_empty()


func _flush_pending_defeat_logs() -> void:
	if _pending_defeat_logs.is_empty():
		return
	for text: String in _pending_defeat_logs:
		_queue_log(text)
	_pending_defeat_logs.clear()


func _drain_log_queue() -> void:
	if _log_sequence_running:
		return
	_log_sequence_running = true
	while not _log_queue.is_empty() and is_inside_tree():
		_set_log(_log_queue.pop_front())
		await get_tree().create_timer(LOG_STEP_DURATION).timeout
	_log_sequence_running = false
	if _pending_chest and _chest_state == ChestState.NONE:
		_pending_chest = false
		_enter_flip_card_state()


## Reward = loot DROPPED on the field (no chest, no hover). The window bursts away
## and the BattleManager scatters the accumulated gold/items at the encounter spot
## on close; the player clicks them to pick up.
func _drop_rewards_and_close() -> void:
	if _close_started:
		return
	_close_started = true
	_running = false
	_turn_timer.stop()
	# Fight resolved → release the modal pause / stop counting toward the cap.
	EventBus.battle_window_resolved.emit(self)
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.55, 0.55), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(_finish_drop_close)


func _finish_drop_close() -> void:
	if not is_inside_tree():
		return
	# BattleManager._on_battle_window_closed claims + drops the gold/items + XP.
	EventBus.battle_window_closed.emit(self)
	queue_free()


# ─── Flip-to-claim card (post-victory reward) ──────────────────────────
## Fight won → the card sits face-up. It only OPENS once EVERY card in its stack is
## resolved; BattleManager drives the chain (top→bottom) + the merge bonus.
func _enter_flip_card_state() -> void:
	if _close_started or _flippable or _flipping:
		return
	_running = false
	_turn_timer.stop()
	_flippable = true
	# Battle over → the text box disappears; the card shows its reward TYPE big +
	# the multiplier. Build the hint FIRST so the manager's readiness update works.
	_show_reward_face()
	_build_flip_hint()
	# Fight resolved → release modal pause + stop counting toward the multi cap.
	EventBus.battle_window_resolved.emit(self)


# ─── Reward helpers ────────────────────────────────────────────────────
func reward_type_id() -> int:
	return _reward_type


func _reward_color() -> Color:
	return REWARD_COLOR.get(_reward_type, DQ_WINDOW_BG)


func _roll_reward_type() -> int:
	# One-time objet drop: a chance to surface an un-acquired objet (village first).
	var objet: StringName = _pick_available_objet()
	if objet != &"" and randf() < OBJET_DROP_CHANCE:
		_objet_id = objet
		return Reward.OBJET
	var total: int = 0
	for k in REWARD_WEIGHT:
		total += int(REWARD_WEIGHT[k])
	var r: int = randi() % maxi(1, total)
	for k in REWARD_WEIGHT:
		r -= int(REWARD_WEIGHT[k])
		if r < 0:
			return int(k)
	return Reward.GOLD


## The next un-acquired objet that can drop, or &"" if none left. (Just the village
## for now; later objets append to this list.)
func _pick_available_objet() -> StringName:
	for oid in OBJET_ORDER:
		if not GameState.is_objet_acquired(oid):
			return oid
	return &""


## Resolved face: hide the combat UI, show the reward type (center, big) + "x{mult}".
func _show_reward_face() -> void:
	if _name_label != null:
		_name_label.visible = false
	if _log_panel != null:
		_log_panel.visible = false
	if _enemy_anchor != null:
		_enemy_anchor.visible = false
	_face_overlay = Control.new()
	_face_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face_overlay)
	# The tiny top readout is for the FIGHT (chips counting up); on the reward card the
	# labeled breakdown below takes over.
	if _score_readout != null:
		_score_readout.visible = false
	# Objet drop: the tile sprite POPS in the card center — "something different!".
	if _reward_type == Reward.OBJET:
		_show_objet_face()
		return
	_render_reward_face()


## The settlement breakdown on a resolved card. Score is the headline; the reward
## TYPE (회복/장비/…) is just a small "보너스". Rebuilt live as the stack changes.
##   단독: 적 골드 N / 보너스 · 회복
##   스택: [족보 이름] / 적 골드 N / 배수 ×M = 총점 / 보너스 · 회복 / 전투창 K개
func _render_reward_face() -> void:
	if _face_overlay == null or _reward_type == Reward.OBJET:
		return
	for c in _face_overlay.get_children():
		c.queue_free()
	var is_stack: bool = _stack_chips >= 0
	var chips: int = _stack_chips if is_stack else _accumulated_chips
	var mult: float = _stack_mult if is_stack else 1.0
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 1)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_top = 5.0
	vb.offset_bottom = -15.0
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_overlay.add_child(vb)
	# 족보 이름 (스택일 때만)
	if is_stack and not _stack_melds.is_empty():
		var names: Array = []
		for m in _stack_melds:
			names.append(str(m.get("name", "")))
		vb.add_child(_back_label(" · ".join(names), 10, Color(1.0, 0.84, 0.3, 1.0)))
	# 적 골드 (메인 — 적에게서 얻은 골드 = 칩)
	vb.add_child(_face_rich("적 골드 [color=#6aa6ff]%d[/color]" % chips, 11))
	# 배수 + 총점 (멜드 있을 때)
	if mult > 1.0:
		vb.add_child(_face_rich("배수 [color=#ff6a6a]×%s[/color] =[color=#ffd23a] %d[/color]" % [_fmt_mult(mult), int(round(float(chips) * mult))], 10))
	# 보너스 (보상 종류 — 작게)
	vb.add_child(_back_label("보너스 · %s" % str(REWARD_LABEL.get(_reward_type, "?")), 8, Color(0.8, 0.82, 0.86, 1.0)))
	# 쌓인 장수(스택) — 또는 단독이면 "겹치면 족보!" 유도로 스택을 자연스럽게 알림
	if is_stack:
		vb.add_child(_back_label("스택 %d장" % _stack_count, 9, Color(1.0, 0.84, 0.36, 1.0)))
	else:
		vb.add_child(_back_label("겹치면 족보!", 8, Color(0.95, 0.78, 0.42, 1.0)))


## Centered RichTextLabel (bbcode) line for the reward-face breakdown.
func _face_rich(bbcode: String, size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_override("normal_font", load("res://assets/fonts/field_ui_font.tres"))
	r.add_theme_font_size_override("normal_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = "[center]%s[/center]" % bbcode
	return r


## The objet reveal face: the tile sprite pops big in the center over a "획득!" call.
func _show_objet_face() -> void:
	var tex: Texture2D = OBJET_TEX.get(_objet_id, null)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_CENTER)
		icon.offset_left = -22.0
		icon.offset_right = 22.0
		icon.offset_top = -26.0
		icon.offset_bottom = 16.0
		icon.pivot_offset = Vector2(22.0, 21.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face_overlay.add_child(icon)
		icon.scale = Vector2(0.2, 0.2)
		var t := create_tween()
		t.tween_property(icon, "scale", Vector2(1.3, 1.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(icon, "scale", Vector2.ONE, 0.12)
	var lbl := _back_label("획득!", 11, Color(1.0, 0.98, 0.82, 1.0))
	lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	lbl.offset_top = -18.0
	lbl.offset_bottom = -6.0
	_face_overlay.add_child(lbl)


## BattleManager sets the same-color stack count → the visible reward multiplier.
func set_multiplier(n: int) -> void:
	_mult = maxi(1, n)
	if _mult_label != null and not _flipping:
		_mult_label.text = "x%d" % _mult


## Resolved (battle done) and not yet flipping/opened.
func is_resolved() -> bool:
	return _flippable and not _flipping


# ─── Formation 족보 inputs (color / type / count) ──────────────────────
## Reward color = the card's Reward enum (the flush "suit").
func reward_color() -> int:
	return _reward_type


## Enemy "kind" = the tier id of this window's foe (the set/멜드 key).
func enemy_type_id() -> StringName:
	return GameState.tier_id_for_enemy_data(enemy_data) if enemy_data != null else &""


## How many enemies this window holds (the straight/동수 "rank").
func enemy_count() -> int:
	return maxi(1, _planned_enemy_count)


## Chip value = total monster gold accrued from kills (the score base). Falls back to
## a pre-fight estimate before any kill so a freshly-spawned card still reads sanely.
func chip_value() -> int:
	if _accumulated_chips > 0:
		return _accumulated_chips
	if enemy_data == null:
		return enemy_count()
	return maxi(1, GameState.scaled_enemy_gold_reward(enemy_data) * enemy_count())


# ─── Top score panel ("칩 × 배수") ─────────────────────────────────────
func _build_score_readout() -> void:
	_score_readout = RichTextLabel.new()
	_score_readout.bbcode_enabled = true
	_score_readout.fit_content = true
	_score_readout.scroll_active = false
	_score_readout.autowrap_mode = TextServer.AUTOWRAP_OFF
	_score_readout.add_theme_font_override("normal_font", load("res://assets/fonts/field_ui_font.tres"))
	_score_readout.add_theme_font_size_override("normal_font_size", 9)
	_score_readout.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_score_readout.offset_left = -62.0
	_score_readout.offset_top = 1.0
	_score_readout.offset_right = -3.0
	_score_readout.offset_bottom = 14.0
	_score_readout.pivot_offset = Vector2(56.0, 6.0)
	_score_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_score_readout)
	_update_score_readout()


## Refresh "칩 × 배수": chips blue. Alone → ×1 grey; a stack override shows the
## combined chips × meld 배수 (배수 red) on the TOP card.
func _update_score_readout() -> void:
	if _score_readout == null:
		return
	var chips: int = _stack_chips if _stack_chips >= 0 else _accumulated_chips
	var stacked: bool = _stack_chips >= 0 and _stack_mult > 1.0
	var mult_str: String = ("×%s" % _fmt_mult(_stack_mult)) if stacked else "×1"
	var mult_col: String = "#ff5b5b" if stacked else "#7a7d85"  # red ignite vs grey
	_score_readout.text = "[right][color=#5b9cff]%d[/color] [color=%s]%s[/color][/right]" % [chips, mult_col, mult_str]


## BattleManager sets the combined stack score on the TOP card (live, while stacked).
## Pass chips<0 to clear back to this card's own "칩 ×1".
func set_stack_score(chips: int, mult: float, melds: Array = [], count: int = 1) -> void:
	_stack_chips = chips
	_stack_mult = mult
	_stack_melds = melds
	_stack_count = count
	_update_score_readout()
	# If this is a resolved reward card on screen, rebuild its labeled breakdown live.
	if _flippable and not _flipping and _reward_type != Reward.OBJET and _face_overlay != null:
		_render_reward_face()


static func _fmt_mult(m: float) -> String:
	if absf(m - round(m)) < 0.01:
		return str(int(round(m)))
	return "%.1f" % m


## Quick scale punch on the chip readout each time a kill adds to it.
func _pop_score_readout() -> void:
	if _score_readout == null:
		return
	_score_readout.scale = Vector2(1.3, 1.3)
	var t := create_tween()
	t.tween_property(_score_readout, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A small "까기" hint (direct child) shown when this card is the openable TOP of a
## stack. Input is handled on the window root: click = flip, drag = move/stack.
func _build_flip_hint() -> void:
	_flip_hint = Label.new()
	_flip_hint.text = "까기 ▸"
	_flip_hint.add_theme_font_size_override("font_size", 7)
	_flip_hint.add_theme_color_override("font_color", Color(1.0, 0.96, 0.6, 1.0))
	_flip_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_flip_hint.add_theme_constant_override("shadow_offset_x", 1)
	_flip_hint.add_theme_constant_override("shadow_offset_y", 1)
	_flip_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_flip_hint.offset_top = -10.0
	_flip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flip_hint.visible = false
	add_child(_flip_hint)


## BattleManager: the TOP card of a fully-resolved stack becomes openable.
func set_chain_ready(ready: bool, stack_count: int = 1) -> void:
	_chain_ready = ready
	if _flip_hint != null and not _flipping:
		_flip_hint.text = ("%d장 까기 ▸" % stack_count) if stack_count >= 2 else "까기 ▸"
		_flip_hint.visible = ready


# ─── Input: press hands the gesture to BattleManager (click vs drag) ───
func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _flipping:
		grab_started.emit(self, event.global_position)


## Reveal + grant THIS card's reward (flip animation), returning the reward so the
## chain can tally the merge bonus. Does NOT close — the chain calls chain_close.
func reveal_and_grant() -> Dictionary:
	if _flipping or not _flippable:
		return {"type": _reward_type, "amount": 0}
	_flippable = false
	_flipping = true
	_close_started = true
	if _flip_hint != null:
		_flip_hint.queue_free()
		_flip_hint = null
	if _face_overlay != null:
		_face_overlay.queue_free()
		_face_overlay = null
	var reward: Dictionary = _grant_reward()
	_build_card_back(reward)
	pivot_offset = size * 0.5
	var t := create_tween()
	# Flip: squash X to a sliver (pop Y for life), swap to the back, snap open.
	t.tween_property(self, "scale:x", 0.04, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(self, "scale:y", 1.16, 0.1).set_trans(Tween.TRANS_QUAD)
	t.tween_callback(_swap_to_back)
	t.tween_property(self, "scale:x", 1.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "scale:y", 1.0, 0.16).set_trans(Tween.TRANS_BACK)
	return reward


## Fade out + close (the chain calls this after the reward lingers).
func chain_close(delay: float) -> void:
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(self, "modulate:a", 0.0, 0.26)
	t.tween_callback(_finish_flip_close)


## Grant THIS card's typed reward (color = type; RANDOM resolves NOW for suspense).
## Returns {type, amount}. Leftover accrued drops are discarded so BattleManager
## grants nothing on close.
func _grant_reward() -> Dictionary:
	var t: int = _reward_type
	if t == Reward.RANDOM:
		t = [Reward.WEAPON, Reward.GOLD, Reward.HP, Reward.XP].pick_random()
	var amount: int = 0
	match t:
		Reward.GOLD:
			# BONUS gold on top of the already-paid immediate kill gold (≈ doubles
			# this fight's gold). Tune by scaling claim_gold_drops() here.
			amount = maxi(1, claim_gold_drops())
			GameState.add_gold(amount)
		Reward.XP:
			amount = maxi(1, claim_xp_reward())
			GameState.add_party_xp(amount)
		Reward.HP:
			amount = HEAL_PER_CARD
			_heal_party(amount)
		Reward.WEAPON:
			var item: ItemData = _random_weapon_item()
			if item != null:
				GameState.collect_item(item, GameState.loot_level_for_item(item))
			amount = 1
		Reward.OBJET:
			# Free + immediate: claim the objet onto the left shelf (one-time).
			GameState.acquire_objet(_objet_id)
			amount = 1
	claim_gold_drops()  # flush any unused accrual → manager drops nothing on close
	claim_xp_reward()
	claim_item_drops()
	return {"type": t, "amount": amount}


func _random_weapon_item() -> ItemData:
	for i in 6:
		var it: ItemData = ItemDB.random_drop()
		if it != null and it.slot == ItemData.Slot.WEAPON:
			return it
	return ItemDB.random_drop()


func _heal_party(amount: int) -> void:
	for i in GameState.party_size():
		GameState.heal_party_member(i, amount)


func _swap_to_back() -> void:
	if _enemy_anchor != null:
		_enemy_anchor.visible = false
	if _name_label != null:
		_name_label.visible = false
	if _log_panel != null:
		_log_panel.visible = false
	# Keep the reward color (lightened to "pop") so the back still reads as its type.
	_background.add_theme_stylebox_override("panel", _flat_panel_style(_reward_color().lightened(0.14), DQ_WINDOW_BORDER))
	if _card_back != null:
		_card_back.visible = true


## Back = the concrete reward revealed: type name + the amount (suspense pay-off,
## especially for purple/random which only resolves on flip).
func _build_card_back(reward: Dictionary) -> void:
	_card_back = Control.new()
	_card_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_back.visible = false
	add_child(_card_back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_back.add_child(center)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 0)
	center.add_child(vb)
	var t: int = int(reward["type"])
	var amt: int = int(reward["amount"])
	if t == Reward.OBJET:
		var tex: Texture2D = OBJET_TEX.get(_objet_id, null)
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(36.0, 36.0)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(icon)
		vb.add_child(_back_label("획득!", 11, Color(1.0, 0.98, 0.82, 1.0)))
		return
	vb.add_child(_back_label(str(REWARD_LABEL[t]), 8, Color(1, 1, 1, 1)))
	var txt: String = "장비!" if t == Reward.WEAPON else "+%d" % amt
	vb.add_child(_back_label(txt, 15, Color(1.0, 0.96, 0.78, 1.0)))


func _back_label(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _finish_flip_close() -> void:
	if not is_inside_tree():
		return
	EventBus.battle_window_closed.emit(self)  # claims return 0/empty → no field drop
	queue_free()


func _close_after_log_sequence() -> void:
	if _close_started:
		return
	_close_started = true
	await get_tree().process_frame
	await get_tree().create_timer(close_delay).timeout
	if not is_inside_tree():
		return
	EventBus.battle_window_closed.emit(self)
	queue_free()


## A party member fell mid-fight → this window is lost. Stop combat, discard all
## accumulated reward (no chest, no gold, no XP), shatter, and close. Other
## windows are untouched. Guarded so it fires at most once.
func _collapse_lost(downed_name: String) -> void:
	if _close_started or _chest_state != ChestState.NONE:
		return
	_close_started = true
	_running = false
	_pending_chest = false
	_turn_timer.stop()
	# Drop the spoils — being so close doesn't matter, the fight is lost.
	_gold_drops_total = 0
	_earned_xp_total = 0
	_set_log("%s 쓰러짐!\n전투 와해 — 보상 없음" % downed_name)
	# Shatter/vanish: flash red, jolt, shrink + fade so "잃었다" reads clearly.
	pivot_offset = size * 0.5
	if _chest_tween and _chest_tween.is_valid():
		_chest_tween.kill()
	modulate = Color(1.0, 0.5, 0.45, 1.0)
	var tween := create_tween()
	tween.tween_property(self, "rotation", randf_range(-0.18, 0.18), COLLAPSE_DURATION * 0.35) \
		.set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "scale", Vector2(0.62, 0.62), COLLAPSE_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "modulate:a", 0.0, COLLAPSE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish_collapse_lost)


func _finish_collapse_lost() -> void:
	if not is_inside_tree():
		return
	EventBus.battle_window_closed.emit(self)
	queue_free()


# ─── Chest reward flow ───────────────────────────────────────────────
## True while the window is sitting as a closed/opening/revealed chest. Used
## by BattleManager to skip drift physics on chests so the hover stays stable.
func is_chest_active() -> bool:
	# Flippable / flipping cards count too → they stop counting toward the multi-
	# window cap (so new fights still spawn) without being freed yet.
	return _chest_state != ChestState.NONE or _flippable or _flipping


func _enter_chest_state() -> void:
	if _chest_state != ChestState.NONE:
		return
	_chest_state = ChestState.CLOSED
	# The fight itself is over the moment we transform — let BattleManager
	# release the modal pause (if any) and stop counting us toward the
	# multi-window cap. Player can move again while the chest waits.
	EventBus.battle_window_resolved.emit(self)
	# The whole window becomes the chest — repaint Background as the body and
	# hide the battle UI. Lid/band/lock overlay on top in _build_chest_visual.
	_background.add_theme_stylebox_override("panel", _flat_panel_style(
		Color(0.42, 0.27, 0.14, 1.0),  # body brown
		Color(0.20, 0.12, 0.06, 1.0)   # rim
	))
	_background_image.visible = false
	_log_panel.visible = false
	_name_label.visible = false
	_hp_label.visible = false
	for child in _enemy_anchor.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false

	_build_chest_visual()
	_build_hover_progress_bar()
	# Capture the mouse over the whole box; hover is sampled per-frame in _process
	# against the box's local rect (robust to the chest scale, unlike the
	# mouse_entered/exited signals which mis-fire once we shrink to CHEST_SCALE).
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Float above active battle windows so a newly spawned fight can't bury the
	# reward — the player can always find and open it.
	z_index = CHEST_Z_INDEX
	move_to_front()

	# Shrink the whole window down to chest scale around its center.
	pivot_offset = size * 0.5
	if _chest_tween and _chest_tween.is_valid():
		_chest_tween.kill()
	_chest_tween = create_tween()
	_chest_tween.tween_property(self, "scale", Vector2(CHEST_SCALE, CHEST_SCALE), CHEST_SHRINK_DURATION) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)


func _build_chest_visual() -> void:
	_chest_root = Control.new()
	_chest_root.name = "ChestVisual"
	_chest_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chest_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chest_root)

	# The Background panel is now the chest body. Overlay the lid (darker
	# upper band that reads as the chest's hinged top) and a gold latch band
	# with a central lock, leaving a 4px inset so the rim shows through.
	var inset: float = 4.0
	var inner_w: float = size.x - inset * 2.0
	var lid_height: float = size.y * 0.34

	var lid := ColorRect.new()
	lid.color = Color(0.32, 0.20, 0.10, 1.0)
	lid.position = Vector2(inset, inset)
	lid.size = Vector2(inner_w, lid_height)
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest_root.add_child(lid)

	var band := ColorRect.new()
	band.color = Color(0.94, 0.78, 0.32, 1.0)
	band.position = Vector2(inset, inset + lid_height - 2.0)
	band.size = Vector2(inner_w, 6.0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest_root.add_child(band)

	var lock := ColorRect.new()
	lock.color = Color(0.18, 0.10, 0.04, 1.0)
	var lock_size: float = 7.0
	lock.size = Vector2(lock_size, lock_size)
	lock.position = Vector2(size.x * 0.5 - lock_size * 0.5, inset + lid_height - 1.0)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest_root.add_child(lock)


func _build_hover_progress_bar() -> void:
	_chest_hover_bar = ProgressBar.new()
	_chest_hover_bar.show_percentage = false
	_chest_hover_bar.max_value = 1.0
	_chest_hover_bar.value = 0.0
	_chest_hover_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest_hover_bar.size = Vector2(size.x * 0.52, 4.0)
	_chest_hover_bar.position = Vector2(size.x * 0.24, size.y * 0.78)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.05, 0.9)
	bg.border_color = Color(0.4, 0.3, 0.15, 1.0)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.88, 0.4, 1.0)
	_chest_hover_bar.add_theme_stylebox_override("background", bg)
	_chest_hover_bar.add_theme_stylebox_override("fill", fill)
	add_child(_chest_hover_bar)


func _process(delta: float) -> void:
	if _chest_state != ChestState.CLOSED:
		return
	# Hover = mouse anywhere over the box (plus a small pad so it's forgiving).
	# get_local_mouse_position() already folds in the chest scale, so this stays
	# correct after the window shrinks to CHEST_SCALE.
	var pad: float = CHEST_HOVER_PADDING
	var hover_rect := Rect2(Vector2(-pad, -pad), size + Vector2(pad, pad) * 2.0)
	if not hover_rect.has_point(get_local_mouse_position()):
		return
	# Duration shrinks with the GREED open-speed upgrade (GameState).
	_chest_hover_progress = clampf(_chest_hover_progress + delta / GameState.chest_hover_duration(), 0.0, 1.0)
	if _chest_hover_bar:
		_chest_hover_bar.value = _chest_hover_progress
	if _chest_hover_progress >= 1.0:
		_open_chest()


func _open_chest() -> void:
	if _chest_state != ChestState.CLOSED:
		return
	_chest_state = ChestState.OPENING
	# At the unlock moment, force the reward to the very top so it's clearly
	# visible even if windows spawned/overlapped while it sat closed.
	z_index = CHEST_Z_INDEX
	move_to_front()
	# Apply the rewards now — claim_* zeroes the totals so we won't double-pay.
	var gold_total: int = claim_gold_drops()
	var items: Array[ItemData] = claim_item_drops()
	if gold_total > 0:
		GameState.add_gold(gold_total)
	var collected_items: Array[ItemData] = []
	for item: ItemData in items:
		if item == null:
			continue
		if GameState.collect_item(item):
			collected_items.append(item)

	# Hide chest + hover bar, play "팡!" pulse, then reveal contents.
	if _chest_hover_bar:
		_chest_hover_bar.visible = false
	if _chest_root:
		_chest_root.visible = false
	_spawn_open_sparkles()
	if _chest_tween and _chest_tween.is_valid():
		_chest_tween.kill()
	_chest_tween = create_tween()
	_chest_tween.tween_property(self, "scale", Vector2(CHEST_SCALE * 1.15, CHEST_SCALE * 1.15), CHEST_OPEN_DURATION * 0.4) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
	_chest_tween.tween_property(self, "scale", Vector2(CHEST_SCALE, CHEST_SCALE), CHEST_OPEN_DURATION * 0.6) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	_chest_tween.tween_callback(_show_reveal.bind(gold_total, collected_items))


func _spawn_open_sparkles() -> void:
	# Four star glyphs radiating from the chest center for ~0.4s.
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	for i in 6:
		var angle: float = TAU * float(i) / 6.0 + randf_range(-0.2, 0.2)
		var spark := Label.new()
		spark.text = "★"
		spark.add_theme_font_size_override("font_size", 10)
		spark.add_theme_color_override("font_color", Color(1.0, 0.94, 0.5, 1.0))
		spark.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
		spark.add_theme_constant_override("shadow_offset_x", 1)
		spark.add_theme_constant_override("shadow_offset_y", 1)
		spark.position = center
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(spark)
		var target: Vector2 = center + Vector2(cos(angle), sin(angle)) * randf_range(16.0, 24.0)
		var t := create_tween()
		t.tween_property(spark, "position", target, 0.4) \
			.set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(spark, "modulate:a", 0.0, 0.4)
		t.tween_callback(spark.queue_free)


func _show_reveal(gold_total: int, items: Array[ItemData]) -> void:
	_chest_state = ChestState.REVEALED
	var reveal := VBoxContainer.new()
	reveal.name = "RewardReveal"
	reveal.add_theme_constant_override("separation", 3)
	reveal.alignment = BoxContainer.ALIGNMENT_CENTER
	reveal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reveal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(reveal)

	if gold_total > 0:
		reveal.add_child(_build_reward_row(GOLD_ICON, "+%d 골드" % gold_total))
	for item: ItemData in items:
		var icon: Texture2D = item.icon if item else null
		var name_text: String = "%s 획득!" % (item.display_name if item else "장비")
		reveal.add_child(_build_reward_row(icon, name_text))

	# Fade-in for the contents (modulate from 0 → 1).
	reveal.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(reveal, "modulate:a", 1.0, 0.18)
	t.tween_interval(CHEST_REVEAL_LINGER)
	t.tween_callback(_begin_chest_close)


func _build_reward_row(icon: Texture2D, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != null:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		tex.custom_minimum_size = Vector2(16.0, 16.0)
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tex)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.78, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


func _begin_chest_close() -> void:
	if _chest_state == ChestState.CLOSING:
		return
	_chest_state = ChestState.CLOSING
	if _chest_tween and _chest_tween.is_valid():
		_chest_tween.kill()
	_chest_tween = create_tween()
	_chest_tween.tween_property(self, "modulate:a", 0.0, CHEST_CLOSE_FADE)
	_chest_tween.parallel().tween_property(self, "scale", Vector2(CHEST_SCALE * 0.6, CHEST_SCALE * 0.6), CHEST_CLOSE_FADE) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_IN)
	_chest_tween.tween_callback(_finish_chest_close)


func _finish_chest_close() -> void:
	if _close_started:
		return
	_close_started = true
	if not is_inside_tree():
		return
	EventBus.battle_window_closed.emit(self)
	queue_free()


const ITEM_DROP_CHANCE: float = 0.4  ## per-victory gear-drop chance (tune freely)

func _add_window_item_drop() -> void:
	if not GameState.item_drops_enabled():
		return
	if randf() > ITEM_DROP_CHANCE:
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
		if not GameState.is_combat_ready(i):
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
		if GameState.is_combat_ready(i):
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
	# First round honors the ambush roll (선공/피습); afterwards, pure agility.
	if _initiative_pending and _initiative != 0:
		_turn_queue.sort_custom(_compare_initiative)
	else:
		_turn_queue.sort_custom(_compare_turn_actors)
	_initiative_pending = false


func _compare_turn_actors(a: Dictionary, b: Dictionary) -> bool:
	var agility_a: int = int(a["agility"])
	var agility_b: int = int(b["agility"])
	if agility_a == agility_b:
		return float(a["tie_break"]) < float(b["tie_break"])
	return agility_a > agility_b


## First-round ordering under ambush: one whole side acts before the other
## (party first on 선공, enemies first on 피습); ties within a side by agility.
func _compare_initiative(a: Dictionary, b: Dictionary) -> bool:
	var a_party: bool = int(a["type"]) == ACTOR_PARTY
	var b_party: bool = int(b["type"]) == ACTOR_PARTY
	if a_party != b_party:
		return a_party if _initiative == 1 else b_party
	return _compare_turn_actors(a, b)


## Roll this fight's initiative from party vs enemy agility, and log the result.
func _roll_initiative() -> void:
	var total: float = 0.0
	var n: int = 0
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy):
			total += float(enemy.agility)
			n += 1
	var enemy_avg: float = total / float(n) if n > 0 else 0.0
	_initiative = GameState.roll_battle_initiative(enemy_avg)
	_initiative_pending = true
	if _initiative == 1:
		_queue_log("선공! 먼저 공격한다!")
	elif _initiative == -1:
		_queue_log("기습당했다!")


func _is_actor_alive(actor: Dictionary) -> bool:
	if int(actor["type"]) == ACTOR_PARTY:
		return GameState.is_combat_ready(int(actor["party_index"]))
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
	return _layout_size_for_rows(_row_counts_for_enemy_count(total)) * _window_size_multiplier


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
