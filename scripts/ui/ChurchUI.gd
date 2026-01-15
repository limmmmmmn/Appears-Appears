# scripts/ui/ChurchUI.gd
# 교회: 부활/회복
extends Panel

signal closed

@onready var dead_heroes_list = $VBoxContainer/DeadHeroesList
@onready var heal_button = $VBoxContainer/HealButton
@onready var gold_label = $GoldLabel
@onready var close_button = $CloseButton

# 죽은 영웅들 (대기실에서)
var dead_heroes: Array = []

func _ready():
	print("[ChurchUI] Created")
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	if heal_button:
		heal_button.pressed.connect(_on_heal_all_pressed)
	
	refresh_ui()

func refresh_ui():
	find_dead_heroes()
	refresh_dead_list()
	update_gold_display()

func update_gold_display():
	if gold_label:
		gold_label.text = "💰 %d Gold" % GameManager.gold

func find_dead_heroes():
	dead_heroes.clear()
	
	# 파티에서 HP 0인 영웅들 찾기
	for hero in GameManager.party:
		if hero.current_hp <= 0:
			dead_heroes.append(hero)

func refresh_dead_list():
	for child in dead_heroes_list.get_children():
		child.queue_free()
	
	if dead_heroes.is_empty():
		var label = Label.new()
		label.text = "부활할 영웅이 없습니다."
		label.add_theme_color_override("font_color", Color.GREEN)
		dead_heroes_list.add_child(label)
		return
	
	for hero in dead_heroes:
		var hbox = HBoxContainer.new()
		
		# 영웅 정보
		var info = Label.new()
		info.text = "💀 %s (Lv.%d)" % [hero.name, hero.level]
		info.custom_minimum_size = Vector2(150, 30)
		hbox.add_child(info)
		
		# 부활 비용
		var cost = calculate_revive_cost(hero)
		
		# 부활 버튼
		var revive_btn = Button.new()
		revive_btn.text = "부활 (💰%d)" % cost
		
		if GameManager.gold < cost:
			revive_btn.disabled = true
		
		revive_btn.pressed.connect(_on_revive_pressed.bind(hero, cost))
		hbox.add_child(revive_btn)
		
		dead_heroes_list.add_child(hbox)

func calculate_revive_cost(hero: Dictionary) -> int:
	# 레벨 * 50
	return hero.level * 50

func _on_revive_pressed(hero: Dictionary, cost: int):
	if GameManager.gold < cost:
		return
	
	GameManager.spend_gold(cost)
	
	# HP 50%로 부활
	hero.current_hp = hero.base_stats.hp / 2
	
	print("[Church] Revived %s for %d gold (HP: %d)" % [hero.name, cost, hero.current_hp])
	refresh_ui()

func _on_heal_all_pressed():
	var total_cost = 0
	var healed = 0
	
	for hero in GameManager.party:
		if hero.current_hp < hero.base_stats.hp:
			var missing_hp = hero.base_stats.hp - hero.current_hp
			var cost = missing_hp  # HP 1당 1골드
			
			if GameManager.gold >= cost:
				GameManager.spend_gold(cost)
				hero.current_hp = hero.base_stats.hp
				total_cost += cost
				healed += 1
	
	if healed > 0:
		print("[Church] Healed %d heroes for %d gold" % [healed, total_cost])
	else:
		print("[Church] All heroes are at full HP!")
	
	refresh_ui()

func _on_close_pressed():
	closed.emit()
	queue_free()
