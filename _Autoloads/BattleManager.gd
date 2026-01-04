extends Node

# 전투 윈도우 씬 미리 로드
const BATTLE_WINDOW_SCENE_PATH = "res://Scenes/Battle/BattleWindow.tscn"
var battle_window_scene: PackedScene

# [추가됨] 전투 창들을 담을 전용 캔버스 레이어
var battle_canvas: CanvasLayer

func _ready() -> void:
	# 1. 씬 로드
	if ResourceLoader.exists(BATTLE_WINDOW_SCENE_PATH):
		battle_window_scene = load(BATTLE_WINDOW_SCENE_PATH)

	# 2. [핵심] 전투 UI 전용 CanvasLayer 생성
	# 이 레이어에 자식으로 추가되는 모든 노드는 카메라 움직임과 무관하게 화면에 고정됩니다.
	battle_canvas = CanvasLayer.new()
	battle_canvas.layer = 10 # HUD보다 위에 뜨거나 아래에 뜨게 조절 (기본 1)
	battle_canvas.name = "BattleCanvas"
	add_child(battle_canvas) # 매니저의 자식으로 등록

func start_battle(enemy_actor: Node) -> void:
	var enemy_data: UnitData = null
	if enemy_actor.get("host_unit_data"):
		enemy_data = enemy_actor.host_unit_data
	
	if enemy_data == null or battle_window_scene == null: return
	
	# 임시 플레이어 데이터
	var player_data = load("res://Data/Units/Hero.tres") 

	# 3. 윈도우 생성
	var window = battle_window_scene.instantiate()
	
	# [수정됨] current_scene 대신 battle_canvas에 추가!
	# 이제 월드 좌표가 아니라 화면(Screen) 좌표계를 따릅니다.
	battle_canvas.add_child(window)
	
	# 4. 위치 랜덤 배치
	_set_random_window_position(window)
	
	# 데이터 주입
	if window.has_method("setup"):
		window.setup(player_data, enemy_data)
	
	# 로그 및 적 삭제
	SignalBus.on_battle_started.emit(enemy_actor)
	SignalBus.on_log_message.emit("🔥 %s와 전투 시작!" % enemy_data.name, Color.ORANGE)
	enemy_actor.queue_free()

func _set_random_window_position(window: Control) -> void:
	# CanvasLayer 위이므로 뷰포트(화면) 크기 기준 좌표가 곧 위치입니다.
	var viewport_rect = get_viewport().get_visible_rect()
	
	# 창 크기 (Custom Minimum Size가 설정되어 있다면 그 값을 참조)
	# 아직 생성 직후라 size가 0일 수 있으므로 예상 크기나 min_size 사용
	var win_size = window.custom_minimum_size 
	if win_size == Vector2.ZERO:
		win_size = Vector2(200, 260) # 기본값
	
	# 화면 밖으로 나가지 않게 안전 구역 계산
	var safe_x = viewport_rect.size.x - win_size.x
	var safe_y = viewport_rect.size.y - win_size.y
	
	window.position = Vector2(
		randf_range(0, safe_x),
		randf_range(0, safe_y)
	)
