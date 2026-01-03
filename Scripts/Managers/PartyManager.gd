extends Node

# 생성할 유닛의 씬 파일 (PartyUnit.tscn을 인스펙터에 할당하거나 로드)
var party_unit_scene = preload("res://Scenes/PartyUnit.tscn") # 경로에 맞춰 수정하세요

# 테스트를 위해 임시로 사용할 데이터 (나중엔 실제 데이터 파일을 로드)
var temp_data_list = [] 

# 관리할 파티원 배열
var party_members: Array[PartyUnit] = []

func _ready():
	# 실제 게임에서는 메인 씬이 로드된 후 호출하거나, 특정 시점에 호출합니다.
	# 지금은 테스트를 위해 바로 실행해봅니다.
	# 주의: 유닛을 추가할 부모 노드(World 등)가 준비되어야 합니다.
	pass

# 게임 시작 시 호출할 함수
func setup_party(start_position: Vector2, parent_node: Node):
	# 진짜 데이터 파일 로드 (경로는 본인 프로젝트에 맞게!)
	var hero_resource = load("res://Resources/Hero_Data.tres")
	
	for i in range(4):
		var unit_instance = party_unit_scene.instantiate() as PartyUnit
		
		# [수정된 부분] 로드한 리소스를 복제해서 넣어줍니다.
		# duplicate()를 안 하면 4명이 체력을 공유하게 됩니다!
		unit_instance.unit_data = hero_resource.duplicate()
		unit_instance.unit_data.initialize()
		
		parent_node.call_deferred("add_child", unit_instance)
		party_members.append(unit_instance)
		
		# 위치 배치 및 리더 설정 (기존과 동일)
		unit_instance.global_position = start_position + Vector2(i * 40, 0)
		
	if party_members.size() > 0:
		party_members[0].is_leader = true
		party_members[0].modulate = Color.RED
