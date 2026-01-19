extends CanvasLayer
class_name BattleManager
## 다중 전투창 관리 - 랜덤 위치 배치

var battle_window_scene: PackedScene = preload("res://scenes/ui/battle_window.tscn")
var game_hud_scene: PackedScene = preload("res://scenes/ui/game_hud.tscn")

var active_windows: Array = []
var hud: GameHUD = null

const WINDOW_SIZE := Vector2(170, 95)
const SCREEN_SIZE := Vector2(640, 360)
const HUD_PANEL_WIDTH := 160
const MARGIN := 8

var play_area: Rect2
var center_point: Vector2  # 가운데 점


func _ready() -> void:
	GameManager.battle_started.connect(_on_battle_started)
	GameManager.register_battle_manager(self)
	
	# 필드 영역 (HUD 제외)
	var field_width = SCREEN_SIZE.x - HUD_PANEL_WIDTH
	
	play_area = Rect2(
		MARGIN,
		MARGIN,
		field_width - WINDOW_SIZE.x - MARGIN * 2,
		SCREEN_SIZE.y - WINDOW_SIZE.y - MARGIN * 2
	)
	
	# 가운데 점 (창 중심 기준)
	center_point = Vector2(
		field_width / 2 - WINDOW_SIZE.x / 2,
		SCREEN_SIZE.y / 2 - WINDOW_SIZE.y / 2
	)
	
	print("[BattleManager] play_area: ", play_area)
	print("[BattleManager] center_point: ", center_point)
	
	_setup_hud()


func _setup_hud() -> void:
	hud = game_hud_scene.instantiate() as GameHUD
	add_child(hud)


func _on_battle_started(enemy_id: String) -> void:
	_spawn_battle_window(enemy_id)


func _spawn_battle_window(enemy_id: String) -> void:
	var window = battle_window_scene.instantiate() as BattleWindow
	
	var pos = _get_random_position()
	window.position = pos
	
	add_child(window)
	active_windows.append(window)
	
	window.battle_finished.connect(_on_battle_finished.bind(window))
	window.log_message.connect(_on_log_message)
	
	window.start_battle(enemy_id)


func _get_random_position() -> Vector2:
	_cleanup_windows()
	
	var max_attempts = 100
	
	for i in range(max_attempts):
		var x = randf_range(play_area.position.x, play_area.position.x + play_area.size.x)
		var y = randf_range(play_area.position.y, play_area.position.y + play_area.size.y)
		var pos = Vector2(x, y)
		
		# 가운데 50x50 영역 체크 (창 중심 기준)
		var dist_to_center = pos.distance_to(center_point)
		if dist_to_center < 50:
			continue
		
		var window_rect = Rect2(pos, WINDOW_SIZE)
		
		# 기존 창과 겹침 체크
		var overlaps = false
		for w in active_windows:
			if is_instance_valid(w):
				var other_rect = Rect2(w.position, WINDOW_SIZE)
				if window_rect.intersects(other_rect):
					overlaps = true
					break
		
		if not overlaps:
			return pos
	
	print("[BattleManager] 위치 찾기 실패!")
	return Vector2(play_area.position.x, play_area.position.y)


func _cleanup_windows() -> void:
	var valid = []
	for w in active_windows:
		if is_instance_valid(w):
			valid.append(w)
	active_windows = valid


func _on_battle_finished(victory: bool, window: BattleWindow) -> void:
	active_windows.erase(window)


func _on_log_message(text: String) -> void:
	if hud:
		hud.add_log(text)
