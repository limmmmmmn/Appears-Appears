extends RefCounted
class_name DragDropManager
## 드래그 앤 드롭 로직 관리

signal drag_started(item_id: String)
signal drag_ended(item_id: String, success: bool)
signal log_message(message: String)

var dragging_item_id: String = ""
var drag_preview: Control = null
var drag_source_type: String = ""  # "inventory" or "equipped"
var drag_source_hero_index: int = -1
var drag_source_slot: String = ""

var party_slots: Array = []  # PartySlotUI 배열
var inventory_panel: Control = null
var preview_parent: Control = null

const SLOT_ICONS: Dictionary = {
	"main_hand": "⚔️",
	"off_hand": "🛡️",
	"head": "👑",
	"body": "👕",
	"accessory": "💍",
	"acc1": "💍",
	"acc2": "💎"
}

const TYPE_ICONS: Dictionary = {
	"sword": "🗡️",
	"dagger": "🔪",
	"axe": "🪓",
	"staff": "🪄",
	"bow": "🏹",
	"shield": "🛡️",
	"helmet": "⛑️",
	"light_armor": "👘",
	"medium_armor": "🦺",
	"heavy_armor": "🛡️",
	"robe": "👗",
	"ring": "💍",
	"amulet": "📿"
}

const RARITY_COLORS: Dictionary = {
	"common": Color.WHITE,
	"magic": Color(0.4, 0.6, 1.0),
	"legendary": Color(1.0, 0.7, 0.2)
}


func setup(slots: Array, inv_panel: Control, parent: Control) -> void:
	party_slots = slots
	inventory_panel = inv_panel
	preview_parent = parent


func is_dragging() -> bool:
	return not dragging_item_id.is_empty()


func start_drag_from_inventory(item_id: String) -> void:
	dragging_item_id = item_id
	drag_source_type = "inventory"
	drag_source_hero_index = -1
	drag_source_slot = ""
	
	_create_drag_preview(item_id)
	_highlight_drop_targets(true)
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	log_message.emit("드래그: %s" % str(data.get("name", item_id)))
	drag_started.emit(item_id)


func start_drag_from_equipped(item_id: String, hero_index: int, slot_name: String) -> void:
	dragging_item_id = item_id
	drag_source_type = "equipped"
	drag_source_hero_index = hero_index
	drag_source_slot = slot_name
	
	_create_drag_preview(item_id)
	_highlight_drop_targets(true)
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	log_message.emit("드래그 (장착): %s" % str(data.get("name", item_id)))
	drag_started.emit(item_id)


func update_drag_position(pos: Vector2) -> void:
	if drag_preview:
		drag_preview.global_position = pos - Vector2(12, 12)


func end_drag(drop_pos: Vector2) -> void:
	if not dragging_item_id:
		return
	
	var item_id := dragging_item_id
	var source_type := drag_source_type
	var source_hero_index := drag_source_hero_index
	var source_slot := drag_source_slot
	var success := false
	
	# 드롭 타겟 찾기
	var drop_target := _find_drop_target(drop_pos)
	
	if drop_target:
		var target_hero_index: int = drop_target.get("hero_index", -1)
		var target_slot: String = drop_target.get("slot_name", "")
		
		if target_hero_index >= 0:
			if source_type == "inventory":
				success = _try_equip_to_hero(item_id, target_hero_index, target_slot)
			elif source_type == "equipped":
				if not (target_hero_index == source_hero_index and target_slot == source_slot):
					success = _try_move_equipment(item_id, source_hero_index, source_slot, target_hero_index, target_slot)
	else:
		if source_type == "equipped" and _is_drop_on_inventory(drop_pos):
			success = _unequip_item(source_hero_index, source_slot)
	
	# 정리
	_highlight_drop_targets(false)
	_destroy_drag_preview()
	
	dragging_item_id = ""
	drag_source_type = ""
	drag_source_hero_index = -1
	drag_source_slot = ""
	
	drag_ended.emit(item_id, success)


func cancel_drag() -> void:
	_highlight_drop_targets(false)
	_destroy_drag_preview()
	
	dragging_item_id = ""
	drag_source_type = ""
	drag_source_hero_index = -1
	drag_source_slot = ""


#region 프리뷰
func _create_drag_preview(item_id: String) -> void:
	if not preview_parent:
		return
	
	drag_preview = PanelContainer.new()
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.7, 1.0)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	drag_preview.add_theme_stylebox_override("panel", style)
	
	var label := Label.new()
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_type: String = str(data.get("type", ""))
	var item_slot: String = str(data.get("slot", ""))
	
	# 아이콘: type > slot > 기본
	var icon: String = TYPE_ICONS.get(item_type, "")
	if icon.is_empty():
		icon = SLOT_ICONS.get(item_slot, "📦")
	
	label.text = icon
	label.add_theme_font_size_override("font_size", 14)
	
	var rarity: String = str(data.get("rarity", "common"))
	label.modulate = RARITY_COLORS.get(rarity, Color.WHITE)
	
	drag_preview.add_child(label)
	drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_preview.z_index = 200
	
	preview_parent.add_child(drag_preview)


func _destroy_drag_preview() -> void:
	if drag_preview and is_instance_valid(drag_preview):
		drag_preview.queue_free()
		drag_preview = null
#endregion


#region 하이라이트
func _highlight_drop_targets(highlight: bool) -> void:
	for slot in party_slots:
		if slot is PartySlotUI and slot.visible:
			slot.set_highlight(highlight)
#endregion


#region 드롭 타겟 찾기
func _find_drop_target(pos: Vector2) -> Dictionary:
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	for i in range(party_slots.size()):
		if i >= party.size():
			continue
		
		var slot = party_slots[i]
		if not slot is PartySlotUI or not slot.visible:
			continue
		
		var slot_rect: Rect2 = slot.get_global_rect()
		
		if slot_rect.has_point(pos):
			# 특정 장비 슬롯 위인지 체크
			for slot_name in ["main_hand", "off_hand", "head", "body", "acc1", "acc2"]:
				var equip_btn: Button = slot.get_equipment_button(slot_name)
				if equip_btn and equip_btn.get_global_rect().has_point(pos):
					return {"hero_index": i, "slot_name": slot_name}
			
			return {"hero_index": i, "slot_name": ""}
	
	return {}


func _is_drop_on_inventory(pos: Vector2) -> bool:
	if inventory_panel and is_instance_valid(inventory_panel):
		return inventory_panel.get_global_rect().has_point(pos)
	return false
#endregion


#region 장비 조작
func _try_equip_to_hero(item_id: String, hero_index: int, target_slot: String) -> bool:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return false
	
	var hero: Hero = party[hero_index]
	
	# 먼저 소비 아이템인지 체크
	var item_data: Dictionary = DataManager.get_item(item_id)
	if item_data.get("type", "") == "consumable":
		return _try_use_consumable(item_id, hero)
	
	var data: Dictionary = DataManager.get_equipment(item_id)
	
	if data.is_empty():
		log_message.emit("장비 데이터 없음")
		return false
	
	var item_name: String = str(data.get("name", item_id))
	var item_slot: String = str(data.get("slot", ""))
	
	# 타겟 슬롯이 지정 안 되었거나 호환 안 되면 자동으로 최적 슬롯 찾기
	if target_slot.is_empty() or not _is_slot_compatible(item_slot, target_slot):
		target_slot = _determine_best_slot(hero, item_slot)
	
	if not _is_slot_compatible(item_slot, target_slot):
		log_message.emit("슬롯 불일치: %s → %s" % [item_slot, target_slot])
		return false
	
	if InventoryManager.equip_item(hero, item_id, target_slot):
		log_message.emit("%s: %s 장착!" % [hero.hero_name, item_name])
		return true
	else:
		log_message.emit("장착 실패: %s" % item_name)
		return false


func _try_use_consumable(item_id: String, hero: Hero) -> bool:
	## 소비 아이템 사용
	var item_data: Dictionary = DataManager.get_item(item_id)
	if item_data.is_empty():
		return false
	
	var item_name: String = str(item_data.get("name", item_id))
	var effect: Dictionary = item_data.get("effect", {})
	var effect_type: String = str(effect.get("type", ""))
	var usable_in_field: bool = item_data.get("usable_in_field", false)
	
	# 필드에서 사용 가능한지 체크
	if not usable_in_field:
		log_message.emit("%s: 전투 중에만 사용 가능" % item_name)
		return false
	
	var success: bool = false
	
	match effect_type:
		"heal_percent":
			# HP 퍼센트 회복
			if hero.is_dead:
				log_message.emit("%s: 사망한 대상에게 사용 불가" % item_name)
				return false
			var heal_percent: float = float(effect.get("value", 0.3))
			var heal_amount: int = int(hero.get_max_hp() * heal_percent)
			var actual_heal: int = hero.heal(heal_amount)
			if actual_heal > 0:
				log_message.emit("%s: %s HP +%d" % [hero.hero_name, item_name, actual_heal])
				success = true
			else:
				log_message.emit("%s: HP가 이미 가득 참" % hero.hero_name)
				return false
		
		"restore_mp_percent":
			# MP 퍼센트 회복
			if hero.is_dead:
				log_message.emit("%s: 사망한 대상에게 사용 불가" % item_name)
				return false
			var mp_percent: float = float(effect.get("value", 0.5))
			var mp_amount: int = int(hero.get_max_mp() * mp_percent)
			var actual_mp: int = hero.restore_mp(mp_amount)
			if actual_mp > 0:
				log_message.emit("%s: %s MP +%d" % [hero.hero_name, item_name, actual_mp])
				success = true
			else:
				log_message.emit("%s: MP가 이미 가득 참" % hero.hero_name)
				return false
		
		"full_restore":
			# HP + MP 완전 회복
			if hero.is_dead:
				log_message.emit("%s: 사망한 대상에게 사용 불가" % item_name)
				return false
			hero.heal(hero.get_max_hp())
			hero.restore_mp(hero.get_max_mp())
			log_message.emit("%s: %s 사용 - 완전 회복!" % [hero.hero_name, item_name])
			success = true
		
		"revive":
			# 부활 (사망한 대상만)
			if not hero.is_dead:
				log_message.emit("%s: 살아있는 대상에게 사용 불가" % item_name)
				return false
			var hp_percent: float = float(effect.get("hp_percent", 0.3))
			hero.revive(hp_percent)
			log_message.emit("%s: %s 부활!" % [hero.hero_name, item_name])
			success = true
		
		"permanent_stat":
			# 영구 스탯 증가 (씨앗)
			if hero.is_dead:
				log_message.emit("%s: 사망한 대상에게 사용 불가" % item_name)
				return false
			var stat: String = str(effect.get("stat", ""))
			var value: int = int(effect.get("value", 1))
			hero.apply_seed_bonus(stat, value)
			log_message.emit("%s: %s 사용 - %s +%d!" % [hero.hero_name, item_name, stat.to_upper(), value])
			success = true
		
		"full_restore_party":
			# 파티 전원 회복 (텐트) - 드래그 대상 무관하게 전원 적용
			var party: Array = PartyManager.get_party() if PartyManager else []
			for member in party:
				if not member.is_dead:
					member.heal(member.get_max_hp())
					member.restore_mp(member.get_max_mp())
			log_message.emit("%s 사용 - 파티 전원 완전 회복!" % item_name)
			success = true
		
		_:
			log_message.emit("%s: 알 수 없는 효과" % item_name)
			return false
	
	if success:
		InventoryManager.remove_item(item_id, 1)
	
	return success


func _try_move_equipment(item_id: String, from_hero_index: int, from_slot: String, to_hero_index: int, to_slot: String) -> bool:
	var party: Array = PartyManager.get_party() if PartyManager else []
	
	if from_hero_index >= party.size() or to_hero_index >= party.size():
		return false
	
	var from_hero: Hero = party[from_hero_index]
	var to_hero: Hero = party[to_hero_index]
	var data: Dictionary = DataManager.get_equipment(item_id)
	var item_name: String = str(data.get("name", item_id))
	var item_slot: String = str(data.get("slot", ""))
	
	# 타겟 슬롯이 지정 안 되었거나 호환 안 되면 자동으로 최적 슬롯 찾기
	if to_slot.is_empty() or not _is_slot_compatible(item_slot, to_slot):
		to_slot = _determine_best_slot(to_hero, item_slot)
	
	if not _is_slot_compatible(item_slot, to_slot):
		log_message.emit("슬롯 불일치")
		return false
	
	if not InventoryManager.unequip_item(from_hero, from_slot):
		log_message.emit("해제 실패")
		return false
	
	if InventoryManager.equip_item(to_hero, item_id, to_slot):
		if from_hero_index == to_hero_index:
			log_message.emit("%s: %s 슬롯 변경" % [to_hero.hero_name, item_name])
		else:
			log_message.emit("%s → %s: %s" % [from_hero.hero_name, to_hero.hero_name, item_name])
		return true
	else:
		InventoryManager.equip_item(from_hero, item_id, from_slot)
		log_message.emit("이동 실패")
		return false


func _unequip_item(hero_index: int, slot_name: String) -> bool:
	var party: Array = PartyManager.get_party() if PartyManager else []
	if hero_index >= party.size():
		return false
	
	var hero: Hero = party[hero_index]
	var equip_id: String = hero.equipment.get(slot_name, "")
	
	if equip_id.is_empty():
		return false
	
	var equip_data: Dictionary = DataManager.get_equipment(equip_id)
	var item_name: String = str(equip_data.get("name", equip_id))
	
	if InventoryManager.unequip_item(hero, slot_name):
		log_message.emit("%s: %s 해제" % [hero.hero_name, item_name])
		return true
	else:
		log_message.emit("해제 실패")
		return false


func _determine_best_slot(hero: Hero, item_slot: String) -> String:
	var target_slot := item_slot
	
	if item_slot == "accessory":
		if hero.equipment.get("acc1", "").is_empty():
			target_slot = "acc1"
		elif hero.equipment.get("acc2", "").is_empty():
			target_slot = "acc2"
		else:
			target_slot = "acc1"
	
	return target_slot


func _is_slot_compatible(item_slot: String, target_slot: String) -> bool:
	if item_slot == target_slot:
		return true
	if item_slot == "accessory" and target_slot in ["acc1", "acc2"]:
		return true
	if item_slot == "weapon" and target_slot == "main_hand":
		return true
	if item_slot == "shield" and target_slot == "off_hand":
		return true
	return false
#endregion
