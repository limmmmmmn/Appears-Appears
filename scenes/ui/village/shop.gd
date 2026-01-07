class_name Shop extends Control

signal closed

@onready var item_list_container = $Content/ItemList
@onready var close_button = $Content/CloseButton
# 상점에서도 골드를 보여주면 좋습니다 (없으면 이 줄 삭제)
@onready var gold_label = $Content/GoldLabel 

func _ready():
	pass 

# 외부에서 아이템 데이터를 받아서 초기화
func setup(items: Array) -> void:
	_refresh_ui(items)
	_apply_focus_logic()

func _refresh_ui(items: Array) -> void:
	# 1. 기존 리스트 청소
	for c in item_list_container.get_children(): 
		c.queue_free()
	
	# 2. 골드 라벨 업데이트 (옵션)
	if gold_label:
		gold_label.text = "보유 골드: %d G" % PartyManager.gold
	
	# 3. 아이템 구매 버튼 생성
	for item_data in items:
		var btn = Button.new()
		# item_data가 Resource나 Dictionary라고 가정
		# 예: { "name": "포션", "price": 50 }
		btn.text = "%s 구매 (%d G)" % [item_data.name, item_data.price]
		
		# 소지금 부족하면 비활성화 (선택 사항)
		if PartyManager.gold < item_data.price:
			btn.disabled = true
		
		btn.pressed.connect(_on_buy_pressed.bind(item_data, items))
		item_list_container.add_child(btn)

# [핵심] 주점과 똑같은 완벽한 포커스 로직 (재사용)
func _apply_focus_logic() -> void:
	await get_tree().process_frame 
	
	var all_buttons = []
	for btn in item_list_container.get_children():
		if btn is Button and not btn.disabled: # 비활성 버튼은 포커스 제외
			all_buttons.append(btn)
	
	all_buttons.append(close_button)
	
	if all_buttons.is_empty(): return

	all_buttons[0].grab_focus()
	
	for i in range(all_buttons.size()):
		var btn = all_buttons[i]
		var path = btn.get_path()
		
		btn.focus_neighbor_left = path
		btn.focus_neighbor_right = path
		
		if i == 0:
			btn.focus_neighbor_top = path 
		else:
			btn.focus_neighbor_top = all_buttons[i-1].get_path()
			
		if i == all_buttons.size() - 1:
			btn.focus_neighbor_bottom = path
		else:
			btn.focus_neighbor_bottom = all_buttons[i+1].get_path()

func _on_buy_pressed(item_data, original_items_list):
	if PartyManager.gold >= item_data.price:
		PartyManager.gold -= item_data.price
		
		# TODO: 인벤토리에 아이템 추가 로직 필요
		# PartyManager.add_item(item_data) 혹은 Inventory.add(item_data)
		print(item_data.name + " 구매 완료!")
		
		# 구매 후 UI 갱신 (골드 차감 반영 및 재고 처리)
		setup(original_items_list)

func _on_close_button_pressed():
	closed.emit()
	queue_free()
