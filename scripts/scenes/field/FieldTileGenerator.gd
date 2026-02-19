extends RefCounted
class_name FieldTileGenerator

const TILE_SIZE: int = 16

const SRC_GRASS: int = 0
const SRC_DESERT: int = 1
const SRC_FOREST: int = 2
const SRC_HILL: int = 3
const SRC_MOUNTAIN: int = 4
const SRC_WATER: int = 5
const SRC_BRIDGE: int = 6
const SRC_CAVE: int = 7
const SRC_SHIREN: int = 8
const SRC_CASTLE: int = 9
const SRC_TOWN: int = 10

const SOURCE_TO_TYPE: Dictionary = {
	SRC_GRASS: "grass",
	SRC_DESERT: "desert",
	SRC_FOREST: "forest",
	SRC_HILL: "hill",
	SRC_MOUNTAIN: "mountain",
	SRC_WATER: "water",
	SRC_BRIDGE: "bridge",
	SRC_CAVE: "cave",
	SRC_SHIREN: "shiren",
	SRC_CASTLE: "castle",
	SRC_TOWN: "town",
}

const TILE_TEXTURE_PATHS: Dictionary = {
	SRC_GRASS: "res://assets/sprites/tilesets/grass.png",
	SRC_DESERT: "res://assets/sprites/tilesets/desert.png",
	SRC_FOREST: "res://assets/sprites/tilesets/forest.png",
	SRC_HILL: "res://assets/sprites/tilesets/hill.png",
	SRC_MOUNTAIN: "res://assets/sprites/tilesets/mountain.png",
	SRC_WATER: "res://assets/sprites/tilesets/water.png",
	SRC_BRIDGE: "res://assets/sprites/tilesets/bridge.png",
	SRC_CAVE: "res://assets/sprites/tilesets/cave.png",
	SRC_SHIREN: "res://assets/sprites/tilesets/shiren.png",
	SRC_CASTLE: "res://assets/sprites/tilesets/castle.png",
	SRC_TOWN: "res://assets/sprites/tilesets/town.png",
}

const WALKABLE_BASE: Array[int] = [SRC_GRASS, SRC_DESERT]
const WALKABLE_OVERLAY: Array[int] = [SRC_FOREST, SRC_HILL, SRC_BRIDGE, SRC_CAVE, SRC_SHIREN, SRC_CASTLE, SRC_TOWN]

var _cached_tileset: TileSet = null


func generate(
	tilemap_bg: TileMapLayer,
	tilemap_fg: TileMapLayer,
	grid_size: Vector2i,
	seed_value: int,
	include_town_tile: bool = true
) -> Dictionary:
	if tilemap_fg == null:
		return {}

	var tile_set: TileSet = _get_or_build_tileset()
	if tile_set != null:
		tilemap_fg.tile_set = tile_set
	if tilemap_bg != null and tile_set != null:
		tilemap_bg.tile_set = tile_set

	tilemap_fg.clear()
	if tilemap_bg != null:
		tilemap_bg.clear()

	var w: int = maxi(8, grid_size.x)
	var h: int = maxi(8, grid_size.y)

	var base: Array = []
	var overlay_src: Array = []
	var overlay_atlas: Array = []
	for y in range(h):
		var base_row: Array = []
		var src_row: Array = []
		var atlas_row: Array = []
		for _x in range(w):
			base_row.append(SRC_GRASS)
			src_row.append(-1)
			atlas_row.append(Vector2i.ZERO)
		base.append(base_row)
		overlay_src.append(src_row)
		overlay_atlas.append(atlas_row)

	var rng := RandomNumberGenerator.new()
	var normalized_seed: int = abs(seed_value)
	if normalized_seed == 0:
		normalized_seed = 1
	rng.seed = normalized_seed

	_paint_base_floor(base, w, h, rng)
	var river_info: Dictionary = _paint_river(base, w, h, rng)
	_place_bridge(base, overlay_src, overlay_atlas, w, h, river_info)
	_paint_mountains(overlay_src, overlay_atlas, base, w, h, rng)

	var special: Dictionary = _place_special_tiles(base, overlay_src, overlay_atlas, w, h, include_town_tile)
	var reserved: Dictionary = special.get("reserved", {})

	_paint_walkable_overlays(base, overlay_src, overlay_atlas, w, h, rng, reserved)
	_force_walkable(base, overlay_src, overlay_atlas, w, h, special)

	_commit_layers(tilemap_bg, tilemap_fg, base, overlay_src, overlay_atlas, w, h)

	return {
		"spawn_cell": special.get("spawn_cell", Vector2i(2, h / 2)),
		"boss_cell": special.get("boss_cell", Vector2i(w - 3, h / 2)),
		"shiren_cell": special.get("shiren_cell", Vector2i(w / 2, h / 2)),
		"town_cells": special.get("town_cells", []),
		"enemy_spawn_cells": _build_enemy_spawn_cells(base, overlay_src, w, h),
	}


func get_tile_type_at_world(tilemap_bg: TileMapLayer, tilemap_fg: TileMapLayer, world_pos: Vector2) -> String:
	var fg_type: String = _read_tile_type(tilemap_fg, world_pos)
	if not fg_type.is_empty():
		return fg_type
	var bg_type: String = _read_tile_type(tilemap_bg, world_pos)
	if not bg_type.is_empty():
		return bg_type
	return "grass"


func _read_tile_type(layer: TileMapLayer, world_pos: Vector2) -> String:
	if layer == null:
		return ""
	var local_pos: Vector2 = layer.to_local(world_pos)
	var cell: Vector2i = layer.local_to_map(local_pos)
	var source_id: int = layer.get_cell_source_id(cell)
	if source_id == -1:
		return ""
	return str(SOURCE_TO_TYPE.get(source_id, ""))


func _paint_base_floor(base: Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	for y in range(h):
		for x in range(w):
			if rng.randf() < 0.16:
				base[y][x] = SRC_DESERT
			else:
				base[y][x] = SRC_GRASS

	for _i in range(4):
		var cx: int = rng.randi_range(2, w - 3)
		var cy: int = rng.randi_range(2, h - 3)
		var rx: int = rng.randi_range(2, 5)
		var ry: int = rng.randi_range(2, 4)
		for y in range(maxi(0, cy - ry), mini(h, cy + ry + 1)):
			for x in range(maxi(0, cx - rx), mini(w, cx + rx + 1)):
				var nx: float = float(x - cx) / maxf(1.0, float(rx))
				var ny: float = float(y - cy) / maxf(1.0, float(ry))
				if nx * nx + ny * ny <= 1.0:
					base[y][x] = SRC_DESERT


func _paint_river(base: Array, w: int, h: int, rng: RandomNumberGenerator) -> Dictionary:
	var river_width: int = 3
	var river_x_by_y: Array = []
	var current_x: int = clampi(w / 2 + rng.randi_range(-2, 2), 3, w - river_width - 3)
	for y in range(h):
		if y > 1 and y < h - 2 and rng.randf() < 0.28:
			current_x = clampi(current_x + rng.randi_range(-1, 1), 3, w - river_width - 3)
		river_x_by_y.append(current_x)
		for dx in range(river_width):
			base[y][current_x + dx] = SRC_WATER

	var bridge_y: int = clampi(h / 2 + rng.randi_range(-2, 2), 3, h - 4)
	return {
		"river_width": river_width,
		"river_x_by_y": river_x_by_y,
		"bridge_y": bridge_y,
	}


func _place_bridge(base: Array, overlay_src: Array, overlay_atlas: Array, w: int, h: int, river_info: Dictionary) -> void:
	var bridge_y: int = int(river_info.get("bridge_y", h / 2))
	var river_width: int = int(river_info.get("river_width", 3))
	var river_x_by_y: Array = river_info.get("river_x_by_y", []) as Array
	if bridge_y < 0 or bridge_y >= h or river_x_by_y.is_empty():
		return
	var rx: int = int(river_x_by_y[bridge_y])
	for dx in range(river_width):
		_set_overlay(overlay_src, overlay_atlas, rx + dx, bridge_y, SRC_BRIDGE, Vector2i.ZERO)
	var left_x: int = rx - 1
	var right_x: int = rx + river_width
	if left_x >= 0:
		base[bridge_y][left_x] = SRC_GRASS
		_clear_overlay(overlay_src, overlay_atlas, left_x, bridge_y)
	if right_x < w:
		base[bridge_y][right_x] = SRC_GRASS
		_clear_overlay(overlay_src, overlay_atlas, right_x, bridge_y)


func _paint_mountains(overlay_src: Array, overlay_atlas: Array, base: Array, w: int, h: int, rng: RandomNumberGenerator) -> void:
	for x in range(w):
		if rng.randf() < 0.35:
			_set_overlay(overlay_src, overlay_atlas, x, 0, SRC_MOUNTAIN, Vector2i.ZERO)
		if rng.randf() < 0.35:
			_set_overlay(overlay_src, overlay_atlas, x, h - 1, SRC_MOUNTAIN, Vector2i.ZERO)
	for y in range(h):
		if rng.randf() < 0.35:
			_set_overlay(overlay_src, overlay_atlas, 0, y, SRC_MOUNTAIN, Vector2i.ZERO)
		if rng.randf() < 0.35:
			_set_overlay(overlay_src, overlay_atlas, w - 1, y, SRC_MOUNTAIN, Vector2i.ZERO)

	for _i in range(26):
		var cx: int = rng.randi_range(2, w - 3)
		var cy: int = rng.randi_range(2, h - 3)
		if base[cy][cx] == SRC_WATER:
			continue
		_set_overlay(overlay_src, overlay_atlas, cx, cy, SRC_MOUNTAIN, Vector2i.ZERO)


func _place_special_tiles(
	base: Array,
	overlay_src: Array,
	overlay_atlas: Array,
	w: int,
	h: int,
	include_town_tile: bool
) -> Dictionary:
	var reserved: Dictionary = {}
	var spawn_cell := Vector2i(2, h / 2)
	var boss_cell := Vector2i(w - 3, h / 2)
	var shiren_cell := Vector2i(maxi(2, w / 2 - 5), h / 2)

	var cave_cell := Vector2i(2, 2)
	_place_single_special(base, overlay_src, overlay_atlas, cave_cell, SRC_CAVE, Vector2i.ZERO)
	reserved[_cell_key(cave_cell)] = true

	_place_single_special(base, overlay_src, overlay_atlas, shiren_cell, SRC_SHIREN, Vector2i.ZERO)
	reserved[_cell_key(shiren_cell)] = true

	var town_cells: Array = []
	if include_town_tile:
		var town_left := Vector2i(clampi(w / 2 - 1, 1, w - 3), h - 2)
		var town_right := Vector2i(town_left.x + 1, town_left.y)
		_place_single_special(base, overlay_src, overlay_atlas, town_left, SRC_TOWN, Vector2i(0, 0))
		_place_single_special(base, overlay_src, overlay_atlas, town_right, SRC_TOWN, Vector2i(1, 0))
		reserved[_cell_key(town_left)] = true
		reserved[_cell_key(town_right)] = true
		town_cells = [town_left, town_right]

	var castle_origin := Vector2i(w - 4, 1)
	for dy in range(2):
		for dx in range(2):
			var c := Vector2i(castle_origin.x + dx, castle_origin.y + dy)
			_place_single_special(base, overlay_src, overlay_atlas, c, SRC_CASTLE, Vector2i(dx, dy))
			reserved[_cell_key(c)] = true

	spawn_cell = _find_nearest_walkable_cell(base, overlay_src, w, h, spawn_cell)
	boss_cell = _find_nearest_walkable_cell(base, overlay_src, w, h, boss_cell)
	_place_base_walkable(base, overlay_src, overlay_atlas, spawn_cell)
	_place_base_walkable(base, overlay_src, overlay_atlas, boss_cell)

	return {
		"spawn_cell": spawn_cell,
		"boss_cell": boss_cell,
		"shiren_cell": shiren_cell,
		"town_cells": town_cells,
		"reserved": reserved,
	}


func _paint_walkable_overlays(base: Array, overlay_src: Array, overlay_atlas: Array, w: int, h: int, rng: RandomNumberGenerator, reserved: Dictionary) -> void:
	for _i in range(9):
		var center := Vector2i(rng.randi_range(2, w - 3), rng.randi_range(2, h - 3))
		var radius: int = rng.randi_range(2, 4)
		var src: int = SRC_FOREST if rng.randf() < 0.6 else SRC_HILL
		for y in range(maxi(1, center.y - radius), mini(h - 1, center.y + radius + 1)):
			for x in range(maxi(1, center.x - radius), mini(w - 1, center.x + radius + 1)):
				var key: String = "%d:%d" % [x, y]
				if reserved.has(key):
					continue
				if base[y][x] == SRC_WATER:
					continue
				if int(overlay_src[y][x]) != -1:
					continue
				var dx: float = float(x - center.x)
				var dy: float = float(y - center.y)
				if dx * dx + dy * dy > float(radius * radius):
					continue
				_set_overlay(overlay_src, overlay_atlas, x, y, src, Vector2i.ZERO)


func _force_walkable(base: Array, overlay_src: Array, overlay_atlas: Array, w: int, h: int, special: Dictionary) -> void:
	var spawn_cell: Vector2i = special.get("spawn_cell", Vector2i(2, h / 2))
	var boss_cell: Vector2i = special.get("boss_cell", Vector2i(w - 3, h / 2))
	_place_base_walkable(base, overlay_src, overlay_atlas, spawn_cell)
	_place_base_walkable(base, overlay_src, overlay_atlas, boss_cell)


func _place_base_walkable(base: Array, overlay_src: Array, overlay_atlas: Array, cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.y >= base.size() or cell.x >= (base[cell.y] as Array).size():
		return
	base[cell.y][cell.x] = SRC_GRASS
	_clear_overlay(overlay_src, overlay_atlas, cell.x, cell.y)


func _place_single_special(base: Array, overlay_src: Array, overlay_atlas: Array, cell: Vector2i, source_id: int, atlas: Vector2i) -> void:
	if cell.y < 0 or cell.y >= base.size():
		return
	var row: Array = base[cell.y] as Array
	if cell.x < 0 or cell.x >= row.size():
		return
	base[cell.y][cell.x] = SRC_GRASS
	_set_overlay(overlay_src, overlay_atlas, cell.x, cell.y, source_id, atlas)


func _build_enemy_spawn_cells(base: Array, overlay_src: Array, w: int, h: int) -> Array:
	var candidates: Array = [
		Vector2i(6, 5),
		Vector2i(w - 7, 5),
		Vector2i(6, h - 6),
		Vector2i(w - 7, h - 6),
	]
	var result: Array = []
	for c_any in candidates:
		var c: Vector2i = Vector2i(c_any)
		result.append(_find_nearest_walkable_cell(base, overlay_src, w, h, c))
	return result


func _find_nearest_walkable_cell(base: Array, overlay_src: Array, w: int, h: int, start: Vector2i) -> Vector2i:
	var sx: int = clampi(start.x, 0, w - 1)
	var sy: int = clampi(start.y, 0, h - 1)
	for radius in range(0, 9):
		for y in range(maxi(0, sy - radius), mini(h, sy + radius + 1)):
			for x in range(maxi(0, sx - radius), mini(w, sx + radius + 1)):
				if _is_cell_walkable(base, overlay_src, x, y):
					return Vector2i(x, y)
	return Vector2i(sx, sy)


func _is_cell_walkable(base: Array, overlay_src: Array, x: int, y: int) -> bool:
	if y < 0 or y >= base.size():
		return false
	var base_row: Array = base[y] as Array
	if x < 0 or x >= base_row.size():
		return false

	var top_src: int = int((overlay_src[y] as Array)[x])
	if top_src != -1:
		return top_src in WALKABLE_OVERLAY
	return int(base_row[x]) in WALKABLE_BASE


func _commit_layers(tilemap_bg: TileMapLayer, tilemap_fg: TileMapLayer, base: Array, overlay_src: Array, overlay_atlas: Array, w: int, h: int) -> void:
	for y in range(h):
		for x in range(w):
			var cell := Vector2i(x, y)
			var bg_src: int = int((base[y] as Array)[x])
			if tilemap_bg != null:
				tilemap_bg.set_cell(cell, bg_src, Vector2i.ZERO, 0)
			else:
				tilemap_fg.set_cell(cell, bg_src, Vector2i.ZERO, 0)

			var fg_src: int = int((overlay_src[y] as Array)[x])
			if fg_src == -1:
				continue
			var atlas: Vector2i = (overlay_atlas[y] as Array)[x]
			tilemap_fg.set_cell(cell, fg_src, atlas, 0)


func _set_overlay(overlay_src: Array, overlay_atlas: Array, x: int, y: int, source_id: int, atlas: Vector2i) -> void:
	if y < 0 or y >= overlay_src.size():
		return
	var src_row: Array = overlay_src[y] as Array
	var atlas_row: Array = overlay_atlas[y] as Array
	if x < 0 or x >= src_row.size():
		return
	src_row[x] = source_id
	atlas_row[x] = atlas


func _clear_overlay(overlay_src: Array, overlay_atlas: Array, x: int, y: int) -> void:
	if y < 0 or y >= overlay_src.size():
		return
	var src_row: Array = overlay_src[y] as Array
	var atlas_row: Array = overlay_atlas[y] as Array
	if x < 0 or x >= src_row.size():
		return
	src_row[x] = -1
	atlas_row[x] = Vector2i.ZERO


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]


func _get_or_build_tileset() -> TileSet:
	if _cached_tileset != null:
		return _cached_tileset

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	var ids: Array = TILE_TEXTURE_PATHS.keys()
	ids.sort()
	for source_id_any in ids:
		var source_id: int = int(source_id_any)
		var path: String = str(TILE_TEXTURE_PATHS[source_id])
		if not ResourceLoader.exists(path):
			continue
		var tex_res := load(path)
		if not (tex_res is Texture2D):
			continue
		var tex: Texture2D = tex_res as Texture2D
		var atlas := TileSetAtlasSource.new()
		atlas.texture = tex
		atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		tile_set.add_source(atlas, source_id)

		var tex_size: Vector2i = Vector2i(tex.get_size())
		var cols: int = maxi(1, tex_size.x / TILE_SIZE)
		var rows: int = maxi(1, tex_size.y / TILE_SIZE)
		for y in range(rows):
			for x in range(cols):
				atlas.create_tile(Vector2i(x, y))

	_cached_tileset = tile_set
	return _cached_tileset
