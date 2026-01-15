# scripts/enemies/Boss.gd
# 보스 전용! 더 강하고 특수 패턴!
extends CharacterBody2D

# 보스 데이터
var boss_data: Dictionary = {}
var boss_id: String = ""

# 스탯 (일반 적보다 강함!)
var current_hp: int = 500
var max_hp: int = 500
var attack: int = 25
var defense: int = 10
var move_speed: float = 60.0

# AI 상태
enum State { IDLE, CHASE, ATTACK, SPECIAL }
var current_state: State = State.CHASE

# 플레이어 참조
var player: Node2D = null

# 특수 공격 타이머
var special_timer: float = 0.0
var special_cooldown: float = 10.0

# 전투 시작 여부
var battle_started: bool = false

# Area2D 참조
@onready var hitbox: Area2D = $Hitbox

func _ready():
	print("[BOSS] Spawned: ", boss_id)
	
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	await get_tree().create_timer(0.5).timeout
	find_player()
	
	# 보스 등장 연출
	spawn_effect()

func _physics_process(delta):
	if battle_started:
		return
	
	# 특수 공격 타이머
	special_timer += delta
	
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.CHASE:
			chase_player()
		State.ATTACK:
			velocity = Vector2.ZERO
		State.SPECIAL:
			perform_special_attack()
	
	move_and_slide()
	
	# 특수 공격 체크
	if special_timer >= special_cooldown:
		special_timer = 0.0
		current_state = State.SPECIAL

func chase_player():
	if player:
		var direction = (player.global_position - global_position).normalized()
		velocity = direction * move_speed

func perform_special_attack():
	# 특수 공격 후 다시 추격
	print("[BOSS] Special Attack!")
	
	# TODO: 특수 패턴 구현
	# 예: 범위 공격, 소환, 돌진 등
	
	current_state = State.CHASE

# ========================================
# 충돌 & 전투
# ========================================

func _on_hitbox_body_entered(body):
	if battle_started:
		return
	
	if body.is_in_group("player") or body.name == "Player":
		start_boss_battle(body)

func start_boss_battle(player_body):
	if battle_started:
		return
	
	battle_started = true
	
	print("\n=== BOSS BATTLE! ===")
	print("  %s (HP: %d)" % [boss_data.get("name", "BOSS"), max_hp])
	
	# 보스 전투창 생성
	var battle_window = preload("res://scenes/ui/BossBattleWindow.tscn").instantiate()
	battle_window.name = "BossBattle_" + str(get_instance_id())
	
	var canvas = get_tree().root.get_node_or_null("BattleCanvas")
	if not canvas:
		canvas = CanvasLayer.new()
		canvas.name = "BattleCanvas"
		canvas.layer = 100
		get_tree().root.add_child(canvas)
	
	canvas.add_child(battle_window)
	
	# 전투 초기화
	battle_window.init_boss_battle(boss_data, str(get_instance_id()))
	
	# 중앙 배치 (더 큰 창)
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	battle_window.position = Vector2(
		viewport_size.x / 2 - 250,
		viewport_size.y / 2 - 200
	)
	
	# 보스 숨김
	visible = false
	
	# 승리/패배 대기
	EventBus.battle_victory.connect(_on_boss_defeated, CONNECT_ONE_SHOT)

func _on_boss_defeated():
	print("[BOSS] Defeated!")
	queue_free()

# ========================================
# 초기화
# ========================================

func init_boss(data: Dictionary):
	boss_data = data
	boss_id = data.get("id", "")
	
	if data.has("base_stats"):
		var stats = data.base_stats
		max_hp = stats.get("hp", 500)
		current_hp = max_hp
		attack = stats.get("attack", 25)
		defense = stats.get("defense", 10)
		move_speed = stats.get("attack_speed", 0.5) * 100.0
	
	# 스테이지 배율 적용
	var multiplier = StageManager.get_enemy_stats_multiplier()
	max_hp = int(max_hp * multiplier)
	current_hp = max_hp
	attack = int(attack * multiplier)
	defense = int(defense * multiplier)
	
	print("  Boss Stats: HP=%d ATK=%d DEF=%d" % [max_hp, attack, defense])

func find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

# ========================================
# 등장 연출
# ========================================

func spawn_effect():
	# 스케일 애니메이션
	scale = Vector2(0.1, 0.1)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.5, 1.5), 0.5)
	tween.tween_property(self, "scale", Vector2(1, 1), 0.2)
	
	# 경고 메시지
	print("⚠️ WARNING: BOSS APPROACHING! ⚠️")
