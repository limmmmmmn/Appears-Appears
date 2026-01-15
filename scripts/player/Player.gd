# scripts/player/Player.gd
extends CharacterBody2D

@export var speed: float = 200.0

var party_members: Array = []
var position_history: Array = []
var history_max_length: int = 30

# UI 상태
var ui_open: bool = false

func _ready():
	print("[Player] Ready!")
	
	await get_tree().create_timer(0.5).timeout
	setup_party_members()

func _process(delta):
	# UI 단축키
	handle_ui_input()

func _physics_process(delta):
	# UI 열려있으면 이동 불가
	if ui_open:
		return
	
	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_direction * speed
	
	if velocity.length() > 0:
		record_position()
	
	move_and_slide()
	update_party_positions()

func handle_ui_input():
	# I 키: 인벤토리
	if Input.is_action_just_pressed("inventory"):
		open_inventory()
	
	# ESC: UI 닫기
	if Input.is_action_just_pressed("ui_cancel"):
		close_all_ui()

func open_inventory():
	if ui_open:
		return
	
	ui_open = true
	
	var inventory_ui = preload("res://scenes/ui/InventoryUI.tscn").instantiate()
	
	var canvas = CanvasLayer.new()
	canvas.name = "UICanvas"
	canvas.layer = 90
	canvas.add_child(inventory_ui)
	get_tree().root.add_child(canvas)
	
	# 중앙 배치
	await get_tree().process_frame
	var viewport_size = get_viewport().get_visible_rect().size
	inventory_ui.position = Vector2(
		viewport_size.x / 2 - 300,
		viewport_size.y / 2 - 200
	)
	
	inventory_ui.closed.connect(_on_ui_closed)

func close_all_ui():
	var ui_canvas = get_tree().root.get_node_or_null("UICanvas")
	if ui_canvas:
		ui_canvas.queue_free()
		ui_open = false

func _on_ui_closed():
	close_all_ui()

func record_position():
	position_history.push_front(global_position)
	if position_history.size() > history_max_length:
		position_history.pop_back()

func update_party_positions():
	for i in range(party_members.size()):
		var member = party_members[i]
		if not is_instance_valid(member):
			continue
		var history_index = (i + 1) * 10
		if history_index < position_history.size():
			member.global_position = position_history[history_index]

func setup_party_members():
	if GameManager.party.size() == 0:
		GameManager.setup_test_party()
	
	print("[Player] Party: ", GameManager.party.size())
	
	var colors = [Color.GREEN, Color.ORANGE, Color.YELLOW, Color.PURPLE]
	
	for i in range(GameManager.party.size()):
		var hero = GameManager.party[i]
		
		var member_sprite = Sprite2D.new()
		var texture = GradientTexture2D.new()
		texture.width = 28
		texture.height = 28
		var gradient = Gradient.new()
		gradient.set_color(0, colors[i % colors.size()])
		gradient.set_color(1, colors[i % colors.size()])
		texture.gradient = gradient
		member_sprite.texture = texture
		
		member_sprite.global_position = global_position - Vector2(0, (i + 1) * 40)
		
		get_parent().add_child(member_sprite)
		party_members.append(member_sprite)
		
		print("  + ", hero.name)
