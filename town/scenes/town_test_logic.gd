extends Node

# 테스트용 데이터 미리 로드 (경로 변경 반영!)
var hero_data = preload("res://common/data/hero_test.tres")
var healer_data = preload("res://common/data/healer_test.tres")

func _ready():
	print("--- 🏘️ 마을 시스템(PartyManager) 테스트 시작 ---")
	
	# 1. 영입 테스트
	print("\n[1] 영입 진행 중...")
	PartyManager.recruit_hero(hero_data)       # 용사 영입
	PartyManager.recruit_hero(healer_data)     # 힐러 영입
	PartyManager.recruit_hero(hero_data)       # 용사 또 영입 (쌍둥이 컨셉?)
	
	# 2. 로스터 확인
	print("\n[2] 현재 보유 영웅 목록:")
	for unit in GameState.roster:
		print("- %s (직업: %s)" % [unit.def.name, unit.def.job_name])
		
	# 3. 파티 편성 테스트
	print("\n[3] 파티 편성 시도...")
	# 로스터의 0번(용사), 1번(힐러)을 파티에 넣음
	var unit1 = GameState.roster[0]
	var unit2 = GameState.roster[1]
	
	PartyManager.add_to_party(unit1)
	PartyManager.add_to_party(unit2)
	PartyManager.add_to_party(unit1) # 중복 편성 시도 (실패해야 함)
	
	# 4. 결과 확인
	print("\n[4] 최종 파티 구성:")
	if GameState.party.size() == 2:
		print("✅ 파티 인원 2명 정상 (용사 + 힐러)")
	else:
		print("❌ 파티 인원 오류: ", GameState.party.size())
		
	# 5. 해고 테스트
	print("\n[5] 힐러 해고 시도...")
	PartyManager.fire_hero(unit2)
	if GameState.party.size() == 1 and GameState.roster.size() == 2:
		print("✅ 해고 성공: 파티에서 빠지고 로스터에서도 사라짐.")
	else:
		print("❌ 해고 처리 오류")
