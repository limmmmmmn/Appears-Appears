extends CanvasLayer

# 카드가 들어갈 컨테이너
@onready var card_container = $BackgroundPanel/MarginContainer/CardContainer

# 아까 만든 카드 씬 연결 (인스펙터에서 StatusCard.tscn 넣으세요!)
@export var card_scene: PackedScene 

@onready var item_select_panel = $ItemSelectPanel
@onready var item_list_container = $ItemSelectPanel/ScrollContainer/ItemListContainer
@onready var close_button = $BackgroundPanel/CloseButton

# 현재 장비 교체 중인 대상 기억용
var selected_unit: UnitData 

func _ready():
	visible = false
	item_select_panel.visible = false
	close_button.pressed.connect(close_window)
	
	# 미리 카드를 만들어둠
	refresh_all_cards()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		if item_select_panel.visible:
			item_select_panel.visible = false
		elif visible:
			close_window()
		else:
			open_window()

func open_window():
	visible = true
	get_tree().paused = true
	refresh_all_cards() # 열 때 최신 상태로 갱신

func close_window():
	visible = false
	item_select_panel.visible = false
	get_tree().paused = false

# --- [핵심] 모든 파티원 카드 생성 및 갱신 ---
func refresh_all_cards():
	# 기존 카드 싹 지우기 (초기화)
	for child in card_container.get_children():
		child.queue_free()
	
	# 파티원 수만큼 카드 생성
	for unit in PartyManager.party_members:
		if not card_scene: return
		
		var card = card_scene.instantiate()
		card_container.add_child(card)
		
		# 카드에 데이터 주입
		card.setup(unit)
		
		# 카드의 장비 슬롯이 눌리면 -> 내 함수(_on_card_slot_clicked) 실행 연결
		card.equip_slot_clicked.connect(_on_card_slot_clicked)

# --- 슬롯 클릭 처리 (카드에서 신호를 받음) ---
func _on_card_slot_clicked(unit: UnitData, type: ItemData.Type):
	selected_unit = unit # "지금 누구 장비 바꾸는 중인지" 기억
	
	# 팝업 띄우기 (기존 로직 재활용)
	show_item_popup(type)

# --- [핵심] 인벤토리 목록 띄우기 ---
func show_item_popup(type: ItemData.Type):
	item_select_panel.visible = true
	
	# 기존 버튼 청소
	for child in item_list_container.get_children():
		child.queue_free()
	
	# 1. 취소 버튼
	var close_btn = Button.new()
	close_btn.text = "취소"
	close_btn.pressed.connect(func(): item_select_panel.visible = false)
	item_list_container.add_child(close_btn)

	# 2. 장비 해제 버튼
	var unequip_btn = Button.new()
	unequip_btn.text = "- 장비 해제 -"
	unequip_btn.pressed.connect(func(): 
		change_equipment(null, type)
		item_select_panel.visible = false
	)
	item_list_container.add_child(unequip_btn)
	
	# 3. [NEW] 실제 인벤토리 아이템 버튼 생성!
	var found_item = false
	for item in GameSettings.inventory:
		# 슬롯 타입(무기/갑옷/반지)이 맞는 것만 보여주기
		if item.item_type == type:
			found_item = true
			var btn = Button.new()
			btn.text = item.name + " (공+%d 방+%d)" % [item.bonus_attack, item.bonus_defense]
			btn.icon = item.icon # 아이콘 있으면 표시
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			
			# 버튼 누르면 -> change_equipment 실행 (해당 아이템을 넘김)
			btn.pressed.connect(func(): 
				change_equipment(item, type)
				item_select_panel.visible = false
			)
			item_list_container.add_child(btn)
			
	if not found_item:
		var empty_lbl = Label.new()
		empty_lbl.text = "(장착 가능한 아이템 없음)"
		item_list_container.add_child(empty_lbl)

#--- [핵심] 장비 교체 (스왑) 로직 ---
func change_equipment(new_item: ItemData, type: ItemData.Type):
	if not selected_unit: return
	
	# 1. 원래 끼고 있던 거 있나? -> 있으면 가방으로 회수
	var old_item = null
	match type:
		ItemData.Type.WEAPON: old_item = selected_unit.equip_weapon
		ItemData.Type.ARMOR: old_item = selected_unit.equip_armor
		ItemData.Type.ACCESSORY: selected_unit.equip_accessory
	
	if old_item:
		GameSettings.add_item(old_item)
		print(old_item.name + " 가방으로 돌아옴")
		
	# 2. 새 아이템 장착
	match type:
		ItemData.Type.WEAPON: selected_unit.equip_weapon = new_item
		ItemData.Type.ARMOR: selected_unit.equip_armor = new_item
		ItemData.Type.ACCESSORY: selected_unit.equip_accessory = new_item
	
	# 3. 새 아이템은 가방에서 제거 (장착했으니까!)
	if new_item:
		GameSettings.remove_item(new_item)
		print(new_item.name + " 장착 완료")
	
	# 4. 화면 갱신
	refresh_all_cards()

func _debug_equip_test(type):
	var temp_item = ItemData.new()
	temp_item.name = "테스트 장비"
	temp_item.item_type = type
	temp_item.bonus_attack = 10
	change_equipment(temp_item, type)
