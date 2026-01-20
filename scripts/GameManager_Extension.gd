## GameManager 확장 코드 - 기존 GameManager.gd에 추가하세요

#region 씬 전환
func go_to_field(stage_id: String = "", field_id: String = "") -> void:
	## 필드로 이동
	if stage_id.is_empty():
		stage_id = "stage_" + str(current_stage)
	if field_id.is_empty():
		field_id = FieldManager.get_first_field_id(stage_id)
	
	FieldManager.set_current_stage(stage_id)
	FieldManager.set_current_field(field_id)
	
	var scene_path := FieldManager.get_current_field_scene()
	if scene_path.is_empty():
		scene_path = "res://scenes/field/Field_1_1.tscn"
	
	print("[GameManager] 필드 이동: ", scene_path)
	change_state(GameState.FIELD)
	get_tree().change_scene_to_file(scene_path)


func go_to_town() -> void:
	## 마을로 이동
	print("[GameManager] 마을 이동")
	change_state(GameState.TOWN)
	get_tree().change_scene_to_file("res://scenes/town/Town.tscn")


func go_to_next_from_field() -> void:
	## 필드 출구 도달 시 호출
	var next := FieldManager.get_next_destination()
	
	if next == "town":
		go_to_town()
	elif next.begins_with("stage_"):
		# 다음 스테이지
		current_stage += 1
		current_field = 1
		go_to_field(next)
	elif next == "ending":
		print("[GameManager] 게임 클리어!")
		# TODO: 엔딩 씬
	else:
		# 같은 스테이지 다음 필드
		current_field += 1
		var stage_id := "stage_" + str(current_stage)
		var field_id := "field_%d_%d" % [current_stage, current_field]
		go_to_field(stage_id, field_id)
#endregion
