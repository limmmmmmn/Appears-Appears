extends Control
## Town: 마을 메인 화면

signal go_to_field

# UI 참조
@onready var gold_label: Label = %GoldLabel
@onready var stage_label: Label = %StageLabel
@onready var main_menu: VBoxContainer = %MainMenu
@onready var sub_panel: PanelContainer = %SubPanel
@onready var sub_content: VBoxContainer = %SubContent
@onready var message_label: Label = %MessageLabel

# 서브패널 버튼 목록 (키보드 네비게이션용)
var sub_buttons: Array[Button] = []


func _ready() -> void:
	_update_top_bar()
	_show_main_menu()
	GameManager.gold_changed.connect(_on_gold_changed)
	
	# 마을 입장 처리
	TownManager.on_enter_town()
	
	# 첫 번째 버튼에 포커스
	await get_tree().process_frame
	_focus_first_menu_button()


func _focus_first_menu_button() -> void:
	var status_btn = main_menu.get_node_or_null("StatusButton")
	if status_btn:
		status_btn.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# ESC로 뒤로가기
		if sub_panel.visible:
			_show_main_menu()
			get_viewport().set_input_as_handled()


func _update_top_bar() -> void:
	gold_label.text = "%d G" % GameManager.gold
	stage_label.text = GameManager.get_stage_display()


func _on_gold_changed(_new_gold: int) -> void:
	_update_top_bar()


func _show_main_menu() -> void:
	main_menu.visible = true
	sub_panel.visible = false
	sub_buttons.clear()
	message_label.text = "마을에 오신 것을 환영합니다."
	
	# 메인 메뉴 첫 버튼에 포커스
	await get_tree().process_frame
	_focus_first_menu_button()


func _clear_sub_content() -> void:
	for child in sub_content.get_children():
		child.queue_free()


func _show_message(text: String) -> void:
	message_label.text = text


#region 메인 메뉴 버튼
func _on_tavern_pressed() -> void:
	_open_tavern()


func _on_status_pressed() -> void:
	_open_status()


func _on_weapon_shop_pressed() -> void:
	_open_shop("weapon_shop")


func _on_armor_shop_pressed() -> void:
	_open_shop("armor_shop")


func _on_item_shop_pressed() -> void:
	_open_shop("item_shop")


func _on_inn_pressed() -> void:
	_open_inn()


func _on_church_pressed() -> void:
	_open_church()


func _on_explore_pressed() -> void:
	_do_explore()


func _on_depart_pressed() -> void:
	if PartyManager.get_party().is_empty():
		_show_message("파티에 영웅이 없습니다!")
		return
	go_to_field.emit()
#endregion


#region 상태창
func _open_status() -> void:
	var status_panel_script := load("res://scripts/ui/PartyStatusPanel.gd")
	var status_panel := Control.new()
	status_panel.set_script(status_panel_script)
	status_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_panel.closed.connect(_on_status_closed)
	add_child(status_panel)


func _on_status_closed() -> void:
	_focus_first_menu_button()
#endregion


#region 선술집
func _open_tavern() -> void:
	main_menu.visible = false
	sub_panel.visible = true
	_clear_sub_content()
	sub_buttons.clear()
	
	var title := Label.new()
	title.text = "[ 선술집 ]"
	sub_content.add_child(title)
	
	var desc := Label.new()
	desc.text = "영입 가능 횟수: %d회 남음 | 현재 파티: %d/4명" % [TownManager.recruit_remaining, PartyManager.get_party().size()]
	sub_content.add_child(desc)
	
	var sep := HSeparator.new()
	sub_content.add_child(sep)
	
	# 현재 파티 표시
	var party_label := Label.new()
	party_label.text = "--- 현재 파티 ---"
	sub_content.add_child(party_label)
	
	var party := PartyManager.get_party()
	if party.is_empty():
		var empty := Label.new()
		empty.text = "(없음)"
		sub_content.add_child(empty)
	else:
		for hero in party:
			var hero_label := Label.new()
			hero_label.text = "• %s (Lv.%d %s)" % [hero.hero_name, hero.level, hero.hero_class_name]
			sub_content.add_child(hero_label)
	
	var sep2 := HSeparator.new()
	sub_content.add_child(sep2)
	
	# 영입 가능 영웅
	var available_label := Label.new()
	available_label.text = "--- 영입 가능 ---"
	sub_content.add_child(available_label)
	
	var tavern_heroes := TownManager.get_tavern_heroes()
	if tavern_heroes.is_empty():
		var none := Label.new()
		none.text = "(없음)"
		sub_content.add_child(none)
	else:
		for hero_id in tavern_heroes:
			var hero_data: Dictionary = DataManager.get_hero(hero_id)
			var class_id: String = hero_data.get("class_id", "")
			var class_data: Dictionary = DataManager.get_class_data(class_id)
			
			var hbox := HBoxContainer.new()
			
			var info := Label.new()
			info.text = "%s (%s)" % [hero_data.get("name", "???"), class_data.get("name", "???")]
			info.custom_minimum_size.x = 200
			hbox.add_child(info)
			
			var recruit_btn := Button.new()
			recruit_btn.text = "영입"
			recruit_btn.disabled = not TownManager.can_recruit() or PartyManager.get_party().size() >= 4
			recruit_btn.pressed.connect(_on_recruit_hero.bind(hero_id))
			hbox.add_child(recruit_btn)
			sub_buttons.append(recruit_btn)
			
			sub_content.add_child(hbox)
	
	_add_back_button()


func _on_recruit_hero(hero_id: String) -> void:
	if TownManager.recruit_hero(hero_id):
		var hero_data: Dictionary = DataManager.get_hero(hero_id)
		_show_message("%s이(가) 파티에 합류했습니다!" % hero_data.get("name", ""))
		_open_tavern()  # 새로고침
	else:
		_show_message("영입에 실패했습니다.")
#endregion


#region 상점 (무기/방어구/도구)
func _open_shop(shop_id: String) -> void:
	var shop_panel_script := load("res://scripts/ui/ShopPanel.gd")
	var shop_panel := Control.new()
	shop_panel.set_script(shop_panel_script)
	shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.setup(shop_id)
	shop_panel.closed.connect(_on_shop_closed)
	add_child(shop_panel)


func _on_shop_closed() -> void:
	_update_top_bar()
	_focus_first_menu_button()
#endregion


#region 여관
func _open_inn() -> void:
	main_menu.visible = false
	sub_panel.visible = true
	_clear_sub_content()
	sub_buttons.clear()
	
	var inn_data: Dictionary = DataManager.get_shop("inn")
	var cost_per_person: int = int(inn_data.get("rest_cost_per_person", 10))
	
	var title := Label.new()
	title.text = "[ 여관 ]"
	sub_content.add_child(title)
	
	var greet := Label.new()
	greet.text = inn_data.get("greeting", "푹 쉬어가세요.")
	sub_content.add_child(greet)
	
	var sep := HSeparator.new()
	sub_content.add_child(sep)
	
	# 파티 상태 표시
	var party := PartyManager.get_party()
	for hero in party:
		var status := Label.new()
		status.text = "%s: HP %d/%d, MP %d/%d" % [
			hero.hero_name,
			hero.current_hp, hero.get_max_hp(),
			hero.current_mp, hero.get_max_mp()
		]
		sub_content.add_child(status)
	
	var sep2 := HSeparator.new()
	sub_content.add_child(sep2)
	
	# 휴식 비용
	var total_cost: int = cost_per_person * party.size()
	var cost_label := Label.new()
	cost_label.text = "휴식 비용: %d G (1인당 %d G)" % [total_cost, cost_per_person]
	sub_content.add_child(cost_label)
	
	var rest_btn := Button.new()
	rest_btn.text = "휴식하기"
	rest_btn.disabled = GameManager.gold < total_cost or party.is_empty()
	rest_btn.pressed.connect(_on_rest.bind(total_cost))
	sub_content.add_child(rest_btn)
	sub_buttons.append(rest_btn)
	
	_add_back_button()


func _on_rest(cost: int) -> void:
	if GameManager.spend_gold(cost):
		PartyManager.full_restore_party()
		_show_message("푹 쉬었습니다. HP/MP가 완전히 회복되었습니다!")
		_open_inn()
#endregion


#region 교회
func _open_church() -> void:
	main_menu.visible = false
	sub_panel.visible = true
	_clear_sub_content()
	sub_buttons.clear()
	
	var church_data: Dictionary = DataManager.get_shop("church")
	
	var title := Label.new()
	title.text = "[ 교회 ]"
	sub_content.add_child(title)
	
	var greet := Label.new()
	greet.text = church_data.get("greeting", "신의 가호가 함께하기를...")
	sub_content.add_child(greet)
	
	var sep := HSeparator.new()
	sub_content.add_child(sep)
	
	# 부활 대상 (사망한 영웅)
	var dead_heroes := PartyManager.get_dead_heroes()
	
	var revive_label := Label.new()
	revive_label.text = "--- 부활 ---"
	sub_content.add_child(revive_label)
	
	if dead_heroes.is_empty():
		var no_dead := Label.new()
		no_dead.text = "부활이 필요한 영웅이 없습니다."
		sub_content.add_child(no_dead)
	else:
		var base_cost: int = int(church_data.get("revive_cost_base", 50))
		var per_level: int = int(church_data.get("revive_cost_per_level", 10))
		
		for hero in dead_heroes:
			var cost: int = base_cost + (hero.level * per_level)
			
			var hbox := HBoxContainer.new()
			
			var name_label := Label.new()
			name_label.text = "%s (Lv.%d)" % [hero.hero_name, hero.level]
			name_label.custom_minimum_size.x = 150
			hbox.add_child(name_label)
			
			var cost_lbl := Label.new()
			cost_lbl.text = "%d G" % cost
			cost_lbl.custom_minimum_size.x = 80
			hbox.add_child(cost_lbl)
			
			var revive_btn := Button.new()
			revive_btn.text = "부활"
			revive_btn.disabled = GameManager.gold < cost
			revive_btn.pressed.connect(_on_revive_hero.bind(hero, cost))
			hbox.add_child(revive_btn)
			sub_buttons.append(revive_btn)
			
			sub_content.add_child(hbox)
	
	_add_back_button()


func _on_revive_hero(hero: Hero, cost: int) -> void:
	if GameManager.spend_gold(cost):
		hero.revive(0.5)
		_show_message("%s이(가) 부활했습니다!" % hero.hero_name)
		PartyManager.party_changed.emit()
		_open_church()
#endregion


#region 마을 탐색
func _do_explore() -> void:
	if not TownManager.can_explore():
		_show_message("오늘은 충분히 돌아다녔다. (탐색 %d/%d)" % [TownManager.explore_count, TownManager.MAX_EXPLORE_PER_VISIT])
		return
	
	var result := TownManager.do_explore()
	var text: String = result.get("text", "")
	var effect: Dictionary = result.get("effect", {})
	
	# 효과 텍스트 추가
	var effect_text := ""
	match effect.get("type", "none"):
		"gold":
			var min_val: int = int(effect.get("min", 0))
			var max_val: int = int(effect.get("max", 0))
			if min_val > 0:
				effect_text = "\n[골드 획득]"
			elif max_val < 0:
				effect_text = "\n[골드 손실]"
		"item":
			var item_id: String = effect.get("item_id", "")
			var item_data: Dictionary = DataManager.get_item(item_id)
			effect_text = "\n[%s 획득!]" % item_data.get("name", "아이템")
	
	_show_message(text + effect_text + "\n\n(탐색 %d/%d)" % [TownManager.explore_count, TownManager.MAX_EXPLORE_PER_VISIT])
	_update_top_bar()
#endregion


#region 유틸리티
func _add_back_button() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	sub_content.add_child(spacer)
	
	var back_btn := Button.new()
	back_btn.text = "뒤로"
	back_btn.pressed.connect(_show_main_menu)
	sub_content.add_child(back_btn)
	sub_buttons.append(back_btn)
	
	# 포커스 네비게이션 설정
	_setup_sub_button_navigation()
	
	# 첫 번째 버튼에 포커스
	await get_tree().process_frame
	if sub_buttons.size() > 0:
		sub_buttons[0].grab_focus()


func _setup_sub_button_navigation() -> void:
	for i in range(sub_buttons.size()):
		var btn := sub_buttons[i]
		if i > 0:
			btn.focus_neighbor_top = sub_buttons[i - 1].get_path()
		if i < sub_buttons.size() - 1:
			btn.focus_neighbor_bottom = sub_buttons[i + 1].get_path()
#endregion
