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
const INVENTORY_HEIGHT := 60
const MARGIN := 8

var play_area: Rect2


func _ready() -> void:
	GameManager.battle_started.connect(_on_battle_started)
	GameManager.register_battle_manager(self)
	
	# 플레이 영역 (우측 HUD, 하단 인벤토리 제외)
	play_area = Rect2(
		MARGIN,
		MARGIN,
		SCREEN_SIZE.x - HUD_PANEL_WIDTH - MARGIN * 2,
		SCREEN_SIZE.y - INVENTORY_HEIGHT - MARGIN * 2
	)
	
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
	
	var max_attempts = 50
	
	for i in range(max_attempts):
		var x = randf_range(play_area.position.x, play_area.end.x - WINDOW_SIZE.x)
		var y = randf_range(play_area.position.y, play_area.end.y - WINDOW_SIZE.y)
		var pos = Vector2(x, y)
		
		var window_rect = Rect2(pos, WINDOW_SIZE)
		
		var overlaps = false
		for w in active_windows:
			if is_instance_valid(w):
				var other_rect = Rect2(w.position, WINDOW_SIZE)
				if window_rect.intersects(other_rect):
					overlaps = true
					break
		
		if not overlaps:
			return pos
	
	return Vector2(MARGIN, MARGIN)


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
