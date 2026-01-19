extends PanelContainer
class_name HeroPanel
## 개별 영웅 정보 패널 - 페이스칩, 스탯, 장비 슬롯

signal item_dropped(hero_id: String, slot: String, item_id: String)

var hero_id: String = ""
var panel_index: int = 0

# UI 참조
@onready var face_texture: TextureRect = $MainVBox/Header/Face
@onready var name_label: Label = $MainVBox/Header/InfoVBox/NameLabel
@onready var hp_bar: ProgressBar = $MainVBox/Header/InfoVBox/HPBar
@onready var atb_bar: ProgressBar = $MainVBox/Header/InfoVBox/ATBBar
@onready var stats_grid: GridContainer = $MainVBox/StatsGrid
@onready var equipment_grid: GridContainer = $MainVBox/EquipmentGrid

var stat_labels: Dictionary = {}
var equipment_slots: Dictionary = {}


func _ready() -> void:
	_setup_style()
	_cache_nodes()
	_connect_equipment_signals()


func _setup_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.25, 0.25, 0.3)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	add_theme_stylebox_override("panel", style)
	
	# HP 바 스타일
	var hp_fill = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.8, 0.2, 0.2)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	var hp_bg = StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.2, 0.1, 0.1)
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	
	# ATB 바 스타일
	var atb_fill = StyleBoxFlat.new()
	atb_fill.bg_color = Color(0.2, 0.6, 0.9)
	atb_bar.add_theme_stylebox_override("fill", atb_fill)
	var atb_bg = StyleBoxFlat.new()
	atb_bg.bg_color = Color(0.1, 0.15, 0.2)
	atb_bar.add_theme_stylebox_override("background", atb_bg)


func _cache_nodes() -> void:
	# 스탯 라벨 캐시
	stat_labels["atk"] = stats_grid.get_node("ATK")
	stat_labels["def"] = stats_grid.get_node("DEF")
	stat_labels["dex"] = stats_grid.get_node("DEX")
	stat_labels["int"] = stats_grid.get_node("INT")
	stat_labels["luk"] = stats_grid.get_node("LUK")
	
	# 장비 슬롯 캐시
	equipment_slots["weapon_left"] = equipment_grid.get_node("WeaponLeft")
	equipment_slots["weapon_right"] = equipment_grid.get_node("WeaponRight")
	equipment_slots["helmet"] = equipment_grid.get_node("Helmet")
	equipment_slots["armor"] = equipment_grid.get_node("Armor")
	equipment_slots["accessory1"] = equipment_grid.get_node("Accessory1")
	equipment_slots["accessory2"] = equipment_grid.get_node("Accessory2")


func _connect_equipment_signals() -> void:
	for slot_name in equipment_slots:
		var slot = equipment_slots[slot_name] as EquipmentSlot
		slot.item_dropped_on_slot.connect(_on_slot_item_dropped.bind(slot_name))


func _on_slot_item_dropped(dropped_item_id: String, slot_name: String) -> void:
	item_dropped.emit(hero_id, slot_name, dropped_item_id)


func set_hero(id: String) -> void:
	hero_id = id
	_update_display()


func clear_hero() -> void:
	hero_id = ""
	name_label.text = "---"
	face_texture.texture = null
	hp_bar.value = 0
	atb_bar.value = 0
	
	for stat in stat_labels:
		stat_labels[stat].text = "%s:--" % stat.to_upper()
	
	for slot in equipment_slots:
		equipment_slots[slot].set_item("")


func _update_display() -> void:
	if hero_id.is_empty():
		clear_hero()
		return
	
	var hero_data = DataManager.get_hero(hero_id)
	if hero_data.is_empty():
		return
	
	# 이름
	name_label.text = str(hero_data.get("name", hero_id))
	
	# 사망 시 이름 회색
	if not GameManager.is_hero_alive(hero_id):
		name_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	else:
		name_label.add_theme_color_override("font_color", Color.WHITE)
	
	# 페이스칩
	var portrait_path = str(hero_data.get("visuals", {}).get("portrait", ""))
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		face_texture.texture = load(portrait_path)
	
	# HP
	var hp = int(GameManager.party_hp.get(hero_id, 0))
	var max_hp = int(GameManager.party_max_hp.get(hero_id, 100))
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	
	# ATB
	var atb_percent = GameManager.get_cooldown_percent(hero_id) * 100
	atb_bar.value = atb_percent
	
	# 스탯 (장비 포함 최종값)
	var total_stats = GameManager.get_hero_total_stats(hero_id)
	var stat_names = {"atk": "ATK", "def": "DEF", "dex": "DEX", "int": "INT", "luk": "LUK"}
	for stat in stat_labels:
		var value = int(total_stats.get(stat, 0))
		stat_labels[stat].text = "%s:%d" % [stat_names[stat], value]
	
	# 장비 슬롯
	var equipment = GameManager.get_all_equipment(hero_id)
	for slot in equipment_slots:
		var eq_item_id = str(equipment.get(slot, ""))
		equipment_slots[slot].set_item(eq_item_id)
		equipment_slots[slot].hero_id = hero_id


func _process(_delta: float) -> void:
	if hero_id.is_empty():
		return
	
	# ATB 실시간 업데이트
	var atb_percent = GameManager.get_cooldown_percent(hero_id) * 100
	atb_bar.value = atb_percent
	
	# HP 업데이트
	var hp = int(GameManager.party_hp.get(hero_id, 0))
	hp_bar.value = hp
