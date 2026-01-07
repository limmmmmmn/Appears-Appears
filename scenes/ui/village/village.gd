class_name Village extends Control
# [Hyper Quest] 마을 메인 로직

@export var tavern_scene: PackedScene 
@export var shop_scene: PackedScene 

@onready var tavern_btn = $MainPanel/TavernButton
@onready var shop_btn = $MainPanel/ShopButton
@onready var main_panel = $MainPanel
@onready var gold_label = $GoldLabel

func _ready() -> void:
	update_gold_ui()
	# 마을 진입 시 첫 번째 버튼에 포커스 (TavernButton)
	if tavern_btn:
		tavern_btn.grab_focus()

func update_gold_ui() -> void:
	# PartyManager에서 골드 정보 갱신
	gold_label.text = "Gold: %d" % PartyManager.gold

# --- [주점 관련] ---
func _on_tavern_button_pressed():
	var tavern_popup = tavern_scene.instantiate()
	add_child(tavern_popup)
	
	# 주점 데이터 주입 (고용 가능한 영웅 목록)
	tavern_popup.setup(PartyManager.get_available_heroes())
	
	# 공통 서브 메뉴 열기 로직 호출
	_open_sub_menu(tavern_popup)

# --- [상점 관련] ---
func _on_shop_button_pressed() -> void:
	var shop = shop_scene.instantiate()
	add_child(shop)
	
	# [임시 데이터] 나중에는 ShopManager.get_items() 등으로 교체하세요.
	var dummy_items = [
		{ "name": "체력 포션", "price": 50 },
		{ "name": "마나 포션", "price": 80 },
		{ "name": "해독제", "price": 30 },
		{ "name": "롱소드", "price": 500 }
	]
	
	# 상점 데이터 주입
	shop.setup(dummy_items) 
	
	# 공통 서브 메뉴 열기 로직 호출
	_open_sub_menu(shop)

# --- [공통 로직] ---
func _open_sub_menu(menu: Control) -> void:
	# [철칙] 서브 메뉴가 열리면 마을 패널(뒷배경)의 입력을 완전히 차단
	main_panel.process_mode = PROCESS_MODE_DISABLED 
	
	# 팝업이 닫힐 때(closed 시그널) 실행될 로직
	menu.closed.connect(func():
		# 1. 마을 패널 입력 다시 활성화
		main_panel.process_mode = PROCESS_MODE_INHERIT 
		
		# 2. 골드 변화가 있었을 수 있으니 UI 갱신
		update_gold_ui()
		
		# 3. 포커스 복구 (닫힌 메뉴가 무엇인지에 따라 분기 가능)
		# 지금은 무조건 TavernButton으로 복구하거나, 마지막 눌린 버튼으로 복구
		if is_instance_valid(tavern_btn):
			tavern_btn.grab_focus()
	)
