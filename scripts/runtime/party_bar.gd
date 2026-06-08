class_name PartyBar
extends HBoxContainer

## Bottom-center party-member boxes, split out of the HUD into its own scene. Rebuilds
## on party_changed and pushes per-member HP / XP / equip / armor / downed updates. The
## row itself (this HBoxContainer) is authored in party_bar.tscn with editor-preview
## boxes; those are cleared at runtime before the live party is populated.

const MEMBER_BOX_SCENE: PackedScene = preload("res://scenes/ui/party_member_box.tscn")

var _member_boxes: Array[PartyMemberBox] = []


func _ready() -> void:
	EventBus.party_changed.connect(_rebuild)
	EventBus.party_member_hp_changed.connect(_on_hp)
	EventBus.party_member_xp_changed.connect(_on_xp)
	EventBus.party_member_downed.connect(_on_downed)
	EventBus.party_member_revived.connect(_on_revived)
	EventBus.party_equipment_changed.connect(_on_equip)
	EventBus.armor_equipped.connect(_on_armor.unbind(1))
	_rebuild()


func _rebuild() -> void:
	# Clear EVERYTHING (incl. the editor-preview boxes authored in the scene) so runtime
	# shows exactly the live party with no duplicates.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_member_boxes.clear()
	for i in GameState.party_size():
		var box: PartyMemberBox = MEMBER_BOX_SCENE.instantiate()
		add_child(box)
		box.setup(i, GameState.party[i])
		_member_boxes.append(box)


func _on_hp(index: int, new_hp: int, max_hp: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_hp(new_hp, max_hp)


func _on_xp(index: int, xp: int, xp_to_next: int, level: int) -> void:
	if index < 0 or index >= _member_boxes.size():
		return
	var ratio: float = 1.0 if level >= GameState.MAX_CHARACTER_LEVEL else clampf(float(xp) / float(maxi(1, xp_to_next)), 0.0, 1.0)
	_member_boxes[index].set_exp_ratio(ratio)
	_member_boxes[index].set_level(level)


func _on_downed(index: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_downed(true)


func _on_revived(index: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_downed(false)


func _on_equip(index: int) -> void:
	if index >= 0 and index < _member_boxes.size():
		_member_boxes[index].set_equipment(GameState.equipment_for_member(index))


func _on_armor() -> void:
	for box in _member_boxes:
		if is_instance_valid(box):
			box.set_armor(GameState.member_armor_level(box.party_index), GameState.member_armor_name(box.party_index))
