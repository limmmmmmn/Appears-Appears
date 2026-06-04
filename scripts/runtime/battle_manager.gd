class_name BattleManager
extends Node2D

## Spawns BattleWindows on enemy_encountered, then lets them drift away from
## overlapping windows or the player and settle into their world position.
## Battle windows live on the field, so the camera can move away from them.

const BATTLE_WINDOW_SCENE: PackedScene = preload("res://scenes/battle_window.tscn")
const DAMAGE_NUMBER_SCENE: PackedScene = preload("res://scenes/effects/damage_number.tscn")

## Fallback if no valid player-relative spawn point exists.
const SPAWN_CENTER_OFFSET: Vector2 = Vector2(-64, -48)

const SLOT_MARGIN: float = 2.0
const SPAWN_DISTANCE: float = 52.0
const WINDOW_PUSH_PADDING: float = 10.0
const WINDOW_PUSH_STRENGTH: float = 260.0
const PARTY_COLLISION_SIZE: Vector2 = Vector2(18.0, 24.0)
const PARTY_COLLISION_STRENGTH: float = 1800.0
const ORC_WINDOW_PUSH_MULTIPLIER: float = 0.35
const ORC_WINDOW_DRAG_SPEED_MULTIPLIER: float = 0.45
const ORC_WINDOW_DRAG_DURATION: float = 0.12
const VELOCITY_DAMPING: float = 4.6
const MAX_WINDOW_SPEED: float = 180.0
const SETTLE_SPEED: float = 10.0
const SETTLE_INTERVAL: float = 0.08
const WINDOW_COLLISION_DAMAGE_COOLDOWN: float = 0.85
const PARTY_COLLISION_DAMAGE_COOLDOWN: float = 0.45
const MODAL_WINDOW_SIZE_MULTIPLIER: float = 1.0
## Width of the left dock. The play area is inset by this on the left so battle
## windows never spawn/drift underneath it.
const LEFT_BAR_WIDTH: float = 46.0
## Top inset so battle windows don't slide under the OS menu bar.
const MENU_BAR_INSET: float = 17.0

## Battle windows tile into the 8 PERIMETER slots of a 3×3 grid (slot 5 = the
## center field). New windows take a random least-occupied slot; once each holds
## one they stack (≤ MAX_PER_SLOT) with a random nudge. Screen coords (640×360).
const SLOT_CENTERS: Array[Vector2] = [
	Vector2(193.0, 74.0), Vector2(324.0, 74.0), Vector2(455.0, 74.0),
	Vector2(193.0, 187.0),                      Vector2(455.0, 187.0),
	Vector2(193.0, 300.0), Vector2(324.0, 300.0), Vector2(455.0, 300.0),
]
const MAX_PER_SLOT: int = 3
## Center of SLOT_CENTERS — slot positions are taken RELATIVE to this and anchored
## to the party's world position so the windows sit on the map around the fight.
const GRID_CENTER: Vector2 = Vector2(324.0, 187.0)
## The battle window opens this far BEYOND the field enemy (on the side away from
## the hero), so the line reads 용사 → 필드에너미 → 전투창 (enemy stands between).
const WINDOW_BEHIND_ENEMY_DIST: float = 90.0
## Windows stay inside this rect (off the wider DOS side panels + menu bar).
const WINDOW_AREA: Rect2 = Rect2(128.0, 18.0, 393.0, 338.0)
## Stack-chain: the "파파파" stagger between sequential flips; merge bonus = this
## fraction of the chain's total gold per EXTRA card (2 cards → +12%, 3 → +24% …).
const CHAIN_GAP: float = 0.13
const STACK_BONUS_PER_EXTRA: float = 0.12
var _slot_counts: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _window_slot: Dictionary = {}    ## BattleWindow -> slot index
var _slot_windows: Dictionary = {}   ## slot index -> Array[BattleWindow] (bottom→top)
var _slot_base: Array[Vector2] = []  ## per-slot MOVABLE base position (init = SLOT_CENTERS)
## Active manual drag (whole stack moves as one).
var _drag_slot: int = -1
var _drag_mouse_start: Vector2 = Vector2.ZERO
var _drag_delta: Vector2 = Vector2.ZERO
var _drag_card_starts: Dictionary = {}  ## window -> position at grab time
var _drag_moved: bool = false


## Play area right edge = viewport minus the right panel. Read at runtime from
## UITheme so narrowing the panel automatically widens the field.
func _play_area_right_edge() -> float:
	return 640.0 - UITheme.RIGHT_PANEL_WIDTH

var _window_rects: Dictionary = {}  ## BattleWindow -> Rect2 target it took
var _window_velocities: Dictionary = {}  ## BattleWindow -> Vector2 world velocity.
var _modal_windows: Dictionary = {}  ## BattleWindow -> true for pre-movement modal battles.
var _collision_cooldowns: Dictionary = {}  ## window pair key -> remaining seconds.
var _party_collision_cooldowns: Dictionary = {}  ## battle window id -> remaining seconds.
var _settle_timer: float = 0.0


func _ready() -> void:
	# GameState.can_accept_new_battle_window() looks us up by group to read
	# active_window_count() against the multi-window cap.
	add_to_group("battle_manager")
	for c: Vector2 in SLOT_CENTERS:
		_slot_base.append(c)  # each slot starts at its grid center, then is movable
	EventBus.enemy_encountered.connect(_on_enemy_encountered)
	EventBus.combo_attack_damage_requested.connect(_on_combo_attack_damage_requested)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)
	EventBus.battle_window_resolved.connect(_on_battle_window_resolved)
	EventBus.party_wiped.connect(_on_party_wiped)
	EventBus.party_collapsed.connect(_on_party_collapsed)


func _process(delta: float) -> void:
	# Drive the downed → refill → auto-stand cycle every frame (runs even between
	# fights so knocked-out members always recover). No passive regen otherwise.
	GameState.tick_downed_recovery(delta)
	# Windows now sit in fixed 3×3 grid slots (no drift/push) — they stay put as
	# stacked floating cards, so the eye stays on the content.


## How many battle windows the cap should treat as "fighting right now".
## Excludes chest windows (reward boxes) since their fight is over — they just
## linger until the player hovers them open.
## All live windows (fighting OR sitting as flippable reward cards). The deadlock
## check uses this so pending reward cards aren't mistaken for a stuck run.
func pending_window_count() -> int:
	return _window_rects.size()


func active_window_count() -> int:
	var count: int = 0
	for window in _window_rects.keys():
		if not is_instance_valid(window):
			continue
		if window.has_method("is_chest_active") and window.is_chest_active():
			continue
		count += 1
	return count


## Fight inside `window` just ended (window is becoming a chest). Release the
## modal-battle pause (if applicable) so the player can move again, and clear
## it from `_modal_windows` so the eventual `_on_battle_window_closed` doesn't
## try to release the same pause a second time.
func _on_battle_window_resolved(window: Node) -> void:
	if _modal_windows.has(window):
		_modal_windows.erase(window)
		GameState.end_field_battle_pause()
	# A card finished its fight → maybe its stack is now fully openable.
	if _window_slot.has(window):
		_update_slot_readiness(int(_window_slot[window]))


# ─── Spawning ─────────────────────────────────────────────────────────
func _on_enemy_encountered(field_enemy: Node) -> void:
	if GameState.is_party_wiped() or not is_instance_valid(field_enemy):
		return
	var data: EnemyData = field_enemy.data
	if data == null:
		return
	var source := field_enemy as Node2D
	var is_combo_encounter: bool = bool(field_enemy.get_meta("combo_encounter", false))
	var is_modal_battle: bool = not is_combo_encounter and not GameState.battle_movement_unlocked()
	var window: BattleWindow = spawn_battle(data, source, is_modal_battle, is_combo_encounter)
	if is_combo_encounter and window:
		window.set_meta("combo_batch_id", int(field_enemy.get_meta("combo_batch_id", 0)))


func _on_combo_attack_damage_requested(damage_ratio: float, combo_batch_id: int) -> void:
	if damage_ratio <= 0.0 or combo_batch_id <= 0:
		return
	for window: BattleWindow in _window_rects.keys():
		if is_instance_valid(window) and int(window.get_meta("combo_batch_id", 0)) == combo_batch_id:
			window.apply_window_collision_damage(damage_ratio, "Combo attack")


## Public API. Used by enemy_encountered handler and debug helpers.
func spawn_battle(data: EnemyData, source: Node2D = null, is_modal_battle: bool = false, at_source_position: bool = false) -> BattleWindow:
	return _spawn_window(data, source, is_modal_battle, at_source_position)


func _spawn_window(data: EnemyData, source: Node2D = null, is_modal_battle: bool = false, at_source_position: bool = false) -> BattleWindow:
	var window: BattleWindow = BATTLE_WINDOW_SCENE.instantiate()
	# WORLD encounter spot — drives the on-field loot drop AND (converted to screen
	# inside the window) the open-zoom origin.
	var drop_world: Vector2 = source.global_position if source != null and is_instance_valid(source) else Vector2.INF
	window.setup(data, drop_world, MODAL_WINDOW_SIZE_MULTIPLIER if is_modal_battle else 1.0)
	var window_size: Vector2 = window.get_expected_window_size()
	# Drop the window into a 3×3 perimeter grid slot (random least-occupied), stacking
	# with a random nudge once each slot has one. Screen-fixed, no drift.
	var slot: int = _pick_slot()
	var count: int = _slot_counts[slot]
	_slot_counts[slot] = count + 1
	_window_slot[window] = slot
	if not _slot_windows.has(slot):
		_slot_windows[slot] = []
	_slot_windows[slot].append(window)
	if window.has_signal("grab_started"):
		window.grab_started.connect(_on_grab_started)
	var spawn_position: Vector2 = _window_position_behind_enemy(source, window_size)
	window.position = spawn_position
	_window_rects[window] = Rect2(spawn_position, window_size)
	_window_velocities[window] = Vector2.ZERO
	if is_modal_battle:
		_modal_windows[window] = true
		GameState.begin_field_battle_pause()
	_window_parent().add_child(window)
	window.play_open_intro()
	_update_slot_readiness(slot)  # a fresh fight in the slot → stack not openable yet
	return window


# ─── Stack = chain explosion ───────────────────────────────────────────
## A slot's stack only opens when EVERY card in it has resolved; then only the TOP
## card is the clickable opener (covered/fighting cards stay inert).
func _update_slot_readiness(slot: int) -> void:
	if slot < 0 or not _slot_windows.has(slot):
		return
	var ws: Array = []
	for w in _slot_windows[slot]:
		if is_instance_valid(w):
			ws.append(w)
	_slot_windows[slot] = ws
	if ws.is_empty():
		return
	var all_resolved: bool = true
	for w in ws:
		if not (w.has_method("is_resolved") and w.is_resolved()):
			all_resolved = false
			break
	var top = ws[ws.size() - 1]
	for w in ws:
		if w.has_method("set_chain_ready"):
			w.set_chain_ready(w == top and all_resolved, ws.size())
	# Same-color multiplier: each card shows xN = how many SAME-color cards are in
	# this stack (the "같은 색 모으기" strategy → bigger combos).
	for w in ws:
		if w.has_method("reward_type_id") and w.has_method("set_multiplier"):
			var c: int = int(w.reward_type_id())
			var same: int = 0
			for o in ws:
				if o.has_method("reward_type_id") and int(o.reward_type_id()) == c:
					same += 1
			w.set_multiplier(same)


# ─── Manual drag: free move + whole-stack (solitaire) move ─────────────
## Press a card → grab its WHOLE stack. Release without moving = click (open).
func _on_grab_started(window: Node, screen_pos: Vector2) -> void:
	if _drag_slot >= 0 or not _window_slot.has(window):
		return
	var slot: int = int(_window_slot[window])
	if not _slot_windows.has(slot) or _slot_windows[slot].is_empty():
		return
	_drag_slot = slot
	_drag_mouse_start = screen_pos
	_drag_delta = Vector2.ZERO
	_drag_moved = false
	_drag_card_starts.clear()
	for w in _slot_windows[slot]:
		if is_instance_valid(w):
			_drag_card_starts[w] = w.position
			if w.get_parent() != null:
				w.get_parent().move_child(w, -1)  # whole stack to front while moving


func _input(event: InputEvent) -> void:
	if _drag_slot < 0:
		return
	if event is InputEventMouseMotion:
		# Windows are world-space now → convert the screen-pixel drag into world
		# units by dividing out the camera zoom, so a card tracks the cursor 1:1.
		_drag_delta = (event.global_position - _drag_mouse_start) / maxf(0.01, GameState.field_camera_zoom)
		if _drag_delta.length() > 4.0:
			_drag_moved = true
		for w in _drag_card_starts:
			if is_instance_valid(w):
				w.position = _clamp_loose(_drag_card_starts[w] + _drag_delta, w.size)
				_window_rects[w] = Rect2(w.position, w.size)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag()


func _end_drag() -> void:
	var slot: int = _drag_slot
	_drag_slot = -1
	if slot < 0:
		return
	if not _drag_moved:
		# A click (no movement) → open the stack if it's fully resolved.
		if _is_slot_ready(slot):
			_open_stack(slot)
		return
	# A real move. Dropped onto another stack → merge; else keep the free position
	# (shift the slot's logical base so new cards cascade from the new spot).
	var target: int = _find_merge_target(slot)
	if target >= 0:
		_merge_slots(slot, target)
	elif slot < _slot_base.size():
		_slot_base[slot] += _drag_delta


## First OTHER non-empty slot whose top card overlaps the dragged stack's top.
func _find_merge_target(from_slot: int) -> int:
	if not _slot_windows.has(from_slot) or _slot_windows[from_slot].is_empty():
		return -1
	var top = _slot_windows[from_slot].back()
	if not is_instance_valid(top):
		return -1
	var top_rect := Rect2(top.position, top.size)
	for s in SLOT_CENTERS.size():
		if s == from_slot or not _slot_windows.has(s) or _slot_windows[s].is_empty():
			continue
		var other = _slot_windows[s].back()
		if is_instance_valid(other) and top_rect.intersects(Rect2(other.position, other.size)):
			return s
	return -1


## Pile every card of `from` ONTO `to`'s current top card (world space), cascading
## down-right so they read as one neat stack — no teleport to a grid slot.
func _merge_slots(from_slot: int, to_slot: int) -> void:
	var to_list: Array = _slot_windows.get(to_slot, [])
	var moving: Array = _slot_windows[from_slot].duplicate()
	# Anchor = where the target stack already sits (its top card). Fallback: keep
	# the dragged cards' own drop spot so nothing jumps.
	var anchor: Vector2
	if not to_list.is_empty() and is_instance_valid(to_list.back()):
		anchor = (to_list.back() as Control).position
	elif not moving.is_empty() and is_instance_valid(moving.back()):
		anchor = (moving.back() as Control).position
	var step: int = 0
	for w in moving:
		if not is_instance_valid(w):
			continue
		step += 1
		_slot_windows[from_slot].erase(w)
		_slot_counts[from_slot] = maxi(0, _slot_counts[from_slot] - 1)
		_slot_windows[to_slot].append(w)
		_slot_counts[to_slot] += 1
		_window_slot[w] = to_slot
		w.position = anchor + Vector2(6.0, 6.0) * float(step)  # cascade onto the pile
		_window_rects[w] = Rect2(w.position, w.size)
		if w.get_parent() != null:
			w.get_parent().move_child(w, -1)  # newest cards to front
	_update_slot_readiness(from_slot)
	_update_slot_readiness(to_slot)


func _clamp_loose(pos: Vector2, _win_size: Vector2) -> Vector2:
	# World space now → no screen clamp; a dragged card stays where it's dropped
	# on the map (the camera can roam to it).
	return pos


## Chain-flip the whole stack top→bottom ("파파파"), tally rewards, then a merge
## bonus pop, then fade them all out together.
func _open_stack(slot: int) -> void:
	if not _slot_windows.has(slot):
		return
	var ws: Array = []
	for w in _slot_windows[slot]:
		if is_instance_valid(w) and w.has_method("is_resolved") and w.is_resolved():
			ws.append(w)
	if ws.is_empty():
		return
	ws.reverse()  # top (newest) first
	var count: int = ws.size()
	for w in ws:
		if not is_instance_valid(w):
			continue
		w.reveal_and_grant()  # each card grants its TYPED reward (color = type)
		await get_tree().create_timer(CHAIN_GAP).timeout
	# Combo pop at the stack's world spot (top card center).
	if count >= 2:
		var top_win = ws[0]
		var center: Vector2 = (top_win.position + top_win.size * 0.5) if is_instance_valid(top_win) else _player_world_position()
		_spawn_bonus_popup(center, "x%d 콤보!" % count)
	for w in ws:
		if is_instance_valid(w):
			w.chain_close(0.25 if count >= 2 else 0.1)


func _spawn_bonus_popup(center: Vector2, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.32, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.size = Vector2(88.0, 16.0)
	lbl.position = center - Vector2(44.0, 8.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.pivot_offset = Vector2(44.0, 8.0)
	lbl.scale = Vector2(0.2, 0.2)
	lbl.z_index = 100
	_window_parent().add_child(lbl)
	var t := create_tween()
	t.tween_property(lbl, "scale", Vector2(1.4, 1.4), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "scale", Vector2.ONE, 0.1)
	t.tween_interval(0.35)
	t.parallel().tween_property(lbl, "position:y", lbl.position.y - 14.0, 0.35)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.35)
	t.tween_callback(lbl.queue_free)


## Pick a perimeter slot: the least-occupied one (random tiebreak); if all are at
## MAX_PER_SLOT, just spread randomly so windows never refuse to open.
func _pick_slot() -> int:
	# Eligible = not full AND not already openable, so a new card NEVER joins (and
	# re-locks) a resolved/ready stack. A slot seals once it's full (MAX) OR all its
	# cards have resolved → new enemies start/extend a different (still-building) stack.
	var slot: int = _least_occupied_eligible(true)
	if slot >= 0:
		return slot
	# Fallback: every slot is full or ready (rare hoard) → least-occupied non-full…
	slot = _least_occupied_eligible(false)
	if slot >= 0:
		return slot
	return randi() % SLOT_CENTERS.size()  # …or random overlap if all 8 are full.


## Least-occupied non-full slot (random tiebreak). When `skip_ready`, also skip
## slots that are already openable (all cards resolved) so they stay clickable.
func _least_occupied_eligible(skip_ready: bool) -> int:
	var min_count: int = MAX_PER_SLOT + 1
	for i in SLOT_CENTERS.size():
		if _slot_counts[i] >= MAX_PER_SLOT:
			continue
		if skip_ready and _is_slot_ready(i):
			continue
		min_count = mini(min_count, _slot_counts[i])
	if min_count > MAX_PER_SLOT:
		return -1
	var candidates: Array[int] = []
	for i in SLOT_CENTERS.size():
		if _slot_counts[i] >= MAX_PER_SLOT:
			continue
		if skip_ready and _is_slot_ready(i):
			continue
		if _slot_counts[i] == min_count:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	return candidates[randi() % candidates.size()]


## A slot is "ready" (openable) when it holds ≥1 card and ALL of them are resolved.
func _is_slot_ready(slot: int) -> bool:
	if not _slot_windows.has(slot):
		return false
	var has_card: bool = false
	for w in _slot_windows[slot]:
		if not is_instance_valid(w):
			continue
		has_card = true
		if not (w.has_method("is_resolved") and w.is_resolved()):
			return false
	return has_card


## Screen position for a window in `slot`. The Nth window in a slot gets a random
## nudge (scaled by N) so the stack reads as separate floating cards.
## Open the window on the FAR side of the field enemy from the hero, so the line
## reads 용사 → 필드에너미 → 전투창 (the enemy stands between them, 대치). World coords.
func _window_position_behind_enemy(source: Node2D, window_size: Vector2) -> Vector2:
	var hero: Vector2 = _player_world_position()
	var enemy: Vector2 = source.global_position if (source != null and is_instance_valid(source)) else hero
	if hero == Vector2.INF:
		hero = enemy
	var dir: Vector2 = enemy - hero
	if dir.length() < 1.0:
		dir = Vector2.RIGHT  # hero & enemy overlap at contact → pick a stable axis
	dir = dir.normalized()
	return enemy + dir * WINDOW_BEHIND_ENEMY_DIST - window_size * 0.5


func _slot_position(slot: int, stack_index: int, window_size: Vector2) -> Vector2:
	# WORLD position: anchor the 3×3 slot grid to the party so windows sit ON THE
	# MAP around the fight (zooming/panning with the camera) instead of pinned to
	# the screen. Each slot keeps its relative place in the grid.
	var anchor: Vector2 = _player_world_position()
	if anchor == Vector2.INF:
		anchor = GRID_CENTER
	var slot_offset: Vector2 = SLOT_CENTERS[slot] - GRID_CENTER
	# Diagonal cascade (down-right) so a stack fans like a dealt hand.
	var nudge := Vector2(6.0, 6.0) * float(stack_index) + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	return anchor + slot_offset - window_size * 0.5 + nudge


func _centered_modal_position(window_size: Vector2) -> Vector2:
	# WORLD center fallback (converted to screen by the caller).
	return _visible_world_rect().get_center() - window_size * 0.5


## Pre-multi-window-unlock modal spawn: cover the spot where the party member
## and the field enemy actually met (midpoint of their world positions). Both
## characters are tiny (~16px) and the window is ~128×96, so anchoring on the
## midpoint reliably hides both behind the popup.
func _encounter_midpoint_position(window_size: Vector2, source: Node2D) -> Vector2:
	if source == null or not is_instance_valid(source):
		return _centered_modal_position(window_size)
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return source.global_position - window_size * 0.5
	var midpoint: Vector2 = (player_position + source.global_position) * 0.5
	return midpoint - window_size * 0.5


# ─── Window drift ─────────────────────────────────────────────────────
func _spawn_position_for_encounter(window_size: Vector2, source: Node2D, at_source_position: bool = false) -> Vector2:
	if source == null or not is_instance_valid(source):
		return _random_spawn_position(window_size)
	if at_source_position:
		return source.global_position - window_size * 0.5
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return _visible_world_rect().get_center() + SPAWN_CENTER_OFFSET
	var source_position: Vector2 = source.global_position
	var direction: Vector2 = source_position - player_position
	if direction.length_squared() < 1.0:
		return _random_spawn_position(window_size)
	direction = direction.normalized()
	var half_extent: float = absf(direction.x) * window_size.x * 0.5 + absf(direction.y) * window_size.y * 0.5
	var center: Vector2 = player_position + direction * (SPAWN_DISTANCE + half_extent)
	return center - window_size * 0.5


func _random_spawn_position(window_size: Vector2) -> Vector2:
	var player_position: Vector2 = _player_world_position()
	if player_position == Vector2.INF:
		return _visible_world_rect().get_center() + SPAWN_CENTER_OFFSET
	var candidates: Array[Vector2] = [
		player_position + Vector2(-window_size.x * 0.5, -SPAWN_DISTANCE - window_size.y),
		player_position + Vector2(-window_size.x * 0.5, SPAWN_DISTANCE),
		player_position + Vector2(-SPAWN_DISTANCE - window_size.x, -window_size.y * 0.5),
		player_position + Vector2(SPAWN_DISTANCE, -window_size.y * 0.5),
	]
	candidates.shuffle()
	for candidate: Vector2 in candidates:
		if _is_spawn_position_valid(candidate, window_size):
			return candidate
	return candidates.front()


func _is_spawn_position_valid(pos: Vector2, size: Vector2) -> bool:
	var field_rect: Rect2 = _field_rect()
	return (
		pos.x >= field_rect.position.x + SLOT_MARGIN
		and pos.y >= field_rect.position.y + SLOT_MARGIN
		and pos.x + size.x <= field_rect.end.x - SLOT_MARGIN
		and pos.y + size.y <= field_rect.end.y - SLOT_MARGIN
	)


func _apply_window_push(delta: float, burst: bool = false) -> void:
	# Windows are screen-space → compare against party SCREEN positions so the
	# push-away-from-the-party effect lines up with where they appear on screen.
	var party_positions: Array[Vector2] = []
	for _party_world: Vector2 in _party_world_positions():
		party_positions.append(_world_to_screen(_party_world))
	var window_collision_enabled: bool = GameState.battle_window_push_enabled()
	var party_collision_enabled: bool = GameState.party_window_push_enabled()
	var windows: Array = _window_rects.keys()
	for window: BattleWindow in windows:
		if not is_instance_valid(window):
			continue
		if _modal_windows.has(window):
			continue
		if window.is_opening():
			continue
		# Chests freeze in place so the hover-to-open gauge isn't fighting a
		# drifting target. Zero velocity too in case something already
		# accumulated before the transition.
		if window.has_method("is_chest_active") and window.is_chest_active():
			_window_velocities[window] = Vector2.ZERO
			continue
		_window_rects[window] = _window_rect(window)
		var force := Vector2.ZERO
		var rect: Rect2 = _window_rects[window]
		for other: BattleWindow in windows:
			if window == other or not is_instance_valid(other):
				continue
			if window_collision_enabled:
				if window.get_instance_id() < other.get_instance_id():
					_apply_window_collision_damage(window, rect, other, _window_rects[other])
				force += _window_overlap_push(window, rect, other, _window_rects[other])
		if party_collision_enabled:
			for party_position: Vector2 in party_positions:
				var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
				if rect.intersects(party_rect):
					_apply_party_collision_effects(window)
					_apply_party_drag_effects(window)
				force += _party_collision_push(rect, party_position)
		force *= _window_push_multiplier(window)
		var velocity: Vector2 = _window_velocities.get(window, Vector2.ZERO)
		var step_delta: float = 1.0 / 60.0 if burst else delta
		velocity += force * step_delta
		velocity = velocity.limit_length(MAX_WINDOW_SPEED)
		velocity = velocity.move_toward(Vector2.ZERO, VELOCITY_DAMPING * velocity.length() * step_delta)
		var next_position: Vector2 = window.position + velocity * step_delta
		# Camera is fixed → keep windows inside the visible play area. On hit
		# we damp the perpendicular velocity component so the window settles
		# against the wall with a tiny cute bounce instead of vibrating.
		var clamped_position: Vector2 = _clamp_position_to_play_area(next_position, rect.size)
		if not is_equal_approx(clamped_position.x, next_position.x):
			velocity.x = -velocity.x * 0.3
		if not is_equal_approx(clamped_position.y, next_position.y):
			velocity.y = -velocity.y * 0.3
		next_position = clamped_position
		_window_velocities[window] = velocity
		_window_rects[window] = Rect2(next_position, rect.size)
		if burst or velocity.length() >= SETTLE_SPEED:
			window.push_to(next_position)
		elif _settle_timer >= SETTLE_INTERVAL:
			window.settle_to(next_position)
	if _settle_timer >= SETTLE_INTERVAL:
		_settle_timer = 0.0


func _window_overlap_push(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> Vector2:
	var padded := Rect2(rect.position - Vector2.ONE * WINDOW_PUSH_PADDING, rect.size + Vector2.ONE * WINDOW_PUSH_PADDING * 2.0)
	var other_padded := Rect2(other.position - Vector2.ONE * WINDOW_PUSH_PADDING, other.size + Vector2.ONE * WINDOW_PUSH_PADDING * 2.0)
	if not padded.intersects(other_padded):
		return Vector2.ZERO
	var delta: Vector2 = padded.get_center() - other_padded.get_center()
	if delta == Vector2.ZERO:
		delta = _stable_separation_direction(window, other_window)
	var overlap_x: float = minf(padded.end.x, other_padded.end.x) - maxf(padded.position.x, other_padded.position.x)
	var overlap_y: float = minf(padded.end.y, other_padded.end.y) - maxf(padded.position.y, other_padded.position.y)
	var push: float = maxf(0.0, minf(overlap_x, overlap_y))
	return delta.normalized() * push * WINDOW_PUSH_STRENGTH


func _window_rect(window: BattleWindow) -> Rect2:
	var size: Vector2 = _window_rects.get(window, Rect2(window.position, window.get_expected_window_size())).size
	return Rect2(window.position, size)


func _window_push_multiplier(window: BattleWindow) -> float:
	if window.has_living_enemy_id(&"orc"):
		return ORC_WINDOW_PUSH_MULTIPLIER
	return 1.0


func _apply_party_drag_effects(window: BattleWindow) -> void:
	if window.has_living_enemy_id(&"orc"):
		GameState.apply_move_speed_drag(ORC_WINDOW_DRAG_SPEED_MULTIPLIER, ORC_WINDOW_DRAG_DURATION)


func _apply_window_collision_damage(window: BattleWindow, rect: Rect2, other_window: BattleWindow, other: Rect2) -> void:
	var damage_ratio: float = GameState.window_collision_damage_ratio()
	if damage_ratio <= 0.0:
		return
	if not rect.intersects(other):
		return
	var key: String = _collision_pair_key(window, other_window)
	if float(_collision_cooldowns.get(key, 0.0)) > 0.0:
		return
	# Ambient window-vs-window crash — damage number / flash only, no log line.
	var dealt: int = window.apply_window_collision_damage(damage_ratio, "Window crash", true)
	dealt += other_window.apply_window_collision_damage(damage_ratio, "Window crash", true)
	if dealt > 0:
		_collision_cooldowns[key] = WINDOW_COLLISION_DAMAGE_COOLDOWN


func _apply_party_collision_effects(window: BattleWindow) -> void:
	var damage_ratio: float = GameState.party_bump_damage_ratio()
	var heal_amount: int = GameState.window_collision_heal_amount()
	if damage_ratio <= 0.0 and heal_amount <= 0:
		return
	var key: String = str(window.get_instance_id())
	if float(_party_collision_cooldowns.get(key, 0.0)) > 0.0:
		return
	var dealt: int = 0
	var counter_damage_ratio: float = 0.0
	if damage_ratio > 0.0:
		counter_damage_ratio = window.party_bump_counter_damage_ratio()
		# Party shoving the window — same silent treatment as window crashes.
		dealt = window.apply_window_collision_damage(damage_ratio, "Bump attack", true)
	var healed: int = 0
	if heal_amount > 0:
		healed = _apply_party_collision_heal(window, heal_amount)
	var countered: int = 0
	if dealt > 0 and counter_damage_ratio > 0.0:
		countered = _apply_party_bump_counter_damage(window, counter_damage_ratio)
	if dealt > 0 or healed > 0 or countered > 0:
		_party_collision_cooldowns[key] = PARTY_COLLISION_DAMAGE_COOLDOWN


func _apply_party_bump_counter_damage(window: BattleWindow, ratio: float) -> int:
	var total_dealt: int = 0
	for i in GameState.party_size():
		if not GameState.is_alive(i):
			continue
		var amount: int = maxi(1, ceili(float(GameState.effective_max_hp(i)) * ratio))
		var before_hp: int = GameState.party_hp[i]
		GameState.damage_party_member(i, amount)
		var dealt: int = before_hp - GameState.party_hp[i]
		if dealt <= 0:
			continue
		total_dealt += dealt
		_spawn_party_damage_number(i, dealt)
	if total_dealt > 0:
		window.show_party_bump_counter_damage(total_dealt, ratio)
	return total_dealt


func _apply_party_collision_heal(window: BattleWindow, amount: int) -> int:
	var target_index: int = _lowest_wounded_party_index()
	if target_index == -1:
		return 0
	var before_hp: int = GameState.party_hp[target_index]
	GameState.heal_party_member(target_index, amount)
	var healed: int = GameState.party_hp[target_index] - before_hp
	if healed > 0:
		var member_name: String = GameState.party[target_index].display_name
		_spawn_party_heal_number(target_index, healed)
		window.show_window_collision_heal(member_name, healed)
	return healed


func _spawn_party_damage_number(party_index: int, amount: int) -> void:
	var target: Node2D = _party_member_node_for_index(party_index)
	if target == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	target.add_child(num)
	num.position = Vector2(randf_range(-5.0, 5.0), -18.0 + randf_range(-2.0, 2.0))
	num.z_index = 30
	num.setup_text("-%d" % amount, Color(1.0, 0.28, 0.18, 1.0))


func _spawn_party_heal_number(party_index: int, amount: int) -> void:
	var target: Node2D = _party_member_node_for_index(party_index)
	if target == null:
		return
	var num: DamageNumber = DAMAGE_NUMBER_SCENE.instantiate()
	target.add_child(num)
	num.position = Vector2(randf_range(-5.0, 5.0), -18.0 + randf_range(-2.0, 2.0))
	num.z_index = 30
	num.setup_heal(amount)


func _party_member_node_for_index(party_index: int) -> Node2D:
	if party_index < 0:
		return null
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return _party_member_node_from_group(party_index)
	if party_index == 0:
		return player
	var party_root: Node = player.get_parent()
	if party_root == null:
		return _party_member_node_from_group(party_index)
	var current_index: int = 0
	for child in party_root.get_children():
		if child is Node2D and child.is_in_group("party_member"):
			if current_index == party_index:
				return child as Node2D
			current_index += 1
	return _party_member_node_from_group(party_index)


func _party_member_node_from_group(party_index: int) -> Node2D:
	var current_index: int = 0
	for node in get_tree().get_nodes_in_group("party_member"):
		var member := node as Node2D
		if member == null:
			continue
		if current_index == party_index:
			return member
		current_index += 1
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


func _collision_pair_key(window: BattleWindow, other_window: BattleWindow) -> String:
	var a: int = int(window.get_instance_id())
	var b: int = int(other_window.get_instance_id())
	if a > b:
		var temp: int = a
		a = b
		b = temp
	return "%d:%d" % [a, b]


func _tick_collision_cooldowns(delta: float) -> void:
	for key: String in _collision_cooldowns.keys():
		var remaining: float = float(_collision_cooldowns[key]) - delta
		if remaining <= 0.0:
			_collision_cooldowns.erase(key)
		else:
			_collision_cooldowns[key] = remaining


func _tick_party_collision_cooldowns(delta: float) -> void:
	for key: String in _party_collision_cooldowns.keys():
		var remaining: float = float(_party_collision_cooldowns[key]) - delta
		if remaining <= 0.0:
			_party_collision_cooldowns.erase(key)
		else:
			_party_collision_cooldowns[key] = remaining


func _stable_separation_direction(window: BattleWindow, other_window: BattleWindow) -> Vector2:
	var pair_hash: int = int(window.get_instance_id() + other_window.get_instance_id())
	var angle: float = float(pair_hash % 360) * TAU / 360.0
	var direction := Vector2(cos(angle), sin(angle))
	if window.get_instance_id() < other_window.get_instance_id():
		return direction
	return -direction


func _party_collision_push(rect: Rect2, party_position: Vector2) -> Vector2:
	var party_rect := Rect2(party_position - PARTY_COLLISION_SIZE * 0.5, PARTY_COLLISION_SIZE)
	if not rect.intersects(party_rect):
		return Vector2.ZERO
	var delta: Vector2 = rect.get_center() - party_position
	if delta == Vector2.ZERO:
		delta = Vector2.UP
	var overlap_x: float = minf(rect.end.x, party_rect.end.x) - maxf(rect.position.x, party_rect.position.x)
	var overlap_y: float = minf(rect.end.y, party_rect.end.y) - maxf(rect.position.y, party_rect.position.y)
	var penetration: float = maxf(1.0, minf(overlap_x, overlap_y))
	return delta.normalized() * penetration * PARTY_COLLISION_STRENGTH


func _field_rect() -> Rect2:
	var field := get_node_or_null("../Field")
	if field and field.has_method("get_field_rect"):
		return field.get_field_rect()
	return Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)


func _visible_world_rect() -> Rect2:
	var camera := get_viewport().get_camera_2d()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if camera == null:
		return Rect2(Vector2.ZERO, viewport_size)
	return Rect2(camera.get_screen_center_position() - viewport_size * 0.5, viewport_size)


## Battle windows live on a CanvasLayer (SCREEN space) now — the follow camera can
## roam freely and the windows stay pinned to the viewport. This is the on-screen
## play area: the viewport minus the left dock and the right shop panel.
func _play_area_screen_rect() -> Rect2:
	# Full-bleed field: battle windows use the WHOLE viewport, inset only for the
	# two floating panels (top-left dock, top-right shop) + the menu bar, so a
	# fight never opens under a panel. Reads UITheme so resizing a panel auto-
	# adjusts the play area.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var left: float = UITheme.LEFT_PANEL_WIDTH + UITheme.PANEL_MARGIN * 2.0
	var right: float = UITheme.RIGHT_PANEL_WIDTH + UITheme.PANEL_MARGIN * 2.0
	var top: float = UITheme.PANEL_TOP
	var bottom_pad: float = UITheme.PANEL_MARGIN
	return Rect2(
		Vector2(left, top),
		Vector2(maxf(1.0, vp.x - left - right), maxf(1.0, vp.y - top - bottom_pad))
	)


## World point → on-screen pixel (folds in the follow camera's transform), so an
## encounter that happens at the enemy's world spot opens a window at the matching
## place on screen.
func _world_to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


## WORLD-space parent: BattleManager is a Node2D under Main, so windows parented
## here live ON THE MAP — they scale with camera zoom and stay anchored to their
## world spot (no longer pinned to the screen via the old CanvasLayer).
func _window_parent() -> Node:
	return self


## Clamp a window's top-left so the whole rect stays inside the visible play
## area (camera viewport minus the right-hand HUD panel). Used both at spawn
## time and inside the drift loop so neither force can shove a window off
## screen.
func _clamp_position_to_play_area(pos: Vector2, window_size: Vector2) -> Vector2:
	var bounds: Rect2 = _play_area_screen_rect()
	var max_x: float = maxf(bounds.position.x, bounds.end.x - window_size.x)
	var max_y: float = maxf(bounds.position.y, bounds.end.y - window_size.y)
	return Vector2(
		clampf(pos.x, bounds.position.x, max_x),
		clampf(pos.y, bounds.position.y, max_y)
	)


func _player_world_position() -> Vector2:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty() or not players[0] is Node2D:
		return Vector2.INF
	return (players[0] as Node2D).global_position


func _party_world_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for member: Node in get_tree().get_nodes_in_group("party_member"):
		if member is Node2D:
			positions.append((member as Node2D).global_position)
	return positions


func _on_battle_window_closed(window: Node) -> void:
	if not _window_rects.has(window):
		return
	_window_rects.erase(window)
	_window_velocities.erase(window)
	# Free the grid slot so a later window can reuse it.
	if _window_slot.has(window):
		var slot: int = _window_slot[window]
		if slot >= 0 and slot < _slot_counts.size():
			_slot_counts[slot] = maxi(0, _slot_counts[slot] - 1)
		if _slot_windows.has(slot):
			_slot_windows[slot].erase(window)
			_update_slot_readiness(slot)  # a card leaving may expose a new top
		_window_slot.erase(window)
	if _modal_windows.has(window):
		_modal_windows.erase(window)
		GameState.end_field_battle_pause()
	var battle_window := window as BattleWindow
	if battle_window:
		var xp_reward: int = battle_window.claim_xp_reward()
		if xp_reward > 0:
			GameState.add_party_xp(xp_reward)
		# Kill GOLD is paid immediately on each kill (GameState._on_enemy_defeated),
		# so we no longer drop a gold pile on close. Items still drop on the field.
		_drop_items_from_window(battle_window)
	# Tell anyone who cares (Field, etc.) when the last fight ends. This is
	# the gate Field uses before declaring field_loop_settled — Echo Strike means
	# the *first* window closing is rarely the last one.
	if _window_rects.is_empty():
		EventBus.all_battles_resolved.emit()


func _drop_items_from_window(window: BattleWindow) -> void:
	var drops: Array[ItemData] = window.claim_item_drops()
	if drops.is_empty():
		return
	var base_pos: Vector2 = _drop_base_position(window)
	for i in drops.size():
		var angle: float = TAU * float(i) / float(maxi(1, drops.size()))
		var radius: float = 10.0 if drops.size() > 1 else 0.0
		# Drop quality = the loot level for the item's category (manual equip).
		var level: int = GameState.loot_level_for_item(drops[i])
		EventBus.field_item_drop_requested.emit(drops[i], base_pos + Vector2(cos(angle), sin(angle)) * radius, level)


func _drop_base_position(window: BattleWindow) -> Vector2:
	var base_pos: Vector2 = window.field_drop_position()
	if base_pos == Vector2.INF:
		var player := get_tree().get_first_node_in_group("player") as Node2D
		base_pos = player.global_position if player else Vector2.ZERO
	return base_pos


# ─── Run-over cleanup ─────────────────────────────────────────────────
func _on_party_wiped() -> void:
	abort_all_battles()


## Death penalty: the whole party went down → every floating (un-flipped) reward
## window is wiped. That's the risk that makes "어디까지 쌓을까" a gamble.
func _on_party_collapsed() -> void:
	if _window_rects.is_empty():
		return
	var lost: int = _window_rects.size()
	abort_all_battles()
	EventBus.narration.emit("전멸! 띄워둔 보상 %d장이 사라졌다…" % lost)


## Force-close every active battle window. No gold, no signals, no log —
## the run is dead. Used on party_wipe / collapse / (later) explicit run resets.
func abort_all_battles() -> void:
	if _drag_slot >= 0:  # cancel any in-progress drag
		_drag_slot = -1
		_drag_card_starts.clear()
	for window: Node in _window_rects.keys():
		if is_instance_valid(window):
			window.queue_free()
		if _modal_windows.has(window):
			GameState.end_field_battle_pause()
	_window_rects.clear()
	_window_velocities.clear()
	_modal_windows.clear()
	_collision_cooldowns.clear()
	_party_collision_cooldowns.clear()
	# Reset the slot/stack bookkeeping so new fights start from a clean board.
	_window_slot.clear()
	_slot_windows.clear()
	_drag_card_starts.clear()
	for i in _slot_counts.size():
		_slot_counts[i] = 0
	for i in _slot_base.size():
		_slot_base[i] = SLOT_CENTERS[i]
