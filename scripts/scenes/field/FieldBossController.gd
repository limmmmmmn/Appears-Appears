extends RefCounted
class_name FieldBossController
## 필드 보스 접촉/보상 팝업/보스전 진입 제어

var host: Node = null
var on_start_boss_battle: Callable = Callable()
var on_system_log: Callable = Callable()
var has_unclaimed_rewards: Callable = Callable()

var pending_boss_data: Dictionary = {}
var boss_reward_popup: CanvasLayer = null


func setup(
	p_host: Node,
	p_on_start_boss_battle: Callable,
	p_on_system_log: Callable,
	p_has_unclaimed_rewards: Callable
) -> void:
	host = p_host
	on_start_boss_battle = p_on_start_boss_battle
	on_system_log = p_on_system_log
	has_unclaimed_rewards = p_has_unclaimed_rewards


func handle_boss_contact(
	enemy_id: String,
	is_elite: bool,
	collision_pos: Vector2,
	field_enemy: Node,
	party_leader: Node
) -> void:
	if party_leader and party_leader.has_method("set_boss_battle_mode"):
		party_leader.call("set_boss_battle_mode", true)

	pending_boss_data = {
		"enemy_id": enemy_id,
		"is_elite": is_elite,
		"collision_pos": collision_pos,
		"field_enemy": field_enemy
	}

	var has_rewards: bool = false
	if has_unclaimed_rewards.is_valid():
		has_rewards = bool(has_unclaimed_rewards.call())
	elif BattleManager:
		var rewards: Dictionary = BattleManager.get_accumulated_rewards()
		has_rewards = int(rewards.get("gold", 0)) > 0 or int(rewards.get("exp", 0)) > 0 or not (rewards.get("items", []) as Array).is_empty()

	if has_rewards:
		show_reward_popup()
	elif on_start_boss_battle.is_valid():
		on_start_boss_battle.call()


func show_reward_popup() -> void:
	if host == null:
		return
	if boss_reward_popup:
		boss_reward_popup.queue_free()

	boss_reward_popup = CanvasLayer.new()
	boss_reward_popup.layer = 100
	boss_reward_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(boss_reward_popup)
	host.get_tree().paused = true

	var full_screen := Control.new()
	full_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	boss_reward_popup.add_child(full_screen)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0, 0, 0, 0.7)
	full_screen.add_child(dimmer)

	var center_panel := PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.offset_left = -160
	center_panel.offset_right = 160
	center_panel.offset_top = -100
	center_panel.offset_bottom = 100
	center_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.1, 0.2, 0.95)
	panel_style.border_width_left = 3
	panel_style.border_width_top = 3
	panel_style.border_width_right = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = Color(1.0, 0.5, 0.3)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 15
	panel_style.content_margin_bottom = 15
	center_panel.add_theme_stylebox_override("panel", panel_style)
	full_screen.add_child(center_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center_panel.add_child(vbox)

	var title := Label.new()
	title.text = "보스 조우!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "수령하지 않은 보상이 있습니다.\n보스전 전에 먼저 수령할까요?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(desc)

	var rewards: Dictionary = BattleManager.get_accumulated_rewards() if BattleManager else {}
	var reward_hbox := HBoxContainer.new()
	reward_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	reward_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(reward_hbox)

	var gold_lbl := Label.new()
	gold_lbl.text = "골드: %d" % int(rewards.get("gold", 0))
	gold_lbl.add_theme_font_size_override("font_size", 11)
	gold_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	reward_hbox.add_child(gold_lbl)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_hbox)

	var claim_btn := Button.new()
	claim_btn.text = "보상 수령"
	claim_btn.custom_minimum_size = Vector2(120, 35)
	claim_btn.add_theme_font_size_override("font_size", 12)
	claim_btn.focus_mode = Control.FOCUS_NONE
	var claim_style := StyleBoxFlat.new()
	claim_style.bg_color = Color(0.3, 0.5, 0.3)
	claim_style.corner_radius_top_left = 4
	claim_style.corner_radius_top_right = 4
	claim_style.corner_radius_bottom_left = 4
	claim_style.corner_radius_bottom_right = 4
	claim_style.border_width_left = 2
	claim_style.border_width_top = 2
	claim_style.border_width_right = 2
	claim_style.border_width_bottom = 2
	claim_style.border_color = Color.WHITE
	claim_btn.add_theme_stylebox_override("normal", claim_style)
	claim_btn.pressed.connect(claim_rewards_and_start)
	btn_hbox.add_child(claim_btn)

	var skip_btn := Button.new()
	skip_btn.text = "보상 건너뛰기"
	skip_btn.custom_minimum_size = Vector2(120, 35)
	skip_btn.add_theme_font_size_override("font_size", 12)
	skip_btn.focus_mode = Control.FOCUS_NONE
	var skip_style := StyleBoxFlat.new()
	skip_style.bg_color = Color(0.4, 0.2, 0.2)
	skip_style.corner_radius_top_left = 4
	skip_style.corner_radius_top_right = 4
	skip_style.corner_radius_bottom_left = 4
	skip_style.corner_radius_bottom_right = 4
	skip_btn.add_theme_stylebox_override("normal", skip_style)
	skip_btn.add_theme_color_override("font_color", Color(0.8, 0.6, 0.6))
	skip_btn.pressed.connect(skip_rewards_and_start)
	btn_hbox.add_child(skip_btn)


func claim_rewards_and_start() -> void:
	_close_popup_and_unpause()
	if BattleManager:
		BattleManager.claim_accumulated_rewards()
	_log("보상을 수령했다.")
	if on_start_boss_battle.is_valid():
		on_start_boss_battle.call()


func skip_rewards_and_start() -> void:
	_close_popup_and_unpause()
	if BattleManager:
		BattleManager.reset_accumulated_rewards()
	_log("보상을 건너뛰었다.")
	if on_start_boss_battle.is_valid():
		on_start_boss_battle.call()


func _close_popup_and_unpause() -> void:
	if host and host.get_tree():
		host.get_tree().paused = false
	if boss_reward_popup:
		boss_reward_popup.queue_free()
		boss_reward_popup = null


func clear_popup() -> void:
	_close_popup_and_unpause()


func get_pending_boss_data() -> Dictionary:
	return pending_boss_data


func clear_pending_boss_data() -> void:
	pending_boss_data.clear()


func _log(text: String) -> void:
	if on_system_log.is_valid():
		on_system_log.call(text)
