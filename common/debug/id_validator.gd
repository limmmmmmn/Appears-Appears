extends Node
class_name IDValidator

const ID_PATTERN := "^[a-z0-9_]+$"

static func validate_all(registry: Node) -> bool:
	var ok := true
	var seen_global: Dictionary[String, String] = {} # id -> resource_path(첫 발견)

	# 레지스트리에서 타입별 dict를 꺼낸다 (명세 고정)
	var groups := [
		{"type": "hero",  "dict": registry.heroes},
		{"type": "enemy", "dict": registry.enemies},
		{"type": "item",  "dict": registry.items},
		{"type": "skill", "dict": registry.skills},
	]

	# A/B: 형식 + 중복(타입 내/전체)
	for g in groups:
		var def_type: String = g.type
		var d: Dictionary = g.dict

		for id in d.keys():
			var def: BaseDef = d[id]
			var path := def.resource_path

			if id == "" or def.id == "":
				_error("EMPTY_ID", def_type, id, path, "id is empty")
				ok = false
				continue

			if id != def.id:
				_error("ID_MISMATCH", def_type, id, path, "dictionary key != def.id (%s)" % def.id)
				ok = false

			if not _regex_ok(def.id):
				_error("INVALID_ID_FORMAT", def_type, def.id, path, "must match %s" % ID_PATTERN)
				ok = false

			var file_base := _file_basename(path)
			if file_base != "" and file_base != def.id:
				_error("FILENAME_ID_MISMATCH", def_type, def.id, path, "filename(%s) != id(%s)" % [file_base, def.id])
				ok = false

			# 전체 통합 중복 금지
			if seen_global.has(def.id):
				_error("DUPLICATE_ID", def_type, def.id, path, "duplicate with %s" % seen_global[def.id])
				ok = false
			else:
				seen_global[def.id] = path

	# C: 참조 검증(get_ref_map 기반)
	# get_ref_map() 규약: { "item": ["item_x"], "skill": ["skill_y"], ... }
	for g in groups:
		var def_type: String = g.type
		var d: Dictionary = g.dict

		for id in d.keys():
			var def: BaseDef = d[id]
			var path := def.resource_path

			var ref_map := def.get_ref_map()
			if ref_map == null:
				continue

			for ref_type in ref_map.keys():
				var arr: Array = ref_map[ref_type]
				for ref_id in arr:
					if typeof(ref_id) != TYPE_STRING:
						_error("REF_NOT_STRING", def_type, def.id, path, "ref id must be String. got: %s" % str(ref_id))
						ok = false
						continue

					if not _exists_in_registry(registry, String(ref_type), String(ref_id)):
						_error("MISSING_REF", def_type, def.id, path, "missing ref: %s:%s" % [String(ref_type), String(ref_id)])
						ok = false

	return ok

static func _exists_in_registry(registry: Node, ref_type: String, ref_id: String) -> bool:
	match ref_type:
		"hero":
			return registry.heroes.has(ref_id)
		"enemy":
			return registry.enemies.has(ref_id)
		"item":
			return registry.items.has(ref_id)
		"skill":
			return registry.skills.has(ref_id)
		_:
			# 타입 키가 잘못된 경우도 즉시 잡히게 false 처리
			return false

static func _regex_ok(s: String) -> bool:
	var re := RegEx.new()
	var err := re.compile(ID_PATTERN)
	if err != OK:
		# 패턴 자체는 고정이라 여기 오면 개발자 실수
		return false
	return re.search(s) != null

static func _file_basename(path: String) -> String:
	if path == "":
		return ""
	return path.get_file().get_basename()

static func _error(code: String, def_type: String, id: String, path: String, msg: String) -> void:
	# 출력 포맷 강제: ERROR_CODE def_type id resource_path message
	var line := "%s %s %s %s %s" % [code, def_type, id, path, msg]
	push_error(line)
