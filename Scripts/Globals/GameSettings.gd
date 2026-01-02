# res://Scripts/Globals/GameSettings.gd
extends Node

var battle_speed: float = 1.0 # 전투 진행 속도 (기본 1배) [cite: 56]

func set_speed(speed: float):
	battle_speed = speed
