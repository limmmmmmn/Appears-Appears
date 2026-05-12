extends Node

## Catalog of equipment items. Loads every ItemData under data/items.

const ITEM_DIR: String = "res://data/items"

var _all: Array[ItemData] = []
var _by_id: Dictionary = {}


func _ready() -> void:
	_load_all()
	print("[ItemDB] loaded %d items" % _all.size())


func get_all() -> Array[ItemData]:
	return _all.duplicate()


func get_by_id(id: StringName) -> ItemData:
	return _by_id.get(id, null)


func random_drop() -> ItemData:
	if _all.is_empty():
		return null
	return _all.pick_random()


func _load_all() -> void:
	_all.clear()
	_by_id.clear()
	var paths: PackedStringArray = _item_paths()
	for path: String in paths:
		var resource := load(path)
		if resource is ItemData:
			_register(resource)


func _register(item: ItemData) -> void:
	if item.id == &"":
		push_warning("[ItemDB] item has empty id: %s" % item.resource_path)
		return
	if _by_id.has(item.id):
		push_warning("[ItemDB] duplicate id: %s" % item.id)
		return
	_all.append(item)
	_by_id[item.id] = item


func _item_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(ITEM_DIR)
	if dir == null:
		push_warning("[ItemDB] item dir not found: %s" % ITEM_DIR)
		return paths
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append("%s/%s" % [ITEM_DIR, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths
