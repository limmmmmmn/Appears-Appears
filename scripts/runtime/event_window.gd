class_name EventWindow
extends Control

## A non-combat counterpart to BattleWindow. Pops up the same way (와앙 팍
## open animation, dim log strip at the bottom), but instead of an enemy
## stack the center holds an event tile (campfire, shrine, …) and a
## scripted dialogue plays between the party leader and an NPC.
##
## When the script ends, event_completed fires so Main can apply the
## recruit + consume the field tile.

signal event_completed(event_id: StringName)

const WINDOW_SIZE: Vector2 = Vector2(180, 116)
const OPEN_ANIMATION_DURATION: float = 0.32
const OPEN_ANIMATION_START_SCALE: float = 0.32
const LINE_HOLD_SECONDS: float = 1.6
const MAGE_SLIDE_DURATION: float = 0.55

const TILE_CENTER_OFFSET: Vector2 = Vector2(0, -6)  ## relative to window center
const ACTOR_HORIZONTAL_GAP: float = 36.0
const BONFIRE_TEXTURE: Texture2D = preload("res://assets/sprites/objects/bonfire.png")

var event_id: StringName = &""
var dialogue: Array = []          ## Array[Dictionary]: { speaker, line }
var recruit_data: CharacterData
## Centerpiece sprite. main injects this per event_id; defaults to the
## bonfire if a caller forgets to pass one.
var tile_texture: Texture2D

var _player_visual: CharacterVisual
var _mage_visual: CharacterVisual
var _log_label: Label
var _campfire_center: Vector2
var _running: bool = true


## Inject the event config before adding to the tree. Must run *before*
## add_child so _ready can see recruit_data + tile_texture when it builds
## the actor + tile visuals.
func setup(id: StringName, dialog_lines: Array, recruit: CharacterData, texture: Texture2D = null) -> void:
	event_id = id
	dialogue = dialog_lines
	recruit_data = recruit
	tile_texture = texture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	# Park ourselves in the middle of the viewport.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	position = (vp - WINDOW_SIZE) * 0.5
	_campfire_center = WINDOW_SIZE * 0.5 + TILE_CENTER_OFFSET
	_build_chrome()
	_build_log()
	_build_tile_visual()
	_build_actors()
	_play_open_animation()
	await _run_dialogue()
	if _running:
		event_completed.emit(event_id)
		queue_free()


# ─── Layout ───────────────────────────────────────────────────────────
func _build_chrome() -> void:
	var bg := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.95, 0.86, 0.97)
	style.border_color = Color(0.16, 0.10, 0.06, 1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	bg.add_theme_stylebox_override("panel", style)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_log() -> void:
	var log_panel := Panel.new()
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.16, 0.10, 0.06, 1)
	log_style.border_color = Color(0.08, 0.05, 0.03, 1)
	log_style.border_width_left = 1
	log_style.border_width_top = 1
	log_style.border_width_right = 1
	log_style.border_width_bottom = 1
	log_panel.add_theme_stylebox_override("panel", log_style)
	log_panel.anchor_left = 0.0
	log_panel.anchor_right = 1.0
	log_panel.anchor_top = 1.0
	log_panel.anchor_bottom = 1.0
	log_panel.offset_left = 4
	log_panel.offset_right = -4
	log_panel.offset_top = -28
	log_panel.offset_bottom = -4
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_panel)

	_log_label = Label.new()
	_log_label.add_theme_font_size_override("font_size", 8)
	_log_label.add_theme_color_override("font_color", Color(0.98, 0.95, 0.86))
	_log_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log_label.offset_left = 4
	_log_label.offset_top = 2
	_log_label.offset_right = -4
	_log_label.offset_bottom = -2
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_panel.add_child(_log_label)


## Event centerpiece — uses whatever tile_texture main injected (campfire,
## shrine, etc.). Falls back to the bonfire if main forgot to set one.
func _build_tile_visual() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = tile_texture if tile_texture else BONFIRE_TEXTURE
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = _campfire_center
	sprite.z_index = 1
	add_child(sprite)
	# Gentle vertical breathing — reads as flicker for fire, "alive air"
	# for shrines, etc. Same curve either way.
	var flicker: Tween = sprite.create_tween().set_loops()
	flicker.tween_property(sprite, "scale", Vector2(1.0, 1.06), 0.42)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	flicker.tween_property(sprite, "scale", Vector2(1.0, 0.96), 0.42)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Player to the left of the fire, facing right. Mage spawns at the fire
## itself and slides out to the right during dialogue.
func _build_actors() -> void:
	_player_visual = _make_visual_for_id(&"hero")
	if _player_visual:
		_player_visual.position = _campfire_center + Vector2(-ACTOR_HORIZONTAL_GAP, 0)
		_player_visual.z_index = 3
		add_child(_player_visual)
		# Nudge once to set facing direction (RIGHT), then stop so the
		# sprite settles on the idle frame of that row.
		_player_visual.set_velocity(Vector2(1, 0))
		_player_visual.set_velocity(Vector2.ZERO)

	if recruit_data != null:
		_mage_visual = CharacterVisual.new()
		_mage_visual.position = _campfire_center
		_mage_visual.modulate.a = 0.0
		_mage_visual.z_index = 2
		add_child(_mage_visual)
		_mage_visual.setup(recruit_data)


func _make_visual_for_id(character_id: StringName) -> CharacterVisual:
	var path: String = "res://data/characters/%s.tres" % character_id
	if not ResourceLoader.exists(path):
		return null
	var data: CharacterData = load(path) as CharacterData
	if data == null:
		return null
	var v := CharacterVisual.new()
	v.setup(data)
	return v


# ─── Animations ───────────────────────────────────────────────────────
func _play_open_animation() -> void:
	pivot_offset = WINDOW_SIZE * 0.5
	scale = Vector2.ONE * OPEN_ANIMATION_START_SCALE
	modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, OPEN_ANIMATION_DURATION)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, OPEN_ANIMATION_DURATION * 0.5)


# ─── Dialogue loop ────────────────────────────────────────────────────
func _run_dialogue() -> void:
	# Let the window settle before the actors animate.
	await get_tree().create_timer(OPEN_ANIMATION_DURATION + 0.12).timeout
	if not _running:
		return
	await _mage_emerges_from_fire()
	for line: Dictionary in dialogue:
		if not _running:
			return
		_log_label.text = "%s: %s" % [String(line.get("speaker", "")), String(line.get("line", ""))]
		await get_tree().create_timer(LINE_HOLD_SECONDS).timeout
	# Tiny breather after the last line so it doesn't snap-close mid-read.
	await get_tree().create_timer(0.3).timeout


## Mage fades in at the fire, slides right while walking, then turns to
## face the player when they reach their final spot.
func _mage_emerges_from_fire() -> void:
	if not is_instance_valid(_mage_visual):
		return
	var target_pos: Vector2 = _campfire_center + Vector2(ACTOR_HORIZONTAL_GAP, 0)
	# Walk-animate while sliding (set_velocity flips _moving on the visual).
	_mage_visual.set_velocity(Vector2(1, 0))
	var slide: Tween = _mage_visual.create_tween()
	slide.set_parallel(true)
	slide.tween_property(_mage_visual, "position", target_pos, MAGE_SLIDE_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	slide.tween_property(_mage_visual, "modulate:a", 1.0, MAGE_SLIDE_DURATION * 0.5)
	await slide.finished
	# Turn to face the player (left) and stand still.
	_mage_visual.set_velocity(Vector2(-1, 0))
	_mage_visual.set_velocity(Vector2.ZERO)
