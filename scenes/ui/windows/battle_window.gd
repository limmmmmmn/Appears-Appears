class_name BattleWindow extends Control
# [Blueprint v1.4] 6. 전투 및 UI - View Only 

# 미리 만들어둔 컴포넌트 씬 로드
const ENEMY_DISPLAY_SCENE = preload("res://scenes/ui/components/enemy_display.tscn")
@onready var enemy_container: HBoxContainer = $EnemyContainer

func setup(instance: BattleInstance) -> void:
	# 기존 자식 제거 (재사용 방지)
	for child in enemy_container.get_children():
		child.queue_free()
	
	# 인스턴스 내 모든 적에 대해 컴포넌트 생성 및 데이터 주입 [cite: 78]
	for enemy_runtime in instance.enemies:
		var display = ENEMY_DISPLAY_SCENE.instantiate() as EnemyDisplay
		enemy_container.add_child(display)
		display.update_view(enemy_runtime)
