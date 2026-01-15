# scripts/ui/ItemChoiceUI.gd
# 전투 승리 시 아이템 3개 중 선택!
extends Panel

signal item_selected(item_id: String)
signal choice_skipped

# UI 참조
@onready var title_label = $VBoxContainer/Title
@onready var items_container = $VBoxContainer/ItemsContainer
@onready var skip_button = $VBoxContainer/SkipButton

# 선택지
var item_choices: Array = []
var selected_item_id: String = ""

func _ready():
	print("[ItemChoiceUI] Created")
	
	if skip_button:
		skip_button.pressed.connect(_on_skip_pressed)
	
	# 테스트용
	if item_choices.is_empty():
		test_choices()

func show_choices(items: Array):
	item_choices = items
	create_item_buttons()
	
	print("[ItemChoiceUI] Showing %d choices" % items.size())

func create_item_buttons():
	# 기존 버튼 제거
	for child in items_container.get_children():
		child.queue_free()
	
	# 아이템 버튼 생성
	for item in item_choices:
		var button = create_item_button(item)
		items_container.add_child(button)

func create_item_button(item: Dictionary) -> Button:
	var button = Button.new()
	
	# 버튼 텍스트
	var rarity_color = get_rarity_color(item.get("rarity", "common"))
	var stats_text = format_stats(item)
	
	button.text = "[%s] %s\n%s\n%s" % [
		item.get("rarity", "common").to_upper(),
		item.get("name", "Unknown"),
		item.get("description", ""),
		stats_text
	]
	
	# 버튼 스타일
	button.custom_minimum_size = Vector2(250, 100)
	button.add_theme_color_override("font_color", rarity_color)
	
	# 클릭 이벤트
	button.pressed.connect(_on_item_selected.bind(item.get("id", "")))
	
	return button

func format_stats(item: Dictionary) -> String:
	if not item.has("stats"):
		return ""
	
	var stats = item.stats
	var parts = []
	
	if stats.has("attack") and stats.attack > 0:
		parts.append("ATK +%d" % stats.attack)
	if stats.has("defense") and stats.defense > 0:
		parts.append("DEF +%d" % stats.defense)
	if stats.has("hp") and stats.hp > 0:
		parts.append("HP +%d" % stats.hp)
	if stats.has("luck") and stats.luck > 0:
		parts.append("LUCK +%d" % stats.luck)
	if stats.has("attack_speed") and stats.attack_speed > 0:
		parts.append("SPD +%.1f" % stats.attack_speed)
	
	return " | ".join(parts)

func get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common":
			return Color.WHITE
		"magic":
			return Color.CYAN
		"unique":
			return Color.GOLD
		"legendary":
			return Color.ORANGE
		_:
			return Color.WHITE

func _on_item_selected(item_id: String):
	selected_item_id = item_id
	print("[ItemChoiceUI] Selected: %s" % item_id)
	
	# 인벤토리에 추가
	GameManager.add_item(item_id)
	
	# 시그널 발송
	item_selected.emit(item_id)
	
	# 창 닫기
	close_ui()

func _on_skip_pressed():
	print("[ItemChoiceUI] Skipped")
	choice_skipped.emit()
	close_ui()

func close_ui():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	queue_free()

# ========================================
# 아이템 풀에서 랜덤 선택
# ========================================

static func get_random_items(count: int = 3) -> Array:
	var all_items = []
	
	# DataManager에서 enabled 아이템만
	if DataManager.items.has("items"):
		for item_id in DataManager.items.items:
			var item = DataManager.items.items[item_id]
			if item.get("enabled", true):
				all_items.append(item)
	
	# 셔플
	all_items.shuffle()
	
	# count개 반환
	var result = []
	for i in range(min(count, all_items.size())):
		result.append(all_items[i])
	
	return result

static func get_weighted_random_items(count: int = 3) -> Array:
	var all_items = []
	
	if DataManager.items.has("items"):
		for item_id in DataManager.items.items:
			var item = DataManager.items.items[item_id]
			if not item.get("enabled", true):
				continue
			
			# 레어리티에 따른 가중치
			var weight = 1
			match item.get("rarity", "common"):
				"common":
					weight = 10
				"magic":
					weight = 5
				"unique":
					weight = 2
				"legendary":
					weight = 1
			
			# 가중치만큼 추가
			for w in range(weight):
				all_items.append(item)
	
	all_items.shuffle()
	
	# 중복 제거하면서 선택
	var result = []
	var selected_ids = []
	
	for item in all_items:
		if result.size() >= count:
			break
		if item.id not in selected_ids:
			result.append(item)
			selected_ids.append(item.id)
	
	return result

# ========================================
# 테스트
# ========================================

func test_choices():
	print("[ItemChoiceUI] Test mode")
	
	var test_items = get_weighted_random_items(3)
	
	if test_items.is_empty():
		# 더미 데이터
		test_items = [
			{"id": "item_001", "name": "테스트 검", "rarity": "common", "description": "기본 검", "stats": {"attack": 5}},
			{"id": "item_002", "name": "마법 갑옷", "rarity": "magic", "description": "마법이 깃든 갑옷", "stats": {"defense": 10}},
			{"id": "item_003", "name": "전설의 반지", "rarity": "unique", "description": "행운을 가져다준다", "stats": {"luck": 20}}
		]
	
	show_choices(test_items)
