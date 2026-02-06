extends Control
## Main: 게임 엔트리 포인트

const TITLE_SCENE := preload("res://scenes/main/Title.tscn")

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
		# 저장된 상태에 따라 분기
		_go_to_field_from_save()
	else:
		push_error("[Main] 로드 실패!")
		_show_title()


func _go_to_field_from_save() -> void:
	## 저장된 필드 위치로 복귀
	_clear_current_scene()
	
	var field_info := SaveManager.get_saved_field_info()
	var stage_id: String = field_info.get("stage_id", "")
	var field_id: String = field_info.get("field_id", "")
	
	# 비어있으면 GameManager의 current_stage/field로 기본값 설정
	if stage_id.is_empty():
		stage_id = "stage_%d" % GameManager.current_stage
	if field_id.is_empty():
		field_id = "field_%d_%d" % [GameManager.current_stage, GameManager.current_field]
	
	
	# FieldManager 설정
	FieldManager.set_current_stage(stage_id)
	FieldManager.set_current_field(field_id)
	
	# 필드 씬 로드
	var scene_path: String = FieldManager.get_current_field_scene()
	
	if scene_path.is_empty():
		scene_path = "res://scenes/field/Field_1_1.tscn"
	
	var field_scene: PackedScene = load(scene_path) as PackedScene
	if field_scene:
		var field: Node = field_scene.instantiate()
		add_child(field)
		current_scene = field
		
		# 저장된 위치로 파티 이동 (Field.gd에서 처리)
		GameManager.change_state(GameManager.GameState.FIELD)
	else:
		push_error("[Main] 필드 씬 로드 실패: ", scene_path)


func _start_new_game() -> void:
	## 새 게임 시작
	# 게임 초기화
	GameManager.start_new_game()

	# 용사(롤랜드)만 파티에 추가 (첫 스테이지는 혼자 시작)
	PartyManager.add_hero_by_id("roland")

	# 시작 아이템 없음 (장비는 파밍)

	# 필드에서 시작! (Stage 1-1)
	GameManager.go_to_field()

	# 새 게임 시작 후 자동 저장
	SaveManager.auto_save("새 게임 시작")


func _go_to_field() -> void:
	_clear_current_scene()
	
	GameManager.change_state(GameManager.GameState.FIELD)


func _clear_current_scene() -> void:
	if current_scene:
		current_scene.queue_free()
		current_scene = null


func _add_random_companions(count: int) -> void:
	## 랜덤 동료 추가 (롤랜드 및 이미 파티에 있는 영웅 제외)
	var all_heroes := DataManager.get_all_hero_ids()
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


func _add_random_runes(count: int) -> void:
	## 랜덤 룬 추가
	var all_runes := DataManager.get_all_rune_ids()
	if all_runes.is_empty():
		return

	# 셔플 후 count개 추가
	all_runes.shuffle()
	for i in range(mini(count, all_runes.size())):
		InventoryManager.add_item(all_runes[i])
