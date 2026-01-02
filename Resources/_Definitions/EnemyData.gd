extends BattleStats  # <--- [핵심] BattleStats의 모든 기능(HP, Agility 등)을 물려받음
class_name EnemyData

# --- [1. 정체성 (Visuals)] ---
# 에너미 스폰 시 Sprite에 입힐 텍스처와 UI에 띄울 이름입니다.
@export_group("Identity")
@export var name: String = "Monster"
@export var texture: Texture2D 

# --- [2. 보상 (Rewards)] ---
# 적을 처치했을 때 줄 보상입니다.
@export_group("Rewards")
@export var drop_gold: int = 10
@export var drop_exp: int = 5
@export var drop_items: Array[Resource] = [] # (선택사항) 아이템 드랍 테이블

# --- [3. 행동 패턴 (AI & Movement)] ---
# 이동 속도나 감지 범위도 여기서 관리하면, 몬스터별로 튜닝하기 편합니다.
@export_group("AI Settings")
@export var move_speed: float = 30.0       # 기본 배회 속도
@export var chase_speed: float = 80.0      # 추격 속도
@export var aggression: float = 1.0        # 공격성 (높을수록 더 멀리서 반응하거나 자주 때림)
@export var wander_radius: float = 50.0    # 배회 반경

# ---------------------------------------------------------
# [주의] 아래 변수들은 BattleStats(부모)에 이미 있으므로 
# 여기서 또 적으면 안 됩니다! (모두 삭제 확인)
# ---------------------------------------------------------
# var max_hp      <-- (삭제됨: 부모에게 있음)
# var attack_power <-- (삭제됨: 부모에게 있음)
# var agility     <-- (삭제됨: 부모에게 있음)
# ---------------------------------------------------------
