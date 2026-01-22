extends PanelContainer
class_name BattleLogUI
## 전투/시스템 로그 표시 UI

var scroll_container: ScrollContainer
var log_container: VBoxContainer

const MAX_LOG_LINES: int = 20


func _ready() -> void:
	_setup_style()
	_create_layout()


func _setup_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	add_theme_stylebox_override("panel", style)


func _create_layout() -> void:
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll_container)
	
	log_container = VBoxContainer.new()
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_container.add_theme_constant_override("separation", 2)
	scroll_container.add_child(log_container)


func add_log(message: String, color: Color = Color.WHITE) -> void:
	# 아직 초기화 안됐으면 대기
	if not log_container:
		await ready
	
	if not log_container:
		return
	
	var label := Label.new()
	label.text = message
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 9)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	log_container.add_child(label)
	
	# 최대 라인 제한
	while log_container.get_child_count() > MAX_LOG_LINES:
		var old: Node = log_container.get_child(0)
		old.queue_free()
	
	# 스크롤 맨 아래로
	_scroll_to_bottom()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if scroll_container:
		scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)


#region 편의 함수
func add_battle(message: String) -> void:
	add_log(message, Color.WHITE)


func add_damage(attacker: String, target: String, damage: int, is_crit: bool = false) -> void:
	var msg: String
	if is_crit:
		msg = "💥%s→%s 크리티컬 %d!" % [attacker, target, damage]
		add_log(msg, Color.YELLOW)
	else:
		msg = "⚔️%s→%s %d" % [attacker, target, damage]
		add_log(msg, Color.WHITE)


func add_heal(healer: String, target: String, amount: int) -> void:
	add_log("💚%s→%s +%d" % [healer, target, amount], Color.GREEN)


func add_defeat(target: String) -> void:
	add_log("💀%s 쓰러짐!" % target, Color.ORANGE_RED)


func add_exp(exp: int) -> void:
	add_log("✨+%d EXP" % exp, Color.CYAN)


func add_gold(gold: int) -> void:
	add_log("💰+%d G" % gold, Color.GOLD)


func add_item(item_name: String) -> void:
	add_log("📦%s 획득" % item_name, Color.MEDIUM_PURPLE)


func add_system(message: String) -> void:
	add_log(message, Color.GRAY)


func add_stat_info(stat_name: String, value: String) -> void:
	add_log("[%s] %s" % [stat_name, value], Color.LIGHT_BLUE)


func clear() -> void:
	for child in log_container.get_children():
		child.queue_free()
#endregion
