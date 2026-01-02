# res://Scenes/UI/PartyMemberSlot.gd
extends Control

@onready var face_icon = $TextureRect
@onready var hp_bar = $ProgressBar
@onready var name_label = $Label

var linked_unit: UnitData # 이 슬롯이 담당하는 캐릭터 데이터

func setup(unit: UnitData):
	linked_unit = unit
	
	# 1. 기본 정보 표시
	name_label.text = unit.name
	if unit.texture:
		face_icon.texture = unit.texture
	else:
		face_icon.texture = load("res://icon.svg")
		
	# 2. 체력바 설정
	hp_bar.max_value = unit.max_hp
	hp_bar.value = unit.current_hp
	

func update_hp():
	if linked_unit:
		# 부드러운 움직임을 원하면 Tween을 쓸 수 있지만, 지금은 즉시 반영
		hp_bar.value = linked_unit.current_hp
