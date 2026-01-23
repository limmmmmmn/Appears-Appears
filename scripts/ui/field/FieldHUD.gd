extends CanvasLayer
class_name FieldHUD
## 필드 HUD 메인 컨트롤러: 컴포넌트 조합 및 조율

signal menu_pressed
signal equipment_slot_clicked(hero_index: int, slot: String)
signal skill_toggled(hero_index: int, skill_id: String, enabled: bool)

# 상단 바
@onready var stage_label: Label = %StageLabel
@onready var gold_label: Label = %GoldLabel
@onready var menu_button: Button = %MenuButton

# 우측 패널
@onready var minimap_panel: PanelContainer = %MinimapPanel
@onready var party_container: VBoxContainer = %PartyContainer
@onready var inventory_panel: PanelContainer = %InventoryPanel
@onready var log_panel: PanelContainer = %LogPanel

# 컴포넌트
var party_slots: Array[PartySlotUI] = []
var inventory_grid: InventoryGridUI = null
var battle_log: BattleLogUI = null
var drag_manager: DragDropManager = null

# 컨텍스트 메뉴/툴팁
var context_menu: PopupMenu = null
var context_menu_item_id: String = ""
var tooltip: EquipmentTooltip = null


func _ready() -> void:
	_setup_components()
	_connect_signals()
	update_all()


func _input(event: InputEvent) -> void:
	if drag_manager and drag_manager.is_dragging():
		if event is InputEventMouseMotion:
			drag_manager.update_drag_position(event.global_position)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
				drag_manager.end_drag(event.global_position)


func _setup_components() -> void:
	# 파티 슬롯 생성
	for i in range(4):
		var slot := PartySlotUI.new()
		slot.setup(i)
		slot.equipment_slot_gui_input.connect(_on_equip_gui_input.bind(i))
		slot.skill_toggled.connect(_on_skill_toggled.bind(i))
		party_container.add_child(slot)
		party_slots.append(slot)
	
	# 인벤토리 그리드
	inventory_grid = InventoryGridUI.new()
	inventory_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inventory_grid.item_clicked.connect(_on_inv_clicked)
	inventory_grid.item_hover_started.connect(_on_inv_hover)
	inventory_grid.item_hover_ended.connect(_hide_tooltip)
	inventory_grid.item_drag_started.connect(_on_inv_drag)
	inventory_grid.item_right_clicked.connect(_on_inv_right_click)
	if inventory_panel:
		for c in inventory_panel.get_children(): c.queue_free()
		inventory_panel.add_child(inventory_grid)
	
	# 배틀 로그
	battle_log = BattleLogUI.new()
	battle_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if log_panel:
		for c in log_panel.get_children(): c.queue_free()
		log_panel.add_child(battle_log)
	
	# 드래그 매니저
	drag_manager = DragDropManager.new()
	var ctrl = get_node_or_null("Control")
	drag_manager.setup(party_slots, inventory_panel, ctrl if ctrl else self)
	drag_manager.log_message.connect(add_system_log)
	drag_manager.drag_ended.connect(func(_id, ok): if ok: update_party_display())


func _connect_signals() -> void:
	if menu_button: menu_button.pressed.connect(func(): menu_pressed.emit())
	if GameManager: GameManager.gold_changed.connect(func(_g): update_top_bar())
	if PartyManager and PartyManager.has_signal("party_changed"):
		if not PartyManager.party_changed.is_connected(update_party_display):
			PartyManager.party_changed.connect(update_party_display)
	
	# BattleManager 신호 연결 - 중복 연결 방지
	if BattleManager:
		if not BattleManager.battle_log_received.is_connected(_on_battle_log_received):
			BattleManager.battle_log_received.connect(_on_battle_log_received)
		if not BattleManager.party_hp_changed.is_connected(update_party_display):
			BattleManager.party_hp_changed.connect(update_party_display)


func _on_battle_log_received(message: String, color: Color) -> void:
	add_log(message, color)


func update_all() -> void:
	update_top_bar()
	update_party_display()
	if inventory_grid: inventory_grid.refresh()


func update_top_bar() -> void:
	if stage_label and FieldManager:
		var fn = FieldManager.get_current_field_name()
		stage_label.text = FieldManager.get_display_name() + (": " + fn if fn else "")
	if gold_label and GameManager:
		gold_label.text = "%d G" % GameManager.gold


func update_party_display() -> void:
	var party = PartyManager.get_party() if PartyManager else []
	for i in range(4):
		if i < party.size():
			party_slots[i].update_display(party[i])
		else:
			party_slots[i].visible = false


func refresh_inventory() -> void:
	if inventory_grid: inventory_grid.refresh()


# === 로그 함수 ===
func add_log(msg: String, color: Color = Color.WHITE) -> void:
	if battle_log: battle_log.add_log(msg, color)

func add_battle_log(msg: String) -> void:
	if battle_log: battle_log.add_battle(msg)

func add_damage_log(atk: String, tgt: String, dmg: int, crit: bool = false) -> void:
	if battle_log: battle_log.add_damage(atk, tgt, dmg, crit)

func add_heal_log(h: String, t: String, amt: int) -> void:
	if battle_log: battle_log.add_heal(h, t, amt)

func add_defeat_log(t: String) -> void:
	if battle_log: battle_log.add_defeat(t)

func add_exp_log(e: int) -> void:
	if battle_log: battle_log.add_exp(e)

func add_gold_log(g: int) -> void:
	if battle_log: battle_log.add_gold(g)

func add_item_log(n: String) -> void:
	if battle_log: battle_log.add_item(n)

func add_system_log(msg: String) -> void:
	if battle_log: battle_log.add_system(msg)

func add_stat_description(n: String, v: String) -> void:
	if battle_log: battle_log.add_stat_info(n, v)

func clear_logs() -> void:
	if battle_log: battle_log.clear()


# === 인벤토리 이벤트 ===
func _on_inv_clicked(item_id: String) -> void:
	var data = DataManager.get_equipment(item_id)
	if data.is_empty():
		data = DataManager.get_item(item_id)
		if not data.is_empty():
			add_stat_description(str(data.get("name", item_id)), str(data.get("effect", "")))
		return
	
	var party = PartyManager.get_party() if PartyManager else []
	if party.is_empty(): return
	
	var hero = party[0]
	var slot = str(data.get("slot", "main_hand"))
	if slot == "accessory":
		slot = "acc1" if hero.equipment.get("acc1", "").is_empty() else "acc2"
	
	if InventoryManager.equip_item(hero, item_id, slot):
		add_system_log("%s: %s 장착" % [hero.hero_name, str(data.get("name", item_id))])
		update_party_display()
		_hide_tooltip()


func _on_inv_hover(item_id: String) -> void:
	if drag_manager and drag_manager.is_dragging(): return
	_show_tooltip(item_id)


func _on_inv_drag(item_id: String, _btn: Button) -> void:
	_hide_tooltip()
	if drag_manager: drag_manager.start_drag_from_inventory(item_id)


func _on_inv_right_click(item_id: String, pos: Vector2) -> void:
	# 장비 또는 소비 아이템 모두 컨텍스트 메뉴 표시
	var equip_data = DataManager.get_equipment(item_id)
	var item_data = DataManager.get_item(item_id)
	
	if not equip_data.is_empty():
		_show_context_menu(item_id, pos, "equip")
	elif not item_data.is_empty() and item_data.get("type", "") == "consumable":
		_show_context_menu(item_id, pos, "consumable")


# === 장비 슬롯 이벤트 ===
func _on_equip_gui_input(event: InputEvent, slot_name: String, hero_idx: int) -> void:
	var party = PartyManager.get_party() if PartyManager else []
	if hero_idx >= party.size(): return
	
	var hero: Hero = party[hero_idx]
	var eid = hero.equipment.get(slot_name, "")
	
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT and not eid.is_empty():
			if InventoryManager.unequip_item(hero, slot_name):
				var n = str(DataManager.get_equipment(eid).get("name", eid))
				add_system_log("%s: %s 해제" % [hero.hero_name, n])
				update_party_display()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if not eid.is_empty() and drag_manager:
				drag_manager.start_drag_from_equipped(eid, hero_idx, slot_name)
			else:
				equipment_slot_clicked.emit(hero_idx, slot_name)


func _on_skill_toggled(skill_id: String, enabled: bool, hero_idx: int) -> void:
	skill_toggled.emit(hero_idx, skill_id, enabled)
	var party = PartyManager.get_party() if PartyManager else []
	if hero_idx < party.size():
		var sn = str(DataManager.get_skill(skill_id).get("name", skill_id))
		add_system_log("%s: %s %s" % [party[hero_idx].hero_name, sn, "ON" if enabled else "OFF"])


# === 컨텍스트 메뉴 ===
var context_menu_type: String = ""  # "equip" or "consumable"

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
			# 소비 아이템 - 필드 사용 가능 여부와 대상 상태 체크
			var data = DataManager.get_item(item_id)
			var effect = data.get("effect", {})
			var effect_type = str(effect.get("type", ""))
			
			if not usable_in_field:
				is_disabled = true
			elif effect_type == "revive":
				# 부활은 사망한 대상만
				is_disabled = not party[i].is_dead
				if party[i].is_dead:
					hero_name += " (사망)"
			else:
				# 일반 회복/씨앗은 살아있는 대상만
				is_disabled = party[i].is_dead
				if party[i].is_dead:
					hero_name += " (사망)"
		else:
			# 장비 - 사망한 대상 불가
			if party[i].is_dead:
				is_disabled = true
				hero_name += " (사망)"
		
		context_menu.add_item(hero_name, i)
		if is_disabled:
			context_menu.set_item_disabled(context_menu.item_count - 1, true)
	
	context_menu.add_separator()
	context_menu.add_item("취소", -2)
	context_menu.id_pressed.connect(_on_ctx_selected)
	# popup_hide 연결 제거 - id_pressed보다 먼저 호출되어 데이터가 사라지는 문제
	
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


func _use_consumable_on_hero(item_id: String, hero: Hero) -> void:
	## 소비 아이템을 영웅에게 사용
	
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
				add_system_log("%s: 사망한 대상에게 사용 불가" % item_name)
				return
			var heal_percent: float = float(effect.get("value", 0.3))
			var heal_amount: int = int(hero.get_max_hp() * heal_percent)
			var actual_heal: int = hero.heal(heal_amount)
			if actual_heal > 0:
				add_system_log("%s: %s HP +%d" % [hero.hero_name, item_name, actual_heal])
				success = true
			else:
				add_system_log("%s: HP가 이미 가득 참" % hero.hero_name)
		
		"restore_mp_percent":
			if hero.is_dead:
				add_system_log("%s: 사망한 대상에게 사용 불가" % item_name)
				return
			var mp_percent: float = float(effect.get("value", 0.5))
			var mp_amount: int = int(hero.get_max_mp() * mp_percent)
			var actual_mp: int = hero.restore_mp(mp_amount)
			if actual_mp > 0:
				add_system_log("%s: %s MP +%d" % [hero.hero_name, item_name, actual_mp])
				success = true
			else:
				add_system_log("%s: MP가 이미 가득 참" % hero.hero_name)
		
		"full_restore":
			if hero.is_dead:
				add_system_log("%s: 사망한 대상에게 사용 불가" % item_name)
				return
			hero.heal(hero.get_max_hp())
			hero.restore_mp(hero.get_max_mp())
			add_system_log("%s: %s 사용 - 완전 회복!" % [hero.hero_name, item_name])
			success = true
		
		"revive":
			if not hero.is_dead:
				add_system_log("%s: 살아있는 대상에게 사용 불가" % item_name)
				return
			var hp_percent: float = float(effect.get("hp_percent", 0.3))
			hero.revive(hp_percent)
			add_system_log("%s: %s 부활!" % [hero.hero_name, item_name])
			success = true
		
		"permanent_stat":
			if hero.is_dead:
				add_system_log("%s: 사망한 대상에게 사용 불가" % item_name)
				return
			var stat: String = str(effect.get("stat", ""))
			var value: int = int(effect.get("value", 1))
			hero.apply_seed_bonus(stat, value)
			add_system_log("%s: %s 사용 - %s +%d!" % [hero.hero_name, item_name, stat.to_upper(), value])
			success = true
		
		"full_restore_party":
			var all_party = PartyManager.get_party() if PartyManager else []
			for member in all_party:
				if not member.is_dead:
					member.heal(member.get_max_hp())
					member.restore_mp(member.get_max_mp())
			add_system_log("%s 사용 - 파티 전원 완전 회복!" % item_name)
			success = true
		
		"revive_all":
			var all_party = PartyManager.get_party() if PartyManager else []
			var hp_percent: float = float(effect.get("hp_percent", 0.5))
			var revived_count: int = 0
			for member in all_party:
				if member.is_dead:
					member.revive(hp_percent)
					revived_count += 1
			if revived_count > 0:
				add_system_log("%s 사용 - %d명 부활!" % [item_name, revived_count])
				success = true
			else:
				add_system_log("부활시킬 대상이 없음")
		
		_:
			add_system_log("%s: 알 수 없는 효과" % item_name)
	
	if success:
		var removed = InventoryManager.remove_item(item_id, 1)
		update_party_display()
		if inventory_grid:
			inventory_grid.refresh()


func _hide_context_menu() -> void:
	if context_menu and is_instance_valid(context_menu):
		context_menu.queue_free()
		context_menu = null
	context_menu_item_id = ""
	context_menu_type = ""


# === 툴팁 ===
func _show_tooltip(item_id: String) -> void:
	_hide_tooltip()
	
	# 장비 또는 소비 아이템 모두 툴팁 표시
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
