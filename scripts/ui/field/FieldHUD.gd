extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러
## - TopBar: 스테이지, 골드, 배속, 메뉴
## - LogPanel: 전투 로그 (좌측 하단)
## - BottomPartyPanel: 파티 정보 (하단 중앙) - 외부 씬
## - InventoryPanel: 인벤토리 (우측 하단)

signal menu_pressed

# === 상단 바 ===
@onready var stage_label: Label = %StageLabel
@onready var gold_label: Label = %GoldLabel
@onready var speed_button: Button = %SpeedButton
@onready var menu_button: Button = %MenuButton

# === 로그 패널 (좌측 하단) ===
@onready var log_panel: PanelContainer = %LogPanel
@onready var log_scroll: ScrollContainer = %LogScroll
@onready var log_container: VBoxContainer = %LogContainer

# === 하단 파티 패널 (중앙) - 외부 씬 ===
@onready var bottom_party_panel: BottomPartyPanel = %BottomPartyPanel

# === 인벤토리 패널 (우측 하단) ===
@onready var inventory_panel: PanelContainer = %InventoryPanel

# === 컴포넌트 ===
var inventory_grid: InventoryGridUI = null
var battle_log: BattleLogUI = null

# === 툴팁 ===
var tooltip: EquipmentTooltip = null

# === 컨텍스트 메뉴 ===
var context_menu: PopupMenu = null
var context_menu_item_id: String = ""
var context_menu_type: String = ""


func _ready() -> void:
	_setup_components()
	_connect_signals()
	update_all()


func _setup_components() -> void:
	_setup_speed_button()
	
	# 인벤토리 그리드
	inventory_grid = InventoryGridUI.new()
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_grid.item_clicked.connect(_on_inv_clicked)
	inventory_grid.item_hover_started.connect(_on_inv_hover)
	inventory_grid.item_hover_ended.connect(_hide_tooltip)
	inventory_grid.item_right_clicked.connect(_on_inv_right_click)
	if inventory_panel:
		for c in inventory_panel.get_children():
			c.queue_free()
		inventory_panel.add_child(inventory_grid)
	
	# 배틀 로그
	battle_log = BattleLogUI.new()
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if log_container:
		log_container.add_child(battle_log)


func _setup_speed_button() -> void:
	if not speed_button:
		return
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.6, 0.9)
	speed_button.add_theme_stylebox_override("normal", style)
	
	var hover := style.duplicate()
	hover.bg_color = Color(0.25, 0.25, 0.3, 0.95)
	speed_button.add_theme_stylebox_override("hover", hover)


func _connect_signals() -> void:
	if menu_button:
		menu_button.pressed.connect(func(): menu_pressed.emit())
	if speed_button:
		speed_button.pressed.connect(_on_speed_button_pressed)
	
	if GameManager:
		GameManager.gold_changed.connect(func(_g): update_top_bar())
	
	if BattleManager:
		if not BattleManager.battle_log_received.is_connected(_on_battle_log_received):
			BattleManager.battle_log_received.connect(_on_battle_log_received)
		if not BattleManager.party_hp_changed.is_connected(update_party_display):
			BattleManager.party_hp_changed.connect(update_party_display)
		if not BattleManager.battle_speed_changed.is_connected(_on_battle_speed_changed):
			BattleManager.battle_speed_changed.connect(_on_battle_speed_changed)
		if not BattleManager.loot_animation_requested.is_connected(_on_loot_animation_requested):
			BattleManager.loot_animation_requested.connect(_on_loot_animation_requested)


#region 이벤트 핸들러
func _on_speed_button_pressed() -> void:
	if BattleManager:
		var new_speed = BattleManager.toggle_battle_speed()
		speed_button.text = "x%d" % int(new_speed)


func _on_battle_speed_changed(speed: float) -> void:
	if speed_button:
		speed_button.text = "x%d" % int(speed)


func _on_battle_log_received(message: String, color: Color) -> void:
	add_log(message, color)


func _on_loot_animation_requested(item_id: String, start_pos: Vector2) -> void:
	var target_pos: Vector2 = _get_inventory_target_position()
	
	var loot_anim := LootAnimationUI.new()
	var ctrl := get_node_or_null("Control")
	if ctrl:
		ctrl.add_child(loot_anim)
	else:
		add_child(loot_anim)
	
	loot_anim.animation_completed.connect(_on_loot_animation_completed)
	loot_anim.setup(item_id, start_pos, target_pos)


func _get_inventory_target_position() -> Vector2:
	if inventory_panel and is_instance_valid(inventory_panel):
		return inventory_panel.global_position + inventory_panel.size / 2
	return Vector2(400, 200)


func _on_loot_animation_completed(_item_id: String) -> void:
	if inventory_grid:
		inventory_grid.refresh()
#endregion


#region 업데이트
func update_all() -> void:
	update_top_bar()
	update_party_display()
	if inventory_grid:
		inventory_grid.refresh()


func update_top_bar() -> void:
	if stage_label and FieldManager:
		var fn = FieldManager.get_current_field_name()
		stage_label.text = FieldManager.get_display_name() + (": " + fn if fn else "")
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold


func update_party_display() -> void:
	if bottom_party_panel:
		bottom_party_panel.update_display()


func refresh_inventory() -> void:
	if inventory_grid:
		inventory_grid.refresh()
#endregion


#region 로그
func add_log(msg: String, color: Color = Color.WHITE) -> void:
	if battle_log:
		battle_log.add_log(msg, color)

func add_battle_log(msg: String) -> void:
	if battle_log:
		battle_log.add_battle(msg)

func add_damage_log(atk: String, tgt: String, dmg: int, crit: bool = false) -> void:
	if battle_log:
		battle_log.add_damage(atk, tgt, dmg, crit)

func add_heal_log(h: String, t: String, amt: int) -> void:
	if battle_log:
		battle_log.add_heal(h, t, amt)

func add_defeat_log(t: String) -> void:
	if battle_log:
		battle_log.add_defeat(t)

func add_exp_log(e: int) -> void:
	if battle_log:
		battle_log.add_exp(e)

func add_gold_log(g: int) -> void:
	if battle_log:
		battle_log.add_gold(g)

func add_item_log(n: String) -> void:
	if battle_log:
		battle_log.add_item(n)

func add_system_log(msg: String) -> void:
	if battle_log:
		battle_log.add_system(msg)

func clear_logs() -> void:
	if battle_log:
		battle_log.clear()
#endregion


#region 인벤토리 이벤트
func _on_inv_clicked(item_id: String) -> void:
	var data = DataManager.get_equipment(item_id)
	if data.is_empty():
		return
	
	var party = PartyManager.get_party() if PartyManager else []
	if party.is_empty():
		return
	
	# 첫 번째 살아있는 파티원에게 장착
	for hero in party:
		if hero.is_dead:
			continue
		var slot = str(data.get("slot", "main_hand"))
		if slot == "accessory":
			slot = "acc1" if hero.equipment.get("acc1", "").is_empty() else "acc2"
		if InventoryManager.equip_item(hero, item_id, slot):
			add_system_log("%s: %s 장착!" % [hero.hero_name, str(data.get("name", item_id))])
			update_party_display()
			if inventory_grid:
				inventory_grid.refresh()
			break


func _on_inv_hover(item_id: String) -> void:
	_show_tooltip(item_id)


func _on_inv_right_click(item_id: String, mouse_pos: Vector2) -> void:
	var equip_data = DataManager.get_equipment(item_id)
	var item_data = DataManager.get_item(item_id)
	
	if not equip_data.is_empty():
		_show_context_menu(item_id, mouse_pos, "equip")
	elif not item_data.is_empty() and item_data.get("type", "") == "consumable":
		_show_context_menu(item_id, mouse_pos, "consumable")
#endregion


#region 컨텍스트 메뉴
func _show_context_menu(item_id: String, pos: Vector2, item_type: String = "equip") -> void:
	_hide_context_menu()
	_hide_tooltip()
	context_menu_item_id = item_id
	context_menu_type = item_type
	
	var item_name: String = ""
	var usable_in_field: bool = true
	
	if item_type == "equip":
		var data = DataManager.get_equipment(item_id)
		item_name = str(data.get("name", item_id))
	else:
		var data = DataManager.get_item(item_id)
		item_name = str(data.get("name", item_id))
		usable_in_field = data.get("usable_in_field", false)
	
	context_menu = PopupMenu.new()
	context_menu.add_theme_font_size_override("font_size", 10)
	context_menu.add_item("[ %s ]" % item_name, -1)
	context_menu.set_item_disabled(0, true)
	context_menu.add_separator()
	
	var party = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		var hero_name: String = party[i].hero_name
		var is_disabled: bool = false
		
		if item_type == "consumable":
			var data = DataManager.get_item(item_id)
			var effect = data.get("effect", {})
			var effect_type = str(effect.get("type", ""))
			
			if not usable_in_field:
				is_disabled = true
			elif effect_type == "revive":
				is_disabled = not party[i].is_dead
			else:
				is_disabled = party[i].is_dead
		else:
			is_disabled = party[i].is_dead
		
		context_menu.add_item(hero_name, i)
		if is_disabled:
			context_menu.set_item_disabled(context_menu.item_count - 1, true)
	
	context_menu.add_separator()
	context_menu.add_item("취소", -2)
	context_menu.id_pressed.connect(_on_ctx_selected)
	
	var ctrl = get_node_or_null("Control")
	(ctrl if ctrl else self).add_child(context_menu)
	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()


func _on_ctx_selected(id: int) -> void:
	var saved_item_id: String = context_menu_item_id
	var saved_type: String = context_menu_type
	
	if id < 0:
		_hide_context_menu()
		return
	
	var party = PartyManager.get_party() if PartyManager else []
	if id >= party.size():
		_hide_context_menu()
		return
	
	var hero = party[id]
	
	if saved_type == "consumable":
		_use_consumable_on_hero(saved_item_id, hero)
	else:
		var data = DataManager.get_equipment(saved_item_id)
		if data.is_empty():
			_hide_context_menu()
			return
		
		var slot = str(data.get("slot", "main_hand"))
		if slot == "accessory":
			slot = "acc1" if hero.equipment.get("acc1", "").is_empty() else "acc2"
		
		if InventoryManager.equip_item(hero, saved_item_id, slot):
			add_system_log("%s: %s 장착!" % [hero.hero_name, str(data.get("name", saved_item_id))])
			update_party_display()
			if inventory_grid:
				inventory_grid.refresh()
	
	_hide_context_menu()


func _hide_context_menu() -> void:
	if context_menu and is_instance_valid(context_menu):
		context_menu.queue_free()
		context_menu = null
	context_menu_item_id = ""
	context_menu_type = ""
#endregion


#region 소비 아이템
func _use_consumable_on_hero(item_id: String, hero: Hero) -> void:
	var item_data: Dictionary = DataManager.get_item(item_id)
	if item_data.is_empty():
		return
	
	var item_name: String = str(item_data.get("name", item_id))
	var effect: Dictionary = item_data.get("effect", {})
	var effect_type: String = str(effect.get("type", ""))
	var usable_in_field: bool = item_data.get("usable_in_field", false)
	
	if not usable_in_field:
		add_system_log("%s: 전투 중에만 사용 가능" % item_name)
		return
	
	var success: bool = false
	
	match effect_type:
		"heal_percent":
			if hero.is_dead:
				return
			var heal_percent: float = float(effect.get("value", 0.3))
			var heal_amount: int = int(hero.get_max_hp() * heal_percent)
			var actual_heal: int = hero.heal(heal_amount)
			if actual_heal > 0:
				add_system_log("%s: %s HP +%d" % [hero.hero_name, item_name, actual_heal])
				success = true
		
		"restore_mp_percent":
			if hero.is_dead:
				return
			var mp_percent: float = float(effect.get("value", 0.5))
			var mp_amount: int = int(hero.get_max_mp() * mp_percent)
			var actual_mp: int = hero.restore_mp(mp_amount)
			if actual_mp > 0:
				add_system_log("%s: %s MP +%d" % [hero.hero_name, item_name, actual_mp])
				success = true
		
		"full_restore":
			if hero.is_dead:
				return
			hero.heal(hero.get_max_hp())
			hero.restore_mp(hero.get_max_mp())
			add_system_log("%s: %s 완전 회복!" % [hero.hero_name, item_name])
			success = true
		
		"revive":
			if not hero.is_dead:
				return
			var hp_percent: float = float(effect.get("hp_percent", 0.3))
			hero.revive(hp_percent)
			add_system_log("%s: %s 부활!" % [hero.hero_name, item_name])
			success = true
		
		"permanent_stat":
			if hero.is_dead:
				return
			var stat: String = str(effect.get("stat", ""))
			var value: int = int(effect.get("value", 1))
			hero.apply_seed_bonus(stat, value)
			add_system_log("%s: %s - %s +%d!" % [hero.hero_name, item_name, stat.to_upper(), value])
			success = true
		
		"full_restore_party":
			var all_party = PartyManager.get_party() if PartyManager else []
			for member in all_party:
				if not member.is_dead:
					member.heal(member.get_max_hp())
					member.restore_mp(member.get_max_mp())
			add_system_log("%s - 파티 전원 회복!" % item_name)
			success = true
		
		"revive_all":
			var all_party = PartyManager.get_party() if PartyManager else []
			var hp_percent: float = float(effect.get("hp_percent", 0.5))
			var count: int = 0
			for member in all_party:
				if member.is_dead:
					member.revive(hp_percent)
					count += 1
			if count > 0:
				add_system_log("%s - %d명 부활!" % [item_name, count])
				success = true
	
	if success:
		InventoryManager.remove_item(item_id, 1)
		update_party_display()
		if inventory_grid:
			inventory_grid.refresh()
#endregion


#region 툴팁
func _show_tooltip(item_id: String) -> void:
	_hide_tooltip()
	
	var equip_data = DataManager.get_equipment(item_id)
	var item_data = DataManager.get_item(item_id)
	
	if equip_data.is_empty() and (item_data.is_empty() or item_data.get("type", "") != "consumable"):
		return
	
	tooltip = EquipmentTooltip.new()
	var ctrl = get_node_or_null("Control")
	(ctrl if ctrl else self).add_child(tooltip)
	tooltip.setup_for_item(item_id, inventory_panel)


func _hide_tooltip() -> void:
	if tooltip and is_instance_valid(tooltip):
		tooltip.queue_free()
		tooltip = null
#endregion
