class_name ModifierCard
extends Button

## A single modifier offering. Click to buy with gold. Greys out when owned.

signal purchase_requested(card: ModifierCard, mod: ModifierData)

const RARITY_COLORS: Dictionary = {
	ModifierData.Rarity.COMMON: Color(0.75, 0.75, 0.78, 1),
	ModifierData.Rarity.UNCOMMON: Color(0.45, 0.85, 0.50, 1),
	ModifierData.Rarity.RARE: Color(0.45, 0.6, 0.95, 1),
	ModifierData.Rarity.LEGENDARY: Color(0.95, 0.65, 0.25, 1),
}

@onready var _name_label: Label = %CardName
@onready var _desc_label: Label = %CardDesc
@onready var _cost_label: Label = %CardCost
@onready var _border: Panel = %CardBorder
@onready var _class_header: HBoxContainer = %ClassHeader
@onready var _portrait: TextureRect = %Portrait
@onready var _effect: TextureRect = %Effect

var data: ModifierData
var cost: int = 0
var purchased: bool = false


## Inject the modifier this card represents.
func setup(mod: ModifierData) -> void:
	data = mod
	cost = GameState.modifier_purchase_cost(mod)
	purchased = false
	disabled = false
	modulate = Color.WHITE
	if is_inside_tree():
		_apply_data()


func _ready() -> void:
	pressed.connect(_on_pressed)
	if data:
		_apply_data()


func _apply_data() -> void:
	cost = GameState.modifier_purchase_cost(data)
	_name_label.text = _display_name_with_level()
	_desc_label.text = data.description
	_cost_label.text = "%d G" % cost
	# Recolor the border via a duplicated stylebox so other cards aren't affected.
	var stylebox: StyleBoxFlat = _border.get_theme_stylebox("panel").duplicate()
	stylebox.border_color = RARITY_COLORS.get(data.rarity, Color.WHITE)
	_border.add_theme_stylebox_override("panel", stylebox)
	_apply_class_header()


## Class-specific upgrade cards (e.g. Heavy Strike → hero) get a header strip
## showing the character's idle portrait + their basic-attack effect, so the
## player can tell at a glance "this is for my Hero."
func _apply_class_header() -> void:
	var owner_id: StringName = data.required_party_member_id
	if owner_id == &"":
		_class_header.visible = false
		return
	var character: CharacterData = _resolve_character(owner_id)
	if character == null:
		_class_header.visible = false
		return
	_portrait.texture = _build_portrait_texture(character)
	_effect.texture = character.attack_effect
	_class_header.visible = true


## Pull the CharacterData for an owner id. Prefer party (so the resource matches
## what the player actually has), then fall back to companion pool entries on
## offered cards (recruit-driven references), then to disk by convention.
func _resolve_character(owner_id: StringName) -> CharacterData:
	for member: CharacterData in GameState.party:
		if member.id == owner_id:
			return member
	var path := "res://data/characters/%s.tres" % owner_id
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is CharacterData:
			return res
	return null


## Carve the idle "facing down" frame out of the walk sheet. Standard layout:
## row 0 = down, column = idle_col (default 1).
func _build_portrait_texture(character: CharacterData) -> Texture2D:
	if character.sprite_sheet == null:
		return null
	var fw: int = character.frame_size.x
	var fh: int = character.frame_size.y
	var idle_col: int = clampi(1, 0, maxi(0, character.frames_per_direction - 1))
	var atlas := AtlasTexture.new()
	atlas.atlas = character.sprite_sheet
	atlas.region = Rect2(idle_col * fw, 0, fw, fh)
	atlas.filter_clip = true
	return atlas


func _display_name_with_level() -> String:
	if data.category == ModifierData.Category.COMPANION or data.max_level <= 1:
		return data.display_name
	var next_level: int = mini(GameState.modifier_level(data.id) + 1, data.max_level)
	return "%s Lv %d/%d" % [data.display_name, next_level, data.max_level]


func _on_pressed() -> void:
	if purchased or data == null:
		return
	purchase_requested.emit(self, data)


func mark_purchased() -> void:
	purchased = true
	disabled = true
	modulate = Color(0.45, 0.45, 0.45, 1)
	_cost_label.text = "OWNED"


func mark_unaffordable_flash() -> void:
	# Brief red flash when player can't afford. No tween dependency on parent.
	var tween: Tween = create_tween()
	tween.tween_property(_cost_label, "modulate", Color(1, 0.3, 0.3, 1), 0.1)
	tween.tween_property(_cost_label, "modulate", Color.WHITE, 0.2)
