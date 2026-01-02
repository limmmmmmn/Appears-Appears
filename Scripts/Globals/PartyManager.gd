# res://Scripts/Globals/PartyManager.gd
extends Node

# 현재 파티원 리스트 (UnitData)
var party_members: Array[UnitData] = []

func _ready():
	# 실제 리소스 파일(.tres)을 로드하여 파티 구성
	# 주의: 파일 경로는 실제 생성한 파일명과 일치해야 합니다.
	var hero = load("res://Resources/Units/Hero.tres")
	var member1 = load("res://Resources/Units/Rogue.tres")
	var member2 = load("res://Resources/Units/Tank.tres")
	var member3 = load("res://Resources/Units/Mage.tres")
	
	# 파티에 추가 (순서대로 1번, 2번, 3번 자리에 섬)
	# 0번 인덱스는 무조건 플레이어(Leader)로 간주합니다.
	add_member(hero)
	add_member(member1)
	add_member(member2)
	add_member(member3)

func add_member(unit: UnitData):
	if unit and not party_members.has(unit):
		# 런타임에 데이터가 꼬이지 않도록 복제본(duplicate)을 사용하는 것이 안전함
		# (단, 상태 저장이 필요하면 원본을 유지하거나 별도 세이브 시스템 필요)
		# 여기서는 간단히 원본을 사용합니다.
		party_members.append(unit)
		print("파티 합류: " + unit.name + " (HP: " + str(unit.max_hp) + ")")
		
func get_party_size() -> int:
	return party_members.size()

# 특정 인덱스의 멤버 데이터 반환
func get_member(index: int) -> UnitData:
	if index >= 0 and index < party_members.size():
		return party_members[index]
	return null
