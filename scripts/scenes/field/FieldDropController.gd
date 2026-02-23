extends RefCounted
class_name FieldDropController

var host: Node2D = null


func setup(p_host: Node2D) -> void:
	host = p_host


func spawn_battle_drops(
	hp_orbs: int,
	gold_amount: int,
	item_ids: Array,
	world_pos: Vector2,
	window_rect: Rect2,
	party_leader: Node2D,
	world_effect_z: int,
	exp_amount: int = 0
) -> void:
	if host == null:
		return

	if hp_orbs <= 0 and gold_amount <= 0 and item_ids.is_empty() and exp_amount <= 0:
		return

	var equip_item_ids: Array[String] = []
	var normal_item_ids: Array[String] = []
	for item_any in item_ids:
		var item_id: String = str(item_any)
		if item_id.is_empty():
			continue
		if DataManager != null and not DataManager.get_equipment(item_id).is_empty():
			equip_item_ids.append(item_id)
		else:
			normal_item_ids.append(item_id)

	var scatter_rect: Rect2 = _resolve_scatter_rect(window_rect, world_pos, party_leader)
	var drops: Array[Dictionary] = []
	var delay: float = 0.0
	const DELAY_STEP: float = 0.08

	# EXP 오브 (하늘색) — 먼저 떨어짐
	var exp_orb_count: int = _calc_exp_orb_count(exp_amount)
	var exp_per_orb: int = int(ceil(float(exp_amount) / float(maxi(1, exp_orb_count))))
	var exp_remaining: int = exp_amount
	for _i in range(exp_orb_count):
		var orb_exp: int = mini(exp_per_orb, exp_remaining)
		exp_remaining -= orb_exp
		drops.append({"type": FieldDrop.DropType.EXP_ORB, "delay": delay, "exp": orb_exp})
		delay += DELAY_STEP

	for _i in range(hp_orbs):
		drops.append({"type": FieldDrop.DropType.HP_ORB, "delay": delay})
		delay += DELAY_STEP
	var gold_chunks: Array[int] = _split_gold_into_drop_chunks(gold_amount)
	for chunk in gold_chunks:
		drops.append({"type": FieldDrop.DropType.GOLD, "delay": delay, "gold": chunk})
		delay += DELAY_STEP
	for normal_item_id in normal_item_ids:
		drops.append({"type": FieldDrop.DropType.ITEM, "delay": delay, "item_id": normal_item_id})
		delay += DELAY_STEP

	for data_any in drops:
		var data: Dictionary = data_any as Dictionary
		var drop := FieldDrop.new()
		drop.drop_type = int(data.get("type", FieldDrop.DropType.HP_ORB))
		drop.spawn_delay = float(data.get("delay", 0.0))
		if drop.drop_type == FieldDrop.DropType.HP_ORB:
			drop.heal_amount = FieldDrop.HP_PER_ORB
		elif drop.drop_type == FieldDrop.DropType.GOLD:
			drop.gold_amount = maxi(1, int(data.get("gold", 1)))
		elif drop.drop_type == FieldDrop.DropType.EXP_ORB:
			drop.exp_amount = maxi(1, int(data.get("exp", 1)))
		elif drop.drop_type == FieldDrop.DropType.ITEM:
			drop.item_id = str(data.get("item_id", ""))
			var item_data: Dictionary = {}
			if DataManager != null:
				item_data = DataManager.get_equipment(drop.item_id)
				if item_data.is_empty():
					item_data = DataManager.get_item(drop.item_id)
			if not item_data.is_empty():
				drop.item_type = str(item_data.get("type", item_data.get("slot", "")))
				drop.item_rarity = str(item_data.get("rarity", "common"))
		drop.position = Vector2(
			randf_range(scatter_rect.position.x, scatter_rect.end.x),
			randf_range(scatter_rect.position.y, scatter_rect.end.y)
		)
		drop.z_index = world_effect_z
		host.add_child(drop)

	if not equip_item_ids.is_empty():
		var chest_drop := FieldDrop.new()
		chest_drop.drop_type = FieldDrop.DropType.BATTLE_CHEST
		chest_drop.spawn_delay = delay
		chest_drop.chest_gold_amount = 0
		chest_drop.chest_hp_orbs = 0
		chest_drop.chest_item_ids = equip_item_ids.duplicate()
		chest_drop.position = Vector2(
			randf_range(scatter_rect.position.x, scatter_rect.end.x),
			randf_range(scatter_rect.position.y, scatter_rect.end.y)
		)
		chest_drop.z_index = world_effect_z
		host.add_child(chest_drop)


func _resolve_scatter_rect(window_rect: Rect2, world_pos: Vector2, party_leader: Node2D) -> Rect2:
	if host == null:
		return Rect2(world_pos - Vector2(40, 30), Vector2(80, 60))

	if window_rect.size != Vector2.ZERO:
		var viewport := host.get_viewport()
		if viewport != null:
			var canvas_xform: Transform2D = viewport.get_canvas_transform()
			var inv_xform: Transform2D = canvas_xform.affine_inverse()
			var world_tl: Vector2 = inv_xform * window_rect.position
			var world_br: Vector2 = inv_xform * (window_rect.position + window_rect.size)
			return Rect2(world_tl, world_br - world_tl)

	if world_pos == Vector2.ZERO and party_leader != null:
		world_pos = party_leader.global_position
	return Rect2(world_pos - Vector2(40, 30), Vector2(80, 60))


func _calc_exp_orb_count(total_exp: int) -> int:
	if total_exp <= 0:
		return 0
	# EXP 10당 1개, 최소 1 최대 5
	return clampi(int(ceil(float(total_exp) / 10.0)), 1, 5)


func _split_gold_into_drop_chunks(total_gold: int) -> Array[int]:
	var chunks: Array[int] = []
	if total_gold <= 0:
		return chunks
	var max_chunks: int = clampi(int(ceil(float(total_gold) / 12.0)), 1, 8)
	var remaining: int = total_gold
	for i in range(max_chunks):
		var remain_slots: int = max_chunks - i
		var value: int = int(round(float(remaining) / float(remain_slots)))
		value = maxi(1, value)
		chunks.append(value)
		remaining -= value
	if remaining != 0 and not chunks.is_empty():
		chunks[chunks.size() - 1] += remaining
	return chunks
