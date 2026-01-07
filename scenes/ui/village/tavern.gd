class_name Tavern extends Control

signal closed

@onready var candidate_list = $Content/CandidateList
@onready var party_list = $Content/PartyList
@onready var close_button = $Content/CloseButton

# _ready()에서 포커스를 잡는 코드는 삭제했습니다.
# 데이터가 로드된 후(setup)에 잡는 것이 안전합니다.
func _ready():
	pass 

func setup(candidates: Array[UnitData]) -> void:
	_refresh_ui(candidates)
	# UI를 다 그린 후, 한 프레임 대기했다가 포커스 연결 (안전성 확보)
	_apply_focus_logic()

func _refresh_ui(candidates: Array[UnitData]) -> void:
	# 기존 아이템들 깨끗이 삭제
	for c in candidate_list.get_children(): c.queue_free()
	for c in party_list.get_children(): c.queue_free()
	
	# 고용 버튼 생성
	for data in candidates:
		var btn = Button.new()
		btn.text = "%s 고용 (%d G)" % [data.name, data.hire_cost]
		btn.pressed.connect(_on_hire_pressed.bind(data))
		candidate_list.add_child(btn)
	
	# 해고 버튼 생성
	for i in range(PartyManager.party.size()):
		var member = PartyManager.party[i]
		var btn = Button.new()
		btn.text = "%s 해고" % member._data.name
		btn.pressed.connect(_on_fire_pressed.bind(i))
		party_list.add_child(btn)

# [핵심] 모든 버튼을 긁어모아 순서대로 '체인'처럼 엮어주는 함수
func _apply_focus_logic() -> void:
	# 큐프리(queue_free)된 노드들이 완전히 사라지도록 1프레임 대기
	await get_tree().process_frame 
	
	# 화면에 존재하는 모든 버튼을 순서대로 하나의 배열에 담습니다.
	# 순서: 고용 리스트 -> 해고 리스트 -> 닫기 버튼
	var all_buttons = []
	
	for btn in candidate_list.get_children():
		if btn is Button: all_buttons.append(btn)
		
	for btn in party_list.get_children():
		if btn is Button: all_buttons.append(btn)
		
	all_buttons.append(close_button)
	
	# 버튼이 하나도 없다면 종료 (예외처리)
	if all_buttons.is_empty():
		return

	# 첫 번째 버튼 강제 포커스 (화면 열리자마자 선택됨)
	all_buttons[0].grab_focus()
	
	# 루프를 돌며 앞뒤 관계를 강제로 맺어줍니다.
	for i in range(all_buttons.size()):
		var btn = all_buttons[i]
		var path = btn.get_path()
		
		# 1. 좌우 이동 봉쇄 (포커스 튀는 것 방지)
		btn.focus_neighbor_left = path
		btn.focus_neighbor_right = path
		
		# 2. 위쪽 연결
		if i == 0:
			# 맨 위 버튼은 위로 가도 제자리 (혹은 순환)
			btn.focus_neighbor_top = path 
		else:
			# 내 위쪽은 '이전 인덱스'의 버튼
			btn.focus_neighbor_top = all_buttons[i-1].get_path()
			
		# 3. 아래쪽 연결
		if i == all_buttons.size() - 1:
			# 맨 마지막(Exit) 버튼은 아래로 가도 제자리
			btn.focus_neighbor_bottom = path
		else:
			# 내 아래쪽은 '다음 인덱스'의 버튼
			btn.focus_neighbor_bottom = all_buttons[i+1].get_path()

func _on_hire_pressed(data: UnitData):
	if PartyManager.gold >= data.hire_cost:
		if PartyManager.add_to_party(data):
			PartyManager.gold -= data.hire_cost
			setup(PartyManager.get_available_heroes()) # setup을 다시 호출해서 UI 갱신 및 포커스 재설정

func _on_fire_pressed(index: int):
	PartyManager.fire_hero(index)
	setup(PartyManager.get_available_heroes()) # setup을 다시 호출해서 UI 갱신 및 포커스 재설정

func _on_close_button_pressed():
	closed.emit()
	queue_free()
