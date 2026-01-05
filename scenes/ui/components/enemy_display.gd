class_name EnemyDisplay extends VBoxContainer
# [Blueprint v1.4] 6. 전투 및 UI - 개별 적 표시용 뷰

@onready var sprite: TextureRect = $Sprite
@onready var name_label: Label = $NameLabel
@onready var hp_bar: ProgressBar = $HPBar

func update_view(enemy: UnitRuntime) -> void:
	# 런타임 데이터를 받아 씬 노드들에 적용
	sprite.texture = enemy.get_texture()
	name_label.text = enemy._data.name
	hp_bar.max_value = enemy._data.base_hp
	hp_bar.value = enemy.current_hp
