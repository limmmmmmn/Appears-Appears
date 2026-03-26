extends Node
## DialogueManager: 대사 선택/우선순위 엔트리포인트
## - 데이터는 DataManager(dialogues/*.json)에서 읽음
## - 카테고리/트리거/화자(speaker_id) 기준으로 랜덤 라인 선택

const FIELD_CATEGORY: String = "field_chatter"


func get_field_line(trigger: String, hero_id: String = "") -> String:
	return get_line(FIELD_CATEGORY, trigger, hero_id)


func get_line(category: String, trigger: String, speaker_id: String = "") -> String:
	if trigger.is_empty():
		return ""
	var lines: Array[String] = get_lines(category, trigger, speaker_id)
	if lines.is_empty() and not speaker_id.is_empty():
		lines = get_lines(category, trigger, "")
	if lines.is_empty():
		return ""
	return lines[randi() % lines.size()]


func get_lines(category: String, trigger: String, speaker_id: String = "") -> Array[String]:
	if category.is_empty() or trigger.is_empty():
		return []
	if DataManager == null or not DataManager.has_method("get_dialogue_lines"):
		return []
	return DataManager.get_dialogue_lines(category, trigger, speaker_id)


func get_speech_bubble_line(category: String, trigger: String, speaker_id: String = "") -> String:
	## SpeechBubble 전용 별칭 (town/npc/enemy/event 공용)
	return get_line(category, trigger, speaker_id)


func get_speech_bubble_lines(category: String, trigger: String, speaker_id: String = "") -> Array[String]:
	## SpeechBubble 전용 별칭 (town/npc/enemy/event 공용)
	return get_lines(category, trigger, speaker_id)
