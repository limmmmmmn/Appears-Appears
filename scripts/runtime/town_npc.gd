class_name TownNpc
extends Node2D

## A party member walking around the town between INN and GUILD.
## Picks a random x target inside [min_x, max_x], walks to it, idles briefly,
## picks a new target. Uses the same CharacterVisual as the field/companion
## so the sprite sheet animation comes for free.

@export var speed: float = 14.0
@export var min_x: float = 130.0
@export var max_x: float = 540.0
@export var idle_min: float = 0.4
@export var idle_max: float = 1.6

@onready var _visual: CharacterVisual = $Visual

var _target_x: float
var _idle_timer: float = 0.0
var _pending_data: CharacterData


func setup(data: CharacterData) -> void:
	_pending_data = data
	if is_inside_tree() and _visual:
		_visual.setup(data)


func _ready() -> void:
	if _pending_data:
		_visual.setup(_pending_data)
	_target_x = randf_range(min_x, max_x)


func _process(delta: float) -> void:
	if _idle_timer > 0.0:
		_idle_timer -= delta
		_visual.set_velocity(Vector2.ZERO)
		if _idle_timer <= 0.0:
			_target_x = randf_range(min_x, max_x)
		return
	var dx: float = _target_x - position.x
	if absf(dx) < 1.0:
		_idle_timer = randf_range(idle_min, idle_max)
		_visual.set_velocity(Vector2.ZERO)
		return
	var dir: float = signf(dx)
	var step: float = minf(absf(dx), speed * delta)
	position.x += dir * step
	_visual.set_velocity(Vector2(dir * speed, 0.0))


## Brief green flash + scale pulse. Called by Town when the INN button heals.
func play_heal_pulse() -> void:
	if _visual == null:
		return
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "modulate", Color(0.65, 1.7, 0.85, 1.0), 0.15)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_visual, "modulate", Color.WHITE, 0.45)\
		.set_delay(0.15)
	tween.tween_property(self, "scale", Vector2(1.18, 1.18), 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.3)\
		.set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


## "뿅!" entrance for newly recruited companions. Scale-up from zero with a
## warm flash, then settle into normal walking.
func play_pop_in() -> void:
	if _visual == null:
		return
	scale = Vector2.ZERO
	_visual.modulate = Color(1.7, 1.55, 1.2, 1.0)
	# Pause walking briefly so the pop reads cleanly.
	_idle_timer = 0.5
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.35, 1.35), 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, 0.22)\
		.set_delay(0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_visual, "modulate", Color.WHITE, 0.45)\
		.set_delay(0.12)
