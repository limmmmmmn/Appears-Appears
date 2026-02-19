extends Control
## Main: 게임 엔트리 포인트

const TITLE_SCENE := preload("res://scenes/main/Title.tscn")
const ACT_NODE_SELECT_SCENE := "res://scenes/main/ActNodeSelect.tscn"
const TRINKET_SELECT_SCENE := "res://scenes/main/TrinketSelect.tscn"

var current_scene: Node = null


func _ready() -> void:
	_show_title()


func _show_title() -> void:
	_clear_current_scene()
	
	var title := TITLE_SCENE.instantiate()
	title.start_new_game.connect(_start_new_game)
	title.continue_game.connect(_continue_game)
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	add_child(title)
	current_scene = title
	


func _continue_game() -> void:
	## 저장된 게임 불러오기
	if SaveManager.load_game():
		match GameManager.current_state:
			GameManager.GameState.NODE_SELECT:
				_clear_current_scene()
				get_tree().change_scene_to_file(ACT_NODE_SELECT_SCENE)
			GameManager.GameState.TOWN:
				_clear_current_scene()
				GameManager.go_to_town()
			_:
				# 기본은 에어리어 복귀
				_go_to_area_from_save()
	else:
		push_error("[Main] 로드 실패!")
		_show_title()


func _go_to_area_from_save() -> void:
	## 저장된 액트/에어리어로 복귀
	_clear_current_scene()

	var area_info: Dictionary = SaveManager.get_saved_field_info()
	var act_id: String = str(area_info.get("act_id", ""))
	var area_id: String = str(area_info.get("area_id", ""))
	if act_id.is_empty():
		act_id = GameManager.current_act_id
	if area_id.is_empty():
		area_id = GameManager.current_area_id
	if act_id.is_empty():
		act_id = "act_1"

	GameManager.go_to_area(act_id, area_id)


func _start_new_game() -> void:
	## 새 게임 시작
	# 게임 초기화
	GameManager.start_new_game()

	# 용사(롤랜드)만 파티에 추가 (첫 액트는 혼자 시작)
	PartyManager.add_hero_by_id("roland")

	# 시작 아이템 없음 (장비는 파밍)

	# 시작 트링켓 선택 화면 진입
	get_tree().change_scene_to_file(TRINKET_SELECT_SCENE)


func _clear_current_scene() -> void:
	if current_scene:
		current_scene.queue_free()
		current_scene = null


func _add_random_companions(count: int) -> void:
	## 랜덤 동료 추가 (롤랜드 및 이미 파티에 있는 영웅 제외)
	var all_heroes: Array = DataManager.get_all_hero_ids()
	var available: Array[String] = []

	# 이미 파티에 있는 영웅 ID 수집
	var party_ids: Array[String] = []
	for hero in PartyManager.get_party():
		party_ids.append(hero.id)

	# 사용 가능한 영웅 필터링
	for hero_id in all_heroes:
		if hero_id not in party_ids:
			available.append(hero_id)

	# 셔플 후 count명 추가
	available.shuffle()
	for i in range(mini(count, available.size())):
		PartyManager.add_hero_by_id(available[i])
