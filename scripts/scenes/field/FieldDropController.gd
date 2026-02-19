extends RefCounted
class_name FieldDropController

var host: Node2D = null


func setup(p_host: Node2D) -> void:
	host = p_host


func spawn_battle_drops(
	hp_orbs: int,
	world_pos: Vector2,
	window_rect: Rect2,
	party_leader: Node2D,
	world_effect_z: int
) -> void:
	if host == null:
		return

	var drops: Array[Dictionary] = []
	var delay: float = 0.0
	const DELAY_STEP: float = 0.08
	for i in range(hp_orbs):
		drops.append({"type": FieldDrop.DropType.HP_ORB, "delay": delay})
		delay += DELAY_STEP

	var scatter_rect: Rect2 = _resolve_scatter_rect(window_rect, world_pos, party_leader)
	for data_any in drops:
		var data: Dictionary = data_any as Dictionary
		var drop := FieldDrop.new()
		drop.drop_type = int(data.get("type", FieldDrop.DropType.HP_ORB))
		drop.spawn_delay = float(data.get("delay", 0.0))
		if drop.drop_type == FieldDrop.DropType.HP_ORB:
			drop.heal_amount = FieldDrop.HP_PER_ORB

		drop.position = Vector2(
			randf_range(scatter_rect.position.x, scatter_rect.end.x),
			randf_range(scatter_rect.position.y, scatter_rect.end.y)
		)
		drop.z_index = world_effect_z
		host.add_child(drop)


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
