# res://Scenes/Field/Enemy.gd
extends CharacterBody2D

@export var data: EnemyData
@onready var health = $HealthComponent
@onready var sprite = $Sprite2D

func _ready():
	if data:
		health.init(data.max_hp)
		if data.sprite:
			sprite.texture = data.sprite
