extends Control
## Title: 타이틀 화면 - 새 게임 / 이어하기

signal start_new_game
signal continue_game

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var save_info_label: Label = %SaveInfoLabel
@onready var confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	_update_ui()


func _update_ui() -> void:
	var has_save: bool = SaveManager.has_save()
	
	# 이어하기 버튼 활성화/비활성화
	continue_button.disabled = not has_save
	
	if has_save:
		# 저장 정보 표시
		var info: Dictionary = SaveManager.get_save_info()
		var timestamp: String = str(info.get("timestamp", ""))
		var act_id: String = str(info.get("act_id", "act_1"))
		var area_id: String = str(info.get("area_id", ""))
		var gold: int = int(info.get("gold", 0))
		var party_size: int = int(info.get("party_size", 0))
		var act_num: int = _extract_numeric_suffix(act_id)
		var area_num: int = _extract_numeric_suffix(area_id)
		
		# 타임스탬프 간략화 (2025-01-23T15:30:00 -> 2025-01-23 15:30)
		if timestamp.length() > 16:
			timestamp = timestamp.substr(0, 10) + " " + timestamp.substr(11, 5)
		
		save_info_label.text = "Act %d-%d | %d G | 파티 %d명\n마지막 저장: %s" % [
			maxi(1, act_num), maxi(1, area_num), gold, party_size, timestamp
		]
		continue_button.grab_focus()
	else:
		save_info_label.text = "저장된 데이터가 없습니다."
		new_game_button.grab_focus()


func _on_continue_pressed() -> void:
	continue_game.emit()


func _on_new_game_pressed() -> void:
	if SaveManager.has_save():
		# 저장 데이터가 있으면 확인 다이얼로그
		confirm_dialog.popup_centered()
	else:
		# 저장 데이터 없으면 바로 시작
		_start_new_game()


func _on_confirm_new_game() -> void:
	# 기존 세이브 삭제
	SaveManager.delete_save()
	_start_new_game()


func _start_new_game() -> void:
	start_new_game.emit()


func _extract_numeric_suffix(raw_id: String) -> int:
	var digits: String = ""
	for i in range(raw_id.length() - 1, -1, -1):
		var ch: String = raw_id.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 0
