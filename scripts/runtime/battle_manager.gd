class_name BattleManager
extends CanvasLayer

## Spawns BattleWindows on enemy_encountered, assigns each a slot, slides them
## to the edge so multiple windows can run in parallel.
##
## CanvasLayer base = screen-space rendering. Battle windows stay locked to
## the viewport regardless of where the world camera is looking.
## Windows themselves are independent — manager only decides where they live.

const BATTLE_WINDOW_SCENE: PackedScene = preload("res://scenes/battle_window.tscn")

## A 120x80 window centered in the 640x328 (above-HUD) play area.
const SPAWN_CENTER: Vector2 = Vector2(260, 124)

## Edge slot grid (12). Center is left clear so newly popped windows are
## visible before they slide out.
const SLOTS: Array[Vector2] = [
	Vector2(2, 2),   Vector2(132, 2),  Vector2(262, 2),  Vector2(392, 2),  Vector2(518, 2),
	Vector2(2, 124), Vector2(518, 124),
	Vector2(2, 246), Vector2(132, 246), Vector2(262, 246), Vector2(392, 246), Vector2(518, 246),
]

var _free_slots: Array[Vector2] = []
var _window_slot: Dictionary = {}  ## BattleWindow -> Vector2 slot it took


func _ready() -> void:
	_free_slots = SLOTS.duplicate()
	_free_slots.shuffle()
	EventBus.enemy_encountered.connect(_on_enemy_encountered)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)


func active_window_count() -> int:
	return _window_slot.size()


# ─── Spawning ─────────────────────────────────────────────────────────
func _on_enemy_encountered(field_enemy: Node) -> void:
	if GameState.is_party_wiped() or not is_instance_valid(field_enemy):
		return
	var data: EnemyData = field_enemy.data
	if data == null:
		return
	spawn_battle(data)
	# Echo Strike & friends: roll for bonus duplicate windows.
	var extras: int = GameState.roll_window_duplicates()
	for i in extras:
		spawn_battle(data)


## Public API. Used by enemy_encountered handler and debug helpers.
func spawn_battle(data: EnemyData) -> void:
	_spawn_window(data)


func _spawn_window(data: EnemyData) -> void:
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	window.setup(data)
	window.position = SPAWN_CENTER
	add_child(window)
	var target: Vector2 = _take_slot()
	_window_slot[window] = target
	window.slide_to(target)


# ─── Slot bookkeeping ────────────────────────────────────────────────
func _take_slot() -> Vector2:
	if _free_slots.is_empty():
		# Overflow: pile near a random slot with jitter for visual chaos.
		# Trailer cut at 100 windows benefits from spread, not stacking.
		var base: Vector2 = SLOTS.pick_random()
		return base + Vector2(randf_range(-32, 32), randf_range(-24, 24))
	return _free_slots.pop_back()


func _on_battle_window_closed(window: Node) -> void:
	if not _window_slot.has(window):
		return
	var slot: Vector2 = _window_slot[window]
	_window_slot.erase(window)
	# Only re-queue real grid slots; overflow picks shouldn't double-add.
	if slot in SLOTS and not slot in _free_slots:
		_free_slots.append(slot)
	# Tell anyone who cares (Field, etc.) when the last fight ends. This is
	# the gate Field uses before declaring stage_cleared — Echo Strike means
	# the *first* window closing is rarely the last one.
	if _window_slot.is_empty():
		EventBus.all_battles_resolved.emit()
