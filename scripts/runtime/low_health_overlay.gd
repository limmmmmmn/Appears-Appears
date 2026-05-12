class_name LowHealthOverlay
extends CanvasLayer

## Radial red-tinted vignette that fades in when the party's total HP drops
## to the danger zone and fades out when it recovers. Stays on its own
## CanvasLayer so it sits above the field but below the HUD / town panels.
##
## Threshold uses a small hysteresis (enter at 50%, exit at 55%) so the
## effect doesn't strobe at the boundary. While active, the intensity
## breathes between a low and high value for a "heartbeat" feel.

const DANGER_HP_RATIO_ENTER: float = 0.5
const DANGER_HP_RATIO_EXIT: float = 0.55
const FADE_IN_DURATION: float = 0.55
const FADE_OUT_DURATION: float = 0.7
## Pulse: when active, intensity breathes between these two values.
const PULSE_MIN: float = 0.7
const PULSE_MAX: float = 1.0
const PULSE_HALF_PERIOD: float = 0.85

@onready var _rect: ColorRect = %VignetteRect

var _material: ShaderMaterial
var _is_active: bool = false
var _fade_tween: Tween
var _pulse_tween: Tween


func _enter_tree() -> void:
	# Process while the game is paused so we can smoothly fade out during the
	# town visit that healed the party past the danger threshold.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_material = _rect.material as ShaderMaterial
	_set_intensity(0.0)
	EventBus.party_member_hp_changed.connect(_on_hp_signal)
	EventBus.party_changed.connect(_evaluate_state)
	EventBus.party_wiped.connect(_force_clear)
	_evaluate_state()


# ─── State ────────────────────────────────────────────────────────────
func _on_hp_signal(_index: int, _new_hp: int, _max_hp: int) -> void:
	_evaluate_state()


## Asymmetric thresholds (50% enter / 55% exit) give a little hysteresis so
## tiny back-and-forth healing doesn't make the vignette flicker on/off.
func _evaluate_state() -> void:
	if GameState.is_party_wiped():
		_force_clear()
		return
	var ratio: float = _party_hp_ratio()
	if not _is_active and ratio <= DANGER_HP_RATIO_ENTER:
		_activate()
	elif _is_active and ratio > DANGER_HP_RATIO_EXIT:
		_deactivate()


func _party_hp_ratio() -> float:
	var total_hp: int = 0
	var total_max: int = 0
	for i in GameState.party_size():
		total_hp += GameState.party_hp[i]
		total_max += GameState.effective_max_hp(i)
	if total_max <= 0:
		return 1.0
	return float(total_hp) / float(total_max)


# ─── Transitions ──────────────────────────────────────────────────────
func _activate() -> void:
	_is_active = true
	_kill_tweens()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_intensity, _get_intensity(), PULSE_MAX, FADE_IN_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_callback(_start_pulse)


func _deactivate() -> void:
	_is_active = false
	_kill_tweens()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_intensity, _get_intensity(), 0.0, FADE_OUT_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## Slow alpha breathing while active — heartbeat-ish without strobing.
func _start_pulse() -> void:
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_method(_set_intensity, PULSE_MAX, PULSE_MIN, PULSE_HALF_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_method(_set_intensity, PULSE_MIN, PULSE_MAX, PULSE_HALF_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _force_clear() -> void:
	_is_active = false
	_kill_tweens()
	_set_intensity(0.0)


func _kill_tweens() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()


# ─── Shader plumbing ──────────────────────────────────────────────────
func _set_intensity(value: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("intensity", value)


func _get_intensity() -> float:
	if _material == null:
		return 0.0
	return float(_material.get_shader_parameter("intensity"))
