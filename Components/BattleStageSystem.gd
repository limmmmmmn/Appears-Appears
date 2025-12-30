# res://Components/BattleStageSystem.gd
class_name BattleStageSystem extends Node

@export var unit_display_scene: PackedScene
@export var damage_label_scene: PackedScene

@export_category("Position Settings")
@export var y_offset: float = 0.0
@export var unit_spacing: float = 120.0

@export_category("Effect Settings")
# [New] 데미지가 뜰 기준 위치 (x: 0이면 중앙, y: -50이면 머리 위 50px)
@export var damage_offset: Vector2 = Vector2(0, -50) 
# [New] 좌우로 랜덤하게 퍼지는 범위 (0이면 일직선으로만 뜸)
@export var damage_spread_x: float = 20.0

# [New] ★ 그림의 중심을 잡아주는 보정값 (기본값: 가로 32, 세로 40만큼 왼쪽 위로 당김)
@export var centering_offset: Vector2 = Vector2(32, 40)

var unit_visuals: Dictionary = {}
var container: Control

# [기능 1] 적군들 무대에 배치하기 (드퀘 스타일 정렬)
func setup_enemies(enemies: Array[BattleUnit]):
	for child in container.get_children():
		if child is UnitDisplay: child.queue_free()
	unit_visuals.clear()

	var enemy_count = enemies.size()
	
	var center_x = container.size.x / 2
	var center_y = container.size.y / 2
	
	for i in range(enemy_count):
		var unit = enemies[i]
		
		# 1. 가로 위치
		var offset_x = (i - (enemy_count - 1) / 2.0) * unit_spacing
		# [수정] 32 대신 변수 사용
		var x_pos = center_x + offset_x - centering_offset.x 
		
		# 2. 세로 위치
		# [수정] 40 대신 변수 사용
		var y_pos = center_y + y_offset - centering_offset.y
		
		_spawn_unit_display(unit, Vector2(x_pos, y_pos))

# [내부 함수] 실제 생성
func _spawn_unit_display(unit: BattleUnit, pos: Vector2):
	# 적 데이터에서 스프라이트 가져오기 (데이터 구조에 따라 경로 수정 필요)
	# 여기서는 unit.unit_name 등을 통해 이미지를 찾는다고 가정하거나
	# BattleUnit 생성 시 sprite 정보를 같이 넘겨야 함. 
	# *간편함을 위해 지금은 BattleUnit에 sprite 변수가 없으니, 
	#  임시로 EnemyData를 BattleUnit이 들고 있게 하거나 외부에서 받아야 함.
	#  -> 리팩토링 편의상: BattleUnit에 'visual_texture' 변수를 추가하는게 베스트!
	
	var display = unit_display_scene.instantiate()
	container.add_child(display)
	display.position = pos
	
	# ★ BattleUnit에 sprite 변수가 있다고 가정 (아래 설명 참조)
	display.setup(unit.sprite, unit.unit_name, unit.max_hp)
	
	unit_visuals[unit] = display

# [기능 2] 애니메이션 재생기
func play_attack(unit: BattleUnit):
	if unit in unit_visuals:
		unit_visuals[unit].play_attack_animation()

# [수정] play_damage 함수 업그레이드
func play_damage(unit: BattleUnit, damage: int, is_crit: bool, is_dead: bool):
	if unit in unit_visuals:
		var display = unit_visuals[unit]
		display.update_hp(unit.current_hp)
		display.play_damage_effect()
		
		# [New] 데미지 숫자 띄우기 (여기에 추가!)
		_spawn_damage_text(display, damage, is_crit)
		
		if is_dead: display.play_death()
		
# [New] 내부 함수: 숫자 생성
# [수정] _spawn_damage_text 함수 안쪽을 고치세요
func _spawn_damage_text(target_display: Control, amount: int, is_crit: bool):
	var label = damage_label_scene.instantiate()
	container.add_child(label)
	
	# 1. 타겟의 "가로 중앙, 세로 맨 위" 좌표 찾기
	# (UnitDisplay의 위치 + 가로 절반 길이)
	var target_top_center = target_display.position + Vector2(target_display.size.x / 2, 0)
	
	# 2. 랜덤값 (좌우 확산)
	var random_x = randf_range(-damage_spread_x, damage_spread_x)
	
	# 3. 최종 위치 = 타겟 머리 위 + 내가 설정한 오프셋 + 랜덤 확산
	var spawn_pos = target_top_center + damage_offset + Vector2(random_x, 0)
	
	label.position = spawn_pos
	label.setup(amount, is_crit)
