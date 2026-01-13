extends Node

# 5-1. 저장 구조(고정)
var party_slots: Array[String] = [] # max 4, hero_id 문자열
var hero_states: Dictionary = {}    # key: hero_id, value: Dictionary(영속 상태)

const MAX_PARTY_SIZE := 4
const EQUIP_SLOTS: Array[String] = ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]

func reset_new_game(default_party: Array[String]) -> void:
	party_slots.clear()
	hero_states.clear()

	# 최대 4, 빈 문자열 제외
	for hero_id in default_party:
		if party_slots.size() >= MAX_PARTY_SIZE:
			break
		if hero_id == "":
			continue
		if party_slots.has(hero_id):
			continue
		party_slots.append(hero_id)
		ensure_hero_state(hero_id)

	_emit_party_changed()
	_emit_all_equipment_changed()

func get_party() -> Array[String]:
	# 외부에서 array를 직접 수정하는 걸 줄이기 위해 복사본 반환
	return party_slots.duplicate()

func is_in_party(hero_id: String) -> bool:
	return party_slots.has(hero_id)

func ensure_hero_state(hero_id: String) -> void:
	if hero_id == "":
		return
	if hero_states.has(hero_id):
		return

	hero_states[hero_id] = _make_default_hero_state(hero_id)

func set_equip(hero_id: String, slot_key: String, item_id: String) -> void:
	# M2: 구조만 고정. 인벤 스택 증감/검증은 M6에서 구현 (지금 금지)
	if hero_id == "":
		return
	ensure_hero_state(hero_id)

	if not _is_valid_slot(slot_key):
		push_error("INVALID_EQUIP_SLOT party %s %s  slot_key=%s" % [hero_id, "", slot_key])
		if OS.is_debug_build():
			assert(false)
		return

	var st: Dictionary = hero_states[hero_id]
	var equips: Dictionary = st.get("equips", {})
	equips[slot_key] = item_id
	st["equips"] = equips
	hero_states[hero_id] = st

	_emit_equipment_changed(hero_id)

# --- Save hooks (고정) ---
func to_save_dict() -> Dictionary:
	# Resource(Def) 저장 금지 → String ID만 저장
	return {
		"party_slots": party_slots.duplicate(),
		"hero_states": _deep_dup(hero_states),
	}

func from_save_dict(data: Dictionary) -> void:
	party_slots.clear()
	hero_states.clear()

	# party_slots
	var raw_party = data.get("party_slots", [])
	if typeof(raw_party) == TYPE_ARRAY:
		for v in raw_party:
			if party_slots.size() >= MAX_PARTY_SIZE:
				break
			if typeof(v) != TYPE_STRING:
				continue
			var hero_id := String(v)
			if hero_id == "" or party_slots.has(hero_id):
				continue
			party_slots.append(hero_id)

	# hero_states
	var raw_states = data.get("hero_states", {})
	if typeof(raw_states) == TYPE_DICTIONARY:
		for k in raw_states.keys():
			if typeof(k) != TYPE_STRING:
				continue
			var hero_id := String(k)
			var st = raw_states[k]
			if typeof(st) != TYPE_DICTIONARY:
				continue

			# 최소 스키마 강제 보정
			var fixed := _make_default_hero_state(hero_id)
			fixed["level"] = int(st.get("level", 1))

			var equips = st.get("equips", {})
			if typeof(equips) == TYPE_DICTIONARY:
				for slot_key in EQUIP_SLOTS:
					var it := ""
					if equips.has(slot_key) and typeof(equips[slot_key]) == TYPE_STRING:
						it = String(equips[slot_key])
					fixed["equips"][slot_key] = it

			hero_states[hero_id] = fixed

	# party에 있는 애들은 state가 반드시 있어야 함
	for hero_id in party_slots:
		ensure_hero_state(hero_id)

	_emit_party_changed()
	_emit_all_equipment_changed()

# --- helpers ---
func _make_default_hero_state(hero_id: String) -> Dictionary:
	var equips := {}
	for slot_key in EQUIP_SLOTS:
		equips[slot_key] = ""
	return {
		"hero_id": hero_id,
		"level": 1,
		"equips": equips
	}

func _is_valid_slot(slot_key: String) -> bool:
	return EQUIP_SLOTS.has(slot_key)

func _deep_dup(d: Dictionary) -> Dictionary:
	return d.duplicate(true)

# --- Events emit 규칙(고정) ---
func _emit_party_changed() -> void:
	var ev := get_node_or_null("/root/Events")
	if ev:
		(ev as Events).party_changed.emit()

func _emit_equipment_changed(hero_id: String) -> void:
	var ev := get_node_or_null("/root/Events")
	if ev:
		(ev as Events).equipment_changed.emit(hero_id)

func _emit_all_equipment_changed() -> void:
	for hero_id in hero_states.keys():
		if typeof(hero_id) == TYPE_STRING:
			_emit_equipment_changed(String(hero_id))
