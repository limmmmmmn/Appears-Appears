extends Node

# 6-1. 내부 상태(고정 키)
var current_node_id: String = ""
var current_area_id: String = ""
var revive_count_remaining: int = 0
var run_used_in_area: bool = false

func reset_new_game() -> void:
	# M2 임시 초기값(고정 가능): M7에서 기획값으로 확정
	current_node_id = "node_start"
	current_area_id = "area_1"
	revive_count_remaining = 1
	run_used_in_area = false
	_emit_changed()

func set_position(node_id: String, area_id: String) -> void:
	current_node_id = node_id
	current_area_id = area_id
	_emit_changed()

func consume_revive() -> bool:
	if revive_count_remaining <= 0:
		return false
	revive_count_remaining -= 1
	_emit_changed()
	return true

func mark_run_used() -> void:
	if run_used_in_area:
		return
	run_used_in_area = true
	_emit_changed()

# --- Save hooks (고정) ---
func to_save_dict() -> Dictionary:
	return {
		"current_node_id": current_node_id,
		"current_area_id": current_area_id,
		"revive_count_remaining": revive_count_remaining,
		"run_used_in_area": run_used_in_area,
	}

func from_save_dict(data: Dictionary) -> void:
	current_node_id = String(data.get("current_node_id", ""))
	current_area_id = String(data.get("current_area_id", ""))
	revive_count_remaining = int(data.get("revive_count_remaining", 0))
	run_used_in_area = bool(data.get("run_used_in_area", false))
	_emit_changed()

# --- Events emit 규칙(고정) ---
func _emit_changed() -> void:
	var ev := get_node_or_null("/root/Events")
	if ev:
		(ev as Events).field_state_changed.emit()
