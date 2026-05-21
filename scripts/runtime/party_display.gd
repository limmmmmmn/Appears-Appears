class_name PartyDisplay
extends Control

## Town party summary. Rebuilds from GameState and reacts to purchased cards.

@export var hero_box_scene: PackedScene
@export var hero_box_min_size: Vector2 = Vector2(116, 72)

@onready var _box_container: HBoxContainer = %HeroBoxes

var _boxes_by_id: Dictionary = {}
var _known_party_ids: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild_boxes()
	EventBus.party_changed.connect(_on_party_changed)
	EventBus.party_hp_changed.connect(_refresh_boxes)
	EventBus.modifier_purchased.connect(_on_modifier_purchased)


func _rebuild_boxes() -> void:
	for child in _box_container.get_children():
		child.queue_free()
	_boxes_by_id.clear()
	for i in GameState.party_size():
		var box: Control = hero_box_scene.instantiate()
		box.custom_minimum_size = hero_box_min_size
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_box_container.add_child(box)
		box.setup(i)
		_boxes_by_id[GameState.party[i].id] = box
	_known_party_ids = _current_party_ids()


func _refresh_boxes() -> void:
	for child in _box_container.get_children():
		if child.has_method("refresh"):
			child.refresh()


func _on_party_changed() -> void:
	var previous_ids: Dictionary = _known_party_ids.duplicate()
	_rebuild_boxes()
	for member: CharacterData in GameState.party:
		if not previous_ids.has(member.id):
			var box: Node = _boxes_by_id.get(member.id, null)
			if box and box.has_method("play_join_feedback"):
				box.play_join_feedback()


func _on_modifier_purchased(mod: ModifierData) -> void:
	_refresh_boxes()
	var affected: Array[Node] = _affected_boxes_for_modifier(mod)
	var popup_text: String = _popup_text_for_modifier(mod)
	for box in affected:
		box.play_modifier_feedback(mod, popup_text)


func _affected_boxes_for_modifier(mod: ModifierData) -> Array[Node]:
	var out: Array[Node] = []
	if mod.category == ModifierData.Category.COMPANION:
		return out
	if mod.required_party_member_id != &"":
		var box: Node = _boxes_by_id.get(mod.required_party_member_id, null)
		if box and box.has_method("play_modifier_feedback"):
			out.append(box)
		return out
	for child in _box_container.get_children():
		if child.has_method("play_modifier_feedback"):
			out.append(child)
	return out


func _popup_text_for_modifier(mod: ModifierData) -> String:
	if mod.effect_data.has("hp_flat"):
		return "+%d HP" % GameState.modifier_last_int_effect(mod, "hp_flat")
	if mod.effect_data.has("atk_flat"):
		return "+%d ATK" % GameState.modifier_last_int_effect(mod, "atk_flat")
	if mod.effect_data.has("def_flat"):
		return "+%d DEF" % GameState.modifier_last_int_effect(mod, "def_flat")
	if mod.effect_data.has("agi_flat"):
		return "+%d AGI" % GameState.modifier_last_int_effect(mod, "agi_flat")
	if mod.effect_data.has("move_speed_flat"):
		return "+%d SPD" % GameState.modifier_last_int_effect(mod, "move_speed_flat")
	if mod.effect_data.has("hero_damage_bonus_mult"):
		return "+%d%% DMG" % int(round(GameState.modifier_last_float_effect(mod, "hero_damage_bonus_mult") * 100.0))
	if mod.effect_data.has("mage_splash_extra_targets"):
		return "+%d AOE" % int(mod.effect_data["mage_splash_extra_targets"])
	if mod.effect_data.has("priest_heal_flat"):
		return "+%d HEAL" % GameState.modifier_last_int_effect(mod, "priest_heal_flat")
	if mod.effect_data.has("thief_steal_chance"):
		return "+%d%% STEAL" % int(round(GameState.modifier_last_float_effect(mod, "thief_steal_chance") * 100.0))
	if mod.effect_data.has("evade_chance"):
		return "+%d%% EVA" % int(round(GameState.modifier_last_float_effect(mod, "evade_chance") * 100.0))
	if mod.effect_data.has("window_collision_heal_flat"):
		return "+%d BUMP HEAL" % GameState.modifier_last_int_effect(mod, "window_collision_heal_flat")
	if mod.effect_data.has("party_bump_damage_ratio"):
		return "BUMP ATK"
	if mod.effect_data.has("window_collision_damage_ratio"):
		return "CRASH"
	return mod.display_name


func _current_party_ids() -> Dictionary:
	var ids: Dictionary = {}
	for member: CharacterData in GameState.party:
		ids[member.id] = true
	return ids
