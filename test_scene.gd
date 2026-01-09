extends Node2D

func _ready():
	print("--- 1주차 구조 테스트 시작 ---")
	
	# 1. 리소스 로드
	var hero_data = load("res://common/data/hero_test.tres")
	if hero_data == null:
		printerr("❌ 데이터 로드 실패!")
		return
		
	# 2. 런타임 객체 생성 (영입 시뮬레이션)
	var new_hero = UnitRuntime.new(hero_data)
	print("🔹 영웅 생성: ", new_hero.def.name, " (HP: ", new_hero.current_hp, ")")
	
	# 3. GameState Roster에 등록
	GameState.roster.append(new_hero)
	print("🔹 로스터 등록 완료. 현재 인원: ", GameState.roster.size(), "명")
	
	# 4. GameState Party에 배치
	GameState.party.append(new_hero)
	print("🔹 파티 배치 완료. 현재 파티원: ", GameState.party.size(), "명")
	
	# 5. 상태 공유 확인 (나중에 멀티 전투창의 기초)
	GameState.party[0].current_hp -= 10
	print("💥 데미지 10 입음! 현재 HP: ", new_hero.current_hp)
	
	if new_hero.current_hp == 90:
		print("✅ 테스트 성공! 데이터 구조가 정상 작동합니다.")
	else:
		print("❌ 테스트 실패! HP가 동기화되지 않았습니다.")
