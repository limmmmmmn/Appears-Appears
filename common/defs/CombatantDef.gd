class_name CombatantDef
extends Resource

# --------------------------------------------------------
# [기본 데이터]
# --------------------------------------------------------
@export var id: String = ""
@export var display_name: String = ""
@export var tags: Array[String] = []

# [수정 2] 누락되었던 스킬 ID 리스트 복구!
@export var skill_ids: Array[String] = [] 

# [참고] 표준 스탯 키: "hp", "atk", "def", "spd" (팀 표준 준수 요망)
@export var base_stats: Dictionary = {"hp": 100, "atk": 10, "def": 0, "spd": 10}

# --------------------------------------------------------
# [비주얼 설정] - 아군/적군 공통 표준
# --------------------------------------------------------
@export_group("Visual Files")

# [수정 1] *.jpeg 추가 & 따옴표 문법 오류 수정 (인자를 따로 분리)
# 1. 초상화 (Hero: 필수 / Enemy: 보통 비움)
@export_file("*.png", "*.webp", "*.jpg", "*.jpeg") var portrait_path: String = ""

# 2. 필드 유닛 (Hero: 필수 / Enemy: 필수)
@export_file("*.png", "*.webp", "*.jpg", "*.jpeg") var field_sprite_path: String = ""

# 3. 전투 유닛 (Enemy: 비워두면 field_sprite 자동 사용 / Hero: 필요시 override)
@export_file("*.png", "*.webp", "*.jpg", "*.jpeg") var battle_sprite_path: String = ""


# --------------------------------------------------------
# [애니메이션 설정]
# --------------------------------------------------------
@export_group("Visual Settings")
@export_subgroup("Sprite Sheet")
@export var hframes: int = 1        # 가로 프레임 수
@export var vframes: int = 1        # 세로 프레임 수
@export var default_anim: String = "idle" 
@export var anim_fps: float = 8.0   

# [추가 제안 반영] 행(Row)별 애니메이션 매핑 (확장성 대비)
@export var anim_rows: Dictionary = {"idle": 0, "walk": 1, "attack": 2}

@export_subgroup("Transform")
@export var field_scale: Vector2 = Vector2.ONE
@export var field_offset: Vector2 = Vector2.ZERO
@export var battle_scale: Vector2 = Vector2.ONE
@export var battle_offset: Vector2 = Vector2.ZERO


# --------------------------------------------------------
# [로직 표준화] - 외부(UI/필드)에서는 이 함수들만 호출할 것!
# --------------------------------------------------------

## 필드에서 사용할 스프라이트 경로 반환
func get_field_sprite_path() -> String:
	return field_sprite_path

## 전투창에서 사용할 스프라이트 경로 반환 (Fallback + 안전장치)
func get_battle_sprite_path() -> String:
	var p: String = ""
	
	# 1. 전투용 이미지가 있으면 우선 사용
	if battle_sprite_path != "":
		p = battle_sprite_path
	# 2. 없으면 필드용 이미지 재사용
	else:
		p = field_sprite_path
	
	# [수정 3] 둘 다 비어있을 경우 경고 로그 출력 (디버깅용)
	if p == "":
		push_warning("[CombatantDef] '%s' has NO sprite path! (battle/field both empty)" % id)
		
	return p

## 초상화 경로 반환
func get_portrait_path() -> String:
	return portrait_path
