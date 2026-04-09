extends Node
## DataLoader: JSON 데이터를 로드하는 오토로드.

var _cache: Dictionary = {}

func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	if not FileAccess.file_exists(path):
		push_error("File not found: " + path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open: " + path)
		return null
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON parse error %s in %s: %s" % [err, path, json.get_error_message()])
		return null
	_cache[path] = json.data
	return json.data

func load_enemy(id: String) -> Dictionary:
	var data: Variant = load_json("res://data/enemies/%s.json" % id)
	return data if data is Dictionary else {}

func load_character(id: String) -> Dictionary:
	var data: Variant = load_json("res://data/characters/%s.json" % id)
	return data if data is Dictionary else {}

func load_equipment(id: String) -> Dictionary:
	var data: Variant = load_json("res://data/equipment/%s.json" % id)
	return data if data is Dictionary else {}

func load_journey(id: String) -> Dictionary:
	var data: Variant = load_json("res://data/journeys/%s.json" % id)
	return data if data is Dictionary else {}

func load_field_table(id: String) -> Dictionary:
	var data: Variant = load_json("res://data/field_tables/%s.json" % id)
	return data if data is Dictionary else {}

func load_all_enemies() -> Array:
	return _load_all_in("res://data/enemies/")

func load_all_equipment() -> Array:
	return _load_all_in("res://data/equipment/")

func load_all_characters() -> Array:
	return _load_all_in("res://data/characters/")

func _load_all_in(dir_path: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Cannot open directory: " + dir_path)
		return results
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Variant = load_json(dir_path + file_name)
			if data != null:
				results.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()
	return results
