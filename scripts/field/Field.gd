# scripts/field/Field.gd
extends Node2D

@export var field_id: String = "field_001"

func _ready():
	print("========================================")
	print("  Field: ", field_id)
	print("========================================")
	
	# 필드 정보 로드
	var field_data = DataManager.get_field(field_id)
	if not field_data.is_empty():
		print("Field name: ", field_data.name)
	
	# 이벤트 발송
	EventBus.field_entered.emit(field_id)
	
	# 적 스폰 (나중에 구현)
	# spawn_enemies()

func spawn_enemies():
	# TODO: Week 2에서 구현
	print("  (Enemy spawning not yet implemented)")
