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


func setup_test_field_layout(
	host: Node2D,
	current_tilemap: TileMapLayer,
	spawn_point: Marker2D,
	is_test_field: bool,
	map_tiles: Vector2i,
	tile_size: int,
	floor_source_id: int,
	wall_source_id: int,
	overlay_texture: Texture2D,
	player_spawn_ratio: Vector2
) -> Dictionary:
	if not is_test_field:
		return {"tilemap": current_tilemap, "bounds": Rect2()}

	var collision_map := host.get_node_or_null("TileMapLayer") as TileMapLayer
	var background_map := host.get_node_or_null("TileMapLayerBg") as TileMapLayer

	if collision_map:
		_build_test_map(collision_map, true, map_tiles, floor_source_id, wall_source_id)
		current_tilemap = collision_map
	if background_map:
		_build_test_map(background_map, false, map_tiles, floor_source_id, wall_source_id)

	var map_size_px := Vector2(map_tiles.x * tile_size, map_tiles.y * tile_size)
	var test_bounds := Rect2(Vector2.ZERO, map_size_px)
	_apply_test_field_overlay(host, map_size_px, overlay_texture)

	var bg_rect := host.get_node_or_null("Background") as ColorRect
	if bg_rect:
		bg_rect.offset_right = map_size_px.x
		bg_rect.offset_bottom = map_size_px.y

	var player_spawn := map_size_px * player_spawn_ratio
	if spawn_point:
		spawn_point.global_position = player_spawn

	var preview_player := host.get_node_or_null("Player") as Node2D
	if preview_player:
		preview_player.global_position = player_spawn

	return {"tilemap": current_tilemap, "bounds": test_bounds}


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


func get_boss_position_from_bounds(is_test_field: bool, bounds: Rect2, boss_spawn_ratio: Vector2) -> Vector2:
	if not is_test_field:
		return Vector2.ZERO
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Vector2.ZERO
	return bounds.position + bounds.size * boss_spawn_ratio


func _build_test_map(
	layer: TileMapLayer,
	add_border_wall: bool,
	map_tiles: Vector2i,
	floor_source_id: int,
	wall_source_id: int
) -> void:
	layer.clear()
	for y in range(map_tiles.y):
		for x in range(map_tiles.x):
			var source_id := floor_source_id
			if add_border_wall and (x == 0 or y == 0 or x == map_tiles.x - 1 or y == map_tiles.y - 1):
				source_id = wall_source_id
			layer.set_cell(Vector2i(x, y), source_id, Vector2i.ZERO)


func _apply_test_field_overlay(host: Node2D, map_size_px: Vector2, overlay_texture: Texture2D) -> void:
	var existing := host.get_node_or_null("FieldMapOverlay") as Sprite2D
	if existing:
		existing.queue_free()

	if overlay_texture == null:
		return

	var overlay := Sprite2D.new()
	overlay.name = "FieldMapOverlay"
	overlay.centered = false
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.texture = overlay_texture
	overlay.position = Vector2.ZERO
	overlay.z_index = 8
	host.add_child(overlay)

	var tex_size: Vector2 = overlay_texture.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0:
		overlay.scale = Vector2(map_size_px.x / tex_size.x, map_size_px.y / tex_size.y)


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
