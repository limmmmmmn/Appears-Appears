# res://Scenes/Field/WorldMap.gd
extends Node2D

var battle_scene_res = preload("res://Scenes/Battle/BattleScene.tscn")

func _ready():
	SignalBus.request_battle.connect(_on_request_battle)

func _on_request_battle(main_enemy: EnemyData, spawn_table: Array[SpawnEntry]):
	var battle_window = battle_scene_res.instantiate()
	
	# [변경] 이제 그냥 add_child만 해도 화면 위에 뜹니다!
	# CanvasLayer가 알아서 처리해주기 때문입니다.
	add_child(battle_window)
	
	battle_window.start_battle(main_enemy, spawn_table)
