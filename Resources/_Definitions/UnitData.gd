# res://Resources/UnitData.gd
extends BattleStats  # 상속 선언!
class_name UnitData

# --- [고유 정보] ---
# BattleStats에는 없는, UnitData만의 정보들
@export_group("Identity")
@export var id: String = ""
@export var name: String = "Unknown"
@export var texture: Texture2D

@export var level: int = 1
@export var current_exp: int = 0
@export var exp_to_next_level: int = 100

# --- [상태 정보] ---
# max_hp는 부모에게 있으니 지우고, 변하는 값인 current_hp만 남깁니다.
@export var current_hp: int = 100

# ---------------------------------------------------------
# [중요] 아래 변수들은 BattleStats(부모)에 이미 있으므로 
# 여기서 또 적으면 절대 안 됩니다! (모두 삭제하세요)
# ---------------------------------------------------------
# var max_hp      <-- (삭제) 부모꺼 쓸 거임
# var attack_power <-- (삭제) 부모꺼 쓸 거임
# var agility     <-- (삭제) 부모꺼 쓸 거임
# var weapon_speed <-- (삭제) 부모꺼 쓸 거임
# ---------------------------------------------------------

# --- [함수 로직] ---
func is_dead() -> bool:
	return current_hp <= 0

func take_damage(amount: int) -> int:
	# self.attack_power 처럼 'self.'을 붙여도 되고 그냥 써도 부모 변수 인식함
	# 여기선 방어력 계산 로직
	var final_damage = max(1, amount - base_defense) # base_defense는 부모한테서 물려받음
	current_hp = max(0, current_hp - final_damage)
	return final_damage

func sync_hp(new_hp: int):
	current_hp = new_hp
	# 만약 힐을 해서 최대 체력을 넘지 않게 하려면 부모의 max_hp 사용
	if current_hp > max_hp:
		current_hp = max_hp
		
		
# 경험치 획득 로직
func gain_exp(amount: int):
	current_exp += amount
	
	# 레벨업 체크
	while current_exp >= exp_to_next_level:
		current_exp -= exp_to_next_level
		level_up()

func level_up():
	level += 1
	exp_to_next_level = int(exp_to_next_level * 1.5) # 필요 경험치 증가
	
	# 스탯 상승 (예시)
	max_hp += 10
	attack_power += 2
	current_hp = max_hp # 레벨업 시 체력 회복 국룰
	
	print(resource_name + " 레벨 업! Lv." + str(level))
