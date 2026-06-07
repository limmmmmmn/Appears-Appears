class_name CharacterData
extends Resource

## Party member archetype data.
## Saved as .tres files under data/characters/.
## A single .tres = one party member (warrior, mage, ...).
## Per-run state (current HP/MP, level) lives on GameState, not here.

## Direction row order in the sprite sheet.
## Standard RPG layout: Down, Left, Right, Up (top to bottom).
enum Direction { DOWN, LEFT, RIGHT, UP }

@export var id: StringName = &""
@export var display_name: String = ""

## Visuals.
## Sprite sheet layout: frames_per_direction columns × 4 rows (one row per direction).
## Default: 3 cols × 4 rows of 16x24 frames (48x96 total).
@export var sprite_sheet: Texture2D
@export var frame_size: Vector2i = Vector2i(16, 24)
@export var frames_per_direction: int = 3
@export var walk_fps: float = 6.0

## Frame-local anchor points. The character node sits on foot_anchor, so
## different-sized party sprites can share the same ground contact point.
@export var foot_anchor: Vector2 = Vector2(8, 22)
@export var speech_anchor: Vector2 = Vector2(8, 0)
@export var popup_anchor: Vector2 = Vector2(8, 2)

## Player-only collision, also authored in frame-local coordinates so a tall
## or short leader can keep its feet, body, and camera feeling aligned.
@export var body_size: Vector2 = Vector2(10, 12)
@export var body_center: Vector2 = Vector2(8, 17)

## Optional UI portrait (separate texture, used in HUD / dialogs).
@export var portrait: Texture2D
@export var attack_effect: Texture2D

## Base stats (level 1).
@export var max_hp: int = 30
@export var max_mp: int = 10
@export var attack: int = 5
@export var agility: int = 5


func frame_size_vec() -> Vector2:
	return Vector2(frame_size)


## A single still icon for UI (property inspector header). Uses the explicit portrait
## if authored, else crops the idle (middle column) DOWN-facing frame from the sheet.
func inspector_icon() -> Texture2D:
	if portrait != null:
		return portrait
	if sprite_sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sprite_sheet
	var col: int = clampi(1, 0, maxi(0, frames_per_direction - 1))  # middle = idle
	atlas.region = Rect2(Vector2(float(col) * float(frame_size.x), 0.0), frame_size_vec())
	return atlas


func visual_center_local() -> Vector2:
	return frame_size_vec() * 0.5 - foot_anchor


func speech_anchor_local() -> Vector2:
	return speech_anchor - foot_anchor


func popup_anchor_local() -> Vector2:
	return popup_anchor - foot_anchor


func body_center_local() -> Vector2:
	return body_center - foot_anchor
