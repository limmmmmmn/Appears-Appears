extends CanvasLayer
class_name GameHUD
## 게임 HUD - 우측 패널에 미니맵, 영웅 정보, 로그 표시

# UI 참조
@onready var right_panel: MarginContainer = $RightPanel
@onready var panel_bg: PanelContainer = $RightPanel/PanelBG
@onready var minimap_placeholder: Panel = $RightPanel/PanelBG/VBox/MinimapPlaceholder
@onready var hero_grid: GridContainer = $RightPanel/PanelBG/VBox/HeroGrid
@onready var log_panel: LogPanel = $RightPanel/PanelBG/VBox/LogPanel
@onready var inventory_panel: InventoryPanel = $BottomPanel/InventoryPanel

var hero_panels: Array[HeroPanel] = []

# 인벤토리 (임시 - 나중에 별도 시스템으로)
var inventory: Array[String] = []


func _ready() -> void:
	_setup_style()
	_cache_hero_panels()
	_connect_signals()
	_init_test_inventory()
	
	call_deferred("_update_all_heroes")


func _setup_style() -> void:
	# 우측 패널 배경
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	panel_style.border_width_left = 2
	panel_style.border_color = Color(0.3, 0.3, 0.35)
	panel_bg.add_theme_stylebox_override("panel", panel_style)
	
	# 미니맵 플레이스홀더
	var minimap_style = StyleBoxFlat.new()
	minimap_style.bg_color = Color(0.15, 0.15, 0.18)
	minimap_style.border_width_bottom = 1
	minimap_style.border_color = Color(0.3, 0.3, 0.35)
	minimap_placeholder.add_theme_stylebox_override("panel", minimap_style)


func _cache_hero_panels() -> void:
	for i in range(4):
		var panel = hero_grid.get_child(i) as HeroPanel
		if panel:
			panel.panel_index = i
			panel.item_dropped.connect(_on_item_dropped)
			hero_panels.append(panel)


func _connect_signals() -> void:
	GameManager.party_status_changed.connect(_update_all_heroes)
	GameManager.equipment_changed.connect(_on_equipment_changed)


func _init_test_inventory() -> void:
	# 테스트용 초기 장비
	inventory = [
		"eq_iron_sword",
		"eq_wooden_shield",
		"eq_leather_armor",
		"eq_wooden_staff",
		"eq_dagger",
		"eq_leather_cap"
	]
	_update_inventory_display()


func _update_all_heroes() -> void:
	var party = GameManager.party
	for i in range(hero_panels.size()):
		if i < party.size():
			hero_panels[i].set_hero(party[i])
		else:
			hero_panels[i].clear_hero()


func _update_inventory_display() -> void:
	if inventory_panel:
		inventory_panel.update_items(inventory)


func _on_equipment_changed(_hero_id: String, _slot: String) -> void:
	_update_all_heroes()


func _on_item_dropped(hero_id: String, slot: String, item_id: String) -> void:
	if item_id.is_empty():
		# 장비 해제 → 인벤토리로
		var unequipped = GameManager.unequip_item(hero_id, slot)
		if unequipped != "":
			inventory.append(unequipped)
			add_log("[%s] %s 해제" % [_get_hero_name(hero_id), _get_item_name(unequipped)])
			_update_inventory_display()
	else:
		# 기존 장비가 있으면 인벤토리로
		var old_item = GameManager.get_equipped_item(hero_id, slot)
		
		if GameManager.equip_item(hero_id, item_id):
			inventory.erase(item_id)
			if old_item != "":
				inventory.append(old_item)
			add_log("[%s] %s 장착!" % [_get_hero_name(hero_id), _get_item_name(item_id)])
			_update_inventory_display()
		else:
			add_log("장착 불가!")


func _get_hero_name(hero_id: String) -> String:
	var data = DataManager.get_hero(hero_id)
	return str(data.get("name", hero_id))


func _get_item_name(item_id: String) -> String:
	var data = DataManager.get_equipment(item_id)
	return str(data.get("name", item_id))


func add_log(text: String) -> void:
	if log_panel:
		log_panel.add_log(text)


func get_inventory() -> Array[String]:
	return inventory
