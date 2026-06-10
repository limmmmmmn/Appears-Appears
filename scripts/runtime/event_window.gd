class_name EventWindow
extends Control

## 이벤트 창 — the game's cutscene window (전투창 / 방문 창 / 이벤트 창).
## A small diorama stage inside a minimal RPG frame: actors are real sprite-sheet
## characters (3×4 walk sheets) who walk, face each other and talk in speech
## bubbles. Understated on purpose (담백): native 1× pixel sprites on a flat green
## stage — no lighting effects, the writing carries the moment.
## The FIELD HOLDS STILL while a scene plays (GameState.open_event_window).
##
## Click anywhere: reveals the current line instantly, then advances — classic
## RPG dialogue pacing with an auto-advance fallback so AFK players still proceed.
##
## All recruitment scenes share one shape (the "만남" beat): a prop in the middle,
## the hero on the left, the guest walking in from beyond the right edge, a short
## exchange, both hop, the guest joins. New events = a MEETINGS entry + a match arm.

const HERO_FALLBACK: CharacterData = preload("res://data/characters/hero.tres")
const MAGE_DATA: CharacterData = preload("res://data/characters/mage.tres")
const PRIEST_DATA: CharacterData = preload("res://data/characters/priest.tres")
const BONFIRE_TEX: Texture2D = preload("res://assets/sprites/objects/bonfire.png")
const SHRINE_TEX: Texture2D = preload("res://assets/sprites/objects/shrine.png")
const BUBBLE_FONT: Font = preload("res://assets/fonts/field_ui_font.tres")

const ACTOR_SCALE: float = 1.0  ## native pixel size — the stage stays quiet/담백
const WALK_FRAME_SEQ: Array[int] = [0, 1, 2, 1]   ## natural step cycle
const TYPE_INTERVAL: float = 0.035                ## typewriter seconds/char
const LINE_HOLD: float = 1.8                      ## auto-advance after a line

@onready var _dim: ColorRect = %Dim
@onready var _panel: PanelContainer = %Panel
@onready var _stage: Control = %Stage
@onready var _prop: TextureRect = %Prop
@onready var _hero: TextureRect = %Hero
@onready var _mage: TextureRect = %Mage
@onready var _hint: Label = %Hint
@onready var _click_catcher: Control = %ClickCatcher

var _playing: bool = false
var _advance_requested: bool = false


func _ready() -> void:
	visible = false
	if Engine.is_editor_hint():
		return
	_click_catcher.gui_input.connect(_on_click)
	EventBus.event_window_requested.connect(_on_event_requested)


func _on_event_requested(event_id: StringName) -> void:
	if _playing:
		return
	match event_id:
		&"campfire_mage":
			# 모닥불 앞, 불을 좋아하는 메이지와의 첫 만남.
			_play_meeting(BONFIRE_TEX, MAGE_DATA, &"mage", [
				{"who": &"guest", "text": "난 불이 좋아"},
				{"who": &"hero", "text": "더 태워볼래?"},
				{"who": &"guest", "text": "좋지"},
			])
		&"sanctuary_priest":
			# 성소 앞, 어린양을 찾아온 프리스트와의 첫 만남.
			_play_meeting(SHRINE_TEX, PRIEST_DATA, &"priest", [
				{"who": &"guest", "text": "나의 치료를 필요로 하는 어린양이 여기있군"},
				{"who": &"hero", "text": "그게 바로 나야"},
			])


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance_requested = true


# ─── The shared "만남" scene ────────────────────────────────────────────
## Prop center, hero left (looking at it), guest walks in from off-right; they
## trade `lines` ([{who: &"hero"|&"guest", text}]), hop, and the guest joins.
func _play_meeting(prop_tex: Texture2D, guest_data: CharacterData,
		join_id: StringName, lines: Array) -> void:
	_playing = true
	GameState.open_event_window()
	visible = true
	await get_tree().process_frame  # let containers lay out so _stage.size is real

	# The hero on the field might be a renamed/custom leader — use their sheet.
	var hero_data: CharacterData = GameState.party[0] if GameState.party_size() > 0 else HERO_FALLBACK

	# Stage blocking: 1× sprites in a roomy flat-green stage — air around the moment.
	var ground: float = _stage.size.y * 0.5 + 20.0
	var cx: float = _stage.size.x * 0.5
	_place_prop(prop_tex, Vector2(cx, ground))
	_place_actor(_hero, hero_data, Vector2(cx - 36.0, ground), CharacterData.Direction.RIGHT)
	_place_actor(_mage, guest_data, Vector2(_stage.size.x + 16.0, ground), CharacterData.Direction.LEFT)
	_hint.modulate.a = 0.0

	# Curtain up: dim fades, the frame swings in.
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.88, 0.88)
	_dim.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_dim, "modulate:a", 1.0, 0.14)
	t.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	await _beat(0.55)

	# The guest wanders in from beyond the window.
	await _walk_actor(_mage, guest_data, CharacterData.Direction.LEFT,
		_stage.size.x + 16.0, cx + 30.0, ground, 1.6)
	await _beat(0.4)

	create_tween().tween_property(_hint, "modulate:a", 1.0, 0.3)
	var guest_spoke: bool = false
	for line: Dictionary in lines:
		if line.get("who") == &"hero":
			await _say(_hero, str(line.get("text", "")))
		else:
			await _say(_mage, str(line.get("text", "")))
			if not guest_spoke:
				guest_spoke = true
				_hop(_hero, 2.0)  # startled — he didn't hear them coming
				await _beat(0.25)

	# Deal struck: both hop in turn (the pixel handshake) — and the party grows.
	await _join_flourish()
	GameState.join_companion(join_id)
	await _beat(0.35)
	await _close_curtain()
	_playing = false


# ─── Actors (sprite-sheet puppets) ──────────────────────────────────────
## Park an actor's FEET at `foot` (stage-local), facing `dir`, idle frame.
func _place_actor(rect: TextureRect, data: CharacterData, foot: Vector2, dir: int) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = data.sprite_sheet
	rect.texture = atlas
	rect.size = data.frame_size_vec() * ACTOR_SCALE
	rect.position = foot - Vector2(rect.size.x * 0.5, rect.size.y)
	_set_frame(rect, data, dir, 1)


func _set_frame(rect: TextureRect, data: CharacterData, dir: int, col: int) -> void:
	var atlas := rect.texture as AtlasTexture
	if atlas == null:
		return
	atlas.region = Rect2(
		Vector2(float(col) * float(data.frame_size.x), float(dir) * float(data.frame_size.y)),
		data.frame_size_vec()
	)


## Frame-animated walk from foot-x `from_x` to `to_x` along the ground line.
func _walk_actor(rect: TextureRect, data: CharacterData, dir: int,
		from_x: float, to_x: float, ground: float, duration: float) -> void:
	var elapsed: float = 0.0
	var half_w: float = rect.size.x * 0.5
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var k: float = clampf(elapsed / duration, 0.0, 1.0)
		rect.position.x = lerpf(from_x, to_x, k) - half_w
		rect.position.y = ground - rect.size.y
		var step: int = int(elapsed * data.walk_fps) % WALK_FRAME_SEQ.size()
		_set_frame(rect, data, dir, WALK_FRAME_SEQ[step])
	_set_frame(rect, data, dir, 1)  # settle on the idle pose


## A quick happy/startled hop.
func _hop(rect: TextureRect, height: float) -> void:
	var y: float = rect.position.y
	var t := create_tween()
	t.tween_property(rect, "position:y", y - height, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(rect, "position:y", y, 0.11).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ─── Speech bubbles (typewriter + click pacing) ─────────────────────────
func _say(actor: TextureRect, text: String) -> void:
	var bubble := Panel.new()
	# Long lines wrap onto extra rows instead of stretching past the stage.
	var est: float = float(text.length()) * 9.0 + 22.0
	var width: float = clampf(est, 56.0, 180.0)
	var rows: int = maxi(1, ceili(est / 180.0))
	bubble.size = Vector2(width, 10.0 + 12.0 * float(rows))
	var head: Vector2 = actor.position + Vector2(actor.size.x * 0.5, 0.0)
	bubble.position = Vector2(
		clampf(head.x - width * 0.5, 4.0, _stage.size.x - width - 4.0),
		maxf(head.y - bubble.size.y - 5.0, 4.0)
	)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_stylebox_override("panel", _bubble_style())
	_stage.add_child(bubble)

	var tail := ColorRect.new()
	tail.size = Vector2(6.0, 6.0)
	tail.position = Vector2(clampf(head.x - bubble.position.x - 3.0, 6.0, width - 12.0), bubble.size.y - 3.0)
	tail.rotation = deg_to_rad(45.0)
	tail.color = Color(1.0, 0.96, 0.82, 1.0)
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(tail)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 6.0
	label.offset_right = -6.0
	label.add_theme_font_override("font", BUBBLE_FONT)
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(label)

	# Pop in.
	bubble.pivot_offset = Vector2(bubble.size.x * 0.5, bubble.size.y)
	bubble.scale = Vector2(0.7, 0.7)
	bubble.modulate.a = 0.0
	var pop := create_tween()
	pop.tween_property(bubble, "modulate:a", 1.0, 0.06)
	pop.parallel().tween_property(bubble, "scale", Vector2.ONE, 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished

	# Typewriter — a click reveals the whole line at once.
	_advance_requested = false
	for i in text.length():
		if _advance_requested:
			break
		label.text = text.substr(0, i + 1)
		await get_tree().create_timer(TYPE_INTERVAL).timeout
	label.text = text

	# Hold for a click (or auto-advance so the scene never stalls).
	_advance_requested = false
	await _wait_for_advance(LINE_HOLD)

	var fade := create_tween()
	fade.tween_property(bubble, "modulate:a", 0.0, 0.1)
	fade.tween_callback(bubble.queue_free)
	await fade.finished


func _wait_for_advance(timeout: float) -> void:
	var waited: float = 0.0
	while waited < timeout and not _advance_requested:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_advance_requested = false


func _beat(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _bubble_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.96, 0.82, 1.0)
	style.border_color = Color(0.08627451, 0.08235294, 0.09411765, 1.0)
	style.set_border_width_all(1)
	style.anti_aliasing = false
	return style


# ─── Center prop (모닥불 / 성소 / …) ────────────────────────────────────
func _place_prop(tex: Texture2D, base: Vector2) -> void:
	_prop.texture = tex
	_prop.size = tex.get_size() * ACTOR_SCALE
	_prop.position = base - Vector2(_prop.size.x * 0.5, _prop.size.y)


## 합류의 순간: no fireworks — just both characters hopping in turn, the pixel
## equivalent of a handshake.
func _join_flourish() -> void:
	_hop(_mage, 3.0)
	await _beat(0.12)
	_hop(_hero, 2.5)
	await _beat(0.4)


func _close_curtain() -> void:
	var t := create_tween()
	t.tween_property(_panel, "scale", Vector2(0.9, 0.9), 0.12).set_trans(Tween.TRANS_QUAD)
	t.parallel().tween_property(_dim, "modulate:a", 0.0, 0.14)
	await t.finished
	visible = false
	GameState.close_event_window()
