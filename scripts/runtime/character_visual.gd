class_name CharacterVisual
extends Sprite2D

## Sprite2D wrapper that animates a 4-row x N-col walk sheet.
## Sheet row order (RPG convention): 0=Down, 1=Left, 2=Right, 3=Up.
## Each row has `frames_per_direction` columns in the order [step1, idle, step2].
##
## Pass it CharacterData via setup(), then call set_velocity() each physics frame.
## The node's own position is the character's ground contact point.

enum Dir { DOWN = 0, LEFT = 1, RIGHT = 2, UP = 3 }

## 4-step walk cycle: left foot → idle → right foot → idle.
const WALK_CYCLE: Array[int] = [0, 1, 2, 1]

@export var character_data: CharacterData
@export var idle_col: int = 1
@export var diagonal_vertical_bias: float = 0.65

var _dir: Dir = Dir.DOWN
var _step: int = 0
var _step_timer: float = 0.0
var _moving: bool = false


func _ready() -> void:
	if character_data:
		_apply_data()


## Inject the character data. Safe to call before _ready.
func setup(data: CharacterData) -> void:
	character_data = data
	if is_inside_tree():
		_apply_data()


func _apply_data() -> void:
	if character_data == null or character_data.sprite_sheet == null:
		return
	texture = character_data.sprite_sheet
	hframes = 1
	vframes = 1
	centered = false
	region_enabled = true
	offset = -character_data.foot_anchor
	_show_idle()


## Drive the animation from a velocity vector. (0, 0) → idle.
func set_velocity(v: Vector2) -> void:
	if v.length_squared() < 1.0:
		if _moving:
			_moving = false
			_step = 0
			_step_timer = 0.0
			_show_idle()
		return
	_moving = true
	var abs_x: float = absf(v.x)
	var abs_y: float = absf(v.y)
	var minor_axis: float = minf(abs_x, abs_y)
	var major_axis: float = maxf(abs_x, abs_y)
	# Near-diagonal movement favors vertical facing, which keeps low-speed
	# party followers from flickering left/right while they trail the path.
	if major_axis > 0.0 and minor_axis / major_axis >= diagonal_vertical_bias:
		_dir = Dir.DOWN if v.y > 0 else Dir.UP
	elif abs_x > abs_y:
		_dir = Dir.RIGHT if v.x > 0 else Dir.LEFT
	else:
		_dir = Dir.DOWN if v.y > 0 else Dir.UP


func _process(delta: float) -> void:
	if not _moving or character_data == null:
		return
	_step_timer += delta
	var step_period: float = 1.0 / maxf(1.0, character_data.walk_fps)
	if _step_timer >= step_period:
		_step_timer = 0.0
		_step = (_step + 1) % WALK_CYCLE.size()
	_set_frame(WALK_CYCLE[_step], int(_dir))


func _show_idle() -> void:
	if character_data == null:
		return
	_set_frame(clampi(idle_col, 0, maxi(0, character_data.frames_per_direction - 1)), int(_dir))


## Force a static facing (no walk). Used by battle formation: the party faces UP
## = back to the camera, looking toward the enemy windows above them.
func face_dir(dir: Dir) -> void:
	_dir = dir
	_moving = false
	_step = 0
	_step_timer = 0.0
	_show_idle()


## ─── Battle-formation juice ────────────────────────────────────────────
## Tweens the sprite's LOCAL offset/modulate only (the owner's logical position is
## untouched), so attacks/hits never desync movement. Killed on retrigger.
var _juice_tween: Tween
var _shake_tween: Tween


func _kill_juice() -> void:
	if _juice_tween != null and _juice_tween.is_valid():
		_juice_tween.kill()
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()


## Attack tell: lunge "forward" (up — the formation faces up) and snap back.
func play_attack_lunge() -> void:
	_kill_juice()
	position = Vector2.ZERO
	modulate = Color(1, 1, 1, 1)
	_juice_tween = create_tween()
	_juice_tween.tween_property(self, "position", Vector2(0.0, -6.0), 0.06)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_juice_tween.tween_property(self, "position", Vector2.ZERO, 0.13)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Hit reaction: white FLASH + a tiny side-to-side rattle that settles back to
## zero — the body never leaves its spot (attacking is the only thing that steps
## a formation row forward; 고전게임 문법).
func play_hit_flinch() -> void:
	_kill_juice()
	position = Vector2.ZERO
	modulate = Color(2.4, 2.4, 2.4, 1.0)  # bright flash
	_juice_tween = create_tween()
	_juice_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.22)
	_shake_tween = create_tween()
	_shake_tween.tween_property(self, "position:x", 2.0, 0.04)
	_shake_tween.tween_property(self, "position:x", -2.0, 0.05)
	_shake_tween.tween_property(self, "position:x", 1.5, 0.05)
	_shake_tween.tween_property(self, "position:x", 0.0, 0.06)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_frame(col: int, row: int) -> void:
	if character_data == null:
		return
	var frame_size := character_data.frame_size_vec()
	region_rect = Rect2(Vector2(col * frame_size.x, row * frame_size.y), frame_size)


func visual_center_offset() -> Vector2:
	return character_data.visual_center_local() if character_data else Vector2.ZERO


func speech_anchor_offset() -> Vector2:
	return character_data.speech_anchor_local() if character_data else Vector2.ZERO


func popup_anchor_offset() -> Vector2:
	return character_data.popup_anchor_local() if character_data else Vector2.ZERO
