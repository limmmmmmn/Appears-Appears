extends Node

# 최대 파티 인원 상수 (기획서 기준 4인)
const MAX_PARTY_SIZE = 4

# --- 1. 영입 (Recruit) ---
# 술집에서 영웅을 고르면 호출됩니다.
# 데이터(def)를 받아서 실제 객체(Runtime)로 만들어 명단(Roster)에 올립니다.
func recruit_hero(data: UnitData) -> void:
	# 이미 있는 영웅인지 체크 (선택 사항, 로직에 따라 다름)
	# 일단은 중복 영입 가능하게 둡니다.
	
	var new_unit = UnitRuntime.new(data)
	GameState.roster.append(new_unit)
	print("📢 [영입] %s 동료가 로스터에 합류했습니다. (현재 로스터: %d명)" % [data.name, GameState.roster.size()])

# --- 2. 파티 편성 (Add to Party) ---
# 대기 중인 동료를 전투 파티에 넣습니다.
func add_to_party(unit: UnitRuntime) -> bool:
	# 예외 처리: 이미 파티에 있는가?
	if unit in GameState.party:
		print("⚠️ [편성 실패] 이미 파티에 있는 동료입니다.")
		return false
	
	# 예외 처리: 파티가 꽉 찼는가?
	if GameState.party.size() >= MAX_PARTY_SIZE:
		print("⚠️ [편성 실패] 파티가 꽉 찼습니다. (최대 %d명)" % MAX_PARTY_SIZE)
		return false
		
	GameState.party.append(unit)
	print("⚔️ [전투 배치] %s 출전! (현재 파티: %d/%d)" % [unit.def.name, GameState.party.size(), MAX_PARTY_SIZE])
	return true

# --- 3. 파티 제외 (Remove from Party) ---
# 전투 파티에서 뺍니다 (로스터에는 남음).
func remove_from_party(unit: UnitRuntime) -> void:
	if unit in GameState.party:
		GameState.party.erase(unit)
		print("💤 [휴식] %s 파티에서 제외됨." % unit.def.name)

# --- 4. 해고 (Fire) ---
# 아예 로스터에서 날려버립니다. (장비 해제 등은 추후 구현)
func fire_hero(unit: UnitRuntime) -> void:
	if unit in GameState.party:
		remove_from_party(unit) # 파티에 있다면 먼저 뺌
	
	if unit in GameState.roster:
		GameState.roster.erase(unit)
		print("👋 [해고] %s... 잘 가시게." % unit.def.name)
