extends Node2D
## 필드 시스템 테스트용 메인 스크립트
## autoload 없이도 기본 테스트 가능

var field_scene: PackedScene = preload("res://scenes/field/Field_Test.tscn")


func _ready() -> void:
	print("=== 필드 테스트 시작 ===")
	print("방향키: 이동")
	print("ESC: 종료")
	
	# FieldManager 초기화 (autoload 안 되어있을 경우 대비)
	if not Engine.has_singleton("FieldManager"):
		print("[테스트] FieldManager autoload 필요!")
		print("[테스트] 프로젝트 설정 > AutoLoad에 FieldManager.gd 추가하세요")
	
	# 테스트 스테이지/필드 설정
	if FieldManager:
		FieldManager.set_current_stage("stage_1")
		FieldManager.set_current_field("field_1_1")
	
	# 필드 씬 로드
	var field := field_scene.instantiate()
	add_child(field)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
