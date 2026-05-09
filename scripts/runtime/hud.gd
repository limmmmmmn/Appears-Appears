class_name HUD
extends CanvasLayer

## Bottom-strip HUD: 4 party slots (portrait + name + HP) and a gold readout.
## Listens to EventBus signals — never poked directly by gameplay code.

const SLOT_COUNT: int = 4

@onready var _slots_container: HBoxContainer = %SlotsContainer
@onready var _gold_label: Label = %GoldLabel

var _slots: Array[HBoxContainer] = []
var _portraits: Array[TextureRect] = []
var _name_labels: Array[Label] = []
var _hp_labels: Array[Label] = []


func _ready() -> void:
	_collect_slot_refs()
	# Child _ready() runs before Main._ready() in Godot, so the party may not
	# be set up yet at this point. Listen for party_changed and (re)populate
	# whenever the roster lands. Initial call covers the rare case where the
	# party was set up via an autoload before the scene tree mounted.
	EventBus.party_changed.connect(_populate_from_game_state)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	_populate_from_game_state()
	_gold_label.text = "%d G" % GameState.gold


func _collect_slot_refs() -> void:
	for i in SLOT_COUNT:
		var slot: HBoxContainer = _slots_container.get_child(i)
		_slots.append(slot)
		_portraits.append(slot.get_node("Portrait") as TextureRect)
		_name_labels.append(slot.get_node("VBox/NameLabel") as Label)
		_hp_labels.append(slot.get_node("VBox/HPLabel") as Label)


func _populate_from_game_state() -> void:
	for i in SLOT_COUNT:
		var has_member: bool = i < GameState.party_size()
		_slots[i].visible = has_member
		if not has_member:
			continue
		var member: CharacterData = GameState.party[i]
		_name_labels[i].text = member.display_name
		_hp_labels[i].text = "HP %d/%d" % [GameState.party_hp[i], GameState.effective_max_hp(i)]
		_portraits[i].texture = _build_portrait(member)
		_slots[i].modulate = Color.WHITE


## Pulls the middle column of the top row (idle facing down) from the sprite sheet.
## RPG sheet convention: row0=down, col1=idle.
func _build_portrait(member: CharacterData) -> AtlasTexture:
	if member.sprite_sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = member.sprite_sheet
	var fw: int = member.frame_size.x
	var fh: int = member.frame_size.y
	atlas.region = Rect2(fw, 0, fw, fh)
	return atlas


# ─── Signal handlers ──────────────────────────────────────────────────
func _on_party_member_hp_changed(index: int, new_hp: int, max_hp: int) -> void:
	if index < 0 or index >= SLOT_COUNT or index >= _hp_labels.size():
		return
	if new_hp <= 0:
		_hp_labels[index].text = "DEAD"
		_slots[index].modulate = Color(0.4, 0.4, 0.4, 1.0)
	else:
		_hp_labels[index].text = "HP %d/%d" % [new_hp, max_hp]
		_slots[index].modulate = Color.WHITE


func _on_gold_changed(new_gold: int) -> void:
	_gold_label.text = "%d G" % new_gold
