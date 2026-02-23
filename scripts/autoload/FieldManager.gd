extends Node
## FieldManager: 액트/에어리어 진행 + 필드 스폰/전투 생성 관리

signal field_loaded(area_id: String)
signal field_enemy_spawned(enemy_id: String, position: Vector2)
signal battle_generated(field_enemy_id: String, battle_enemies: Array)

const ACT_JSON_PATH := "res://data/acts.json"

const DEFAULT_TILE_TYPES: Dictionary = {
	"grass": {"can_spawn": true, "walkable": true},
	"desert": {"can_spawn": true, "walkable": true},
	"forest": {"can_spawn": true, "walkable": true},
	"hill": {"can_spawn": true, "walkable": true},
	"mountain": {"can_spawn": false, "walkable": false},
	"cave": {"can_spawn": false, "walkable": true, "is_exit": true, "exit_type": "dungeon"},
	"bridge": {"can_spawn": false, "walkable": true},
	"shiren": {"can_spawn": false, "walkable": true},
	"castle": {"can_spawn": false, "walkable": true, "is_exit": true, "exit_type": "castle"},
	"town": {"can_spawn": false, "walkable": true, "is_exit": true, "exit_type": "town"},
	"stone": {"can_spawn": true, "walkable": true},
	"water": {"can_spawn": false, "walkable": false},
	"road": {"can_spawn": false, "walkable": true},
	"wall": {"can_spawn": false, "walkable": false},
}
const DEFAULT_BATTLE_CONFIG: Dictionary = {"min_enemies": 1, "max_enemies": 3}
const DEFAULT_ENEMY_COUNT: Dictionary = {"min": 2, "max": 4}
const DEFAULT_ENEMY_POOL: Dictionary = {"default": {"slime": 55, "bat": 45}}
const DEFAULT_TERRAIN_ENEMIES: Dictionary = {
	"grass": {"slime": 55, "bat": 45},
	"desert": {"slime": 45, "bat": 55},
	"forest": {"slime": 55, "bat": 45},
	"hill": {"slime": 45, "bat": 55},
	"cave": {"slime": 55, "bat": 45},
	"stone": {"slime": 55, "bat": 45},
}
const DEFAULT_ELITE_POOL: Array[String] = ["orc_warrior"]
const DEFAULT_ELITE_CHANCE: float = 0.2
const DEFAULT_BOSS_ID: String = "boss_goblin_king"

var tile_types: Dictionary = DEFAULT_TILE_TYPES.duplicate(true)
var battle_config: Dictionary = DEFAULT_BATTLE_CONFIG.duplicate(true)

var auto_generate_runtime_acts: bool = true
var balance_only_act_1: bool = true
var runtime_act_seed: int = 0
var runtime_acts: Array[Dictionary] = []
var runtime_acts_by_id: Dictionary = {}
var act_graph_generator: ActGraphGenerator = ActGraphGenerator.new()

var current_act_id: String = ""
var current_area_id: String = ""
var current_act_data: Dictionary = {}
var current_area_data: Dictionary = {}


func _ready() -> void:
	tile_types = DEFAULT_TILE_TYPES.duplicate(true)
	battle_config = DEFAULT_BATTLE_CONFIG.duplicate(true)
	if auto_generate_runtime_acts:
		ensure_runtime_acts(runtime_act_seed)
	_ensure_current_area_selected()


func generate_runtime_acts(seed: int = 0) -> Array[Dictionary]:
	var templates: Array[ActTemplate] = _load_act_templates()
	runtime_acts.clear()
	runtime_acts_by_id.clear()

	if templates.is_empty():
		push_warning("[FieldManager] 액트 템플릿이 없어 runtime_acts 생성 생략")
		return runtime_acts

	var resolved_seed: int = seed
	if resolved_seed == 0:
		resolved_seed = int(Time.get_unix_time_from_system()) ^ randi()
	if resolved_seed == 0:
		resolved_seed = 1

	runtime_act_seed = resolved_seed
	runtime_acts = act_graph_generator.build_runtime_acts(templates, runtime_act_seed)
	for act in runtime_acts:
		var act_id: String = str(act.get("id", ""))
		if act_id.is_empty():
			continue
		runtime_acts_by_id[act_id] = act

	_ensure_current_area_selected()
	return runtime_acts


func get_runtime_acts() -> Array[Dictionary]:
	return runtime_acts


func ensure_runtime_acts(seed: int = 0) -> Array[Dictionary]:
	if runtime_acts.is_empty():
		return generate_runtime_acts(seed)
	return runtime_acts


func debug_print_runtime_acts_summary() -> void:
	for act in ensure_runtime_acts():
		var act_id: String = str(act.get("id", ""))
		var areas: Array = act.get("areas", []) as Array
		print("[FieldManager] RuntimeAct %s areas=%d seed=%s" % [
			act_id,
			areas.size(),
			str(act.get("seed", 0))
		])


func get_runtime_act(act_id: String) -> Dictionary:
	return runtime_acts_by_id.get(act_id, {}) as Dictionary


func get_runtime_area(act_id: String, area_id: String) -> Dictionary:
	if act_id.is_empty() or area_id.is_empty():
		return {}
	var act: Dictionary = get_runtime_act(act_id)
	if act.is_empty():
		return {}
	var areas: Array = act.get("areas", []) as Array
	for area in areas:
		var area_dict: Dictionary = area as Dictionary
		if str(area_dict.get("id", "")) == area_id:
			return area_dict
	return {}


func get_next_runtime_area_ids(act_id: String, area_id: String) -> Array[String]:
	var area: Dictionary = get_runtime_area(act_id, area_id)
	if area.is_empty():
		return []
	var next_any: Array = area.get("next", []) as Array
	var result: Array[String] = []
	for entry in next_any:
		var next_id: String = str(entry)
		if next_id.is_empty():
			continue
		var next_area: Dictionary = get_runtime_area(act_id, next_id)
		if str(next_area.get("type", "")) == "boss":
			continue
		result.append(next_id)
	return result


func set_current_act(act_id: String) -> bool:
	ensure_runtime_acts(runtime_act_seed)
	if act_id.is_empty():
		return false
	var act: Dictionary = get_runtime_act(act_id)
	if act.is_empty():
		push_error("[FieldManager] 존재하지 않는 액트: " + act_id)
		return false

	current_act_id = act_id
	current_act_data = act
	return true


func set_current_area(area_id: String) -> bool:
	if current_act_data.is_empty():
		push_error("[FieldManager] 액트가 설정되지 않음")
		return false

	var resolved_area_id: String = area_id
	if resolved_area_id.begins_with("field_"):
		resolved_area_id = get_first_area_id(current_act_id)

	var area: Dictionary = get_runtime_area(current_act_id, resolved_area_id)
	if area.is_empty():
		push_error("[FieldManager] 존재하지 않는 에어리어: " + resolved_area_id)
		return false

	current_area_id = resolved_area_id
	current_area_data = area
	field_loaded.emit(current_area_id)
	return true


func get_first_area_id(act_id: String) -> String:
	var act: Dictionary = get_runtime_act(act_id)
	if act.is_empty():
		return ""
	var start_id: String = str(act.get("start_area_id", ""))
	if not start_id.is_empty():
		return start_id
	var areas: Array = act.get("areas", []) as Array
	if areas.is_empty():
		return ""
	var first_area: Dictionary = areas[0] as Dictionary
	return str(first_area.get("id", ""))


func get_next_act_id(act_id: String) -> String:
	var current_order: int = -1
	for act in ensure_runtime_acts(runtime_act_seed):
		var act_dict: Dictionary = act as Dictionary
		if str(act_dict.get("id", "")) == act_id:
			current_order = int(act_dict.get("order", -1))
			break
	if current_order < 0:
		return ""

	var best_order: int = 999999
	var best_id: String = ""
	for act in runtime_acts:
		var act_dict: Dictionary = act as Dictionary
		var order: int = int(act_dict.get("order", -1))
		if order > current_order and order < best_order:
			best_order = order
			best_id = str(act_dict.get("id", ""))
	return best_id


func get_current_area_scene() -> String:
	return str(current_area_data.get("scene", ""))


func get_current_area_name() -> String:
	return str(current_area_data.get("name", ""))


func get_current_act_name() -> String:
	return str(current_act_data.get("name", ""))


func get_current_area_type() -> String:
	return str(current_area_data.get("type", "field"))


func is_boss_field() -> bool:
	if current_area_data.is_empty():
		return false
	if bool(current_area_data.get("is_boss", false)):
		return true
	if bool(current_area_data.get("is_boss_field", false)):
		return true
	return get_current_area_type() == "boss"


func get_next_area_ids() -> Array[String]:
	return get_next_runtime_area_ids(current_act_id, current_area_id)


func get_next_destination() -> String:
	var next_ids: Array[String] = get_next_area_ids()
	if not next_ids.is_empty():
		return next_ids[0]
	var legacy_next: String = str(current_area_data.get("next", ""))
	return legacy_next


func get_display_name() -> String:
	var act_num: String = _extract_numeric_suffix(current_act_id)
	if act_num.is_empty():
		act_num = "1"
	var area_num: String = _extract_numeric_suffix(current_area_id)
	if area_num.is_empty():
		area_num = "1"
	return "Act %s-%s" % [act_num, area_num]


#region 타일 기반 스폰
func can_spawn_on_tile(tile_type: String) -> bool:
	if not tile_types.has(tile_type):
		return false
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return tile_data.get("can_spawn", false) as bool


func is_tile_walkable(tile_type: String) -> bool:
	if not tile_types.has(tile_type):
		return true
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return tile_data.get("walkable", true) as bool


func is_exit_tile(tile_type: String) -> bool:
	if not tile_types.has(tile_type):
		return false
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return tile_data.get("is_exit", false) as bool


func get_exit_type(tile_type: String) -> String:
	if not tile_types.has(tile_type):
		return ""
	var tile_data: Dictionary = tile_types[tile_type] as Dictionary
	return str(tile_data.get("exit_type", ""))


func get_enemy_pool_for_tile(tile_type: String) -> Dictionary:
	var area_enemy_pool: Dictionary = current_area_data.get("enemy_pool", {}) as Dictionary
	if area_enemy_pool.has(tile_type):
		return area_enemy_pool[tile_type] as Dictionary
	if area_enemy_pool.has("default"):
		return area_enemy_pool["default"] as Dictionary

	var default_enemy_pool: Dictionary = current_act_data.get("default_enemy_pool", DEFAULT_ENEMY_POOL) as Dictionary
	if default_enemy_pool.has(tile_type):
		return default_enemy_pool[tile_type] as Dictionary
	if default_enemy_pool.has("default"):
		return default_enemy_pool["default"] as Dictionary

	var terrain_enemies: Dictionary = current_act_data.get("terrain_enemies", DEFAULT_TERRAIN_ENEMIES) as Dictionary
	if terrain_enemies.has(tile_type):
		return terrain_enemies[tile_type] as Dictionary
	if terrain_enemies.has("grass"):
		return terrain_enemies["grass"] as Dictionary
	return {}


func select_field_enemy_for_tile(tile_type: String) -> String:
	var pool: Dictionary = get_enemy_pool_for_tile(tile_type)
	if pool.is_empty():
		return "slime"
	return _weighted_random_select(pool)
#endregion


#region 전투 에너미 생성
func generate_battle_enemies(field_enemy_id: String, _tile_type: String) -> Array:
	var bonus_count: int = 0
	if GameManager != null and GameManager.has_method("get_trinket_battle_enemy_bonus"):
		bonus_count = int(GameManager.call("get_trinket_battle_enemy_bonus"))
	var max_battle_size: int = clampi(2 + bonus_count, 1, 4)
	var battle_size: int = randi_range(1, max_battle_size)
	var enemies: Array = [field_enemy_id]
	if battle_size == 1:
		battle_generated.emit(field_enemy_id, enemies)
		return enemies

	while enemies.size() < battle_size:
		enemies.append(field_enemy_id)
	battle_generated.emit(field_enemy_id, enemies)
	return enemies


func _weighted_random_select(pool: Dictionary) -> String:
	var total_weight: float = 0.0
	for enemy_id in pool:
		total_weight += float(pool[enemy_id])

	if total_weight <= 0:
		var keys: Array = pool.keys()
		if keys.is_empty():
			return "slime"
		return str(keys[0])

	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for enemy_id in pool:
		cumulative += float(pool[enemy_id])
		if roll <= cumulative:
			return str(enemy_id)

	var keys: Array = pool.keys()
	return str(keys[0]) if not keys.is_empty() else "slime"
#endregion


#region 필드 적 스폰
func spawn_field_enemies(spawn_tiles: Array) -> Array:
	var enemy_count_data: Dictionary = current_area_data.get("enemy_count", current_act_data.get("default_enemy_count", DEFAULT_ENEMY_COUNT)) as Dictionary
	var min_count: int = int(enemy_count_data.get("min", 3))
	var max_count: int = int(enemy_count_data.get("max", 5))
	var count: int = randi_range(min_count, max_count)

	var valid_tiles: Array = []
	for tile_data in spawn_tiles:
		var tile_dict: Dictionary = tile_data as Dictionary
		var tile_type: String = str(tile_dict.get("tile_type", "grass"))
		if can_spawn_on_tile(tile_type):
			valid_tiles.append(tile_dict)

	if valid_tiles.is_empty():
		for i in range(count):
			valid_tiles.append({
				"position": Vector2(150 + i * 80, 120 + randf() * 60),
				"tile_type": "grass"
			})

	valid_tiles.shuffle()
	var spawned: Array = []

	for i in range(mini(count, valid_tiles.size())):
		var tile_dict: Dictionary = valid_tiles[i] as Dictionary
		var tile_type: String = str(tile_dict.get("tile_type", "grass"))
		var enemy_id: String = select_field_enemy_for_tile(tile_type)
		if enemy_id.is_empty():
			continue

		var spawn_data: Dictionary = {
			"enemy_id": enemy_id,
			"position": tile_dict.get("position", Vector2.ZERO),
			"tile_type": tile_type
		}
		spawned.append(spawn_data)
		field_enemy_spawned.emit(enemy_id, spawn_data["position"])

	return spawned


func should_spawn_elite() -> bool:
	var chance: float = float(current_area_data.get("elite_chance", current_act_data.get("default_elite_chance", DEFAULT_ELITE_CHANCE)))
	return randf() < chance


func get_elite_enemy() -> String:
	var elite_pool: Array = current_area_data.get("elite_pool", current_act_data.get("elite_pool", DEFAULT_ELITE_POOL)) as Array
	if elite_pool.is_empty():
		return ""
	return str(elite_pool[randi() % elite_pool.size()])


func get_boss_enemy() -> String:
	var boss_id: String = str(current_area_data.get("boss_enemy_id", current_act_data.get("boss_enemy_id", DEFAULT_BOSS_ID)))
	if boss_id.is_empty():
		return DEFAULT_BOSS_ID
	return boss_id


func get_field_boss_enemy() -> String:
	var field_boss_id: String = str(current_area_data.get("field_boss_id", ""))
	if not field_boss_id.is_empty():
		return field_boss_id
	return get_boss_enemy()
#endregion


func _ensure_current_area_selected() -> void:
	var acts: Array[Dictionary] = ensure_runtime_acts(runtime_act_seed)
	if acts.is_empty():
		return
	if current_act_id.is_empty() or get_runtime_act(current_act_id).is_empty():
		var first_act: Dictionary = acts[0] as Dictionary
		current_act_id = str(first_act.get("id", ""))
		current_act_data = first_act
	if current_area_id.is_empty() or get_runtime_area(current_act_id, current_area_id).is_empty():
		var first_area_id: String = get_first_area_id(current_act_id)
		if not first_area_id.is_empty():
			current_area_id = first_area_id
			current_area_data = get_runtime_area(current_act_id, current_area_id)


func _load_act_templates() -> Array[ActTemplate]:
	var templates: Array[ActTemplate] = []
	var all_acts: Dictionary = _load_acts_json()
	if all_acts.is_empty():
		return templates

	for act_id in all_acts:
		var data: Dictionary = all_acts[act_id] as Dictionary
		if data.is_empty():
			continue
		var template: ActTemplate = _dict_to_act_template(data)
		if template == null:
			push_warning("[FieldManager] 액트 템플릿 변환 실패: " + str(act_id))
			continue
		if balance_only_act_1 and template.act_id != "act_1":
			continue
		templates.append(template)
	return templates


func _load_acts_json() -> Dictionary:
	if not FileAccess.file_exists(ACT_JSON_PATH):
		push_error("[FieldManager] acts.json not found: " + ACT_JSON_PATH)
		return {}
	var file := FileAccess.open(ACT_JSON_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[FieldManager] acts.json parse failed")
		return {}
	if not (json.data is Dictionary):
		return {}
	return json.data as Dictionary


func _dict_to_act_template(data: Dictionary) -> ActTemplate:
	var t := ActTemplate.new()
	t.act_id = str(data.get("act_id", ""))
	t.act_name = str(data.get("act_name", ""))
	t.act_order = int(data.get("act_order", 1))
	t.terrain_enemies = (data.get("terrain_enemies", {}) as Dictionary).duplicate(true)
	t.default_enemy_pool = (data.get("default_enemy_pool", {}) as Dictionary).duplicate(true)
	t.boss_enemy_id = str(data.get("boss_enemy_id", "boss_goblin_king"))
	t.default_enemy_count = (data.get("default_enemy_count", {"min": 4, "max": 6}) as Dictionary).duplicate(true)
	t.default_elite_chance = float(data.get("default_elite_chance", 0.2))
	t.min_regular_areas = int(data.get("min_regular_areas", 5))
	t.max_regular_areas = int(data.get("max_regular_areas", 7))
	t.guaranteed_town_count = int(data.get("guaranteed_town_count", 1))
	t.guaranteed_event_count = int(data.get("guaranteed_event_count", 1))
	t.guaranteed_dungeon_count = int(data.get("guaranteed_dungeon_count", 1))
	t.field_weight = float(data.get("field_weight", 0.5))
	t.dungeon_weight = float(data.get("dungeon_weight", 0.25))
	t.event_weight = float(data.get("event_weight", 0.15))
	t.town_weight = float(data.get("town_weight", 0.10))
	t.skip_link_chance = float(data.get("skip_link_chance", 0.28))
	t.side_branch_chance = float(data.get("side_branch_chance", 0.12))
	t.boss_area = (data.get("boss_area", {}) as Dictionary).duplicate(true)

	var raw_start: Array = data.get("start_area_pool", []) as Array
	t.start_area_pool = []
	for entry in raw_start:
		t.start_area_pool.append((entry as Dictionary).duplicate(true))

	var raw_field: Array = data.get("field_pool", []) as Array
	t.field_pool = []
	for entry in raw_field:
		t.field_pool.append((entry as Dictionary).duplicate(true))

	var raw_dungeon: Array = data.get("dungeon_pool", []) as Array
	for entry in raw_dungeon:
		t.dungeon_pool.append((entry as Dictionary).duplicate(true))

	var raw_event: Array = data.get("event_pool", []) as Array
	for entry in raw_event:
		t.event_pool.append((entry as Dictionary).duplicate(true))

	var raw_town: Array = data.get("town_pool", []) as Array
	for entry in raw_town:
		t.town_pool.append((entry as Dictionary).duplicate(true))

	var raw_fixed_path: Array = data.get("fixed_area_path", []) as Array
	for entry in raw_fixed_path:
		t.fixed_area_path.append((entry as Dictionary).duplicate(true))

	var raw_fixed_seq: Array = data.get("fixed_area_sequence", []) as Array
	for entry in raw_fixed_seq:
		t.fixed_area_sequence.append(str(entry))

	var raw_elite: Array = data.get("elite_pool", []) as Array
	for entry in raw_elite:
		t.elite_pool.append(str(entry))

	return t


func _extract_numeric_suffix(raw_id: String) -> String:
	if raw_id.is_empty():
		return ""
	var digits: String = ""
	for i in range(raw_id.length() - 1, -1, -1):
		var ch: String = raw_id.substr(i, 1)
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		elif not digits.is_empty():
			break
	return digits
