extends Control
class_name LootAnimationUI
## 아이템 획득 애니메이션: 전투창에서 인벤토리로 날아가는 연출
## Loop Hero 스타일 - 아이템이 팝업되고 커브를 그리며 인벤토리로 이동

signal animation_completed(item_id: String)

# === 아이템 정보 ===
var item_id: String = ""
var item_data: Dictionary = {}

# === 애니메이션 상태 ===
var start_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO
var control_point: Vector2 = Vector2.ZERO  # 베지어 곡선용

var animation_time: float = 0.0
var animation_duration: float = 0.6  # 총 애니메이션 시간

# 단계: popup -> fly -> shrink
enum AnimState { POPUP, FLY, SHRINK, DONE }
var current_state: AnimState = AnimState.POPUP

var popup_duration: float = 0.25  # 팝업 시간
var fly_duration: float = 0.3     # 날아가는 시간
var shrink_duration: float = 0.1  # 축소 시간

# === UI 요소 ===
var icon_label: Label
var name_label: Label
var glow_panel: Panel

# === 등급 색상 ===
const RARITY_COLORS: Dictionary = {
	"common": Color(0.7, 0.7, 0.7),      # 회색
	"uncommon": Color(0.4, 0.8, 0.4),    # 초록
	"magic": Color(0.4, 0.6, 1.0),       # 파랑
	"rare": Color(0.8, 0.5, 1.0),        # 보라
	"epic": Color(1.0, 0.5, 0.2),        # 주황
	"legendary": Color(1.0, 0.8, 0.2),   # 금색
}

const RARITY_GLOW: Dictionary = {
	"common": Color(0.5, 0.5, 0.5, 0.3),
	"uncommon": Color(0.3, 0.6, 0.3, 0.4),
	"magic": Color(0.3, 0.5, 1.0, 0.5),
	"rare": Color(0.6, 0.4, 0.8, 0.5),
	"epic": Color(1.0, 0.4, 0.1, 0.6),
	"legendary": Color(1.0, 0.7, 0.1, 0.7)
}

const TYPE_ICONS: Dictionary = {
	"sword": "🗡️", "dagger": "🔪", "axe": "🪓", "staff": "🪄", "bow": "🏹",
	"shield": "🛡️", "helmet": "⛑️", "light_armor": "👘", "medium_armor": "🦺",
	"heavy_armor": "🛡️", "robe": "👗", "ring": "💍", "necklace": "📿", "shoes": "👟"
}

const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️", "off_hand": "🛡️", "head": "👑", "body": "👕", "shoes": "👟", "necklace": "📿", "ring1": "💍", "ring2": "💍"
}


func _ready() -> void:
	set_process(false)
	visible = false
	z_index = 100  # 최상위에 표시


func setup(p_item_id: String, p_start_pos: Vector2, p_target_pos: Vector2) -> void:
	## 애니메이션 초기화
	item_id = p_item_id
	start_pos = p_start_pos
	target_pos = p_target_pos
	
	# 데이터 로드
	item_data = DataManager.get_equipment(item_id)
	if item_data.is_empty():
		item_data = DataManager.get_item(item_id)
	
	if item_data.is_empty():
		queue_free()
		return
	
	# 베지어 곡선 컨트롤 포인트 (위로 휘어지는 곡선)
	var mid_x: float = (start_pos.x + target_pos.x) / 2
	var mid_y: float = min(start_pos.y, target_pos.y) - 80  # 위로 볼록
	control_point = Vector2(mid_x, mid_y)
	
	# UI 구성
	_create_ui()
	
	# 시작 위치 설정 (팝업 시작)
	global_position = start_pos
	scale = Vector2(0.1, 0.1)
	modulate.a = 0.0
	
	visible = true
	current_state = AnimState.POPUP
	animation_time = 0.0
	set_process(true)


func _create_ui() -> void:
	## 아이템 표시 UI 생성
	var rarity: String = str(item_data.get("rarity", "common"))
	var item_type: String = str(item_data.get("type", ""))
	var item_slot: String = str(item_data.get("slot", ""))
	var item_name: String = str(item_data.get("name", item_id))
	
	# 아이콘 결정
	var icon: String = TYPE_ICONS.get(item_type, "")
	if icon.is_empty():
		icon = SLOT_ICONS.get(item_slot, "📦")
	
	# 컨테이너
	var container := VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(container)
	
	# 글로우 배경 (Panel) - 작은 크기
	glow_panel = Panel.new()
	glow_panel.custom_minimum_size = Vector2(24, 24)
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = RARITY_GLOW.get(rarity, RARITY_GLOW["common"])
	glow_style.corner_radius_top_left = 4
	glow_style.corner_radius_top_right = 4
	glow_style.corner_radius_bottom_left = 4
	glow_style.corner_radius_bottom_right = 4
	glow_panel.add_theme_stylebox_override("panel", glow_style)
	container.add_child(glow_panel)

	# 아이콘 라벨 (글로우 위에) - 작은 크기
	icon_label = Label.new()
	icon_label.text = icon
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	icon_label.anchors_preset = Control.PRESET_CENTER
	icon_label.position = Vector2(-6, -8)
	glow_panel.add_child(icon_label)

	# 이름 라벨 - 작은 크기
	name_label = Label.new()
	name_label.text = item_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 6)
	name_label.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	name_label.custom_minimum_size = Vector2(30, 0)
	container.add_child(name_label)

	# 컨테이너 중앙 정렬을 위한 오프셋
	container.position = Vector2(-15, -18)


func _process(delta: float) -> void:
	animation_time += delta
	
	match current_state:
		AnimState.POPUP:
			_process_popup(delta)
		AnimState.FLY:
			_process_fly(delta)
		AnimState.SHRINK:
			_process_shrink(delta)
		AnimState.DONE:
			_finish_animation()


func _process_popup(_delta: float) -> void:
	## 팝업 단계: 스케일업 + 페이드인 + 살짝 위로
	var t: float = clampf(animation_time / popup_duration, 0.0, 1.0)
	
	# 이징: 탄성 효과
	var eased_t: float = _ease_out_back(t)
	
	# 스케일 (0.1 -> 1.2 -> 1.0 느낌)
	scale = Vector2.ONE * lerpf(0.1, 1.0, eased_t)
	
	# 페이드인
	modulate.a = lerpf(0.0, 1.0, minf(t * 2.0, 1.0))
	
	# 살짝 위로 이동
	global_position = start_pos + Vector2(0, lerpf(0, -20, eased_t))
	
	# 글로우 펄스
	if glow_panel:
		var pulse: float = sin(animation_time * 10.0) * 0.2 + 0.8
		glow_panel.modulate.a = pulse
	
	if t >= 1.0:
		current_state = AnimState.FLY
		animation_time = 0.0


func _process_fly(_delta: float) -> void:
	## 날아가는 단계: 베지어 곡선으로 인벤토리로 이동
	var t: float = clampf(animation_time / fly_duration, 0.0, 1.0)
	
	# 이징: 부드러운 가속
	var eased_t: float = _ease_in_out_quad(t)
	
	# 베지어 곡선 위치 계산
	global_position = _quadratic_bezier(start_pos + Vector2(0, -20), control_point, target_pos, eased_t)
	
	# 날아가면서 살짝 회전
	rotation_degrees = sin(t * PI * 2) * 15.0
	
	# 글로우 펄스 유지
	if glow_panel:
		var pulse: float = sin(animation_time * 12.0) * 0.3 + 0.7
		glow_panel.modulate.a = pulse
	
	if t >= 1.0:
		current_state = AnimState.SHRINK
		animation_time = 0.0
		rotation_degrees = 0.0


func _process_shrink(_delta: float) -> void:
	## 축소 단계: 인벤토리에 흡수되는 느낌
	var t: float = clampf(animation_time / shrink_duration, 0.0, 1.0)
	
	# 스케일 축소
	scale = Vector2.ONE * lerpf(1.0, 0.2, t)
	
	# 페이드아웃
	modulate.a = lerpf(1.0, 0.0, t)
	
	if t >= 1.0:
		current_state = AnimState.DONE


func _finish_animation() -> void:
	set_process(false)
	animation_completed.emit(item_id)
	queue_free()


#region 수학 유틸리티
func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	## 2차 베지어 곡선
	var q0: Vector2 = p0.lerp(p1, t)
	var q1: Vector2 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


func _ease_out_back(t: float) -> float:
	## 탄성 효과 (살짝 튀어나갔다 돌아오는)
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)


func _ease_in_out_quad(t: float) -> float:
	## 부드러운 가속/감속
	if t < 0.5:
		return 2.0 * t * t
	else:
		return 1.0 - pow(-2.0 * t + 2.0, 2) / 2.0
#endregion
