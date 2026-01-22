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
		PartyManager.party_changed.connect(update_party_display)
	
	# BattleManager 신호 연결 - 전투 로그와 파티 HP 업데이트
	if BattleManager:
		BattleManager.battle_log_received.connect(_on_battle_log_received)
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
		if i < party.size(): party_slots[i].update_display(party[i])
		else: party_slots[i].visible = false


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
	if not DataManager.get_equipment(item_id).is_empty():
		_show_context_menu(item_id, pos)


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
func _show_context_menu(item_id: String, pos: Vector2) -> void:
	_hide_context_menu()
	_hide_tooltip()
	context_menu_item_id = item_id
	
	var data = DataManager.get_equipment(item_id)
	context_menu = PopupMenu.new()
	context_menu.add_theme_font_size_override("font_size", 10)
	context_menu.add_item("[ %s ]" % str(data.get("name", item_id)), -1)
	context_menu.set_item_disabled(0, true)
	context_menu.add_separator()
	
	var party = PartyManager.get_party() if PartyManager else []
	for i in range(party.size()):
		context_menu.add_item(party[i].hero_name, i)
		if party[i].is_dead: context_menu.set_item_disabled(context_menu.item_count - 1, true)
	
	context_menu.add_separator()
	context_menu.add_item("취소", -2)
	context_menu.id_pressed.connect(_on_ctx_selected)
	context_menu.popup_hide.connect(_hide_context_menu)
	
	var ctrl = get_node_or_null("Control")
	(ctrl if ctrl else self).add_child(context_menu)
	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()


func _on_ctx_selected(id: int) -> void:
	if id < 0:
		_hide_context_menu()
		return
	
	var party = PartyManager.get_party() if PartyManager else []
	if id >= party.size():
		_hide_context_menu()
		return
	
	var hero = party[id]
	var data = DataManager.get_equipment(context_menu_item_id)
	var slot = str(data.get("slot", "main_hand"))
	if slot == "accessory":
		slot = "acc1" if hero.equipment.get("acc1", "").is_empty() else "acc2"
	
	if InventoryManager.equip_item(hero, context_menu_item_id, slot):
		add_system_log("%s: %s 장착!" % [hero.hero_name, str(data.get("name", context_menu_item_id))])
		update_party_display()
	_hide_context_menu()


func _hide_context_menu() -> void:
	if context_menu and is_instance_valid(context_menu):
		context_menu.queue_free()
		context_menu = null
	context_menu_item_id = ""


# === 툴팁 ===
func _show_tooltip(item_id: String) -> void:
	_hide_tooltip()
	if DataManager.get_equipment(item_id).is_empty(): return
	
	tooltip = EquipmentTooltip.new()
	var ctrl = get_node_or_null("Control")
	(ctrl if ctrl else self).add_child(tooltip)
	tooltip.setup_for_item(item_id, inventory_panel)


func _hide_tooltip() -> void:
	if tooltip and is_instance_valid(tooltip):
		tooltip.queue_free()
		tooltip = null
