# scripts/ui/TownUI.gd
# 마을 메인 메뉴
extends Panel

signal closed
signal building_selected(building: String)

@onready var town_name_label = $VBoxContainer/TownName
@onready var buttons_container = $VBoxContainer/ButtonsContainer
@onready var leave_button = $VBoxContainer/LeaveButton

var town_data: Dictionary = {}

func _ready():
	print("[TownUI] Created")
	
	if leave_button:
		leave_button.pressed.connect(_on_leave_pressed)
	
	create_building_buttons()

func init_town(data: Dictionary):
	town_data = data
	
	if town_name_label:
		town_name_label.text = data.get("name", "마을")
	
	create_building_buttons()

func create_building_buttons():
	# 기존 버튼 제거
	for child in buttons_container.get_children():
		child.queue_free()
	
	# 건물 버튼들
	var buildings = [
		{"id": "tavern", "name": "🍺 선술집", "desc": "영웅 영입/해고"},
		{"id": "shop", "name": "🛒 상점", "desc": "아이템 구매/판매"},
		{"id": "church", "name": "⛪ 교회", "desc": "부활/회복"},
		{"id": "blacksmith", "name": "🔨 대장간", "desc": "장비 강화"},
		{"id": "inn", "name": "🛏️ 여관", "desc": "HP 완전 회복"}
	]
	
	for building in buildings:
		var button = Button.new()
		button.text = "%s\n%s" % [building.name, building.desc]
		button.custom_minimum_size = Vector2(200, 60)
		button.pressed.connect(_on_building_pressed.bind(building.id))
		buttons_container.add_child(button)

func _on_building_pressed(building_id: String):
	print("[TownUI] Selected: %s" % building_id)
	building_selected.emit(building_id)
	
	# 해당 건물 UI 열기
	match building_id:
		"tavern":
			open_tavern()
		"shop":
			open_shop()
		"church":
			open_church()
		"blacksmith":
			open_blacksmith()
		"inn":
			open_inn()

func open_tavern():
	var tavern_ui = preload("res://scenes/ui/TavernUI.tscn").instantiate()
	get_parent().add_child(tavern_ui)

func open_shop():
	var shop_ui = preload("res://scenes/ui/ShopUI.tscn").instantiate()
	get_parent().add_child(shop_ui)

func open_church():
	var church_ui = preload("res://scenes/ui/ChurchUI.tscn").instantiate()
	get_parent().add_child(church_ui)

func open_blacksmith():
	print("[Town] Blacksmith not implemented yet")
	# TODO: 대장간 UI

func open_inn():
	# 여관: 즉시 회복
	for hero in GameManager.party:
		hero.current_hp = hero.base_stats.hp
	
	GameManager.spend_gold(50)
	print("[Town] Party fully healed! (-50 Gold)")

func _on_leave_pressed():
	print("[TownUI] Leaving town")
	closed.emit()
	queue_free()
