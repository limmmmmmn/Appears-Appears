class_name BattleWindow
extends Control

## A single auto-battle window. Self-contained: spawned, ticks turns, closes itself.
## Runs in parallel with up to 100 sibling windows — must stay independent.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/enemy.tscn")

@export var enemy_data: EnemyData
@export var turn_interval: float = 0.5
@export var close_delay: float = 0.4

## How long to linger at spawn center before sliding to the assigned slot.
@export var slide_delay: float = 0.3
@export var slide_duration: float = 0.3

@onready var _name_label: Label = %NameLabel
@onready var _hp_label: Label = %HPLabel
@onready var _log_label: Label = %LogLabel
@onready var _enemy_anchor: Node2D = %EnemyAnchor
@onready var _turn_timer: Timer = $TurnTimer

enum Phase { PARTY, ENEMY }

var _enemy: Enemy
var _phase: Phase = Phase.PARTY
var _running: bool = false


func _ready() -> void:
	_turn_timer.wait_time = turn_interval
	_turn_timer.timeout.connect(_on_turn_tick)
	_spawn_enemy()
	EventBus.battle_window_opened.emit(self)
	_running = true
	_turn_timer.start()


## Allow spawner to inject data before _ready completes.
func setup(data: EnemyData) -> void:
	enemy_data = data


## Slide from spawn position to the assigned slot. Caller decides target.
## Linger at spawn for `slide_delay`, then ease into `target` over `slide_duration`.
func slide_to(target: Vector2) -> void:
	var tween: Tween = create_tween()
	tween.tween_interval(slide_delay)
	tween.tween_property(self, "position", target, slide_duration)\
		.set_trans(Tween.TRANS_CUBIC)\
		.set_ease(Tween.EASE_OUT)


func _spawn_enemy() -> void:
	if enemy_data == null:
		push_warning("[BattleWindow] no enemy_data set")
		return
	_enemy = ENEMY_SCENE.instantiate()
	_enemy.setup(enemy_data)
	_enemy_anchor.add_child(_enemy)
	_enemy.hp_changed.connect(_on_enemy_hp_changed)
	_enemy.died.connect(_on_enemy_died)
	_name_label.text = enemy_data.display_name
	_refresh_hp_label(enemy_data.max_hp, enemy_data.max_hp)
	_log_label.text = "%s appears!" % enemy_data.display_name


# ─── Turn loop ────────────────────────────────────────────────────────
func _on_turn_tick() -> void:
	if not _running:
		return
	match _phase:
		Phase.PARTY:
			_party_attack()
			_phase = Phase.ENEMY
		Phase.ENEMY:
			_enemy_attack()
			_phase = Phase.PARTY


func _party_attack() -> void:
	if _enemy == null or not _enemy.is_alive():
		return
	var log_parts: PackedStringArray = []
	for i in GameState.party_size():
		if not GameState.is_alive(i):
			continue
		var member: CharacterData = GameState.party[i]
		var atk: int = GameState.effective_attack(i)
		var crit: Dictionary = GameState.roll_crit()
		var damage: int = int(round(atk * float(crit["mult"])))
		var dealt: int = _enemy.take_damage(damage, crit["is_crit"])
		var tag: String = "%s -%d" % [member.display_name, dealt]
		if crit["is_crit"]:
			tag += "!"
		log_parts.append(tag)
		if not _enemy.is_alive():
			break
	if log_parts.size() > 0:
		_log_label.text = " / ".join(log_parts)


func _enemy_attack() -> void:
	if _enemy == null or not _enemy.is_alive():
		return
	var alive_indices: Array[int] = []
	for i in GameState.party_size():
		if GameState.is_alive(i):
			alive_indices.append(i)
	if alive_indices.is_empty():
		return
	var target_index: int = alive_indices.pick_random()
	var target: CharacterData = GameState.party[target_index]
	var dealt: int = max(1, enemy_data.attack - GameState.effective_defense(target_index))
	GameState.damage_party_member(target_index, dealt)
	_log_label.text = "%s hits %s -%d" % [enemy_data.display_name, target.display_name, dealt]


# ─── Enemy callbacks ──────────────────────────────────────────────────
func _on_enemy_hp_changed(current: int, max_hp: int) -> void:
	_refresh_hp_label(current, max_hp)


func _on_enemy_died() -> void:
	_running = false
	_turn_timer.stop()
	var reward: int = GameState.modify_gold_reward(enemy_data.gold_reward)
	GameState.add_gold(reward)
	_log_label.text = "%s defeated! +%d gold" % [enemy_data.display_name, reward]
	await get_tree().create_timer(close_delay).timeout
	EventBus.battle_window_closed.emit(self)
	queue_free()


func _refresh_hp_label(current: int, max_hp: int) -> void:
	_hp_label.text = "HP %d/%d" % [current, max_hp]
