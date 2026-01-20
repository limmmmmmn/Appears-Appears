extends Node2D
## Main: 게임 엔트리 포인트


func _ready() -> void:
	print("========== HyperQuest 시작 ==========")
	
	# 테스트: 파티 생성
	PartyManager.add_hero_by_id("roland")
	PartyManager.add_hero_by_id("luna")
	PartyManager.add_hero_by_id("elena")
	PartyManager.add_hero_by_id("shadow")
	
	# 파티 상태 출력
	PartyManager.print_party_status()
	
	# 테스트: 장비 추가 및 자동 장착
	print("\n----- 장비 테스트 -----")
	PartyManager.add_item("sword_common", 2)
	PartyManager.add_item("staff_common", 1)
	PartyManager.add_item("shield_common", 1)
	PartyManager.add_item("leather_armor", 4)
	
	# 자동 장착 테스트
	PartyManager.auto_equip_to_party("sword_common")
	PartyManager.auto_equip_to_party("staff_common")
	PartyManager.auto_equip_to_party("shield_common")
	
	print("\n장비 장착 후:")
	PartyManager.print_party_status()
	
	# 테스트: 적 생성
	print("\n----- 적 테스트 -----")
	var slime := Enemy.create_from_id("slime")
	var goblin := Enemy.create_from_id("goblin")
	print("생성된 적: %s (HP: %d), %s (HP: %d)" % [slime.enemy_name, slime.max_hp, goblin.enemy_name, goblin.max_hp])
	
	# 테스트: 데미지 계산
	print("\n----- 전투 계산 테스트 -----")
	var roland := PartyManager.get_hero_at(0)
	var result := CombatCalculator.perform_attack(roland.get_atk(), roland.get_crit(), slime.get_p_def(), slime.get_eva())
	print("롤랜드 -> 슬라임 공격: %s, 데미지: %d" % [CombatCalculator.DamageResult.keys()[result["result"]], result["damage"]])
	
	# 게임 시작
	GameManager.start_new_game()
	print("\n게임 상태: " + GameManager.get_stage_display())
	print("보유 골드: " + str(GameManager.gold))
	
	print("\n========== 초기화 완료 ==========")
