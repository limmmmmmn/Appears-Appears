extends CanvasLayer
## 단일 전투창을 관리하고 적을 추가

var battle_window_scene: PackedScene = preload("res://scenes/ui/battle_window.tscn")
var battle_hud_scene: PackedScene = preload("res://scenes/ui/battle_hud.tscn")

var battle_window: BattleWindow = null
var hud: BattleHUD = null

const WINDOW_POS := Vector2(140, 20)  # 전투창 고정 위치 (상단 중앙)


func _ready() -> void:
	GameManager.battle_started.connect(_on_battle_started)
	_setup_hud()


func _setup_hud() -> void:
	hud = battle_hud_scene.instantiate() as BattleHUD
	add_child(hud)


func _on_battle_started(enemy_id: String) -> void:
	# 전투창이 없으면 생성
	if battle_window == null or not is_instance_valid(battle_window):
		_create_battle_window()
	
	# 적 추가
	battle_window.add_enemy(enemy_id)
	
	# 전투창 크기 조절 (적 수에 따라)
	_resize_window()


func _create_battle_window() -> void:
	battle_window = battle_window_scene.instantiate() as BattleWindow
	battle_window.position = WINDOW_POS
	
	add_child(battle_window)
	
	# 시그널 연결
	battle_window.battle_finished.connect(_on_battle_finished)
	battle_window.log_message.connect(_on_log_message)
	battle_window.party_updated.connect(_on_party_updated)


func _resize_window() -> void:
	if battle_window == null:
		return
	
	# 적 수에 따라 창 너비 조절 (최소 200, 적당 +70)
	var enemy_count = battle_window.get_enemy_count()
	var width = max(200, 70 + enemy_count * 65)
	battle_window.custom_minimum_size = Vector2(width, 110)
	battle_window.size = Vector2(width, 110)
	
	# 중앙 정렬
	battle_window.position.x = (480 - width) / 2


func _on_battle_finished(victory: bool) -> void:
	battle_window = null


func _on_log_message(text: String) -> void:
	if hud:
		hud.add_log(text)


func _on_party_updated(party_hp: Dictionary, party_cooldowns: Dictionary, max_cooldowns: Dictionary) -> void:
	if hud:
		hud.update_party_status(party_hp, party_cooldowns, max_cooldowns)
