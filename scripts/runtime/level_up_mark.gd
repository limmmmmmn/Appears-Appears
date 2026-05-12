class_name LevelUpMark
extends Control

## Floating "+" badge that pops above (or on) a party member when they level
## up. Two flavors driven by the `mode` @export:
##   • TRANSIENT  — brief pop, short hold, fade out, auto queue_free. No
##                  click handling. Used on the field as a "look up at the
##                  HUD!" hint.
##   • PERSISTENT — pop in, slow alpha blink + gentle bounce, stays until
##                  the player clicks. Emits `dismissed` on click. Used on
##                  the HUD portrait to mark unspent level-ups.
##
## The widget owns its own animation lifecycle, so the spawner only needs
## to parent + set mode (+ optionally listen to `dismissed`).

signal dismissed

enum Mode { PERSISTENT, TRANSIENT }

@export var mode: Mode = Mode.PERSISTENT

const POP_IN_DURATION: float = 0.18
## TRANSIENT-only timings.
const TRANSIENT_VISIBLE_DURATION: float = 0.85
const TRANSIENT_FADE_DURATION: float = 0.4
## PERSISTENT-only timings.
const BLINK_HALF_PERIOD: float = 0.7
const BLINK_LOW_ALPHA: float = 0.35
const BOUNCE_AMPLITUDE: float = 2.0
const BOUNCE_HALF_PERIOD: float = 0.55


func _ready() -> void:
	pivot_offset = size * 0.5
	if mode == Mode.PERSISTENT:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_play_persistent_sequence()
	else:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_play_transient_sequence()


## Clicks only matter in PERSISTENT mode — TRANSIENT marks ignore input and
## just clean themselves up.
func _gui_input(event: InputEvent) -> void:
	if mode != Mode.PERSISTENT:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		dismissed.emit()
		queue_free()


# ─── Animation flavors ────────────────────────────────────────────────
func _play_persistent_sequence() -> void:
	_pop_in()
	_start_blink_loop()
	_start_bounce_loop()


func _play_transient_sequence() -> void:
	_pop_in()
	var tween: Tween = create_tween()
	tween.tween_interval(TRANSIENT_VISIBLE_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, TRANSIENT_FADE_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _pop_in() -> void:
	scale = Vector2(0.55, 0.55)
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, POP_IN_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Slow alpha pulse — visible enough to draw the eye, soft enough not to
## strobe distractingly when several marks are up at once.
func _start_blink_loop() -> void:
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(self, "modulate:a", BLINK_LOW_ALPHA, BLINK_HALF_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "modulate:a", 1.0, BLINK_HALF_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_bounce_loop() -> void:
	var base_y: float = position.y
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(self, "position:y", base_y - BOUNCE_AMPLITUDE, BOUNCE_HALF_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", base_y, BOUNCE_HALF_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
