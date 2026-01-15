# scripts/field/TownExit.gd
extends Area2D

@export var target_town: String = "town_001"

var player_in_area: bool = false

func _ready():
	print("[TownExit] Ready")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body):
	if body.is_in_group("player") or body.name == "Player":
		player_in_area = true
		print("[TownExit] Press SPACE to enter town")

func _on_body_exited(body):
	if body.is_in_group("player") or body.name == "Player":
		player_in_area = false

func _input(event):
	if event.is_action_pressed("ui_accept") and player_in_area:
		enter_town()

func enter_town():
	print("=== Entering Town ===")
	
	# 마을 UI 열기
	var town_ui = preload("res://scenes/ui/TownUI.tscn").instantiate()
	
	var canvas = CanvasLayer.new()
	canvas.name = "TownCanvas"
	canvas.layer = 95
	canvas.add_child(town_ui)
	get_tree().root.add_child(canvas)
	
	# 중앙 배치
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	town_ui.position = Vector2(
		viewport_size.x / 2 - 150,
		viewport_size.y / 2 - 200
	)
	
	town_ui.closed.connect(_on_town_closed)

func _on_town_closed():
	var canvas = get_tree().root.get_node_or_null("TownCanvas")
	if canvas:
		canvas.queue_free()
