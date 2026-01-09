class_name UnitData
extends Resource

# --- 기본 정보 ---
@export_group("Identity") # 인스펙터에서 보기 좋게 그룹 묶기
@export var id: String = ""
@export var name: String = ""
@export var job_name: String = "전사" # 직업명 (예: 전사, 마법사)

# --- 비주얼 (Visuals) --- ✨ 여기가 추가되었습니다!
@export_group("Visuals")
@export var face_icon: Texture2D       # 대화창, UI에 쓸 얼굴 사진
@export var field_sprite: SpriteFrames # 필드에서 뽈뽈거리고 다닐 캐릭터 애니메이션

# --- 스탯 (Stats) ---
@export_group("Stats")
@export var base_hp: int = 100
@export var base_atk: int = 10
@export var base_def: int = 0
@export var speed: int = 10
@export var magic_speed: int = 10
@export var luck: int = 0
