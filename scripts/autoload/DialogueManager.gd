extends Node
## DialogueManager: 대사 선택/우선순위 엔트리포인트
## - 데이터는 DataManager(dialogues.json)에서 읽음
## - 현재는 필드 잡담(field_chatter) 트리거를 우선 지원

const FIELD_CATEGORY: String = "field_chatter"


func get_field_line(trigger: String, hero_id: String = "") -> String:
	if trigger.is_empty():
		return ""
	if DataManager == null or not DataManager.has_method("get_dialogue_lines"):
		return ""

	var lines: Array[String] = DataManager.get_dialogue_lines(FIELD_CATEGORY, trigger, hero_id)
	if lines.is_empty() and not hero_id.is_empty():
		lines = DataManager.get_dialogue_lines(FIELD_CATEGORY, trigger, "")
	if lines.is_empty():
		return ""
	return lines[randi() % lines.size()]
