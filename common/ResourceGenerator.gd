@tool
extends EditorScript

# [설정] true면 기존 파일을 무시하고 덮어씀 (주의!)
const FORCE_OVERWRITE = false 
const BASE_DIR = "res://common/data"

func _run():
	print("🚀 리소스 생성 시작... (덮어쓰기 모드: %s)" % FORCE_OVERWRITE)
	
	# 1. 절대 경로 방식으로 안전하게 폴더 생성
	_ensure_dir_absolute(BASE_DIR + "/acts")
	_ensure_dir_absolute(BASE_DIR + "/nodes")
	_ensure_dir_absolute(BASE_DIR + "/towns")
	_ensure_dir_absolute(BASE_DIR + "/stages")
	_ensure_dir_absolute(BASE_DIR + "/heroes")
	_ensure_dir_absolute(BASE_DIR + "/enemies")
	_ensure_dir_absolute(BASE_DIR + "/skills")
	_ensure_dir_absolute(BASE_DIR + "/items")
	_ensure_dir_absolute(BASE_DIR + "/loot_tables")

	# ---------------------------------------------------------
	# [A] MapNodeDef 데이터 + 자동 연결
	# ---------------------------------------------------------
	var nodes_data = [
		{"id": "node_001_entry", "type": "ENTRY", "next": ["node_010_field_01"]},
		{"id": "node_010_field_01", "type": "STAGE", "next": ["node_020_town_01"], "ref": "stage_field_01_grass"},
		{"id": "node_020_town_01", "type": "TOWN", "next": ["node_030_field_02"], "ref": "town_01_waystation"},
		{"id": "node_030_field_02", "type": "STAGE", "next": ["node_040_town_02"], "ref": "stage_field_02_forest"},
		# 분기점
		{"id": "node_040_town_02", "type": "TOWN", "next": ["node_050_side_dungeon", "node_051_elite", "node_060_field_03"], "ref": "town_02_crossroads"},
		# 사이드/엘리트 (클리어 후 060 합류)
		{"id": "node_050_side_dungeon", "type": "STAGE", "next": ["node_060_field_03"], "ref": "stage_side_01_cave"},
		{"id": "node_051_elite", "type": "STAGE", "next": ["node_060_field_03"], "ref": "stage_elite_01_ruins"},
		# 합류 및 후반
		{"id": "node_060_field_03", "type": "STAGE", "next": ["node_070_town_03"], "ref": "stage_field_03_ruins"},
		{"id": "node_070_town_03", "type": "TOWN", "next": ["node_080_boss"], "ref": "town_03_outpost"},
		{"id": "node_080_boss", "type": "BOSS", "next": ["node_090_end"], "ref": "stage_boss_01_grove"},
		{"id": "node_090_end", "type": "END", "next": []}
	]
	
	var all_node_ids: Array[String] = []

	for d in nodes_data:
		all_node_ids.append(d["id"])
		var res = MapNodeDef.new()
		res.id = d["id"]
		
		# [핵심] 주석 해제 및 실제 데이터 주입
		# 주의: MapNodeDef 스크립트에 해당 변수들이 선언되어 있어야 함
		if "node_type" in res: res.node_type = d["type"] # Enum 처리 필요시 수정
		if "next_node_ids" in res: res.next_node_ids = d["next"]
		if "content_id" in res and "ref" in d: res.content_id = d["ref"]
		
		_save_resource(res, "nodes/" + d["id"])

	# ---------------------------------------------------------
	# [B] ActDef 생성 (노드 리스트 자동 주입)
	# ---------------------------------------------------------
	var act = ActDef.new()
	act.id = "act_001_greenwood"
	act.display_name = "Act 1: Green Wood"
	
	# [핵심] 자동 연결
	if "start_node_id" in act: act.start_node_id = "node_001_entry"
	if "node_ids" in act: act.node_ids = all_node_ids
	
	_save_resource(act, "acts/act_001_greenwood")

	# ---------------------------------------------------------
	# [C ~ G] 기본 리소스 (Town, Stage, Hero, Enemy, Skill)
	# ---------------------------------------------------------
	# Town
	for tid in ["town_01_waystation", "town_02_crossroads", "town_03_outpost"]:
		var res = TownDef.new(); res.id = tid
		_save_resource(res, "towns/" + tid)

	# Stage
	for sid in ["stage_field_01_grass", "stage_field_02_forest", "stage_field_03_ruins", "stage_side_01_cave", "stage_elite_01_ruins", "stage_boss_01_grove"]:
		var res = StageDef.new(); res.id = sid
		_save_resource(res, "stages/" + sid)

	# Hero
	for hid in ["hero_warrior", "hero_ranger", "hero_mage", "hero_cleric", "hero_rogue", "hero_guardian"]:
		var res = HeroDef.new(); res.id = hid
		res.base_stats = {"hp": 50, "atk": 8, "def": 2, "spd": 10}
		_save_resource(res, "heroes/" + hid)

	# Enemy
	for eid in ["enemy_slime", "enemy_bat", "enemy_rat", "enemy_goblin", "enemy_wolf", "enemy_skeleton", "enemy_mimic_elite", "enemy_ancient_treant_boss"]:
		var res = EnemyDef.new(); res.id = eid
		res.base_stats = {"hp": 20, "atk": 5, "def": 0, "spd": 8}
		_save_resource(res, "enemies/" + eid)
		
	# Skill
	for skid in ["skill_attack", "skill_guard", "skill_arrow", "skill_multi_shot", "skill_firebolt", "skill_arcane_blast", "skill_heal", "skill_smite", "skill_stab", "skill_poison", "skill_shield_bash", "skill_taunt"]:
		var res = SkillDef.new(); res.id = skid; res.display_name = skid.replace("_", " ").capitalize()
		_save_resource(res, "skills/" + skid)

	# ---------------------------------------------------------
	# [H] ItemDef 생성 (의미 있는 ID로 변경)
	# ---------------------------------------------------------
	# 18개: 무기 6, 방어구 6, 유틸 6
	var item_ids = [
		"item_wpn_sword_01", "item_wpn_bow_01", "item_wpn_staff_01", "item_wpn_mace_01", "item_wpn_dagger_01", "item_wpn_shield_01",
		"item_arm_plate_01", "item_arm_leather_01", "item_arm_robe_01", "item_arm_boots_01", "item_arm_helm_01", "item_arm_gloves_01",
		"item_util_potion_hp", "item_util_potion_mp", "item_util_scroll_atk", "item_util_scroll_def", "item_util_bomb", "item_util_key"
	]
	
	for i_id in item_ids:
		var res = ItemDef.new()
		res.id = i_id
		res.display_name = i_id.replace("item_", "").replace("_", " ").capitalize()
		_save_resource(res, "items/" + i_id)

	# ---------------------------------------------------------
	# [I] LootTableDef
	# ---------------------------------------------------------
	for lid in ["loot_reward_common", "loot_reward_uncommon", "loot_reward_rare", "loot_shop_stock", "loot_recruit_pool", "loot_elite_reward", "loot_boss_reward"]:
		var res = LootTableDef.new(); res.id = lid
		_save_resource(res, "loot_tables/" + lid)

	print("✅ 모든 리소스 생성 완료!")


# [안전한 디렉토리 생성]
func _ensure_dir_absolute(path: String):
	# make_dir_recursive_absolute는 static 함수라 인스턴스 없이 호출 가능
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)

# [안전한 저장]
func _save_resource(res: Resource, sub_path: String):
	var full_path = BASE_DIR + "/" + sub_path + ".tres"
	
	# 덮어쓰기 방지 체크
	if FileAccess.file_exists(full_path) and not FORCE_OVERWRITE:
		print("⏭️ Skip (Exists): " + sub_path)
		return

	ResourceSaver.save(res, full_path)
	print("💾 Saved: " + sub_path)
