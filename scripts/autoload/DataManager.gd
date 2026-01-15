# scripts/autoload/DataManager.gd
extends Node

var heroes: Dictionary = {}
var items: Dictionary = {}
var skills: Dictionary = {}
var synergies: Dictionary = {}
var enemies: Dictionary = {}

func _ready() -> void:
	print("[DataManager] Loading...")
	load_all_data()

func load_all_data() -> void:
	heroes = _load_json("res://data/heroes.json")
	items = _load_json("res://data/items.json")
	skills = _load_json("res://data/skills.json")
	synergies = _load_json("res://data/synergies.json")
	enemies = _load_json("res://data/enemies.json")
	print("[DataManager] Loaded!")

func _load_json(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open: " + path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		push_error("JSON Parse Error: " + path)
		return {}
	
	return json.data

func get_enabled_heroes() -> Array:
	var result = []
	if not heroes.has("heroes"):
		return result
	for hero_id in heroes.heroes:
		var hero = heroes.heroes[hero_id]
		if hero.enabled:
			result.append(hero)
	return result

func get_hero(hero_id: String) -> Dictionary:
	if heroes.has("heroes") and heroes.heroes.has(hero_id):
		return heroes.heroes[hero_id]
	return {}

func get_skill(skill_id: String) -> Dictionary:
	if skills.has("skills") and skills.skills.has(skill_id):
		return skills.skills[skill_id]
	return {}

func get_item(item_id: String) -> Dictionary:
	if items.has("items") and items.items.has(item_id):
		return items.items[item_id]
	return {}

func get_enemy(enemy_id: String) -> Dictionary:
	if enemies.has("enemies") and enemies.enemies.has(enemy_id):
		return enemies.enemies[enemy_id]
	return {}
