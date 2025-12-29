# res://Components/InteractionComponent.gd
class_name InteractionComponent extends Area2D

# 이 구역에 들어오면 전투가 시작되는가?
@export var is_enemy: bool = true
@export var enemy_data: EnemyData # 만약 적이라면 데이터 필요

func _ready():
	# 충돌 감지 설정 (레이어 등은 나중에 디테일하게)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	# 플레이어가 들어왔는지 확인 (이름이나 그룹으로 체크)
	if body.name == "Player":
		print("플레이어 감지! 상호작용 발생!")
		
		if is_enemy and enemy_data:
			# ★ 전 세계에 소리칩니다: "전투 시작해!"
			SignalBus.battle_requested.emit(enemy_data)
			
			# (선택) 적은 전투 들어가면 잠시 멈추거나 사라져야 함
			get_parent().queue_free() # 일단은 사라지게 처리 (임시)
