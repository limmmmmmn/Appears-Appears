extends Node

## Catalog of every modifier in the game.
## Loads all .tres files under data/modifiers/ on startup.
## Query by id / rarity / category, or pull random offerings for the shop.

const MODIFIERS_ROOT := "res://data/modifiers"

var _all: Array[ModifierData] = []
var _by_id: Dictionary = {}                  # StringName -> ModifierData
var _by_rarity: Dictionary = {}              # Rarity -> Array[ModifierData]


func _ready() -> void:
	_load_all()
	print("[ModifierDB] loaded %d modifiers" % _all.size())


func _load_all() -> void:
	_all.clear()
	_by_id.clear()
	_by_rarity.clear()
	_load_dir(MODIFIERS_ROOT)
	# Build rarity buckets.
	for mod: ModifierData in _all:
		var bucket: Array = _by_rarity.get(mod.rarity, [])
		bucket.append(mod)
		_by_rarity[mod.rarity] = bucket


func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_load_dir(full)
		elif entry.ends_with(".tres"):
			var res := load(full)
			if res is ModifierData:
				_register(res)
		entry = dir.get_next()
	dir.list_dir_end()


func _register(mod: ModifierData) -> void:
	if mod.id == &"":
		push_warning("[ModifierDB] modifier has empty id: %s" % mod.resource_path)
		return
	if _by_id.has(mod.id):
		push_warning("[ModifierDB] duplicate id: %s" % mod.id)
		return
	_all.append(mod)
	_by_id[mod.id] = mod


# ─── Queries ──────────────────────────────────────────────────────────
func get_by_id(id: StringName) -> ModifierData:
	return _by_id.get(id, null)


func get_by_rarity(rarity: ModifierData.Rarity) -> Array[ModifierData]:
	var typed: Array[ModifierData] = []
	for mod: ModifierData in _by_rarity.get(rarity, []):
		typed.append(mod)
	return typed


func count() -> int:
	return _all.size()


## Pull `n` random modifiers (with replacement = false).
## Returns fewer than `n` if the catalog is too small.
func get_random_modifiers(n: int) -> Array[ModifierData]:
	var pool := _all.duplicate()
	pool.shuffle()
	var out: Array[ModifierData] = []
	for i in mini(n, pool.size()):
		out.append(pool[i])
	return out
