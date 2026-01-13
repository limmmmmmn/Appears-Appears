extends Node

const DATA_ROOT := "res://common/data/"
const ID_PATTERN := "^[a-z0-9_]+$"

var heroes: Dictionary[String, HeroDef] = {}
var enemies: Dictionary[String, EnemyDef] = {}
var items: Dictionary[String, ItemDef] = {}
var skills: Dictionary[String, SkillDef] = {}

# 내부 중복 체크(전체 타입 통합)
var _seen_global: Dictionary[String, String] = {} # id -> resource_path

func _ready() -> void:
	load_all_defs()

	# 로딩 완료 후 Validator 실행
	var ok := IDValidator.validate_all(self)

	# 에러가 있으면 디버그 빌드에서 즉시 중단
	if not ok and OS.is_debug_build():
		assert(false)

func load_all_defs() -> void:
	heroes.clear()
	enemies.clear()
	items.clear()
	skills.clear()
	_seen_global.clear()

	var paths: Array[String] = []
	_collect_tres_paths_recursive(DATA_ROOT, paths)

	for p in paths:
		var res := load(p)
		if res == null:
			_push_err("LOAD_FAIL", "unknown", "", p, "failed to load resource")
			if OS.is_debug_build(): assert(false)
			continue

		if not (res is BaseDef):
			# BaseDef가 아니면 무시(경고 권장)
			push_warning("NOT_BASEDEF ignored: %s (%s)" % [p, res.get_class()])
			continue

		var def: BaseDef = res
		_validate_and_register(def)

func _validate_and_register(def: BaseDef) -> void:
	var path := def.resource_path
	var def_id := def.id

	# 1) id 비어있음
	if def_id == "":
		_push_err("EMPTY_ID", _type_of(def), def_id, path, "id is empty")
		if OS.is_debug_build(): assert(false)
		return

	# 2) regex 위반
	if not _regex_ok(def_id):
		_push_err("INVALID_ID_FORMAT", _type_of(def), def_id, path, "must match %s" % ID_PATTERN)
		if OS.is_debug_build(): assert(false)
		return

	# 3) 파일명 != id
	var file_base := path.get_file().get_basename()
	if file_base != def_id:
		_push_err("FILENAME_ID_MISMATCH", _type_of(def), def_id, path, "filename(%s) != id(%s)" % [file_base, def_id])
		if OS.is_debug_build(): assert(false)
		return

	# 4) 전체 통합 중복 금지
	if _seen_global.has(def_id):
		_push_err("DUPLICATE_ID", _type_of(def), def_id, path, "duplicate with %s" % _seen_global[def_id])
		if OS.is_debug_build(): assert(false)
		return
	_seen_global[def_id] = path

	# 5) 타입별 인덱싱
	if def is HeroDef:
		heroes[def_id] = def
	elif def is EnemyDef:
		enemies[def_id] = def
	elif def is ItemDef:
		items[def_id] = def
	elif def is SkillDef:
		skills[def_id] = def
	else:
		# BaseDef를 상속했지만 아직 레지스트리가 모르는 타입(월드 등)은 일단 경고만
		push_warning("UNINDEXED_DEF %s %s %s (extend registry later)" % [_type_of(def), def_id, path])

func get_hero(id: String) -> HeroDef:
	return _get_typed("hero", heroes, id)

func get_enemy(id: String) -> EnemyDef:
	return _get_typed("enemy", enemies, id)

func get_item(id: String) -> ItemDef:
	return _get_typed("item", items, id)

func get_skill(id: String) -> SkillDef:
	return _get_typed("skill", skills, id)

func _get_typed(def_type: String, dict: Dictionary, id: String):
	if dict.has(id):
		return dict[id]

	_push_err("MISSING_ID", def_type, id, "", "not found in registry")
	if OS.is_debug_build():
		assert(false)
	return null

func _collect_tres_paths_recursive(root: String, out_paths: Array[String]) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		_push_err("DIR_OPEN_FAIL", "registry", "", root, "cannot open data root")
		if OS.is_debug_build(): assert(false)
		return

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue

		var full := root.path_join(name)
		if dir.current_is_dir():
			_collect_tres_paths_recursive(full, out_paths)
		else:
			if name.get_extension() == "tres":
				out_paths.append(full)
	dir.list_dir_end()

func _regex_ok(s: String) -> bool:
	var re := RegEx.new()
	var err := re.compile(ID_PATTERN)
	if err != OK:
		return false
	return re.search(s) != null

func _type_of(def: BaseDef) -> String:
	if def is HeroDef: return "hero"
	if def is EnemyDef: return "enemy"
	if def is ItemDef: return "item"
	if def is SkillDef: return "skill"
	return def.get_class()

func _push_err(code: String, def_type: String, id: String, path: String, msg: String) -> void:
	# 출력 포맷 강제: ERROR_CODE def_type id resource_path message
	var line := "%s %s %s %s %s" % [code, def_type, id, path, msg]
	push_error(line)
