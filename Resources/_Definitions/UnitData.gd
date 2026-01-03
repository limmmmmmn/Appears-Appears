extends BattleStats  # 부모 상속 확인!
class_name UnitData

# --- [1] 고유 정보 ---
@export_group("Identity")
@export var id: String = ""
@export var name: String = "Unknown" # [복구 완료] 이제 에러 안 납니다!
@export var texture: Texture2D

# --- [2] 성장 정보 ---
@export_group("Growth")
@export var level: int = 1
@export var current_exp: int = 0
@export var exp_to_next_level: int = 100

# --- [3] 상태 정보 ---
# (max_hp, attack_power 등은 부모 BattleStats에 있으므로 여기엔 안 적습니다)
@export var current_hp: int = 100

# --- [4] 장비 슬롯 (NEW) ---
@export_group("Equipment")
@export var equip_weapon: ItemData
@export var equip_armor: ItemData
@export var equip_accessory: ItemData

# ---------------------------------------------------------
# [핵심] 스탯 합산 로직 (기본 스탯 + 장비 스탯)
# ---------------------------------------------------------

# 1. 최종 공격력
func get_total_attack() -> int:
	var total = attack_power
	if equip_weapon: total += equip_weapon.bonus_attack
	if equip_armor: total += equip_armor.bonus_attack
	if equip_accessory: total += equip_accessory.bonus_attack
	return total

# 2. 최종 방어력
func get_total_defense() -> int:
	var total = base_defense
	if equip_weapon: total += equip_weapon.bonus_defense
	if equip_armor: total += equip_armor.bonus_defense
	if equip_accessory: total += equip_accessory.bonus_defense
	return total

# 3. 최종 최대 체력
func get_total_max_hp() -> int:
	var total = max_hp
	if equip_weapon: total += equip_weapon.bonus_hp
	if equip_armor: total += equip_armor.bonus_hp
	if equip_accessory: total += equip_accessory.bonus_hp
	return total

# 4. 최종 민첩성
func get_total_agility() -> float:
	var total = agility
	if equip_weapon: total += equip_weapon.bonus_agility
	if equip_armor: total += equip_armor.bonus_agility
	if equip_accessory: total += equip_accessory.bonus_agility
	return total

# ---------------------------------------------------------
# [전투 및 성장 로직]
# ---------------------------------------------------------

func is_dead() -> bool:
	return current_hp <= 0

func take_damage(amount: int) -> int:
	# 방어력 계산 시 장비 빨 적용!
	var final_defense = get_total_defense()
	var final_damage = max(1, amount - final_defense)
	
	current_hp = max(0, current_hp - final_damage)
	return final_damage

func sync_hp(new_hp: int):
	current_hp = new_hp
	# 최대 체력 넘지 않게 보정 (장비 체력 포함)
	var limit = get_total_max_hp()
	if current_hp > limit:
		current_hp = limit

func gain_exp(amount: int):
	current_exp += amount
	while current_exp >= exp_to_next_level:
		current_exp -= exp_to_next_level
		level_up()

func level_up():
	level += 1
	exp_to_next_level = int(exp_to_next_level * 1.5)
	
	# 기본 스탯 성장
	max_hp += 10
	attack_power += 2
	
	# 체력 풀 회복 (장비 빨 포함)
	current_hp = get_total_max_hp()
	
	print(name + " 레벨 업! Lv." + str(level))
