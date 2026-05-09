class_name ModifierCard
extends Button

## A single modifier offering. Click to buy with gold. Greys out when owned.

signal purchase_requested(card: ModifierCard, mod: ModifierData)

const COST_BY_RARITY: Dictionary = {
	ModifierData.Rarity.COMMON: 5,
	ModifierData.Rarity.UNCOMMON: 10,
	ModifierData.Rarity.RARE: 20,
	ModifierData.Rarity.LEGENDARY: 40,
}

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

var data: ModifierData
var cost: int = 0
var purchased: bool = false


## Inject the modifier this card represents.
func setup(mod: ModifierData) -> void:
	data = mod
	cost = COST_BY_RARITY.get(mod.rarity, 5)


func _ready() -> void:
	pressed.connect(_on_pressed)
	if data:
		_apply_data()


func _apply_data() -> void:
	_name_label.text = data.display_name
	_desc_label.text = data.description
	_cost_label.text = "%d G" % cost
	# Recolor the border via a duplicated stylebox so other cards aren't affected.
	var stylebox: StyleBoxFlat = _border.get_theme_stylebox("panel").duplicate()
	stylebox.border_color = RARITY_COLORS.get(data.rarity, Color.WHITE)
	_border.add_theme_stylebox_override("panel", stylebox)


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
