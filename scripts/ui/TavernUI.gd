# scripts/ui/TavernUI.gd
# 선술집: 영웅 영입/해고
extends Panel

signal closed

# UI 참조 - 노드 이름만으로 찾기
var available_list: VBoxContainer
var party_list: VBoxContainer
var gold_label: Label
var close_button: Button

func _ready():
	print("[TavernUI] Created")
	
	# 노드 찾기 (이름으로 검색)
	available_list = find_child("AvailableList", true, false)
	party_list = find_child("PartyList", true, false)
	gold_label = find_child("GoldLabel", true, false)
	close_button = find_child("CloseButton", true, false)
	
	# 디버그
	print("  available_list: ", available_list)
	print("  party_list: ", party_list)
	print("  gold_label: ", gold_label)
	print("  close_button: ", close_button)
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	refresh_ui()

func refresh_ui():
	refresh_available_heroes()
	refresh_party()
	update_gold_display()

func update_gold_display():
	if gold_label:
		gold_label.text = "💰 %d Gold" % GameManager.gold

# ========================================
# 영입 가능한 영웅 목록
# ========================================

func refresh_available_heroes():
	if not available_list:
		print("[TavernUI] ERROR: available_list is null!")
		return
	
	# 기존 자식 제거
	for child in available_list.get_children():
		child.queue_free()
	
	var available_heroes = DataManager.get_enabled_heroes()
	
	for hero in available_heroes:
		# 이미 파티에 있는지 체크
		var in_party = false
		for party_hero in GameManager.party:
			if party_hero.id == hero.id:
				in_party = true
				break
		
		if in_party:
			continue
		
		# 영입 버튼
		var button = Button.new()
		var cost = 100
		if hero.has("recruitment") and hero.recruitment.has("cost"):
			cost = hero.recruitment.cost
		
		button.text = "%s (%s)\n💰 %d Gold" % [hero.name, hero.get("class", "?"), cost]
		button.custom_minimum_size = Vector2(180, 50)
		
		# 골드 부족하면 비활성화
		if GameManager.gold < cost:
			button.disabled = true
			button.add_theme_color_override("font_color", Color.GRAY)
		
		button.pressed.connect(_on_recruit_pressed.bind(hero))
		available_list.add_child(button)

# ========================================
# 현재 파티
# ========================================

func refresh_party():
	if not party_list:
		print("[TavernUI] ERROR: party_list is null!")
		return
	
	# 기존 자식 제거
	for child in party_list.get_children():
		child.queue_free()
	
	# 파티 제한 표시
	var party_label = Label.new()
	party_label.text = "파티 (%d/4)" % GameManager.party.size()
	party_label.add_theme_color_override("font_color", Color.YELLOW)
	party_list.add_child(party_label)
	
	for hero in GameManager.party:
		var hbox = HBoxContainer.new()
		
		# 영웅 정보
		var info_label = Label.new()
		info_label.text = "%s Lv.%d" % [hero.name, hero.get("level", 1)]
		info_label.custom_minimum_size = Vector2(120, 30)
		hbox.add_child(info_label)
		
		# 해고 버튼
		var fire_button = Button.new()
		fire_button.text = "해고"
		fire_button.add_theme_color_override("font_color", Color.RED)
		fire_button.pressed.connect(_on_fire_pressed.bind(hero))
		hbox.add_child(fire_button)
		
		party_list.add_child(hbox)

# ========================================
# 영입/해고
# ========================================

func _on_recruit_pressed(hero: Dictionary):
	var cost = 100
	if hero.has("recruitment") and hero.recruitment.has("cost"):
		cost = hero.recruitment.cost
	
	if GameManager.gold < cost:
		print("[Tavern] Not enough gold!")
		return
	
	if GameManager.party.size() >= 4:
		print("[Tavern] Party is full!")
		return
	
	# 골드 차감
	GameManager.spend_gold(cost)
	
	# 파티에 추가
	GameManager.add_to_party(hero.id)
	
	print("[Tavern] Recruited %s for %d gold" % [hero.name, cost])
	refresh_ui()

func _on_fire_pressed(hero: Dictionary):
	if GameManager.party.size() <= 1:
		print("[Tavern] Can't fire last hero!")
		return
	
	# 장비 해제
	if hero.has("equipped"):
		for slot in hero.equipped.keys():
			var item = DataManager.get_item(hero.equipped[slot])
			if not item.is_empty():
				GameManager.inventory.append(item)
		hero.equipped.clear()
	
	# 파티에서 제거
	GameManager.party.erase(hero)
	
	# 환불 (절반)
	var refund = 50
	if hero.has("recruitment") and hero.recruitment.has("cost"):
		refund = hero.recruitment.cost / 2
	GameManager.add_gold(refund)
	
	print("[Tavern] Fired %s (+%d gold refund)" % [hero.name, refund])
	refresh_ui()

func _on_close_pressed():
	closed.emit()
	queue_free()
