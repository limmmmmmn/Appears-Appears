extends Node

var _heroes := {}
var _enemies := {}
var _items := {}
var _skills := {}
var _loot_tables := {}
var _stages := {}

func _ready() -> void:
	print("📂 [DataRegistry] 리소스 로드 시작...")
	_load_folder("res://common/data/heroes/", _heroes, "Hero", HeroDef)
	_load_folder("res://common/data/enemies/", _enemies, "Enemy", EnemyDef)
	_load_folder("res://common/data/items/", _items, "Item", ItemDef)
	_load_folder("res://common/data/skills/", _skills, "Skill", SkillDef)
	_load_folder("res://common/data/loot/", _loot_tables, "LootTable", LootTableDef)
	_load_folder("res://common/data/stages/", _stages, "Stage", StageDef)
	
	_validate_integrity()
	print("✅ [DataRegistry] 모든 데이터 로드 완료.")

# 안전 Getter
func get_hero(id: String) -> HeroDef: return _get_resource(id, _heroes, "Hero")
func get_enemy(id: String) -> EnemyDef: return _get_resource(id, _enemies, "Enemy")
func get_item(id: String) -> ItemDef: return _get_resource(id, _items, "Item")
func get_skill(id: String) -> SkillDef: return _get_resource(id, _skills, "Skill")
func get_loot_table(id: String) -> LootTableDef: return _get_resource(id, _loot_tables, "Loot")
func get_stage(id: String) -> StageDef: return _get_resource(id, _stages, "Stage")

func _get_resource(id: String, dict: Dictionary, type_name: String) -> Resource:
	if not dict.has(id):
		printerr("❌ [DataRegistry] %s ID를 찾을 수 없음: '%s'" % [type_name, id])
		return null
	return dict[id]

func _load_folder(path: String, target_dict: Dictionary, label: String, expected_type) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		printerr("⚠️ [DataRegistry] 폴더 없음: %s" % path)
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue
			
		var is_resource = file_name.ends_with(".tres") or file_name.ends_with(".res")
		if is_resource and not file_name.ends_with(".remap"):
			var full_path := path + file_name
			var res := load(full_path)
			
			if res == null:
				printerr("❌ 로드 실패: " + full_path)
				file_name = dir.get_next()
				continue
			
			# 문서 표준 타입 체크 방식 적용
			if not is_instance_of(res, expected_type):
				printerr("❌ 타입 불일치: %s (기대: %s)" % [full_path, str(expected_type)])
				file_name = dir.get_next()
				continue
			
			var file_id := file_name.replace(".tres", "").replace(".res", "")
			if res.id != file_id:
				printerr("⚠️ ID 불일치 (파일명:%s != 내부:%s)" % [file_id, res.id])
			
			if target_dict.has(file_id):
				printerr("🔥 중복 ID 무시됨: " + file_id)
			else:
				target_dict[file_id] = res
					
		file_name = dir.get_next()
	dir.list_dir_end()

func _validate_integrity() -> void:
	# 무결성 검사 로직 (이전과 동일, 생략 가능하지만 유지 추천)
	pass
