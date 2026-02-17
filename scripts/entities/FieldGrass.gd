extends Node2D
class_name FieldGrass
## 2-레이어 회전 기반 풀 흔들림:
## - 기본 사인 흔들림 + 바람 편향 + 플레이어 접촉 반응

@export var texture_a: Texture2D
@export var texture_b: Texture2D
@export var pivot_base_px: Vector2 = Vector2(8, 14)
@export var pivot_b_offset_px: Vector2 = Vector2.ZERO
@export var seed_override: int = 0

@export var base_amp_a_deg: float = 2.4
@export var base_amp_b_deg: float = 3.2
@export var speed_a_min: float = 0.72
@export var speed_a_max: float = 1.25
@export var speed_b_min: float = 0.9
@export var speed_b_max: float = 1.55

@export var wind_amp_boost: float = 0.95
@export var wind_bias_deg: float = 8.0
@export var max_contact_bend_deg: float = 25.0

@onready var pivot_a: Node2D = $PivotA
@onready var pivot_b: Node2D = $PivotB
@onready var sprite_a: Sprite2D = $PivotA/SpriteA
@onready var sprite_b: Sprite2D = $PivotB/SpriteB

var _rng := RandomNumberGenerator.new()
var _seed_value: int = 0
var _time: float = 0.0
var _phase_a: float = 0.0
var _phase_b: float = 0.0
var _speed_a: float = 1.3
var _speed_b: float = 1.8
var _amp_a: float = deg_to_rad(2.4)
var _amp_b: float = deg_to_rad(3.2)
var _wind_strength: float = 0.0
var _wind_dir: float = 1.0
var _contact_angle: float = 0.0
var _fallback_dir_sign: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_init_seed()
	_apply_layout()
	_randomize_motion()
	set_process(true)


func set_grass_textures(a: Texture2D, b: Texture2D) -> void:
	texture_a = a
	texture_b = b
	if is_inside_tree():
		_apply_layout()


func set_global_wind(wind_strength: float, wind_dir: float) -> void:
	_wind_strength = clampf(wind_strength, 0.0, 1.0)
	var s: float = sign(wind_dir)
	if absf(s) > 0.0:
		_wind_dir = s


func apply_player_influence(
		player_position: Vector2,
		player_velocity: Vector2,
		radius: float,
		interact_strength: float,
		delta: float
	) -> void:
	if radius <= 0.0:
		_contact_angle = lerpf(_contact_angle, 0.0, clampf(delta * 4.0, 0.0, 1.0))
		return

	var base_world_pos: Vector2 = global_position + pivot_base_px
	var to_grass: Vector2 = base_world_pos - player_position
	var dist: float = to_grass.length()
	var influence: float = clampf(1.0 - dist / radius, 0.0, 1.0) * maxf(0.0, interact_strength)

	if influence <= 0.0001:
		_contact_angle = lerpf(_contact_angle, 0.0, clampf(delta * 4.5, 0.0, 1.0))
		return

	var dir_sign: float = 0.0
	if absf(player_velocity.x) > 1.0:
		# 지나가는 방향의 반대로 휘게
		dir_sign = -sign(player_velocity.x)
	elif absf(to_grass.x) > 0.2:
		# 정지 상태에서는 플레이어에서 멀어지는 방향
		dir_sign = sign(to_grass.x)
	else:
		dir_sign = _fallback_dir_sign

	var target_angle: float = deg_to_rad(max_contact_bend_deg) * influence * dir_sign
	_contact_angle = lerpf(_contact_angle, target_angle, clampf(delta * 10.0, 0.0, 1.0))


func _process(delta: float) -> void:
	_time += delta

	var amp_mul: float = 1.0 + _wind_strength * wind_amp_boost
	var wind_bias: float = _wind_dir * _wind_strength * deg_to_rad(wind_bias_deg)

	var wave_a: float = sin(_time * _speed_a + _phase_a)
	var wave_b: float = sin(_time * _speed_b + _phase_b)

	var rot_a: float = wave_a * _amp_a * amp_mul + wind_bias + _contact_angle * 0.82
	var rot_b: float = wave_b * _amp_b * amp_mul + wind_bias * 0.92 + _contact_angle * 1.08

	pivot_a.rotation = clampf(rot_a, deg_to_rad(-30.0), deg_to_rad(30.0))
	pivot_b.rotation = clampf(rot_b, deg_to_rad(-34.0), deg_to_rad(34.0))


func _init_seed() -> void:
	if seed_override != 0:
		_seed_value = seed_override
	else:
		_seed_value = int(hash("%s|%.2f|%.2f" % [str(get_path()), position.x, position.y]))
	_rng.seed = absi(_seed_value)
	_fallback_dir_sign = -1.0 if (_seed_value & 1) == 0 else 1.0


func _randomize_motion() -> void:
	_phase_a = _rng.randf_range(0.0, TAU)
	_phase_b = _rng.randf_range(0.0, TAU)
	_speed_a = _rng.randf_range(speed_a_min, speed_a_max)
	_speed_b = _rng.randf_range(speed_b_min, speed_b_max)
	_amp_a = deg_to_rad(base_amp_a_deg * _rng.randf_range(0.85, 1.2))
	_amp_b = deg_to_rad(base_amp_b_deg * _rng.randf_range(0.85, 1.2))


func _apply_layout() -> void:
	if pivot_a == null or pivot_b == null or sprite_a == null or sprite_b == null:
		return

	pivot_a.position = pivot_base_px
	pivot_b.position = pivot_base_px + pivot_b_offset_px

	sprite_a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_a.centered = false
	sprite_b.centered = false

	sprite_a.texture = texture_a
	sprite_b.texture = texture_b if texture_b != null else texture_a

	# 피벗 기준으로 동일 캔버스 위치 정렬 (밑동 고정)
	sprite_a.position = -pivot_a.position
	sprite_b.position = -pivot_b.position
	sprite_a.z_index = 0
	sprite_b.z_index = 1
