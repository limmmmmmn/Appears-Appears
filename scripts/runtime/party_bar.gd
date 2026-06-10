class_name PartyBar
extends HBoxContainer

## Bottom party strip — compact 초상화+HP chips, one per member, laid out horizontally
## under the field. Rebuilds on party_changed and pushes per-member HP / XP / equip /
## armor / downed updates (XP/equip land on hidden nodes in the compact box — harmless).
## The row itself is authored in party_bar.tscn with editor-preview boxes; those are
## cleared at runtime before the live party is populated.

const MEMBER_BOX_SCENE: PackedScene = preload("res://scenes/ui/party_member_box.tscn")
## 따로 다니기: each squad cluster sits past this gap — the visibly broken chain.
const DETACH_GAP: float = 14.0

var _member_boxes: Array[PartyMemberBox] = []
var _spacers: Array[Control] = []


func _ready() -> void:
	EventBus.party_changed.connect(_rebuild)
	EventBus.party_member_hp_changed.connect(_on_hp)
	EventBus.party_member_xp_changed.connect(_on_xp)
	EventBus.party_member_downed.connect(_on_downed)
	EventBus.party_member_revived.connect(_on_revived)
	EventBus.party_equipment_changed.connect(_on_equip)
	EventBus.armor_equipped.connect(_on_armor.unbind(1))
	EventBus.member_group_changed.connect(_on_group_changed)
	_rebuild()


func _rebuild() -> void:
	# Clear EVERYTHING (incl. the editor-preview boxes authored in the scene) so runtime
	# shows exactly the live party with no duplicates.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_member_boxes.clear()
	_spacers.clear()
	for i in GameState.party_size():
		var box: PartyMemberBox = MEMBER_BOX_SCENE.instantiate()
		add_child(box)
		box.setup(i, GameState.party[i])
		_member_boxes.append(box)
	for g in Balance.PARTY_GROUP_MAX - 1:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(DETACH_GAP, 0.0)
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.visible = false
		add_child(spacer)
		_spacers.append(spacer)
	_reorder()


## Bar order mirrors the field: group-0 chain first, then each squad cluster
## behind a gap. Group badges refresh in the same pass.
func _reorder() -> void:
	var group_boxes: Array = []
	for g in Balance.PARTY_GROUP_MAX:
		group_boxes.append([])
	for box in _member_boxes:
		if not is_instance_valid(box):
			continue
		var g: int = clampi(GameState.member_group(box.party_index), 0, Balance.PARTY_GROUP_MAX - 1)
		group_boxes[g].append(box)
		box.set_group_badge(g)
	var order: Array = []
	for g in Balance.PARTY_GROUP_MAX:
		for box in group_boxes[g]:
			order.append(box)
		if g < _spacers.size():
			# A gap shows only BETWEEN two occupied clusters (empty squads collapse).
			var occupied_before: bool = false
			for gg in g + 1:
				occupied_before = occupied_before or not group_boxes[gg].is_empty()
			_spacers[g].visible = occupied_before and not group_boxes[g + 1].is_empty()
			order.append(_spacers[g])
	for i in order.size():
		move_child(order[i], i)


func _on_group_changed(index: int, group: int) -> void:
	_reorder()
	if index >= 0 and index < _member_boxes.size() and is_instance_valid(_member_boxes[index]):
		_member_boxes[index].play_detach_pop(group != 0)


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
