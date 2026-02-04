extends RefCounted
class_name StatCompareUtil
## 스탯 비교 유틸리티: 장비 변경 시 스탯 변화 계산

const STAT_KEYS := ["atk", "def", "p_def", "int", "dex", "luk", "hp", "mp", "str"]

const SLOT_DISPLAY_NAMES := {
	"main_hand": "주무기",
	"off_hand": "보조",
	"head": "머리",
	"body": "몸통",
	"accessory": "장신구",
	"acc1": "장신구1",
	"acc2": "장신구2"
}


## 장비 변경 시 스탯 변화 계산
## 반환: { "stat_name": { "current": int, "new": int, "diff": int }, ... }
static func calculate_stat_changes(hero: Hero, new_item_id: String) -> Dictionary:
	var result := {}
	
	var equip_data: Dictionary = DataManager.get_equipment(new_item_id)
	if equip_data.is_empty():
		return result
	
	var new_stats: Dictionary = equip_data.get("stats", {})
	var slot: String = equip_data.get("slot", "")
	var target_slot := _get_target_slot(hero, slot)
	
	# 현재 장착 장비 스탯
	var current_equip_id: String = hero.equipment.get(target_slot, "")
	var current_stats := {}
	if not current_equip_id.is_empty():
		var current_data: Dictionary = DataManager.get_equipment(current_equip_id)
		current_stats = current_data.get("stats", {})
	
	# ATK 계산
	if new_stats.has("atk") or current_stats.has("atk"):
		var cur := hero.get_atk()
		var old_bonus: int = int(current_stats.get("atk", 0))
		var new_bonus: int = int(new_stats.get("atk", 0))
		var new_val := cur - old_bonus + new_bonus
		result["ATK"] = {"current": cur, "new": new_val, "diff": new_val - cur}
	
	# DEF 계산 (p_def 또는 def)
	if new_stats.has("p_def") or new_stats.has("def") or current_stats.has("p_def") or current_stats.has("def"):
		var cur := hero.get_p_def()
		var old_bonus: int = int(current_stats.get("p_def", current_stats.get("def", 0)))
		var new_bonus: int = int(new_stats.get("p_def", new_stats.get("def", 0)))
		var new_val := cur - old_bonus + new_bonus
		result["DEF"] = {"current": cur, "new": new_val, "diff": new_val - cur}
	
	# INT 계산
	if new_stats.has("int") or current_stats.has("int"):
		var cur := hero.get_int()
		var old_bonus: int = int(current_stats.get("int", 0))
		var new_bonus: int = int(new_stats.get("int", 0))
		var new_val := cur - old_bonus + new_bonus
		result["INT"] = {"current": cur, "new": new_val, "diff": new_val - cur}
	
	# DEX 계산
	if new_stats.has("dex") or current_stats.has("dex"):
		var cur := hero.get_dex()
		var old_bonus: int = int(current_stats.get("dex", 0))
		var new_bonus: int = int(new_stats.get("dex", 0))
		var new_val := cur - old_bonus + new_bonus
		result["DEX"] = {"current": cur, "new": new_val, "diff": new_val - cur}
	
	# LUK 계산
	if new_stats.has("luk") or current_stats.has("luk"):
		var cur := hero.get_luk()
		var old_bonus: int = int(current_stats.get("luk", 0))
		var new_bonus: int = int(new_stats.get("luk", 0))
		var new_val := cur - old_bonus + new_bonus
		result["LUK"] = {"current": cur, "new": new_val, "diff": new_val - cur}
	
	# HP 계산
	if new_stats.has("hp") or current_stats.has("hp"):
		var cur := hero.get_max_hp()
		var old_bonus: int = int(current_stats.get("hp", 0))
		var new_bonus: int = int(new_stats.get("hp", 0))
		var new_val := cur - old_bonus + new_bonus
		result["HP"] = {"current": cur, "new": new_val, "diff": new_val - cur}
	
	# MP 계산
	if new_stats.has("mp") or current_stats.has("mp"):
		var cur := hero.get_max_mp()
		var old_bonus: int = int(current_stats.get("mp", 0))
		var new_bonus: int = int(new_stats.get("mp", 0))
		var new_val := cur - old_bonus + new_bonus
		result["MP"] = {"current": cur, "new": new_val, "diff": new_val - cur}
	
	return result


## 스탯 변화를 BBCode 문자열로 포맷팅
static func format_stat_change(stat_name: String, current: int, new_val: int, diff: int) -> String:
	if diff > 0:
		return "%s: %d → %d ([color=lime]+%d[/color])  " % [stat_name, current, new_val, diff]
	elif diff < 0:
		return "%s: %d → %d ([color=red]%d[/color])  " % [stat_name, current, new_val, diff]
	else:
		return "%s: %d → %d  " % [stat_name, current, new_val]


## 스탯 변화 Dictionary를 BBCode 문자열로 변환
static func format_all_changes(changes: Dictionary) -> String:
	if changes.is_empty():
		return "(스탯 변화 없음)"
	
	var text := ""
	for stat_name in changes:
		var data: Dictionary = changes[stat_name]
		text += format_stat_change(stat_name, data["current"], data["new"], data["diff"])
	
	return text if not text.is_empty() else "(스탯 변화 없음)"


## 간단한 스탯 변화 (ATK/DEF만) - 컨텍스트 메뉴용
static func format_simple_change(hero: Hero, item_id: String) -> String:
	var changes := calculate_stat_changes(hero, item_id)
	var parts := []
	
	if changes.has("ATK"):
		var diff: int = changes["ATK"]["diff"]
		if diff > 0:
			parts.append("[color=lime]ATK+%d[/color]" % diff)
		elif diff < 0:
			parts.append("[color=red]ATK%d[/color]" % diff)
	
	if changes.has("DEF"):
		var diff: int = changes["DEF"]["diff"]
		if diff > 0:
			parts.append("[color=lime]DEF+%d[/color]" % diff)
		elif diff < 0:
			parts.append("[color=red]DEF%d[/color]" % diff)
	
	return " ".join(parts)


## 장비 스탯을 텍스트로 포맷팅
static func format_equipment_stats(stats: Dictionary) -> String:
	var parts := []
	
	if stats.has("atk"):
		parts.append("ATK +%d" % int(stats["atk"]))
	if stats.has("p_def") or stats.has("def"):
		var val: int = int(stats.get("p_def", stats.get("def", 0)))
		parts.append("DEF +%d" % val)
	if stats.has("int"):
		parts.append("INT +%d" % int(stats["int"]))
	if stats.has("dex"):
		parts.append("DEX +%d" % int(stats["dex"]))
	if stats.has("str"):
		parts.append("STR +%d" % int(stats["str"]))
	if stats.has("luk"):
		parts.append("LUK +%d" % int(stats["luk"]))
	if stats.has("hp"):
		parts.append("HP +%d" % int(stats["hp"]))
	if stats.has("mp"):
		parts.append("MP +%d" % int(stats["mp"]))
	
	return "  ".join(parts) if not parts.is_empty() else "(스탯 없음)"


## 슬롯 이름 표시용
static func get_slot_display_name(slot: String) -> String:
	return SLOT_DISPLAY_NAMES.get(slot, slot)


## 악세서리 슬롯 결정
static func _get_target_slot(hero: Hero, slot: String) -> String:
	if slot == "accessory":
		if hero.equipment.get("acc1", "").is_empty():
			return "acc1"
		return "acc1"  # 기본값
	return slot


## 장착할 최적 슬롯 결정
static func determine_equip_slot(hero: Hero, item_slot: String) -> String:
	if item_slot == "accessory":
		if hero.equipment.get("acc1", "").is_empty():
			return "acc1"
		elif hero.equipment.get("acc2", "").is_empty():
			return "acc2"
		else:
			return "acc1"
	return item_slot
