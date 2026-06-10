@tool
class_name Field
extends Node2D

## Top-down field loop. Spawns enemies + the visible party (player leading,
## companions trailing). Player movement lives on the Player node;
## encounters fire EventBus signals.

const FIELD_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/field_enemy.tscn")
const FIELD_DECORATION_SCENE: PackedScene = preload("res://scenes/decorations/field_decoration.tscn")
const FIELD_ITEM_DROP_SCENE: PackedScene = preload("res://scenes/objects/field_item_drop.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const COMPANION_SCENE: PackedScene = preload("res://scenes/companion.tscn")
const SLIME_DATA: EnemyData = preload("res://data/enemies/slime.tres")
const SLIME_CHASER_DATA: EnemyData = preload("res://data/enemies/slime_chaser.tres")
const BAT_DATA: EnemyData = preload("res://data/enemies/bat.tres")
const ORC_DATA: EnemyData = preload("res://data/enemies/orc.tres")
const BLADE_BUG_DATA: EnemyData = preload("res://data/enemies/blade_bug.tres")
const GRASS_FIELD_TEXTURE: Texture2D = preload("res://assets/sprites/field/grass_field.png")
const TREE_TEXTURE: Texture2D = preload("res://assets/sprites/decorations/tree.png")
const FOREST_TREE_TEXTURE: Texture2D = preload("res://assets/sprites/decorations/forest_tree.png")
const COMBO_ATTACK_TEXTURE: Texture2D = preload("res://assets/sprites/skeleton_scythe.png")
const COMBO_SKELETON_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")
## "쉰다" rest: fast heal while the party is held at the campfire + the green "+" feel.
const REST_HEAL_RATE: float = 14.0     ## HP/sec while resting
const HEAL_FX_INTERVAL: float = 0.32   ## seconds between green "+" pops per member

## Base play-area size in world px. The field is camera-centered, so the hero sits
## dead-center with the side panels overlaying the edges; movement is capped to the
## visible play area (_play_right) and the follow-camera is clamped to these bounds.
##
## EDITABLE IN THE SCENE: the field's on-screen rect is authored by the
## `HudLayer/FieldLayoutRect` control in main.tscn — drag/resize THAT rect in the
## 2D editor and the green board follows live (and the runtime camera places the
## field there). `field_size` is only the fallback used when no layout rect exists
## (e.g. editing field.tscn standalone). NEVER move/scale the Field Node2D itself —
## that distorts every child at runtime, so the editor pins it back to identity.
## `FIELD_SIZE` is a static mirror kept in sync so other scripts (e.g. the left
## log's right-edge clamp) can read it without a node ref.
static var FIELD_SIZE: Vector2 = Vector2(360, 360)
@export var field_size: Vector2 = Vector2(360, 360):
	set(value):
		field_size = value
		FIELD_SIZE = value
		if Engine.is_editor_hint() and is_node_ready():
			_apply_editor_field_size()
@export_node_path("Control") var field_layout_rect_path: NodePath = NodePath("../HudLayer/FieldLayoutRect")
## Plain-green backdrop is oversized this far beyond the map on every side so the
## roaming camera never sees past it into the void.
const BG_MARGIN: float = 1400.0
## Player-driven placement / refill spawns land this far from the hero — kept
## inside the inset field "app window" (the desktop frame hides the far edges).
const SPAWN_NEAR_MIN: float = 48.0
const SPAWN_NEAR_MAX: float = 150.0
## Spawned enemies wander within this half-extent of where they appeared — the
## field is wide again so they have room to roam.
const ENEMY_WANDER_HALF_EXTENT: float = 110.0
## Left edge kept clear for the enemy-toggle bar (matches LeftEnemyBar.BAR_WIDTH)
## so the player + enemies stay out from under it.
const LEFT_UI_INSET: float = 48.0
const TILE_SIZE: int = 16
const SPAWN_MARGIN: float = 24.0
## Don't drop slimes within this radius of the player on field-loop start.
const PARTY_SAFE_RADIUS: float = 48.0
const DECOR_SAFE_RADIUS: float = 104.0
const DROP_PLAYER_SAFE_RADIUS: float = 42.0
const DROP_SEPARATION_RADIUS: float = 20.0
const DROP_SCATTER_RADIUS_MIN: float = 28.0
const DROP_SCATTER_RADIUS_MAX: float = 52.0
const COMBO_ATTACK_KILLS: int = 5
const COMBO_ATTACK_DAMAGE_RATIO: float = 0.35
const COMBO_ATTACK_COOLDOWN: float = 8.0
const GRASS_FIELD_COLOR: Color = Color(0.3529412, 0.70980394, 0.32156864, 1)
const FOREST_FIELD_COLOR: Color = Color(0.18039216, 0.4862745, 0.23921569, 1)

# ─── World-edge diorama: the field reads as a floating island over deep water ──
## How far the void backdrop extends past the field edge. Must comfortably cover
## what the camera can show beyond the edge (half a viewport ≈ 320px).
const VOID_MARGIN: float = 900.0
const DEEP_WATER_COLOR: Color = Color(0.09, 0.18, 0.27, 1.0)
const DEEP_WATER_FOREST_COLOR: Color = Color(0.05, 0.11, 0.16, 1.0)
const VOID_VIGNETTE_COLOR: Color = Color(0.01, 0.02, 0.05, 0.92)
const ISLAND_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.26)
const ISLAND_SHADOW_OFFSET: Vector2 = Vector2(0.0, 12.0)
const ISLAND_SHADOW_EXPAND: float = 14.0
## Thin earthy rim peeking around the grass + a taller, darker cliff face below.
const CLIFF_RIM_COLOR: Color = Color(0.36, 0.26, 0.16, 1.0)
const CLIFF_FACE_COLOR: Color = Color(0.22, 0.15, 0.09, 1.0)
const CLIFF_RIM_FOREST_COLOR: Color = Color(0.26, 0.2, 0.13, 1.0)
const CLIFF_FACE_FOREST_COLOR: Color = Color(0.14, 0.1, 0.07, 1.0)
const CLIFF_RIM: float = 4.0
const CLIFF_FACE_HEIGHT: float = 11.0

@export var initial_slime_count: int = 16
@export var small_forest_cluster_count_min: int = 3
@export var small_forest_cluster_count_max: int = 5
@export var small_forest_min_trees: int = 8
@export var small_forest_max_trees: int = 16
@export var large_forest_cluster_count_min: int = 1
@export var large_forest_cluster_count_max: int = 2
@export var large_forest_min_trees: int = 100
@export var large_forest_max_trees: int = 200
@export var scattered_tree_count: int = 8
@export var spawn_interval: float = 2.5
@export var spawn_batch_size: int = 3
@export var entry_burst_bonus: int = 0
@export var crowd_growth_per_wave: int = 1
@export var max_crowd_pressure: int = 7

@onready var _background: ColorRect = $Background
@onready var _background_texture: TextureRect = $BackgroundTexture
@onready var _decorations_root: Node2D = $Decorations
@onready var _tiles_root: Node2D = $Tiles
@onready var _items_root: Node2D = $Items
@onready var _enemies_root: Node2D = $Enemies
@onready var _party_root: Node2D = $Party
@onready var _message_panel: Panel = %MessagePanel
@onready var _message_label: Label = %MessageLabel

var _player: CharacterBody2D
## Campfire field tile: visual node + the one-time "party walks over → 마법사" event.
var _campfire_node: Node2D
var _sanctuary_node: Node2D
var _campfire_event_pending: bool = false
var _resting: bool = false                ## party is resting at the campfire
var _rest_heal_accum: Dictionary = {}     ## party index -> fractional HP carry
var _heal_fx_accum: Dictionary = {}       ## party index -> green-"+" spawn timer
var _decor_rng := RandomNumberGenerator.new()
var _forest_cells: Dictionary = {}
var _spawn_timer: float = 0.0
var _crowd_pressure: int = 0
var _field_size: Vector2 = FIELD_SIZE
var _loop_complete: bool = false
var _active_battle_windows: int = 0
var _chaser_spawned_this_loop: bool = false
var _combo_kills: int = 0
var _combo_attack_running: bool = false
var _combo_cooldown_remaining: float = 0.0
var _combo_attack_batch_id: int = 0
var _message_tween: Tween
var _warned_about_transform: bool = false  ## editor-only: one warning per session
var _diorama_root: Node2D
var _void_rect: ColorRect
var _void_vignette: TextureRect
var _island_shadow: ColorRect
var _cliff_face: ColorRect
var _cliff_rim: ColorRect


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		_apply_editor_field_size()  # editor-only: show the board at its authored size
		return
	EventBus.party_changed.connect(_setup_party_visuals)
	EventBus.battle_window_opened.connect(_on_battle_window_opened)
	EventBus.battle_window_closed.connect(_on_battle_window_closed)
	EventBus.all_battles_resolved.connect(_check_refill_after_battles)
	EventBus.field_loop_started.connect(_on_field_loop_started)
	EventBus.field_item_drop_requested.connect(_on_field_item_drop_requested)
	EventBus.field_gold_drop_requested.connect(_on_field_gold_drop_requested)
	EventBus.field_loop_finish_requested.connect(_on_field_loop_finish_requested)
	EventBus.enemy_encountered.connect(_on_enemy_encountered_for_story)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.skill_node_purchase_succeeded.connect(_on_skill_node_purchase_succeeded)
	EventBus.combat_upgrade_changed.connect(_on_combat_upgrade_changed)
	EventBus.companion_appeared.connect(_on_companion_appeared)
	EventBus.companion_recruited.connect(_on_companion_recruited)
	EventBus.party_member_downed.connect(_on_party_member_downed_visual)
	EventBus.party_member_revived.connect(_on_party_member_revived_visual)
	EventBus.campfire_placed.connect(_on_campfire_placed)
	EventBus.enemy_place_requested.connect(_on_enemy_place_requested)
	EventBus.building_built.connect(_on_building_built)
	EventBus.structure_placed.connect(_on_structure_placed)
	EventBus.rest_requested.connect(_begin_rest)
	EventBus.structure_visit_requested.connect(_on_structure_visit_requested)
	EventBus.world_started.connect(_on_world_started)
	EventBus.rescue_offered.connect(_on_rescue_offered)
	_hide_message()
	# Cover the case where party was already set before this scene mounted.
	_setup_party_visuals()
	_apply_field_size()        # oversize the plain backdrop so the void fills the screen
	_apply_world_visibility()  # opening: black field + hero only until grass is laid


# ─── Opening: black field until the grass is laid ──────────────────────
## Before world_started, hide the terrain/decorations/diorama and paint the base
## black — only the hero stands in the void. Laying grass reveals it all.
func _apply_world_visibility() -> void:
	var started: bool = GameState.world_started
	if _decorations_root != null:
		_decorations_root.visible = started
	if _diorama_root != null:
		_diorama_root.visible = started
	if not started:
		if _background_texture != null:
			_background_texture.visible = false
		if _background != null:
			_background.color = Color(0.035, 0.04, 0.05, 1.0)  # near-black void


func _on_world_started() -> void:
	# Reveal the world the player just "laid": fade the plain-green field in over
	# the opening void. (Island diorama / grass texture stay off — plain green.)
	_apply_field_background()
	if _decorations_root != null:
		_decorations_root.visible = true
		_decorations_root.modulate.a = 0.0
		create_tween().tween_property(_decorations_root, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_apply_editor_field_size()
		return
	if GameState.field_loop_count <= 0 or GameState.is_party_wiped():
		return
	_tick_campfire(delta)  # proximity regen + first-place mage event (runs always)
	_tick_rest(delta)      # "쉰다": walk to fire, hold, fast-heal to full (runs always)
	_tick_structure_walk() # release the post-placement walk once the hero arrives
	_combo_cooldown_remaining = maxf(0.0, _combo_cooldown_remaining - delta)
	if GameState.is_field_frozen_for_battle():
		return
	if _loop_complete:
		return
	# Incremental model: the field continuously maintains a population of the
	# toggled-on tiers. Killed/cleared enemies are replenished toward the target.
	# Toggling a tier OFF just stops it joining the spawn mix (random_active_tier
	# _enemy_data drops it) — existing wanderers are never culled.
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval * GameState.field_spawn_interval_multiplier()
	_grow_crowd_pressure()
	_refill_enemy_population(spawn_batch_size + GameState.field_spawn_batch_bonus())


# ─── Party visuals (data-driven) ──────────────────────────────────────
## Rebuilds the visible party from GameState.party. Slot 0 = player avatar,
## slots 1..N = companions trailing each previous member like a JRPG snake.
func _setup_party_visuals() -> void:
	var start_position: Vector2 = _player.position if _player != null else _field_size * 0.5
	for child in _party_root.get_children():
		child.queue_free()
	_player = null
	if GameState.party_size() == 0:
		return
	_player = PLAYER_SCENE.instantiate() as CharacterBody2D
	_player.setup(GameState.party[0])
	if _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)
	if _player.has_method("set_camera_world_center"):
		_player.set_camera_world_center(_camera_world_center())
	_player.position = start_position
	_party_root.add_child(_player)
	for i in range(1, GameState.party_size()):
		var comp := COMPANION_SCENE.instantiate()
		comp.setup(GameState.party[i])
		comp.player = _player
		comp.slot_index = i
		comp.position = _player.position
		_party_root.add_child(comp)
		comp.call_deferred("snap_to_formation")


# ─── Enemy spawning ───────────────────────────────────────────────────
func _on_field_loop_started(_loop_num: int) -> void:
	_decor_rng.randomize()
	_apply_field_size()
	_apply_field_background()
	_combo_kills = 0
	_combo_attack_running = false
	_combo_cooldown_remaining = 0.0
	_loop_complete = false
	_active_battle_windows = 0
	_chaser_spawned_this_loop = false
	EventBus.field_loop_timer_changed.emit(-1)
	_clear_field_enemies()
	_clear_decorations()
	_clear_items()
	_crowd_pressure = entry_burst_bonus
	_recenter_party()
	_scatter_region_decorations()
	_spawn_timer = spawn_interval
	_refill_enemy_population(_desired_enemy_count())
	_apply_world_visibility()  # keep the field black until the grass is laid
	if GameState.STORY_MODE_ENABLED:
		var intro: String = GameState.story_field_intro()
		if not intro.is_empty():
			_show_message(intro)


## Teleport the whole party back to the field center for a fresh start.
## Without this, party would drift further and further from spawn each loop.
## Right edge of the VISIBLE play area in world x. The field fills 640 but the
## right panel overlays its far edge, so player/enemy movement caps here so the
## hero never wanders behind the panel.
## Right edge of the WORLD placement area. The right panel is screen-space now
## (battle windows handle that inset), so world placement uses the full map width.
func _play_right() -> float:
	return _field_size.x


## Movement bounds max — visible play area (not the full background width).
func _play_bounds_max() -> Vector2:
	return Vector2(_play_right(), _field_size.y)


func _recenter_party() -> void:
	if _player == null:
		return
	var center: Vector2 = _field_size * 0.5
	if _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)
	if _player.has_method("set_camera_world_center"):
		_player.set_camera_world_center(_camera_world_center())
	_player.position = center
	# Center the fixed camera on the field center → hero at true viewport center.
	if _player.has_method("recenter_camera"):
		_player.recenter_camera(center)
	elif _player.has_method("snap_camera"):
		_player.snap_camera()
	for child in _party_root.get_children():
		if child.is_in_group("party_member") and child != _player:
			if child.has_method("snap_to_formation"):
				child.snap_to_formation()
			else:
				child.position = center


func _clear_field_enemies() -> void:
	for child in _enemies_root.get_children():
		_enemies_root.remove_child(child)
		child.queue_free()


func _despawn_field_enemies() -> void:
	for child in _enemies_root.get_children():
		if child is FieldEnemy:
			(child as FieldEnemy).despawn_with_pop()
		else:
			child.queue_free()


func _clear_decorations() -> void:
	_forest_cells.clear()
	for child in _decorations_root.get_children():
		child.queue_free()


func _clear_items() -> void:
	for child in _items_root.get_children():
		child.queue_free()


func _on_enemy_defeated(_enemy: Node, _gold: int, _world_position: Vector2) -> void:
	if _loop_complete or GameState.field_loop_count <= 0:
		return
	if GameState.STORY_MODE_ENABLED and GameState.story_should_recruit_first_companion():
		if GameState.story_recruit_first_companion():
			_show_message(GameState.story_first_companion_join_message())
	if GameState.combo_attack_unlocked() and not _combo_attack_running and _combo_cooldown_remaining <= 0.0:
		_combo_kills += 1
		if _combo_kills >= COMBO_ATTACK_KILLS:
			var targets: Array[FieldEnemy] = _combo_attack_targets()
			if targets.is_empty():
				return
			_combo_kills = 0
			_trigger_combo_attack(targets)


func _on_enemy_encountered_for_story(_enemy: Node) -> void:
	var line: String = GameState.story_claim_movement_battle_line()
	if line.is_empty():
		return
	_show_player_speech_bubble(line)


func _trigger_combo_attack(targets: Array[FieldEnemy]) -> void:
	if _combo_attack_running:
		return
	if targets.is_empty():
		return
	_combo_attack_running = true
	_combo_cooldown_remaining = COMBO_ATTACK_COOLDOWN
	_combo_attack_batch_id += 1
	_show_message("합체 공격! 거대 해골이 전장을 쓸어버립니다.")
	await _play_combo_skeleton(targets, _combo_attack_batch_id)
	_combo_attack_running = false


## A giant reaper skeleton rears up from below the screen, cackles "하하하!",
## then swings its scythe to wipe the field. Screen-space spectacle on its own
## CanvasLayer; the per-target scythes and field-wide damage fire on the swing.
func _play_combo_skeleton(targets: Array[FieldEnemy], combo_batch_id: int) -> void:
	const REST_Y: float = 186.0
	const HIDDEN_Y: float = 560.0
	const SKULL_X: float = 240.0

	var layer := CanvasLayer.new()
	layer.name = "ComboSkeletonLayer"
	layer.layer = 9
	add_child(layer)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.0, 0.06, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dim)

	var skeleton := Sprite2D.new()
	skeleton.texture = COMBO_ATTACK_TEXTURE
	skeleton.centered = true
	skeleton.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	skeleton.scale = Vector2(2.3, 2.3)
	skeleton.position = Vector2(SKULL_X, HIDDEN_Y)
	skeleton.rotation_degrees = -6.0
	layer.add_child(skeleton)

	var laugh := Label.new()
	laugh.text = "하하하!"
	laugh.add_theme_font_override("font", COMBO_SKELETON_FONT)
	laugh.add_theme_font_size_override("font_size", 34)
	laugh.add_theme_color_override("font_color", Color(0.97, 1.0, 0.92, 1.0))
	laugh.add_theme_color_override("font_outline_color", Color(0.05, 0.01, 0.08, 1.0))
	laugh.add_theme_constant_override("outline_size", 6)
	laugh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	laugh.position = Vector2(274.0, 60.0)
	laugh.pivot_offset = Vector2(48.0, 22.0)
	laugh.scale = Vector2(0.3, 0.3)
	laugh.modulate = Color(1.0, 1.0, 1.0, 0.0)
	layer.add_child(laugh)

	# 1) Darken the field and let the skeleton burst up from below.
	var rise := create_tween()
	rise.set_parallel(true)
	rise.tween_property(dim, "color", Color(0.03, 0.0, 0.06, 0.5), 0.28)
	rise.tween_property(skeleton, "position:y", REST_Y, 0.36)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await rise.finished

	# 2) Cackle: text pops in while the skull bobs.
	var laugh_tween := create_tween()
	laugh_tween.tween_property(laugh, "modulate:a", 1.0, 0.08)
	laugh_tween.parallel().tween_property(laugh, "scale", Vector2(1.18, 1.18), 0.14)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	laugh_tween.tween_property(laugh, "scale", Vector2(1.0, 1.0), 0.08)
	var bob := create_tween()
	bob.set_loops(3)
	bob.tween_property(skeleton, "position:y", REST_Y - 9.0, 0.09).set_trans(Tween.TRANS_SINE)
	bob.tween_property(skeleton, "position:y", REST_Y, 0.09).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.58).timeout

	# 3) Wind the scythe back, then swing down hard.
	var windup := create_tween()
	windup.tween_property(skeleton, "rotation_degrees", -22.0, 0.13)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await windup.finished
	var swing := create_tween()
	swing.tween_property(skeleton, "rotation_degrees", 24.0, 0.08)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await swing.finished

	# 4) Impact — flash, per-target scythes, field-wide damage.
	_flash_screen(layer)
	for target: FieldEnemy in targets:
		if is_instance_valid(target):
			_spawn_combo_scythe(target.global_position)
	for target: FieldEnemy in targets:
		if is_instance_valid(target):
			target.trigger_combo_encounter(combo_batch_id)
	var fade_laugh := create_tween()
	fade_laugh.tween_property(laugh, "modulate:a", 0.0, 0.12)
	await get_tree().process_frame
	await get_tree().process_frame
	EventBus.combo_attack_damage_requested.emit(COMBO_ATTACK_DAMAGE_RATIO, combo_batch_id)
	var settle := create_tween()
	settle.tween_property(skeleton, "rotation_degrees", 6.0, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.42).timeout

	# 5) Sink back below and clear the overlay.
	var sink := create_tween()
	sink.set_parallel(true)
	sink.tween_property(skeleton, "position:y", HIDDEN_Y, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	sink.tween_property(dim, "color", Color(0.03, 0.0, 0.06, 0.0), 0.3)
	await sink.finished
	layer.queue_free()


func _flash_screen(layer: CanvasLayer) -> void:
	var flash := ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1.0, 1.0, 1.0, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	var t := create_tween()
	t.tween_property(flash, "color:a", 0.7, 0.04)
	t.tween_property(flash, "color:a", 0.0, 0.18)
	t.tween_callback(Callable(flash, "queue_free"))


func _combo_attack_targets() -> Array[FieldEnemy]:
	var targets: Array[FieldEnemy] = []
	var visible_rect: Rect2 = _visible_world_rect()
	for child: Node in _enemies_root.get_children():
		if child is FieldEnemy and not child.is_queued_for_deletion() and visible_rect.has_point((child as FieldEnemy).global_position):
			targets.append(child as FieldEnemy)
	return targets


func _visible_world_rect() -> Rect2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return Rect2(Vector2.ZERO, viewport_size)
	var visible_size: Vector2 = viewport_size * camera.zoom
	return Rect2(camera.get_screen_center_position() - visible_size * 0.5, visible_size)


func _spawn_combo_scythe(world_position: Vector2) -> void:
	var effect := Node2D.new()
	effect.name = "ComboScythe"
	effect.z_index = 80
	add_child(effect)
	effect.global_position = world_position

	var sprite := Sprite2D.new()
	sprite.texture = COMBO_ATTACK_TEXTURE
	sprite.centered = true
	sprite.position = Vector2(0.0, 18.0)
	sprite.scale = Vector2(0.72, 0.18)
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	sprite.rotation_degrees = -10.0
	effect.add_child(sprite)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.08)
	tween.tween_property(sprite, "position:y", -10.0, 0.16)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.16)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "rotation_degrees", 18.0, 0.16)\
		.set_trans(Tween.TRANS_QUAD)\
		.set_ease(Tween.EASE_OUT)
	tween.chain().set_parallel(true)
	tween.tween_property(sprite, "position:x", 10.0, 0.06)
	tween.tween_property(sprite, "rotation_degrees", -22.0, 0.06)
	tween.chain().set_parallel(true)
	tween.tween_property(sprite, "position:x", -10.0, 0.06)
	tween.tween_property(sprite, "rotation_degrees", 26.0, 0.06)
	tween.chain().set_parallel(true)
	tween.tween_property(sprite, "position:x", 0.0, 0.08)
	tween.tween_property(sprite, "position:y", -24.0, 0.12)
	tween.tween_property(sprite, "scale", Vector2(1.38, 0.32), 0.12)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.12)
	tween.chain().tween_callback(Callable(effect, "queue_free"))


func _show_message(text: String) -> void:
	# Mirror every field message into the always-on narration window (OS desktop).
	EventBus.narration.emit(text)
	if _message_panel == null or _message_label == null:
		return
	_message_label.text = text
	_message_panel.visible = true
	_message_panel.modulate.a = 0.0
	if _message_tween and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(_message_panel, "modulate:a", 1.0, 0.12)
	_message_tween.tween_interval(2.0)
	_message_tween.tween_property(_message_panel, "modulate:a", 0.0, 0.2)
	_message_tween.tween_callback(_hide_message)


## Gold hit 0 with nothing in progress → the dock offers a free rescue slime.
## Flash the overlord's intervention line (a seed for later narrative).
func _on_rescue_offered() -> void:
	_show_message("[저런..]")


func _hide_message() -> void:
	if _message_panel:
		_message_panel.visible = false
		_message_panel.modulate.a = 0.0


func _show_player_speech_bubble(text: String) -> void:
	if _player == null or not is_instance_valid(_player) or GameState.party_size() <= 0:
		return
	var bubble := Panel.new()
	bubble.name = "PlayerSpeechBubble"
	bubble.size = Vector2(134.0, 28.0)
	var anchor: Vector2 = GameState.party[0].speech_anchor_local()
	bubble.position = anchor + Vector2(-bubble.size.x * 0.5, -bubble.size.y - 6.0)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = 120
	bubble.add_theme_stylebox_override("panel", _speech_bubble_style())
	_player.add_child(bubble)

	var tail := ColorRect.new()
	tail.name = "Tail"
	tail.size = Vector2(7.0, 7.0)
	tail.position = Vector2(bubble.size.x * 0.5 - 3.5, bubble.size.y - 3.0)
	tail.rotation = deg_to_rad(45.0)
	tail.color = Color(1.0, 0.96, 0.82, 1.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(tail)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 7.0
	label.offset_right = -7.0
	label.add_theme_font_override("font", COMBO_SKELETON_FONT)
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)
	_play_player_speech_bubble(bubble, label, text)


func _play_player_speech_bubble(bubble: Control, label: Label, text: String) -> void:
	bubble.modulate.a = 0.0
	bubble.scale = Vector2(0.78, 0.78)
	bubble.pivot_offset = bubble.size * 0.5
	var pop := create_tween()
	pop.tween_property(bubble, "modulate:a", 1.0, 0.06)
	pop.parallel().tween_property(bubble, "scale", Vector2(1.05, 1.05), 0.08)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	pop.tween_property(bubble, "scale", Vector2.ONE, 0.05)
	await pop.finished
	label.text = ""
	for i in text.length():
		label.text = text.substr(0, i + 1)
		await get_tree().create_timer(0.03).timeout
	await get_tree().create_timer(0.75).timeout
	if not is_instance_valid(bubble):
		return
	var fade := create_tween()
	fade.tween_property(bubble, "modulate:a", 0.0, 0.12)
	fade.parallel().tween_property(bubble, "scale", Vector2(0.86, 0.86), 0.12)
	fade.tween_callback(Callable(bubble, "queue_free"))


func _speech_bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.96, 0.82, 1.0)
	style.border_color = Color(0.12, 0.09, 0.05, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


func _scatter_decorations() -> void:
	if not GameState.has_skill_node(&"map_expand"):
		return
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var occupied: Dictionary = {}
	var large_count: int = _decor_range(large_forest_cluster_count_min, large_forest_cluster_count_max)
	for i in large_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			large_forest_min_trees,
			large_forest_max_trees,
			7,
			10
		)
	var small_count: int = _decor_range(small_forest_cluster_count_min, small_forest_cluster_count_max)
	for i in small_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			small_forest_min_trees,
			small_forest_max_trees,
			2,
			4
		)
	for i in scattered_tree_count:
		var cell: Vector2i = _random_decor_cell(safe_origin, occupied)
		if cell == Vector2i(-1, -1):
			return
		_add_tree_cell(cell, occupied)


func _scatter_region_decorations() -> void:
	if GameState.current_field_region_id == GameState.FIELD_REGION_FOREST:
		_scatter_forest_field_decorations()
	else:
		_scatter_decorations()


func _scatter_forest_field_decorations() -> void:
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var occupied: Dictionary = {}
	var large_count: int = maxi(1, _decor_range(large_forest_cluster_count_min, large_forest_cluster_count_max))
	for i in large_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			large_forest_min_trees,
			large_forest_max_trees,
			7,
			10
		)
	var small_count: int = maxi(2, _decor_range(small_forest_cluster_count_min, small_forest_cluster_count_max))
	for i in small_count:
		_add_forest_cluster(
			safe_origin,
			occupied,
			small_forest_min_trees,
			small_forest_max_trees,
			2,
			4
		)


func _add_decoration(texture: Texture2D, pos: Vector2) -> void:
	var sprite := FIELD_DECORATION_SCENE.instantiate() as Sprite2D
	sprite.texture = texture
	sprite.position = pos
	sprite.scale = Vector2.ONE
	_decorations_root.add_child(sprite)


func _add_forest_cluster(
	avoid: Vector2,
	occupied: Dictionary,
	min_trees: int,
	max_trees: int,
	min_radius: int,
	max_radius: int
) -> void:
	var center: Vector2i = _random_decor_cell(avoid, occupied)
	if center == Vector2i(-1, -1):
		return
	var target_count: int = _decor_range(min_trees, max_trees)
	var radius: int = _decor_range(min_radius, max_radius)
	var cluster: Array[Vector2i] = [center]
	var cluster_set: Dictionary = { center: true }
	var attempts: int = target_count * 28
	while cluster.size() < target_count and attempts > 0:
		attempts -= 1
		var anchor: Vector2i = cluster[_decor_rng.randi_range(0, cluster.size() - 1)]
		var candidate: Vector2i = anchor + _random_forest_step()
		if cluster_set.has(candidate):
			continue
		if not _is_valid_decor_cell(candidate, avoid, occupied):
			continue
		var offset := Vector2(candidate - center)
		var distance: float = offset.length()
		var soft_radius: float = float(radius) + _decor_rng.randf_range(-0.8, 1.15)
		if distance > soft_radius:
			continue
		var keep_chance: float = clampf(1.08 - (distance / maxf(float(radius), 1.0)) * 0.58, 0.38, 0.96)
		if _decor_rng.randf() > keep_chance:
			continue
		cluster.append(candidate)
		cluster_set[candidate] = true
	for cell in cluster:
		_add_tree_cell(cell, occupied, true)


func _random_forest_step() -> Vector2i:
	var steps: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	return steps[_decor_rng.randi_range(0, steps.size() - 1)]


func _decor_range(min_value: int, max_value: int) -> int:
	return _decor_rng.randi_range(mini(min_value, max_value), maxi(min_value, max_value))


func _add_tree_cell(cell: Vector2i, occupied: Dictionary, is_forest: bool = false) -> void:
	occupied[cell] = true
	if is_forest:
		_forest_cells[cell] = true
	var texture: Texture2D = FOREST_TREE_TEXTURE if GameState.current_field_region_id == GameState.FIELD_REGION_FOREST else TREE_TEXTURE
	_add_decoration(texture, _cell_to_world(cell))


func _random_decor_cell(avoid: Vector2, occupied: Dictionary) -> Vector2i:
	for attempt in 80:
		var cell := Vector2i(
			_decor_rng.randi_range(_min_grid_index(), _max_grid_x()),
			_decor_rng.randi_range(_min_grid_index(), _max_grid_y())
		)
		if _is_valid_decor_cell(cell, avoid, occupied):
			return cell
	return Vector2i(-1, -1)


func _is_valid_decor_cell(cell: Vector2i, avoid: Vector2, occupied: Dictionary) -> bool:
	if occupied.has(cell):
		return false
	var pos: Vector2 = _cell_to_world(cell)
	return pos.distance_to(avoid) >= DECOR_SAFE_RADIUS


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE_SIZE + TILE_SIZE * 0.5, cell.y * TILE_SIZE + TILE_SIZE * 0.5)


func _min_grid_index() -> int:
	return ceili(SPAWN_MARGIN / float(TILE_SIZE))


func _max_grid_x() -> int:
	return floori((_play_right() - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _max_grid_y() -> int:
	return floori((_field_size.y - SPAWN_MARGIN) / float(TILE_SIZE)) - 1


func _grow_crowd_pressure() -> void:
	if _active_field_enemy_count() <= 0:
		_crowd_pressure = 0
		return
	_crowd_pressure = mini(max_crowd_pressure + GameState.field_crowd_cap_bonus(), _crowd_pressure + crowd_growth_per_wave)


## A tier was toggled (left bar). Turning one ON should feel instant, so we top
## up the population right away — but this only ADDS toward the target count and
## NEVER clears. So toggling a tier OFF leaves its existing wanderers alive; they
## simply stop being respawned (random_active_tier_enemy_data drops the tier).
func _on_combat_upgrade_changed(axis: StringName) -> void:
	if axis != &"tier":
		return
	if GameState.field_loop_count <= 0 or _loop_complete:
		return
	_spawn_timer = 0.0
	_refill_enemy_population(_desired_enemy_count())


# ─── Companions ────────────────────────────────────────────────────────
## A companion appeared (its building was built) — announce the "만남" so the
## player knows a recruit is now available in the panel.
func _on_companion_appeared(id: StringName) -> void:
	# Event-driven recruits (모닥불→마법사, 성소→사제) get their moment in the
	# 이벤트 창 instead — no spoiler banner on placement.
	if id == &"mage" or id == &"priest":
		return
	var comp: Dictionary = Balance.companion_by_id(id)
	_show_message(str(comp.get("appear_text", "새로운 동료가 나타났다!")))


## A companion actually joined the party (영입 완료).
func _on_companion_recruited(id: StringName) -> void:
	var comp: Dictionary = Balance.companion_by_id(id)
	_show_message("%s이(가) 합류했다!" % str(comp.get("name", "동료")))


# ─── Campfire tile (field-placed HP-regen outpost) ─────────────────────
## Player paid for the campfire → drop it at a random spot, point the party at it
## for the one-time mage-arrival event.
func _on_campfire_placed() -> void:
	if is_instance_valid(_campfire_node):
		return
	var pos: Vector2
	if GameState.pending_placement_position != Vector2.INF:
		pos = _clamp_field_position(GameState.pending_placement_position)
		GameState.pending_placement_position = Vector2.INF
	else:
		pos = _random_campfire_position()
	GameState.set_campfire_position(pos)
	_campfire_node = FieldStructure.new()
	_campfire_node.setup(Balance.tile_by_id(&"campfire"))
	_campfire_node.position = pos
	_decorations_root.add_child(_campfire_node)
	# First placement: party auto-walks to the fire, then 마법사 appears + joins.
	# (No 방문 창 here — the story beat owns the arrival; later visits go through
	# the [간다] bubble like any other structure.)
	# No announcement banner here — the walk + 이벤트 창 carry the moment.
	_campfire_event_pending = true
	if _player and _player.has_method("set_forced_move_target"):
		_player.set_forced_move_target(pos)


## How near the hero must get to a freshly placed structure before it stops
## auto-walking toward it and resumes normal roaming.
const STRUCTURE_ARRIVE_DIST: float = 20.0
## World point the party is currently walking toward after placing a structure
## (e.g. the village), or INF when not reacting.
var _structure_walk_target: Vector2 = Vector2.INF
## The structure node the hero is walking to — its 방문 창 opens on arrival.
var _structure_walk_node: Node2D = null


## Generic TILES structures (village, …) — spawn the sprite at the dropped spot.
func _on_structure_placed(tile_id: StringName) -> void:
	var pos: Vector2
	if GameState.pending_placement_position != Vector2.INF:
		pos = _clamp_field_position(GameState.pending_placement_position)
		GameState.pending_placement_position = Vector2.INF
	else:
		pos = _spawn_position_near_player(_player.position if _player else _field_size * 0.5)
	var node := FieldStructure.new()
	node.setup(Balance.tile_by_id(tile_id))
	node.position = pos
	_decorations_root.add_child(node)
	# RPG flow: the party walks over to the freshly placed structure, and its
	# 방문 창 opens on arrival (see _tick_structure_walk).
	_begin_structure_visit(node)
	var sname: String = str(Balance.tile_by_id(tile_id).get("name", "무언가"))
	_show_message("%s%s 발견했다!" % [sname, _kor_obj_particle(sname)])


## Korean object particle: 을 after a syllable WITH a final consonant (받침), else
## 를. Picks the right one off the last character so messages read naturally.
func _kor_obj_particle(word: String) -> String:
	if word.is_empty():
		return "을"
	var code: int = word[word.length() - 1].unicode_at(0)
	if code >= 0xAC00 and code <= 0xD7A3:  # Hangul syllable block
		return "을" if (code - 0xAC00) % 28 != 0 else "를"
	return "을"


## Start an RPG "visit": the hero walks to the structure; on arrival its 방문 창
## opens (마을 → 상점/여관, 모닥불 → 쉰다/강화 …) and the field holds still.
func _begin_structure_visit(node: Node2D) -> void:
	if node == null:
		return
	_structure_walk_target = node.position
	_structure_walk_node = node
	if _player and _player.has_method("set_forced_move_target"):
		_player.set_forced_move_target(node.position)


## [간다] pressed on a structure's bubble (or any future visit trigger).
func _on_structure_visit_requested(structure: Node) -> void:
	if structure is Node2D and is_instance_valid(structure):
		_begin_structure_visit(structure as Node2D)


## Once the hero reaches the visited structure: stop walking and swing open its
## window — a story 이벤트 창 if this arrival owns one (e.g. the sanctuary's
## priest meeting), else the regular 방문 창. Either freezes the field.
func _tick_structure_walk() -> void:
	if _structure_walk_target == Vector2.INF or _player == null:
		return
	if _player.global_position.distance_to(_structure_walk_target) <= STRUCTURE_ARRIVE_DIST:
		_structure_walk_target = Vector2.INF
		var node: Node2D = _structure_walk_node
		_structure_walk_node = null
		if _player.has_method("clear_forced_move_target"):
			_player.clear_forced_move_target()
		if is_instance_valid(node):
			if node.has_method("pulse"):
				node.pulse()
			var event_id: StringName = _arrival_event_for(node)
			if event_id != &"":
				EventBus.event_window_requested.emit(event_id)
			else:
				EventBus.object_window_requested.emit(node)


## One-time story beats that hijack a structure arrival. Returns &"" when the
## arrival should just open the normal 방문 창.
func _arrival_event_for(node: Node2D) -> StringName:
	if node == _sanctuary_node and not GameState.is_companion_recruited(&"priest"):
		return &"sanctuary_priest"
	return &""


## Drag-placed buildings that live on the field (sanctuary). Spawn a structure at
## the dropped spot so it actually shows up + is clickable.
func _on_building_built(id: StringName) -> void:
	if id != &"sanctuary" or is_instance_valid(_sanctuary_node):
		return
	var pos: Vector2
	if GameState.pending_placement_position != Vector2.INF:
		pos = _clamp_field_position(GameState.pending_placement_position)
		GameState.pending_placement_position = Vector2.INF
	else:
		pos = _spawn_position_near_player(_player.position if _player else _field_size * 0.5)
	_sanctuary_node = FieldStructure.new()
	_sanctuary_node.setup(Balance.building_by_id(&"sanctuary"))
	_sanctuary_node.position = pos
	_decorations_root.add_child(_sanctuary_node)
	# RPG flow: walk over + open its 방문 창 on arrival, same as TILES structures.
	_begin_structure_visit(_sanctuary_node)


func _random_campfire_position() -> Vector2:
	# Near the hero so a player-placed campfire lands on-screen on the large map.
	var origin: Vector2 = _player.position if _player else _field_size * 0.5
	return _spawn_position_near_player(origin)


## Per-frame: heal party members standing near the campfire; trigger the mage
## event once the party reaches it the first time.
func _tick_campfire(delta: float) -> void:
	if not GameState.campfire_placed or not is_instance_valid(_campfire_node):
		return
	var center: Vector2 = _campfire_node.position
	var radius: float = GameState.campfire_regen_radius()
	# Collect in-range party member indices for proximity regen.
	var in_range: Array[int] = []
	for child in _party_root.get_children():
		var idx: int = _party_member_index_of(child)
		if idx < 0:
			continue
		if (child as Node2D).position.distance_to(center) <= radius:
			in_range.append(idx)
	GameState.tick_campfire_regen(in_range, delta)
	# One-time mage event: party reached the fire → play the 이벤트 창 cutscene
	# (모닥불 앞에서 메이지와 첫 만남 — the join happens at the scene's end).
	if _campfire_event_pending and _player and _player.position.distance_to(center) <= radius:
		_campfire_event_pending = false
		if _player.has_method("clear_forced_move_target"):
			_player.clear_forced_move_target()
		if _campfire_node.has_method("pulse"):
			_campfire_node.pulse()
		EventBus.event_window_requested.emit(&"campfire_mage")


# ─── Campfire "쉰다" (rest): walk over, hold, fast-heal to full ─────────
func _begin_rest() -> void:
	if not GameState.campfire_placed or not is_instance_valid(_campfire_node):
		return
	var bm: Node = get_tree().get_first_node_in_group("battle_manager")
	if bm != null and bm.has_method("pending_window_count") and int(bm.pending_window_count()) > 0:
		_show_message("전투가 끝나야 쉴 수 있다.")
		return
	if GameState.is_party_full_hp():
		_show_message("이미 충분히 쉬었다.")
		return
	_resting = true
	if _player and _player.has_method("set_forced_move_target"):
		_player.set_forced_move_target(_campfire_node.position)  # walk the party over


func _end_rest() -> void:
	if not _resting:
		return
	_resting = false
	GameState.party_resting = false
	_rest_heal_accum.clear()
	_heal_fx_accum.clear()
	if _player and _player.has_method("clear_forced_move_target"):
		_player.clear_forced_move_target()


func _tick_rest(delta: float) -> void:
	if not _resting:
		return
	if not GameState.campfire_placed or not is_instance_valid(_campfire_node):
		_end_rest()
		return
	# A fight broke out → can't rest mid-battle.
	var bm: Node = get_tree().get_first_node_in_group("battle_manager")
	if bm != null and bm.has_method("pending_window_count") and int(bm.pending_window_count()) > 0:
		_end_rest()
		return
	# Still walking over → freeze the party once they reach the fire.
	if not GameState.party_resting:
		if _player and _player.position.distance_to(_campfire_node.position) <= GameState.campfire_regen_radius():
			GameState.party_resting = true  # hold still (is_movement_frozen)
			if _player.has_method("clear_forced_move_target"):
				_player.clear_forced_move_target()
		return
	_rest_heal(delta)
	if GameState.is_party_full_hp():
		_end_rest()


func _rest_heal(delta: float) -> void:
	for child in _party_root.get_children():
		var idx: int = _party_member_index_of(child)
		if idx < 0 or not GameState.is_combat_ready(idx):
			continue
		if GameState.party_hp[idx] >= GameState.effective_max_hp(idx):
			continue
		var carry: float = float(_rest_heal_accum.get(idx, 0.0)) + REST_HEAL_RATE * delta
		var whole: int = int(carry)
		_rest_heal_accum[idx] = carry - float(whole)
		if whole >= 1:
			GameState.heal_party_member(idx, whole)
		# Green "+" pop above the healing member (뿅뿅뿅).
		var fx: float = float(_heal_fx_accum.get(idx, 0.0)) + delta
		if fx >= HEAL_FX_INTERVAL:
			fx = 0.0
			_spawn_heal_plus(child as Node2D)
		_heal_fx_accum[idx] = fx


## A small green "+" that pops above a healing avatar and floats up — retro juice.
func _spawn_heal_plus(avatar: Node2D) -> void:
	if avatar == null:
		return
	var lbl := Label.new()
	lbl.text = "+"
	lbl.add_theme_font_override("font", COMBO_SKELETON_FONT)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.36, 1.0, 0.45, 1.0))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.position = Vector2(randf_range(-7.0, 5.0), -20.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.add_child(lbl)
	var t := create_tween().set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - 12.0, 0.5).set_trans(Tween.TRANS_QUAD)
	t.tween_property(lbl, "modulate:a", 0.0, 0.5)
	t.chain().tween_callback(lbl.queue_free)


## Map a party-visual node back to its GameState party index. Player = 0,
## companions carry slot_index. -1 if it's not a party member.
func _party_member_index_of(node: Node) -> int:
	if node == _player:
		return 0
	if "slot_index" in node:
		return int(node.slot_index)
	return -1


# ─── Downed avatar pose (lie down while refilling, stand when full) ─────
func _on_party_member_downed_visual(index: int) -> void:
	_set_avatar_downed(index, true)


func _on_party_member_revived_visual(index: int) -> void:
	_set_avatar_downed(index, false)


func _set_avatar_downed(index: int, is_down: bool) -> void:
	var avatar: Node = _avatar_for_party_index(index)
	if avatar and avatar.has_method("set_downed_visual"):
		avatar.set_downed_visual(is_down)


## Index 0 = the player avatar; index > 0 = the companion with that slot_index.
func _avatar_for_party_index(index: int) -> Node:
	if index == 0:
		return _player
	for child in _party_root.get_children():
		if child is Companion and child.slot_index == index:
			return child
	return null


func _refill_enemy_population(max_to_spawn: int) -> void:
	var desired_count: int = _desired_enemy_count()
	var missing_count: int = desired_count - _active_field_enemy_count()
	var spawn_count: int = maxi(0, mini(max_to_spawn, missing_count))
	for i in spawn_count:
		_spawn_field_enemy(_enemy_data_for_current_nodes())


func _active_field_enemy_count() -> int:
	var count: int = 0
	for child in _enemies_root.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


func _on_battle_window_opened(_window: Node) -> void:
	_active_battle_windows += 1


func _on_battle_window_closed(_window: Node) -> void:
	_active_battle_windows = maxi(0, _active_battle_windows - 1)


func debug_spawn_all_enemy_types() -> int:
	var enemy_types: Array[EnemyData] = [
		SLIME_DATA,
		SLIME_CHASER_DATA,
		BAT_DATA,
		ORC_DATA,
		BLADE_BUG_DATA,
	]
	for data: EnemyData in enemy_types:
		_spawn_field_enemy(data)
	return enemy_types.size()


func _desired_enemy_count() -> int:
	return _enemy_count_for_current_nodes() + _crowd_pressure


## Player clicked an enemy in the dock (already paid). Drop ONE at a random spot.
func _on_enemy_place_requested(tier_id: StringName) -> void:
	if GameState.field_loop_count <= 0:
		return
	var data: EnemyData = GameState.tier_enemy_data(tier_id)
	if data != null:
		_spawn_field_enemy(data)


func _spawn_field_enemy(data: EnemyData) -> void:
	if data == null:
		return  # every tier toggled off → nothing to spawn this tick
	var safe_origin: Vector2 = _player.position if _player else _field_size * 0.5
	var fe: FieldEnemy = FIELD_ENEMY_SCENE.instantiate()
	fe.setup(data)
	# Drag-and-drop: if the player dropped this on a specific map spot, use it
	# (clamped to the map); otherwise fall back to a random spot near the party.
	var spawn: Vector2
	if GameState.pending_placement_position != Vector2.INF:
		spawn = _clamp_field_position(GameState.pending_placement_position)
		GameState.pending_placement_position = Vector2.INF
	else:
		spawn = _random_spawn_position_for_enemy(data, safe_origin)
	fe.position = spawn
	# Wander stays local to the spawn so the fight doesn't drift off the big map.
	var half := Vector2(ENEMY_WANDER_HALF_EXTENT, ENEMY_WANDER_HALF_EXTENT)
	fe.wander_bounds_min = _clamp_field_position(spawn - half)
	fe.wander_bounds_max = _clamp_field_position(spawn + half)
	_enemies_root.add_child(fe)
	if data == SLIME_CHASER_DATA:
		_chaser_spawned_this_loop = true


func _enemy_count_for_current_nodes() -> int:
	if GameState.STORY_MODE_ENABLED:
		return GameState.story_field_enemy_count()
	return initial_slime_count + GameState.field_enemy_count_bonus()


func _enemy_data_for_current_nodes() -> EnemyData:
	# The field spawns a random mix of whichever tiers are toggled ON (left bar).
	# Returns null when every tier is toggled off — _spawn_field_enemy guards it,
	# so the field simply stops adding new enemies (existing ones stay alive).
	return GameState.random_active_tier_enemy_data()


func _random_spawn_position_for_enemy(_data: EnemyData, avoid: Vector2) -> Vector2:
	# Scatter enemies randomly across the whole field, just kept clear of the party.
	return _random_safe_position(avoid)


## A point a short distance from `origin` (the hero), kept on the map and clear of
## the party. Falls back to a clamped random offset if the ring stays blocked.
func _spawn_position_near_player(origin: Vector2) -> Vector2:
	for _attempt in 24:
		var angle: float = randf() * TAU
		var radius: float = randf_range(SPAWN_NEAR_MIN, SPAWN_NEAR_MAX)
		var pos: Vector2 = _clamp_field_position(origin + Vector2(cos(angle), sin(angle)) * radius)
		if _is_safe_enemy_spawn_position(pos, origin):
			return pos
	return _clamp_field_position(origin + Vector2(
		randf_range(-SPAWN_NEAR_MAX, SPAWN_NEAR_MAX),
		randf_range(-SPAWN_NEAR_MAX, SPAWN_NEAR_MAX)
	))


func _random_forest_position(avoid: Vector2) -> Vector2:
	var cells: Array = _forest_cells.keys()
	cells.shuffle()
	for cell: Vector2i in cells:
		var pos: Vector2 = _cell_to_world(cell)
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_safe_position(avoid)


func _random_grassland_position(avoid: Vector2) -> Vector2:
	for attempt in 48:
		var cell := Vector2i(
			_decor_rng.randi_range(_min_grid_index(), _max_grid_x()),
			_decor_rng.randi_range(_min_grid_index(), _max_grid_y())
		)
		if _forest_cells.has(cell):
			continue
		var pos: Vector2 = _cell_to_world(cell)
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_safe_position(avoid)


func _random_safe_position(avoid: Vector2) -> Vector2:
	for attempt in 24:
		var pos: Vector2 = _random_position()
		if _is_safe_enemy_spawn_position(pos, avoid):
			return pos
	return _random_position()


func _is_safe_enemy_spawn_position(pos: Vector2, avoid: Vector2) -> bool:
	return pos.distance_to(avoid) >= _party_safe_radius()


func _party_safe_radius() -> float:
	return PARTY_SAFE_RADIUS


func _on_field_item_drop_requested(item: ItemData, world_position: Vector2, level: int = 1) -> void:
	if item == null:
		return
	_spawn_item_drop(item, world_position, level)


func _spawn_item_drop(item: ItemData, world_position: Vector2, level: int = 1) -> void:
	var drop := FIELD_ITEM_DROP_SCENE.instantiate() as FieldItemDrop
	drop.setup(item, level)
	drop.position = _drop_position_near(world_position)
	_items_root.add_child(drop)
	drop.reveal_with_pop()


func _on_field_gold_drop_requested(amount: int, world_position: Vector2) -> void:
	if amount <= 0:
		return
	_spawn_gold_drop(amount, world_position)


func _spawn_gold_drop(amount: int, world_position: Vector2) -> void:
	var drop := FIELD_ITEM_DROP_SCENE.instantiate() as FieldItemDrop
	drop.setup_gold_drop(amount)
	drop.position = _drop_position_near(world_position)
	_items_root.add_child(drop)
	drop.reveal_with_pop()


func _drop_position_near(origin: Vector2) -> Vector2:
	var safe_origin: Vector2 = _clamp_field_position(origin)
	for attempt in 36:
		var angle: float = randf() * TAU
		var radius: float = randf_range(DROP_SCATTER_RADIUS_MIN, DROP_SCATTER_RADIUS_MAX)
		var candidate: Vector2 = _clamp_field_position(safe_origin + Vector2(cos(angle), sin(angle)) * radius)
		if _is_valid_drop_position(candidate):
			return candidate
	for attempt in 36:
		var candidate: Vector2 = _random_position()
		if _is_valid_drop_position(candidate):
			return candidate
	return safe_origin


func _is_valid_drop_position(pos: Vector2) -> bool:
	var party_pos: Vector2 = _player.position if _player else _field_size * 0.5
	if pos.distance_to(party_pos) < DROP_PLAYER_SAFE_RADIUS:
		return false
	for child in _items_root.get_children():
		if child is Node2D and not child.is_queued_for_deletion():
			if pos.distance_to((child as Node2D).position) < DROP_SEPARATION_RADIUS:
				return false
	return true


func _clamp_field_position(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, 16.0, _play_right() - 16.0),
		clampf(pos.y, 16.0, _field_size.y - 16.0)
	)


func _random_position() -> Vector2:
	return Vector2(
		randf_range(SPAWN_MARGIN, _play_right() - SPAWN_MARGIN),
		randf_range(SPAWN_MARGIN, _field_size.y - SPAWN_MARGIN),
	)


## Editor-only preview: size the authored green board to `field_size` so the scene
## matches the running game without pressing play. Touches ONLY the two backdrop nodes
## — no GameState / EventBus — so it's safe to run under @tool in the editor.
func _apply_editor_field_size() -> void:
	# Sizing/positioning is authored via HudLayer/FieldLayoutRect; a transform on
	# this Node2D would distort every runtime child, so pin it back to identity.
	if transform != Transform2D.IDENTITY:
		transform = Transform2D.IDENTITY
		if not _warned_about_transform:
			_warned_about_transform = true
			push_warning("Field 노드는 직접 움직이거나 스케일하지 마세요 — HudLayer/FieldLayoutRect를 드래그해서 필드 위치/크기를 조절하세요.")
	# Fetch fresh (not via @onready) so this works for an INSTANCED Field in the editor,
	# where @onready timing for instances can be unreliable.
	var layout_rect: Rect2 = _field_layout_screen_rect()
	var authored_size: Vector2 = layout_rect.size
	FIELD_SIZE = authored_size
	var bg := get_node_or_null(^"Background") as ColorRect
	if bg != null:
		bg.size = authored_size
		bg.position = layout_rect.position.round()
	var bgt := get_node_or_null(^"BackgroundTexture") as TextureRect
	if bgt != null:
		bgt.visible = false


## Project's base (design) viewport size — the rect the editor draws as the game view.
func _design_viewport_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 360)),
	)


func _layout_rect_node() -> Control:
	if field_layout_rect_path == NodePath():
		return null
	return get_node_or_null(field_layout_rect_path) as Control


func _field_layout_screen_rect() -> Rect2:
	var layout := _layout_rect_node()
	if layout != null and layout.size.x > 1.0 and layout.size.y > 1.0:
		return Rect2(layout.global_position, layout.size)
	var viewport_size: Vector2 = _design_viewport_size()
	return Rect2(((viewport_size - field_size) * 0.5).round(), field_size)


func _authored_field_size() -> Vector2:
	var rect: Rect2 = _field_layout_screen_rect()
	if rect.size.x > 1.0 and rect.size.y > 1.0:
		return rect.size
	return field_size


func _camera_world_center() -> Vector2:
	# A world point appears on screen at: point - camera_center + viewport / 2.
	# To place the field's local origin at the authored layout rect's top-left:
	# camera_center = viewport / 2 - layout_top_left.
	return _design_viewport_size() * 0.5 - _field_layout_screen_rect().position


func _apply_field_size() -> void:
	_field_size = _authored_field_size() * GameState.field_size_multiplier()
	FIELD_SIZE = _field_size
	# The field is a single 4:3 "board": green covers EXACTLY the board rect and
	# nothing more. Beyond its edges the dark WallpaperLayer (behind everything)
	# shows through as the void, so zooming all the way out reveals the whole board
	# floating in a dark margin (wide on the sides since 4:3 < the 16:9 viewport).
	_background.position = Vector2.ZERO
	_background.size = _field_size
	_background_texture.visible = false
	if _player and _player.has_method("set_field_bounds"):
		_player.set_field_bounds(Vector2.ZERO, _field_size)
	if _player and _player.has_method("set_camera_world_center"):
		_player.set_camera_world_center(_camera_world_center())


func _apply_field_background() -> void:
	# Plain green grassland (decoration/grass texture deferred — see task notes).
	_background.color = GRASS_FIELD_COLOR
	_background_texture.visible = false


func _field_background_color() -> Color:
	return FOREST_FIELD_COLOR if GameState.current_field_region_id == GameState.FIELD_REGION_FOREST else GRASS_FIELD_COLOR


# ─── World-edge diorama ───────────────────────────────────────────────
## Out-of-bounds used to be raw black. Instead we paint the field as a floating
## island: deep water all around, a soft depth vignette, a cast shadow under the
## island and an earthy cliff edge so the world ends on something intentional.
func _apply_diorama() -> void:
	_ensure_diorama()
	var fs: Vector2 = _field_size
	var is_forest: bool = GameState.current_field_region_id == GameState.FIELD_REGION_FOREST

	# Deep water filling everything the camera can see past the edge.
	_void_rect.color = DEEP_WATER_FOREST_COLOR if is_forest else DEEP_WATER_COLOR
	_void_rect.position = Vector2(-VOID_MARGIN, -VOID_MARGIN)
	_void_rect.size = fs + Vector2(VOID_MARGIN * 2.0, VOID_MARGIN * 2.0)

	# Radial vignette centered on the island darkens the far abyss for depth.
	_void_vignette.position = _void_rect.position
	_void_vignette.size = _void_rect.size

	# Cast shadow on the water, nudged down so the island feels lifted.
	_island_shadow.position = Vector2(-CLIFF_RIM - ISLAND_SHADOW_EXPAND, -CLIFF_RIM) + ISLAND_SHADOW_OFFSET
	_island_shadow.size = fs + Vector2(
		(CLIFF_RIM + ISLAND_SHADOW_EXPAND) * 2.0,
		CLIFF_RIM * 2.0 + CLIFF_FACE_HEIGHT + ISLAND_SHADOW_EXPAND
	)

	# Earthy rim peeking around the grass on every side...
	_cliff_rim.position = Vector2(-CLIFF_RIM, -CLIFF_RIM)
	_cliff_rim.size = fs + Vector2(CLIFF_RIM * 2.0, CLIFF_RIM * 2.0)
	_cliff_rim.color = CLIFF_RIM_FOREST_COLOR if is_forest else CLIFF_RIM_COLOR

	# ...and a taller, darker cliff face along the bottom for 3D thickness.
	_cliff_face.position = Vector2(-CLIFF_RIM, fs.y)
	_cliff_face.size = Vector2(fs.x + CLIFF_RIM * 2.0, CLIFF_FACE_HEIGHT)
	_cliff_face.color = CLIFF_FACE_FOREST_COLOR if is_forest else CLIFF_FACE_COLOR


func _ensure_diorama() -> void:
	if _diorama_root != null and is_instance_valid(_diorama_root):
		return
	_diorama_root = Node2D.new()
	_diorama_root.name = "Diorama"
	add_child(_diorama_root)
	move_child(_diorama_root, 0)
	# z_index (not child order) drives layering; all sit behind the grass (-100).
	_void_rect = _make_diorama_rect(-300)
	_void_vignette = TextureRect.new()
	_void_vignette.name = "VoidVignette"
	_void_vignette.z_index = -290
	_void_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_void_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_void_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_void_vignette.texture = _build_vignette_texture()
	_diorama_root.add_child(_void_vignette)
	_island_shadow = _make_diorama_rect(-200)
	_island_shadow.color = ISLAND_SHADOW_COLOR
	_cliff_face = _make_diorama_rect(-149)
	_cliff_rim = _make_diorama_rect(-150)


func _make_diorama_rect(z: int) -> ColorRect:
	var rect := ColorRect.new()
	rect.z_index = z
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diorama_root.add_child(rect)
	return rect


func _build_vignette_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	grad.set_color(1, VOID_VIGNETTE_COLOR)
	grad.add_point(0.32, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 256
	tex.height = 256
	return tex


func get_field_rect() -> Rect2:
	return Rect2(Vector2.ZERO, _field_size)


func _settle_field_loop() -> void:
	_loop_complete = true
	GameState.clear_move_speed_drag()
	EventBus.field_loop_settled.emit(GameState.field_loop_count)


func _on_field_loop_finish_requested() -> void:
	if GameState.field_loop_count <= 0 or _loop_complete:
		return
	_settle_field_loop()


## All windows closed AND the field is empty → refill pressure.
## Echo Strike can keep extra windows running after the last field enemy is
## consumed, so we listen to all_battles_resolved (not battle_window_closed)
## and combine with the field-empty check.
func _check_refill_after_battles() -> void:
	_active_battle_windows = 0
	if _loop_complete:
		return
	if _active_field_enemy_count() == 0:
		_refill_enemy_population(spawn_batch_size)


func _on_skill_node_purchase_succeeded(_node) -> void:
	if GameState.field_loop_count <= 0 or GameState.is_party_wiped():
		return
	_apply_field_size()
	_apply_field_background()
	if _loop_complete:
		return
	_refill_enemy_population(spawn_batch_size + GameState.field_spawn_batch_bonus())
