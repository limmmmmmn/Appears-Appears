extends Control
## Main: 게임 엔트리 포인트

const TOWN_SCENE := preload("res://scenes/town/Town.tscn")

var current_scene: Node = null


func _ready() -> void:
	print("========== HyperQuest 시작 ==========")
	_start_new_game()


func _start_new_game() -> void:
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
	
	# 마을로 이동
	_go_to_town()


func _go_to_town() -> void:
	_clear_current_scene()
	
	var town := TOWN_SCENE.instantiate()
	town.go_to_field.connect(_go_to_field)
	
	# Control 노드가 전체 화면을 채우도록 설정
	town.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	add_child(town)
	current_scene = town
	
	GameManager.change_state(GameManager.GameState.TOWN)
	print("[Main] 마을 입장")


func _go_to_field() -> void:
	_clear_current_scene()
	
	# TODO: 필드 씬 구현 후 연결
	print("[Main] 필드로 출발! (아직 미구현)")
	
	# 임시: 다시 마을로
	# _go_to_town()
	
	GameManager.change_state(GameManager.GameState.FIELD)


func _clear_current_scene() -> void:
	if current_scene:
		current_scene.queue_free()
		current_scene = null
