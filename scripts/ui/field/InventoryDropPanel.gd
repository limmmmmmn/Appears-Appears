extends PanelContainer
class_name InventoryDropPanel

var hud_ref: FieldHUD = null


func set_hud_ref(hud: FieldHUD) -> void:
	hud_ref = hud


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	return data.get("type", "") == "equipment" and data.get("source", "") == "equipment"


func _drop_data(_pos: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var hero_index: int = data.get("hero_index", -1)
	var source_slot: String = data.get("source_slot", "")
	if hero_index < 0 or source_slot.is_empty():
		return
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size() or party[hero_index] == null:
		return
	var hero: Hero = party[hero_index]
	if InventoryManager and InventoryManager.unequip_item(hero, source_slot):
		if hud_ref:
			hud_ref.update_party_display()
			hud_ref._update_inventory_display()
