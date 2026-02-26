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
	world_effect_z: int,
	wave_count: int = 1
) -> void:
	## 전투 승리 후 초록 전리품 조각를 kill_count개 드롭
	## 각 오브에 전리품 점수 + 골드를 균등 분배
	## wave_count > 1이면 웨이브 단위로 시간차 드롭 (엘리트x2, 보스x4 등)
	if host == null or kill_count <= 0:
		return
	if total_loot_score <= 0 and total_gold <= 0:
		return

	wave_count = maxi(1, wave_count)
	var scatter_rect: Rect2 = _resolve_scatter_rect(window_rect, world_pos, party_leader)
	var orb_count: int = maxi(1, kill_count)
	# floor 분배 후 나머지를 앞쪽 오브에 +1씩 배분 (정확히 orb_count개 보장)
	var base_score: int = int(floor(float(total_loot_score) / float(orb_count))) if total_loot_score > 0 else 0
	var extra_score: int = (total_loot_score - base_score * orb_count) if total_loot_score > 0 else 0
	var base_gold: int = int(floor(float(total_gold) / float(orb_count))) if total_gold > 0 else 0
	var extra_gold: int = (total_gold - base_gold * orb_count) if total_gold > 0 else 0
	const DELAY_STEP: float = 0.12  # 피스 하나씩 두두두두 떨어지는 간격

	for i in range(orb_count):
		var orb_score: int = base_score + (1 if i < extra_score else 0)
		var orb_gold: int = base_gold + (1 if i < extra_gold else 0)

		var drop := FieldDrop.new()
		drop.drop_type = FieldDrop.DropType.LOOT_ORB
		drop.loot_score = orb_score
		drop.gold_amount = orb_gold
		drop.spawn_delay = float(i) * DELAY_STEP
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
