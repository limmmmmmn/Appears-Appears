extends Resource
class_name UnitData

# --- 기본 속성 (Base Stats) [설계도 70-75] ---
@export var name: String
@export var job_class: GameConstants.JobClass
@export var base_stats: Dictionary = {"hp": 100, "atk": 10, "def": 0}
@export var sprite: Texture2D
@export var skills: Array[SkillData] # [설계도 75] 이제 에러 안 남!

# --- 상태 (Runtime) [설계도 76-78] ---
var current_hp: int
var equipment: Dictionary = {} # Slot Type -> ItemData

# --- 시그널 (Signals) [설계도 81, 네이밍 사전 29-34] ---
signal hp_changed(current_hp: int, max_hp: int)
signal dead()
signal on_damage_taken()
signal on_attack()
signal xp_gained(amount: int)       # [네이밍 사전 33]
signal level_up(new_level: int)     # [네이밍 사전 34]

# --- 초기화 ---
func _init() -> void:
	# 안전한 초기화를 위해 기본값 설정
	if base_stats.has("hp"):
		current_hp = base_stats["hp"]
	else:
		current_hp = 1

# --- 함수 ---
# [설계도 80]
func get_total_stat(stat_name: String) -> int:
	var total = base_stats.get(stat_name, 0)
	
	# 장비 스탯 합산 (Equipment가 구현되면 작동)
	for slot in equipment:
		var item: ItemData = equipment[slot]
		if item and item.stat_bonuses.has(stat_name):
			total += item.stat_bonuses[stat_name]
			
	return total

# [설계도 156 관련] 데미지 받는 로직 미리 구현
func take_damage(amount: int) -> void:
	var actual_damage = clampi(amount - get_total_stat("def"), 1, 9999)
	current_hp = clampi(current_hp - actual_damage, 0, get_total_stat("hp"))
	
	on_damage_taken.emit()
	hp_changed.emit(current_hp, get_total_stat("hp"))
	
	if current_hp <= 0:
		dead.emit()
