class_name VillageMenu extends Control
# [Blueprint v1.4] 6. UI - 데이터 기반 마을 로직

# 1. 스크립트 상단(변수 선언부)에 추가
@onready var gold_label: Label = $GoldLabel # 노드 이름이 다를 경우 실제 이름으로 수정하세요

# 인스펙터에서 마을마다 다른 .tres 파일을 넣어줍니다.
@export var tavern_pool: UnitPool
@export var shop_pool: ItemPool

func _ready() -> void:
	# 1. 골드 UI 갱신 (기존 코드)
	_update_gold_ui()
	
	# 2. 키보드 제어를 위해 첫 번째 버튼에 포커스 강제 할당
	# $MainPanel/TavernButton 부분은 파트너님의 실제 노드 경로에 맞게 수정하세요.
	var first_button = $MainPanel/TavernButton
	if first_button:
		first_button.grab_focus()

func _on_tavern_button_pressed() -> void:
	if not tavern_pool: return
	
	# 마을 풀에서 랜덤하게 1명을 뽑아 영입 시도
	var candidates = tavern_pool.pick_random(1)
	if candidates.is_empty(): return
	
	var hero = candidates[0]
	if PartyManager.gold >= hero.hire_cost:
		if PartyManager.add_to_party(hero):
			PartyManager.gold -= hero.hire_cost
			_update_gold_ui()
			print("%s 영입 완료!" % hero.name)

func _on_shop_button_pressed() -> void:
	if not shop_pool: return
	
	# 상점 풀에 있는 아이템 중 첫 번째 구매 시도 (나중에 상점 UI에서 선택하게 수정)
	var inventory = shop_pool.get_inventory()
	if inventory.is_empty(): return
	
	var item = inventory[0]
	if PartyManager.gold >= item.price:
		PartyManager.gold -= item.price
		PartyManager.inventory.append(item)
		_update_gold_ui()
		print("%s 구매 완료!" % item.name)
		
# 나가기 버튼 눌렀을 때 실행 (에디터 시그널 연결 확인 필수)
func _on_exit_button_pressed() -> void:
	print("필드로 복귀합니다.")
	# 원래 있던 필드(test_world)로 씬을 전환합니다.
	get_tree().change_scene_to_file("res://scenes/world/test_world.tscn")
	
# 2. 스크립트 맨 하단에 함수 정의 추가 (이게 없어서 에러가 난 것입니다!)
func _update_gold_ui() -> void:
	if gold_label:
		gold_label.text = "Gold: %dG" % PartyManager.gold
