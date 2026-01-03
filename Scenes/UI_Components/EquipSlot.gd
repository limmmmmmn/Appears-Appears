extends Control

# 이 슬롯이 어떤 종류인지 (무기/방어구/장신구)
@export var slot_type: ItemData.Type = ItemData.Type.WEAPON

var current_item: ItemData

@onready var icon = $Icon
@onready var type_label = $TypeLabel

# 부모(StatusUI)에게 "나 클릭됐어!"라고 알리는 신호
signal slot_pressed(type)

func _ready():
	# 버튼 연결
	$Button.pressed.connect(func(): slot_pressed.emit(slot_type))
	
	# 라벨 설정 (W:무기, A:방어구, S:장신구)
	match slot_type:
		ItemData.Type.WEAPON: type_label.text = "W"
		ItemData.Type.ARMOR: type_label.text = "A"
		ItemData.Type.ACCESSORY: type_label.text = "S"

func set_item(item: ItemData):
	current_item = item
	
	if item:
		icon.texture = item.icon
		# 툴팁에 아이템 정보 표시
		tooltip_text = "[%s]\n%s\n공격+%d 방어+%d" % [item.name, item.description, item.bonus_attack, item.bonus_defense]
	else:
		icon.texture = null
		tooltip_text = "비어있음"
