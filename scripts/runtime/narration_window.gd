class_name NarrationWindow
extends Control

## The always-on narration window — the bottom "text terminal" of the OS desktop.
## Shows the latest story / system line; field messages are mirrored here via
## EventBus.narration.
##
## LOOK = scenes/ui/narration_window.tscn (window chrome, title chip, fonts, colors,
## placement — all editable in the editor). This script is LOGIC ONLY: it pipes
## narration text into the %Text label.

## The dim "idle" tint vs the bright tint once a real line arrives. (Kept in code
## because it's a state change, not static styling — tweak the dim default on the
## %Text node in the scene, this just brightens it on the first message.)
const ACTIVE_TEXT: Color = Color(0.9, 0.91, 0.94, 1.0)

@onready var _text_label: Label = %Text


func _ready() -> void:
	EventBus.narration.connect(_on_narration)


func _on_narration(text: String) -> void:
	if _text_label != null:
		_text_label.text = text
		_text_label.add_theme_color_override("font_color", ACTIVE_TEXT)
