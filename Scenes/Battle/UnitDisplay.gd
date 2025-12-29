# res://Scenes/Battle/UnitDisplay.gd
class_name UnitDisplay extends Control

@onready var visual = $Visual
@onready var hp_bar = $HPBar
@onready var name_label = $NameLabel

# 초기 설정: 화가가 대상을 보고 그림을 그립니다.
func setup(texture: Texture2D, unit_name: String, max_hp: int):
	visual.texture = texture
	name_label.text = unit_name
	
	hp_bar.max_value = max_hp
	hp_bar.value = max_hp
	
	# 중심점 잡기 (애니메이션할 때 중요)
	pivot_offset = size / 2

# 기능 1: HP 갱신
func update_hp(current_hp: int):
	# 부드럽게 깎이는 연출 (Tween)
	var tween = create_tween()
	tween.tween_property(hp_bar, "value", current_hp, 0.2)

# 기능 2: 맞았을 때 연출 (빨간맛)
func play_damage_effect():
	var tween = create_tween()
	tween.tween_property(visual, "modulate", Color.RED, 0.1)
	tween.tween_property(visual, "modulate", Color.WHITE, 0.1)
	
	# 흔들림 효과
	var shake = create_tween()
	shake.tween_property(self, "position:x", position.x + 5, 0.05)
	shake.tween_property(self, "position:x", position.x - 5, 0.05)
	shake.tween_property(self, "position:x", position.x, 0.05)

# 기능 3: 공격할 때 연출 (앞으로 툭)
func play_attack_animation():
	var tween = create_tween()
	# 앞으로 살짝 나갔다가 돌아오기
	var forward = Vector2(0, -20) # 위쪽(적 기준)으로 공격한다고 가정
	# (참고: 아군/적군 위치에 따라 방향을 다르게 줘야 하지만 일단 단순하게)
	
	tween.tween_property(visual, "position", visual.position + forward, 0.1)
	tween.tween_property(visual, "position", visual.position, 0.1)

# 기능 4: 사망 연출
func play_death():
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5) # 투명해짐
