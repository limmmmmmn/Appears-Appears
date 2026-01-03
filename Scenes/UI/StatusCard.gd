extends PanelContainer

# 부모(StatusUI)에게 "이 유닛의 이 슬롯이 눌렸어!" 라고 알리는 신호
signal equip_slot_clicked(unit, type)

@onready var portrait = $MainVBox/HeaderBox/Portrait
@onready var name_label = $MainVBox/HeaderBox/NameLabel
@onready var stats_label = $MainVBox/StatsLabel

@onready var slot_weapon = $MainVBox/EquipBox/EquipSlot_Weapon
@onready var slot_armor = $MainVBox/EquipBox/EquipSlot_Armor
@onready var slot_acc = $MainVBox/EquipBox/EquipSlot_Acc

var my_unit: UnitData

func _ready():
	# 각 슬롯이 눌리면 -> 내 유닛 정보(my_unit)를 담아서 위로 쏘아올림
	slot_weapon.slot_pressed.connect(func(type): equip_slot_clicked.emit(my_unit, type))
	slot_armor.slot_pressed.connect(func(type): equip_slot_clicked.emit(my_unit, type))
	slot_acc.slot_pressed.connect(func(type): equip_slot_clicked.emit(my_unit, type))

func setup(unit: UnitData):
	my_unit = unit
	
	# 1. 기본 정보
	name_label.text = "Lv.%d\n%s" % [unit.level, unit.name]
	portrait.texture = unit.texture
	
	# 2. 스탯 정보 (한눈에 보기 좋게)
	var txt = ""
	txt += "HP: %d/%d\n" % [unit.current_hp, unit.get_total_max_hp()]
	txt += "ATK: %d  DEF: %d" % [unit.get_total_attack(), unit.get_total_defense()]
	stats_label.text = txt
	
	# 3. 장비 아이콘 갱신
	slot_weapon.set_item(unit.equip_weapon)
	slot_armor.set_item(unit.equip_armor)
	slot_acc.set_item(unit.equip_accessory)
