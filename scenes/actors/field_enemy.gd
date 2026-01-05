class_name FieldEnemy extends CharacterBody2D
# [Blueprint v1.4] 5. 액터 카드 - 필드 에너미

# 런타임 객체 (HP, 상태 등 관리)
var _runtime: UnitRuntime
# 타겟 (플레이어) 추적용
var _target: Node2D
# [Blueprint v1.4] 5. 액터 카드 - 필드 에너미 [cite: 41]
var _spawn_table: SpawnTable # 추가: 나중에 BattleManager에 넘겨줄 테이블 저장

@onready var sprite_2d: Sprite2D = $Sprite2D

# setup 함수의 매개변수 개수를 4개로 맞춰줍니다.
func setup(data: UnitData, spawn_position: Vector2, target: Node2D, table: SpawnTable) -> void:
	position = spawn_position
	_target = target
	_spawn_table = table # 주입받은 테이블 저장 
	
	# 런타임 객체 생성 [cite: 33, 34]
	_runtime = UnitRuntime.new(data)
	
	# 비주얼 적용
	if _runtime.get_texture():
		sprite_2d.texture = _runtime.get_texture()
	
	name = data.name

func _physics_process(_delta: float) -> void:
	if not _target: return
	
	# 간단한 추적 AI
	var direction = global_position.direction_to(_target.global_position)
	
	# UnitRuntime을 통해 데이터(속도) 참조
	velocity = direction * _runtime.get_speed()
	
	# 이동 전 바라보는 방향 업데이트 추가
	_update_facing_direction()
	
	move_and_slide()
	
	# 플레이어와 충돌 체크
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		if body.is_in_group("player"):
			_on_encounter()
			break
			
	

# --- 신규 추가 함수 ---
func _update_facing_direction() -> void:
	# 스프라이트 기본 방향이 '왼쪽' 기준
	if velocity.x > 0:
		# 오른쪽으로 이동 중 -> 뒤집기
		sprite_2d.flip_h = true
	elif velocity.x < 0:
		# 왼쪽으로 이동 중 -> 원래대로
		sprite_2d.flip_h = false

func _on_encounter() -> void:
	# [Blueprint v1.4] 8. 핵심 로직 흐름 - Encounter & Request
	# 원본 데이터와 스폰 테이블을 넘겨줌
	BattleManager.start_battle(_runtime._data, _spawn_table)
	
	# "필드위의 적은 전투창이 생성됨과 동시에 사라지게 하고"
	queue_free()
