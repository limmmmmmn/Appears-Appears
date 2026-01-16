extends CanvasLayer
class_name BattleManager
## 다중 전투창 관리 - 랜덤 위치 배치

var battle_window_scene: PackedScene = preload("res://scenes/ui/battle_window.tscn")
var battle_hud_scene: PackedScene = preload("res://scenes/ui/battle_hud.tscn")

var active_windows: Array = []
var hud: BattleHUD = null

const WINDOW_SIZE := Vector2(180, 140)
const SCREEN_SIZE := Vector2(640, 360)
const CENTER_AVOID := Rect2(190, 85, 100, 100)  # 중앙 회피
const MARGIN := 8
const HUD_HEIGHT := 0  # 하단 HUD 공간


func _ready() -> void:
	GameManager.battle_started.connect(_on_battle_started)
	_setup_hud()


func _setup_hud() -> void:
	hud = battle_hud_scene.instantiate() as BattleHUD
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
	window.party_updated.connect(_on_party_updated)
	
	window.start_battle(enemy_id)


func _get_random_position() -> Vector2:
	_cleanup_windows()
	
	var max_attempts = 50
	var max_y = SCREEN_SIZE.y - WINDOW_SIZE.y - HUD_HEIGHT - MARGIN
	
	for i in range(max_attempts):
		var x = randf_range(MARGIN, SCREEN_SIZE.x - WINDOW_SIZE.x - MARGIN)
		var y = randf_range(MARGIN, max_y)
		var pos = Vector2(x, y)
		
		var window_rect = Rect2(pos, WINDOW_SIZE)
		
		# 중앙 회피
		if window_rect.intersects(CENTER_AVOID):
			continue
		
		# 다른 창과 겹침 방지
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


func _on_party_updated(party_hp: Dictionary, party_cooldowns: Dictionary, max_cooldowns: Dictionary) -> void:
	if hud:
		hud.update_party_status(party_hp, party_cooldowns, max_cooldowns)
