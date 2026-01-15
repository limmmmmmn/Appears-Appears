# scenes/main/Main.gd
extends Node

func _ready():
	print("=== HYPER QUEST TEST ===")
	
	await get_tree().create_timer(1.0).timeout
	
	var heroes = DataManager.get_enabled_heroes()
	print("Heroes: ", heroes.size())
	for h in heroes:
		print("  - ", h.name)
	
	GameManager.setup_test_party()
	print("=== TEST COMPLETE ===")
