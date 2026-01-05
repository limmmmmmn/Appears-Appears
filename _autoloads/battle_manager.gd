extends Node
# [Blueprint v1.4] 6. 전투 및 UI - 중앙 시야 절대 보존 로직 [cite: 11, 52]

const MAX_ENEMIES: int = 3
const WINDOW_SIZE: Vector2 = Vector2(140, 100)
# 중앙에 절대 창이 들어올 수 없는 구역 (60x60) 
const SAFE_AREA_SIZE: Vector2 = Vector2(40, 40) 

@export var battle_window_scene: PackedScene = preload("res://scenes/ui/windows/battle_window.tscn")

var _active_windows: Array[Control] = []
var _battle_ui_layer: CanvasLayer

func _ready() -> void:
	_battle_ui_layer = CanvasLayer.new()
	_battle_ui_layer.layer = 10 
	add_child(_battle_ui_layer)

func start_battle(source_unit_data: UnitData, spawn_table: SpawnTable) -> void:
	var enemies = _generate_enemy_party(source_unit_data, spawn_table) 
	var battle_instance := BattleInstance.new(enemies)
	var window := battle_window_scene.instantiate() as BattleWindow
	
# 	B. UI 레이어에 추가 및 데이터 주입 [cite: 78]
	_battle_ui_layer.add_child(window)
	window.setup(battle_instance)
	
	# C. 위치 설정 및 트윈 애니메이션 준비
	var target_pos := _find_smart_position()
	window.position = target_pos
	window.size = WINDOW_SIZE
	
	# --- 트윈(Tween) 추가: 팝업 애니메이션 ---
	# 1. 피벗을 중앙으로 설정하여 중앙에서 커지도록 함
	window.pivot_offset = WINDOW_SIZE / 2
	window.scale = Vector2.ZERO
	
	var tween = create_tween()
	# TRANS_BACK과 EASE_OUT을 사용하면 약간 더 커졌다가 돌아오는 "탄력" 효과가 생깁니다.
	tween.tween_property(window, "scale", Vector2.ONE, 0.25)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	
	_active_windows.append(window)
	
	_active_windows.append(window)
	get_tree().create_timer(1.0).timeout.connect(func(): _end_battle(window))

func _end_battle(window: BattleWindow) -> void:
	if window in _active_windows:
		_active_windows.erase(window)
	window.queue_free()

# --- 5. 스마트 레이아웃 (중앙 침범 절대 방어) ---
func _find_smart_position() -> Vector2:
	var screen := get_viewport().get_visible_rect().size
	var center := screen / 2
	# 중앙 세이프존 사각형 정의
	var safe_rect := Rect2(center - (SAFE_AREA_SIZE / 2), SAFE_AREA_SIZE)
	
	# 탐색 범위 (화면 밖 20px까지 허용하여 골고루 분산)
	var m: float = 10.0
	var min_x = -m
	var max_x = screen.x - WINDOW_SIZE.x + m
	var min_y = -m
	var max_y = screen.y - WINDOW_SIZE.y + m

	# 1단계: 최상 (세이프존 회피 + 창 겹침 없음)
	for i in range(80):
		var pos = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		var test_rect := Rect2(pos, WINDOW_SIZE)
		
		# [절대 규칙] 세이프존과 조금이라도 겹치면 즉시 탈락
		if test_rect.intersects(safe_rect): continue
		
		# 다른 창과 겹침 확인 (5px 여유)
		if not _is_overlapping_others(test_rect, 5):
			return pos

	# 2단계: 차선 (세이프존 회피 + 약간의 창 겹침 허용)
	for i in range(50):
		var pos = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		var test_rect := Rect2(pos, WINDOW_SIZE)
		
		# [절대 규칙] 세이프존 회피는 여기서도 반드시 유지
		if test_rect.intersects(safe_rect): continue
		return pos

	# 3단계: 폴백 (세이프존을 피한 가장 먼 외곽)
	return _get_safe_fallback(screen, center, safe_rect)

# 다른 창들과의 겹침 여부만 체크하는 헬퍼
func _is_overlapping_others(rect: Rect2, margin: float) -> bool:
	for win in _active_windows:
		if is_instance_valid(win) and rect.intersects(win.get_global_rect().grow(margin)):
			return true
	return false

# 어떤 상황에서도 세이프존을 침범하지 않는 폴백 좌표
func _get_safe_fallback(screen: Vector2, center: Vector2, safe_rect: Rect2) -> Vector2:
	for i in range(20):
		var angle = randf_range(0, TAU)
		# 세이프존 밖으로 충분히 밀어냄
		var pos = center + Vector2.from_angle(angle) * 120.0 - (WINDOW_SIZE / 2)
		if not Rect2(pos, WINDOW_SIZE).intersects(safe_rect):
			return pos
	return Vector2.ZERO # 이론상 도달 불가

# --- 6. 적 파티 생성 로직 (기존 유지) ---
func _generate_enemy_party(source: UnitData, table: SpawnTable) -> Array[UnitRuntime]:
	var party: Array[UnitRuntime] = []
	var total_count: int = randi_range(1, MAX_ENEMIES)
	var source_count: int = ceil(total_count / 2.0)
	var random_count: int = total_count - source_count
	for i in range(source_count): party.append(UnitRuntime.new(source))
	for i in range(random_count):
		var next_data: UnitData = source
		if table:
			var rolled := _pick_weighted_squared(table)
			if rolled: next_data = rolled
		party.append(UnitRuntime.new(next_data))
	return party

func _pick_weighted_squared(table: SpawnTable) -> UnitData:
	var total_weight: float = 0.0
	var squared_entries: Array[Dictionary] = []
	for entry in table.entries:
		if entry.unit:
			var sq_w: float = entry.weight * entry.weight
			squared_entries.append({"unit": entry.unit, "weight": sq_w})
			total_weight += sq_w
	if total_weight == 0: return null
	var rnd := randf() * total_weight
	var current: float = 0.0
	for item in squared_entries:
		current += item.weight
		if rnd < current: return item.unit
	return null
