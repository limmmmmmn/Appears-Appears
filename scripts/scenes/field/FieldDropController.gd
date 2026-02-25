extends RefCounted
class_name FieldDropController

var host: Node2D = null


func setup(p_host: Node2D) -> void:
	host = p_host


func spawn_loot_orbs(
	total_loot_score: int,
	total_gold: int,
	kill_count: int,
	world_pos: Vector2,
	window_rect: Rect2,
	party_leader: Node2D,
	world_effect_z: int
) -> void:
	## 전투 승리 후 초록 루트 오브를 kill_count개 드롭
	## 각 오브에 루트점수 + 골드를 균등 분배
	if host == null or kill_count <= 0:
		return
	if total_loot_score <= 0 and total_gold <= 0:
		return

	var scatter_rect: Rect2 = _resolve_scatter_rect(window_rect, world_pos, party_leader)
	var orb_count: int = maxi(1, kill_count)
	var score_per_orb: int = maxi(0, int(ceil(float(total_loot_score) / float(orb_count)))) if total_loot_score > 0 else 0
	var gold_per_orb: int = maxi(0, int(ceil(float(total_gold) / float(orb_count)))) if total_gold > 0 else 0
	var remaining_score: int = total_loot_score
	var remaining_gold: int = total_gold
	var delay: float = 0.0
	const DELAY_STEP: float = 0.06

	for i in range(orb_count):
		var orb_score: int = mini(score_per_orb, remaining_score)
		var orb_gold: int = mini(gold_per_orb, remaining_gold)
		remaining_score -= orb_score
		remaining_gold -= orb_gold
		if orb_score <= 0 and orb_gold <= 0:
			break

		var drop := FieldDrop.new()
		drop.drop_type = FieldDrop.DropType.LOOT_ORB
		drop.loot_score = orb_score
		drop.gold_amount = orb_gold
		drop.spawn_delay = delay
		drop.position = Vector2(
			randf_range(scatter_rect.position.x, scatter_rect.end.x),
			randf_range(scatter_rect.position.y, scatter_rect.end.y)
		)
		drop.z_index = world_effect_z
		host.add_child(drop)
		delay += DELAY_STEP


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
