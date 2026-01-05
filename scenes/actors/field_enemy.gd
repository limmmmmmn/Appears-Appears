class_name FieldEnemy extends CharacterBody2D
# [Blueprint v1.4] 5. 액터 카드 - 필드 에너미

# 런타임 객체 (HP, 상태 등 관리)
var _runtime: UnitRuntime

# 타겟 (플레이어) 추적용
var _target: Node2D

@onready var sprite_2d: Sprite2D = $Sprite2D

# 스포너가 생성 직후 호출하는 초기화 함수
func setup(data: UnitData, spawn_position: Vector2, target: Node2D) -> void:
	position = spawn_position
	_target = target
	
	# [cite_start]런타임 객체 생성 (데이터 주입) [cite: 33]
	_runtime = UnitRuntime.new(data)
	
	# 외형 적용
	if _runtime.get_texture():
		sprite_2d.texture = _runtime.get_texture()
	
	# 디버그: 이름 표시 (선택 사항)
	name = data.name

func _physics_process(_delta: float) -> void:
	if not _target: return
	
	# 간단한 추적 AI (테스트용)
	var direction = global_position.direction_to(_target.global_position)
	
	# [cite_start]UnitRuntime을 통해 데이터(속도) 참조 [cite: 34]
	velocity = direction * _runtime.get_speed()
	move_and_slide()
