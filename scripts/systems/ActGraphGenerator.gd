extends RefCounted
class_name ActGraphGenerator


func build_runtime_acts(templates: Array[ActTemplate], run_seed: int) -> Array[Dictionary]:
	var sorted_templates: Array = templates.duplicate()
	sorted_templates.sort_custom(func(a, b) -> bool:
		var left: ActTemplate = a as ActTemplate
		var right: ActTemplate = b as ActTemplate
		if left == null or right == null:
			return false
		return left.act_order < right.act_order
	)

	var runtime_acts: Array[Dictionary] = []
	for i in range(sorted_templates.size()):
		var template: ActTemplate = sorted_templates[i] as ActTemplate
		if template == null:
			continue
		var act_seed: int = _mix_seed(run_seed, i + 1)
		var runtime_act: Dictionary = _build_single_act(template, act_seed)
		if runtime_act.is_empty():
			continue
		runtime_acts.append(runtime_act)
	return runtime_acts


func _build_single_act(template: ActTemplate, act_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = act_seed

	var min_count: int = maxi(1, template.min_regular_areas)
	var max_count: int = maxi(min_count, template.max_regular_areas)
	var regular_area_count: int = rng.randi_range(min_count, max_count)

	var picks: Array[Dictionary] = []
	var picks_types: Array[String] = []

	var start_entry: Dictionary = _pick_start_entry(template, rng)
	if start_entry.is_empty():
		return {}
	picks.append(start_entry)
	picks_types.append(str(start_entry.get("type", "field")))

	var remaining: int = regular_area_count - 1
	if remaining > 0:
		var forced_types: Array[String] = []
		for _i in range(template.guaranteed_town_count):
			forced_types.append("town")
		for _i in range(template.guaranteed_event_count):
			forced_types.append("event")
		for _i in range(template.guaranteed_dungeon_count):
			forced_types.append("dungeon")
		_shuffle_strings(forced_types, rng)

		for forced_type in forced_types:
			if remaining <= 0:
				break
			var forced_entry: Dictionary = _pick_from_pool(template, forced_type, rng)
			if forced_entry.is_empty():
				continue
			picks.append(forced_entry)
			picks_types.append(forced_type)
			remaining -= 1

		for _i in range(remaining):
			var weighted_type: String = _pick_weighted_type(template, rng)
			var entry: Dictionary = _pick_from_pool(template, weighted_type, rng)
			if entry.is_empty():
				entry = _pick_any_non_empty_area(template, rng)
			if entry.is_empty():
				continue
			picks.append(entry)
			picks_types.append(str(entry.get("type", weighted_type)))

	if picks.size() <= 0:
		return {}

	_shuffle_middle_sections(picks, picks_types, rng)

	var areas: Array[Dictionary] = []
	for i in range(picks.size()):
		var base_entry: Dictionary = picks[i]
		var area_id: String = "%s_area_%02d" % [template.act_id, i + 1]
		areas.append(_make_runtime_area(area_id, base_entry, false))

	var boss_entry: Dictionary = _pick_boss_entry(template, rng)
	if boss_entry.is_empty():
		var fallback_boss_scene: String = _resolve_fallback_field_scene(template)
		boss_entry = {
			"id": "%s_boss" % template.act_id,
			"name": "%s 보스" % template.act_name,
			"scene": fallback_boss_scene,
			"type": "boss",
			"weight": 1.0,
		}
	var boss_area_id: String = "%s_boss" % template.act_id
	areas.append(_make_runtime_area(boss_area_id, boss_entry, true))

	_apply_branch_links(areas, template, rng)

	return {
		"id": template.act_id,
		"name": template.act_name,
		"order": template.act_order,
		"seed": act_seed,
		"terrain_enemies": template.terrain_enemies.duplicate(true),
		"default_enemy_pool": template.default_enemy_pool.duplicate(true),
		"elite_pool": template.elite_pool.duplicate(),
		"boss_enemy_id": template.boss_enemy_id,
		"default_enemy_count": template.default_enemy_count.duplicate(true),
		"default_elite_chance": template.default_elite_chance,
		"start_area_id": str(areas[0].get("id", "")),
		"boss_area_id": boss_area_id,
		"areas": areas,
	}


func _apply_branch_links(areas: Array[Dictionary], template: ActTemplate, rng: RandomNumberGenerator) -> void:
	for i in range(areas.size()):
		var next_ids: Array[String] = []
		if i + 1 < areas.size():
			next_ids.append(str(areas[i + 1].get("id", "")))
		if i + 2 < areas.size() and rng.randf() < template.skip_link_chance:
			next_ids.append(str(areas[i + 2].get("id", "")))
		if i > 0 and i + 2 < areas.size() and rng.randf() < template.side_branch_chance:
			next_ids.append(str(areas[i + 2].get("id", "")))
		next_ids = _unique_strings(next_ids)
		areas[i]["next"] = next_ids


func _pick_start_entry(template: ActTemplate, rng: RandomNumberGenerator) -> Dictionary:
	if not template.start_area_pool.is_empty():
		var start_pool: Array[Dictionary] = _with_type(template.start_area_pool, "field")
		var from_start: Dictionary = _pick_weighted_entry(start_pool, rng)
		if not from_start.is_empty():
			if not from_start.has("type"):
				from_start["type"] = "field"
			return from_start
	var field_entry: Dictionary = _pick_from_pool(template, "field", rng)
	if not field_entry.is_empty():
		return field_entry
	return _pick_any_non_empty_area(template, rng)


func _pick_boss_entry(template: ActTemplate, _rng: RandomNumberGenerator) -> Dictionary:
	if template.boss_area.is_empty():
		return {}
	var entry: Dictionary = template.boss_area.duplicate(true)
	entry["type"] = "boss"
	return entry


func _resolve_fallback_field_scene(template: ActTemplate) -> String:
	for raw in template.start_area_pool:
		var entry: Dictionary = _to_entry_dict(raw)
		if entry.is_empty():
			continue
		var scene_path: String = str(entry.get("scene", ""))
		if not scene_path.is_empty():
			return scene_path

	for raw in template.field_pool:
		var entry: Dictionary = _to_entry_dict(raw)
		if entry.is_empty():
			continue
		var scene_path: String = str(entry.get("scene", ""))
		if not scene_path.is_empty():
			return scene_path

	return ""


func _pick_any_non_empty_area(template: ActTemplate, rng: RandomNumberGenerator) -> Dictionary:
	var merged: Array[Dictionary] = []
	merged.append_array(_with_type(template.field_pool, "field"))
	merged.append_array(_with_type(template.dungeon_pool, "dungeon"))
	merged.append_array(_with_type(template.event_pool, "event"))
	merged.append_array(_with_type(template.town_pool, "town"))
	if merged.is_empty():
		return {}
	return _pick_weighted_entry(merged, rng)


func _pick_from_pool(template: ActTemplate, area_type: String, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array[Dictionary] = []
	match area_type:
		"field":
			pool = _with_type(template.field_pool, "field")
		"dungeon":
			pool = _with_type(template.dungeon_pool, "dungeon")
		"event":
			pool = _with_type(template.event_pool, "event")
		"town":
			pool = _with_type(template.town_pool, "town")
		_:
			pool = []
	if pool.is_empty():
		return {}
	return _pick_weighted_entry(pool, rng)


func _pick_weighted_type(template: ActTemplate, rng: RandomNumberGenerator) -> String:
	var entries: Array[Dictionary] = []
	if not template.field_pool.is_empty():
		entries.append({"type": "field", "weight": maxf(0.0, template.field_weight)})
	if not template.dungeon_pool.is_empty():
		entries.append({"type": "dungeon", "weight": maxf(0.0, template.dungeon_weight)})
	if not template.event_pool.is_empty():
		entries.append({"type": "event", "weight": maxf(0.0, template.event_weight)})
	if not template.town_pool.is_empty():
		entries.append({"type": "town", "weight": maxf(0.0, template.town_weight)})

	if entries.is_empty():
		return "field"

	var total: float = 0.0
	for e in entries:
		total += float(e.get("weight", 0.0))
	if total <= 0.0:
		var idx: int = rng.randi_range(0, entries.size() - 1)
		return str(entries[idx].get("type", "field"))

	var roll: float = rng.randf() * total
	var accum: float = 0.0
	for e in entries:
		accum += float(e.get("weight", 0.0))
		if roll <= accum:
			return str(e.get("type", "field"))
	return str(entries.back().get("type", "field"))


func _pick_weighted_entry(pool: Array[Dictionary], rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	var total: float = 0.0
	for entry in pool:
		total += maxf(0.0, float(entry.get("weight", 1.0)))
	if total <= 0.0:
		var idx_random: int = rng.randi_range(0, pool.size() - 1)
		return pool[idx_random].duplicate(true)
	var roll: float = rng.randf() * total
	var accum: float = 0.0
	for entry in pool:
		accum += maxf(0.0, float(entry.get("weight", 1.0)))
		if roll <= accum:
			return entry.duplicate(true)
	return pool.back().duplicate(true)


func _make_runtime_area(area_id: String, entry: Dictionary, is_boss: bool) -> Dictionary:
	var area_type: String = str(entry.get("type", "field"))
	if is_boss:
		area_type = "boss"
	var area: Dictionary = {
		"id": area_id,
		"type": area_type,
		"name": str(entry.get("name", area_id)),
		"scene": str(entry.get("scene", "")),
		"template_id": str(entry.get("id", "")),
		"is_boss": is_boss,
		"next": [],
	}
	for key in ["enemy_count", "enemy_pool", "elite_chance", "field_boss_id", "elite_pool", "boss_enemy_id"]:
		if entry.has(key):
			area[key] = entry.get(key)
	if entry.has("is_boss_field"):
		area["is_boss_field"] = bool(entry.get("is_boss_field", false))
	elif is_boss:
		area["is_boss_field"] = true
	return area


func _with_type(pool: Array, area_type: String) -> Array[Dictionary]:
	var typed_pool: Array[Dictionary] = []
	for raw in pool:
		var copy: Dictionary = _to_entry_dict(raw)
		if copy.is_empty():
			continue
		copy["type"] = area_type
		typed_pool.append(copy)
	return typed_pool


func _to_entry_dict(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	if raw is FieldTemplate:
		var field_template: FieldTemplate = raw as FieldTemplate
		if field_template == null:
			return {}
		return field_template.to_runtime_dict()
	return {}


func _shuffle_middle_sections(picks: Array[Dictionary], picks_types: Array[String], rng: RandomNumberGenerator) -> void:
	if picks.size() <= 2:
		return
	var indices: Array[int] = []
	for i in range(1, picks.size()):
		indices.append(i)
	for i in range(indices.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var a_idx: int = indices[i]
		var b_idx: int = indices[j]
		var temp_entry: Dictionary = picks[a_idx]
		picks[a_idx] = picks[b_idx]
		picks[b_idx] = temp_entry
		var temp_type: String = picks_types[a_idx]
		picks_types[a_idx] = picks_types[b_idx]
		picks_types[b_idx] = temp_type


func _shuffle_strings(values: Array[String], rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp: String = values[i]
		values[i] = values[j]
		values[j] = temp


func _unique_strings(values: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	for v in values:
		if v.is_empty():
			continue
		if seen.has(v):
			continue
		seen[v] = true
		result.append(v)
	return result


func _mix_seed(base_seed: int, salt: int) -> int:
	var mixed: int = int(base_seed)
	mixed = int((mixed * 1103515245 + 12345 + salt * 1013904223) & 0x7fffffff)
	if mixed == 0:
		mixed = salt * 7919 + 17
	return mixed
