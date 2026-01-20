## Town.gd 확장 코드 - 기존 Town.gd에 추가하세요

## 출발 버튼이 있다면 연결
func _on_depart_button_pressed() -> void:
	print("[Town] 필드로 출발!")
	GameManager.go_to_field()


## 또는 Town 씬에서 직접 버튼 추가:
## 1. Town.tscn에 "DepartButton" Button 노드 추가
## 2. 버튼의 pressed 시그널을 _on_depart_button_pressed에 연결
