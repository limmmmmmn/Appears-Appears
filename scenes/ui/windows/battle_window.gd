class_name BattleWindow extends Control
# [Blueprint v1.4] 6. 전투 및 UI - View Only

@onready var enemy_container: HBoxContainer = $EnemyContainer

var _battle_instance: BattleInstance

func setup(instance: BattleInstance) -> void:
	_battle_instance = instance
	_render_enemies()

func _render_enemies() -> void:
	# 기존 자식 제거
	for child in enemy_container.get_children():
		child.queue_free()
	
	# 적 스프라이트 생성 (1~3마리)
	for enemy_runtime in _battle_instance.enemies:
		var texture_rect = TextureRect.new()
		texture_rect.texture = enemy_runtime.get_texture()
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.custom_minimum_size = Vector2(16, 16) # 적당한 크기
		enemy_container.add_child(texture_rect)
