extends Node

const SAVE_PATH_FMT := "user://save_slot_%d.json"

# 팀 룰(고정): "세이브가 없으면 새게임 생성 후 즉시 저장" 으로 통일
const AUTO_SAVE_ON_NEW_GAME := true

func boot_auto_load_or_new_game(slot: int = 0) -> void:
	if has_save(slot):
		var ok := load_game(slot)
		if ok:
			return
		# 로드 실패 시 새게임으로 폴백
		_new_game(slot)
	else:
		_new_game(slot)

func save_game(slot: int = 0) -> void:
	var path := SAVE_PATH_FMT % slot
	var now := Time.get_unix_time_from_system()

	var created_at := now
	if has_save(slot):
		var existing = _read_json_dict(path)
		if typeof(existing) == TYPE_DICTIONARY and existing.has("created_at_unix"):
			created_at = int(existing.get("created_at_unix", now))

	var root := {
		"schema_version": SaveSchema.SCHEMA_VERSION,
		"created_at_unix": created_at,
		"updated_at_unix": now,
		"inventory": InventoryManager.to_save_dict(),
		"party": PartyManager.to_save_dict(),
		"field_state": FieldStateManager.to_save_dict(),
	}

	_write_json_dict(path, root)

	var ev := get_node_or_null("/root/Events")
	if ev:
		(ev as Events).save_completed.emit(slot)

func load_game(slot: int = 0) -> bool:
	var path := SAVE_PATH_FMT % slot
	if not FileAccess.file_exists(path):
		return false

	var root = _read_json_dict(path)
	if typeof(root) != TYPE_DICTIONARY:
		push_error("SAVE_READ_FAIL save %d %s invalid json root" % [slot, path])
		if OS.is_debug_build():
			assert(false)
		return false

	# schema 체크 (지금은 1만 허용)
	var ver := int(root.get("schema_version", 0))
	if ver != SaveSchema.SCHEMA_VERSION:
		push_error("SCHEMA_VERSION_MISMATCH save %d %s got=%d expected=%d" % [slot, path, ver, SaveSchema.SCHEMA_VERSION])
		if OS.is_debug_build():
			assert(false)
		return false

	# 상태 직접 조작 금지: 반드시 from_save_dict로 위임
	InventoryManager.from_save_dict(_safe_dict(root.get("inventory", {})))
	PartyManager.from_save_dict(_safe_dict(root.get("party", {})))
	FieldStateManager.from_save_dict(_safe_dict(root.get("field_state", {})))

	var ev := get_node_or_null("/root/Events")
	if ev:
		(ev as Events).load_completed.emit(slot)

	return true

func has_save(slot: int = 0) -> bool:
	var path := SAVE_PATH_FMT % slot
	return FileAccess.file_exists(path)

# --- internal: json io ---
func _write_json_dict(path: String, data: Dictionary) -> void:
	var json := JSON.stringify(data, "\t") # pretty
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SAVE_WRITE_FAIL %s" % path)
		if OS.is_debug_build():
			assert(false)
		return
	f.store_string(json)
	f.close()

func _read_json_dict(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()

	var v = JSON.parse_string(txt)
	return v

func _safe_dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _new_game(slot: int) -> void:
	# 초기값 생성은 각 매니저가 소유
	InventoryManager.reset_new_game()

	# M2 기본 파티(샘플 Def 기반): hero_test
	PartyManager.reset_new_game(["hero_test"])

	FieldStateManager.reset_new_game()

	if AUTO_SAVE_ON_NEW_GAME:
		save_game(slot)
