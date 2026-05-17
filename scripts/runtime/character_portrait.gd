class_name CharacterPortrait
extends Panel

## Square portrait box. Feed it a CharacterData and it crops a head+shoulders
## thumbnail from the character's walk sheet — same data the field/town
## already use, so no separate portrait asset pipeline is required.
##
## Reusable anywhere that needs a "who is this party member" badge: HUD
## boxes, town recruit cards, future inventory headers, etc.

@onready var _texture: TextureRect = %PortraitTexture

var _pending_character: CharacterData


## Inject the character to portray. Safe to call before the node is in tree.
func set_character(data: CharacterData) -> void:
	_pending_character = data
	if is_inside_tree():
		_apply()


## Clear back to an empty frame (used when a party slot is vacated).
func clear() -> void:
	_pending_character = null
	if is_inside_tree():
		_texture.texture = null


func _ready() -> void:
	if _pending_character:
		_apply()


func _apply() -> void:
	if _pending_character == null:
		_texture.texture = null
		return
	_texture.texture = _head_crop_for(_pending_character)


## Carve a square head+shoulders crop out of the idle-down frame. The 16×16
## region scales 2× cleanly to a 32×32 display target with NEAREST filter,
## which is what the box uses.
func _head_crop_for(data: CharacterData) -> Texture2D:
	if data.sprite_sheet == null:
		return null
	var fw: int = data.frame_size.x
	var idle_col: int = clampi(1, 0, maxi(0, data.frames_per_direction - 1))
	var atlas := AtlasTexture.new()
	atlas.atlas = data.sprite_sheet
	atlas.region = Rect2(idle_col * fw, 0, fw, fw)
	atlas.filter_clip = true
	return atlas
