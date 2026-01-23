extends Control
## Main: 게임 엔트리 포인트

const TITLE_SCENE := preload("res://scenes/main/Title.tscn")
const TOWN_SCENE := preload("res://scenes/town/Town.tscn")

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
		match GameManager.current_state:
			GameManager.GameState.FIELD:
				_go_to_field_from_save()
			GameManager.GameState.TOWN, _:
				_go_to_town()
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
		_go_to_town()


func _start_new_game() -> void:
	## 새 게임 시작
	# 게임 초기화
	GameManager.start_new_game()
	
	# 용사(롤랜드)를 파티에 자동 추가
	PartyManager.add_hero_by_id("roland")
	
	# 시작 장비 지급
	PartyManager.add_item("sword_common")
	PartyManager.add_item("leather_armor")
	PartyManager.add_item("potion_small", 3)
	
	# 롤랜드에게 기본 장비 장착
	var roland := PartyManager.get_hero_at(0)
	if roland:
		PartyManager.equip_to_hero(roland, "sword_common", "main_hand")
		PartyManager.equip_to_hero(roland, "leather_armor", "body")
	
	# 선술집 초기화 (영웅 5명 배치)
	TownManager.init_new_game()
	
	# 필드에서 시작! (Stage 1-1)
	GameManager.go_to_field()
	
	# 새 게임 시작 후 자동 저장
	SaveManager.auto_save("새 게임 시작")


func _go_to_town() -> void:
	_clear_current_scene()
	
	var town := TOWN_SCENE.instantiate()
	town.go_to_field.connect(_go_to_field)
	
	# Control 노드가 전체 화면을 채우도록 설정
	town.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	add_child(town)
	current_scene = town
	
	GameManager.change_state(GameManager.GameState.TOWN)


func _go_to_field() -> void:
	_clear_current_scene()
	
	# TODO: 필드 씬 구현 후 연결
	
	# 임시: 다시 마을로
	# _go_to_town()
	
	GameManager.change_state(GameManager.GameState.FIELD)


func _clear_current_scene() -> void:
	if current_scene:
		current_scene.queue_free()
		current_scene = null
