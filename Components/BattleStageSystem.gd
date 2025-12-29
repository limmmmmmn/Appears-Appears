# res://Components/BattleStageSystem.gd
class_name BattleStageSystem extends Node

# 그림 그릴 도구들
var unit_display_scene = preload("res://Scenes/Battle/UnitDisplay.tscn")
var unit_visuals: Dictionary = {} # 데이터-그림 연결 장부

# 그림이 그려질 캔버스 (BattleScene에서 주입받음)
var container: Control 

# [기능 1] 적군들 무대에 배치하기 (드퀘 스타일 정렬)
func setup_enemies(enemies: Array[BattleUnit]):
	# 기존 그림들 싹 지우기 (초기화)
	for child in container.get_children():
		if child is UnitDisplay: child.queue_free()
	unit_visuals.clear()

	var enemy_count = enemies.size()
	var container_width = container.size.x
	var section_width = container_width / enemy_count
	
	for i in range(enemy_count):
		var unit = enemies[i]
		
		# 좌표 계산 (가로 정렬)
		var x_pos = (section_width * i) + (section_width / 2) - 32
		var y_pos = (container.size.y / 2) - 40
		
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

func play_damage(unit: BattleUnit, damage: int, is_dead: bool):
	if unit in unit_visuals:
		var display = unit_visuals[unit]
		display.update_hp(unit.current_hp)
		display.play_damage_effect()
		if is_dead: display.play_death()
