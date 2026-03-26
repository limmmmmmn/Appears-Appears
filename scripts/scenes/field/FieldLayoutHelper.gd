extends RefCounted
class_name FieldLayoutHelper


func find_tilemap(host: Node, current_tilemap: TileMapLayer) -> TileMapLayer:
	if current_tilemap:
		return current_tilemap

	var named_tilemap := host.get_node_or_null("TileMapLayer")
	if named_tilemap is TileMapLayer:
		return named_tilemap as TileMapLayer

	for child in host.get_children():
		if child is TileMapLayer:
			return child as TileMapLayer

	return _find_node_recursive(host, TileMapLayer) as TileMapLayer


func apply_camera_limits(party_leader: Node2D) -> void:
	if party_leader == null:
		return
	var camera := _ensure_player_camera(party_leader)
	if camera == null:
		return
	camera.limit_enabled = false


func get_map_bounds(tilemap: TileMapLayer, cached_bounds: Rect2, fallback_tile_size: int) -> Rect2:
	if cached_bounds.size.x > 0.0 and cached_bounds.size.y > 0.0:
		return cached_bounds

	if tilemap:
		var used_rect: Rect2i = tilemap.get_used_rect()
		if used_rect.size.x > 0 and used_rect.size.y > 0:
			var tile_size := Vector2(fallback_tile_size, fallback_tile_size)
			if tilemap.tile_set:
				tile_size = Vector2(tilemap.tile_set.tile_size)
			return Rect2(Vector2(used_rect.position) * tile_size, Vector2(used_rect.size) * tile_size)

	return Rect2()


func _ensure_player_camera(party_leader: Node2D) -> Camera2D:
	var camera := party_leader.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		party_leader.add_child(camera)

	camera.enabled = true
	camera.make_current()
	return camera


func _find_node_recursive(node: Node, type) -> Node:
	for child in node.get_children():
		if is_instance_of(child, type):
			return child
		var found := _find_node_recursive(child, type)
		if found:
			return found
	return null
