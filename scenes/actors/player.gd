class_name Player extends CharacterBody2D
# [Blueprint v1.4] 5. 액터 카드 - 필드 상호작용 [cite: 40]

# 에디터에서 할당하는 정적 데이터 (Data)
@export var unit_data: UnitData

# 내부 로직이 사용하는 동적 객체 (Runtime)
var _runtime: UnitRuntime

@onready var sprite_2d: Sprite2D = $Sprite2D

func _ready() -> void:
	# 데이터가 없으면 에러 출력 (안전 장치)
	if not unit_data:
		push_error("Player: UnitData is missing!")
		set_physics_process(false)
		return

	# 1. 런타임 객체 초기화 (Dependency Injection)
	_runtime = UnitRuntime.new(unit_data)

	# 2. 비주얼 초기화
	if _runtime.get_texture():
		sprite_2d.texture = _runtime.get_texture()

func _physics_process(_delta: float) -> void:
	_handle_movement()
	# 이동 후 바라보는 방향 업데이트 추가
	_update_facing_direction()
	
func _update_facing_direction() -> void:
	# 스프라이트 기본 방향이 '왼쪽' 기준
	if velocity.x > 0:
		# 오른쪽으로 이동 중 -> 뒤집기
		sprite_2d.flip_h = true
	elif velocity.x < 0:
		# 왼쪽으로 이동 중 -> 원래대로
		sprite_2d.flip_h = false
	# velocity.x == 0 일 때는 이전 상태를 유지합니다.


func _handle_movement() -> void:
	# Godot 4.5+ Input Handling
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	if direction != Vector2.ZERO:
		# Runtime을 통해 속도 정보를 가져옴 (추후 버프 적용 시 코드 수정 불필요)
		velocity = direction * _runtime.get_speed()
	else:
		velocity = Vector2.ZERO

	move_and_slide()
