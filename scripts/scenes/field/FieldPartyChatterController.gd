extends RefCounted
class_name FieldPartyChatterController
## ?꾨뱶 ?뚰떚 ????먮룞 ??? ?ㅻ쾭?덉씠/荑⑤떎???쒖뼱

const PARTY_CHATTER_ATTACK_LINES: Array[String] = [
	"醫뗭븘, 諛쏆븘爾?",
	"媛꾨떎!",
	"吏湲덉씠??",
	"?곌퀎 ?ㅼ뼱媛꾨떎!",
]
const PARTY_CHATTER_SKILL_LINES: Array[String] = [
	"湲곗닠 媛꾨떎!",
	"諛쏆븘??",
	"?쒓납?쇰줈 紐곗븘!",
	"?ш린 諛쒕룞!",
]
const PARTY_CHATTER_HIT_LINES: Array[String] = [
	"??.!",
	"愿쒖갖?? 踰꾪떥 ???덉뼱!",
	"醫留???踰꾪뀲!",
	"?꾩쭅 ?앸궃 寃??꾨깘!",
]
const PARTY_CHATTER_ENEMY_SEEN_LINES: Array[String] = [
	"?곸씠 ?꾩껌 留롮븘 蹂댁씠?붾뜲?",
	"?쒕몢瑜닿린 ?꾩뿉 ?뺣━?섏옄.",
	"?쒖빞 ?뺣낫?? 媛곸옄 議곗떖!",
	"移⑥갑?섍쾶 ?섎굹???딆옄.",
]
const PARTY_CHATTER_ATTACK_REPLY_LINES: Array[String] = [
	"醫뗭븘, 洹몃?濡?諛??",
	"媛꾧꺽 留욎떠???ㅼ뼱媛꾨떎!",
	"醫뗭븘! ??대컢 ?≫삍??",
]
const PARTY_CHATTER_SKILL_REPLY_LINES: Array[String] = [
	"洹?湲곗닠??留욎떠 ?ㅼ뼱媛寃좎뼱!",
	"吏湲??먮쫫 醫뗭븘!",
	"洹몃?濡?紐곗븘遺숈뿬!",
]
const PARTY_CHATTER_HIT_REPLY_LINES: Array[String] = [
	"踰꾪뀲! 諛붾줈 而ㅻ쾭?좉쾶!",
	"愿쒖갖?? ?ㅻ뒗 ?닿? 蹂몃떎!",
	"吏묒쨷! ?꾩쭅 ??留뚰빐!",
]
const PARTY_CHATTER_ENEMY_SEEN_REPLY_LINES: Array[String] = [
	"?? ?쒖꽌遺???뺣━?섏옄.",
	"嫄곕━ ?좎??섎㈃ 踰꾪떥 ???덉뼱.",
	"?좊몢瑜?留됯퀬 媛?留욎텛??",
]

var host: Node2D = null
var field_world_effect_z: int = 0
var party_chatter_layer_index: int = 220
var bubble_extra_lift: float = 24.0
var bubble_hold_time: float = 1.65
var bubble_fade_time: float = 0.22

var party_chatter_layer: CanvasLayer = null
var party_chatter_root: Control = null
var party_chatter_cooldown: float = 0.0
var party_chatter_attack_cooldown: float = 0.0
var party_chatter_hit_cooldown: float = 0.0
var party_chatter_enemy_seen_cooldown: float = 0.0
var party_chatter_queue: Array[Dictionary] = []
var party_chatter_is_showing: bool = false
var active_party_chatter_speaker: Node2D = null
var active_party_chatter_bubble: PanelContainer = null
var active_party_chatter_time_left: float = 0.0

var runtime_paused: bool = false
var runtime_recruit_event_active: bool = false
var runtime_external_blocking: bool = false
var runtime_party_leader: PartyMember = null
var runtime_party_followers: Array[PartyMember] = []


func setup(
	p_host: Node2D,
	p_field_world_effect_z: int,
	p_party_chatter_layer_index: int,
	p_bubble_extra_lift: float,
	p_bubble_hold_time: float,
	p_bubble_fade_time: float
) -> void:
	host = p_host
	field_world_effect_z = p_field_world_effect_z
	party_chatter_layer_index = p_party_chatter_layer_index
	bubble_extra_lift = p_bubble_extra_lift
	bubble_hold_time = p_bubble_hold_time
	bubble_fade_time = p_bubble_fade_time


func set_runtime_context(
	p_paused: bool,
	p_recruit_event_active: bool,
	p_external_blocking: bool,
	p_party_leader: PartyMember,
	p_party_followers: Array[PartyMember]
) -> void:
	runtime_paused = p_paused
	runtime_recruit_event_active = p_recruit_event_active
	runtime_external_blocking = p_external_blocking
	runtime_party_leader = p_party_leader
	runtime_party_followers = p_party_followers


func ensure_overlay() -> void:
	if host == null:
		return
	if party_chatter_layer != null and is_instance_valid(party_chatter_layer):
		return

	party_chatter_layer = CanvasLayer.new()
	party_chatter_layer.layer = party_chatter_layer_index
	party_chatter_layer.name = "PartyChatterLayer"
	host.add_child(party_chatter_layer)

	party_chatter_root = Control.new()
	party_chatter_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	party_chatter_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	party_chatter_layer.add_child(party_chatter_root)


func get_overlay_root() -> Control:
	return party_chatter_root


func is_showing() -> bool:
	return party_chatter_is_showing


func clear_queue() -> void:
	party_chatter_queue.clear()
	if active_party_chatter_bubble != null and is_instance_valid(active_party_chatter_bubble):
		active_party_chatter_bubble.queue_free()
	active_party_chatter_speaker = null
	active_party_chatter_bubble = null
	active_party_chatter_time_left = 0.0
	party_chatter_is_showing = false


func update_cooldowns_and_lifecycle(delta: float) -> void:
	party_chatter_cooldown = maxf(0.0, party_chatter_cooldown - delta)
	party_chatter_attack_cooldown = maxf(0.0, party_chatter_attack_cooldown - delta)
	party_chatter_hit_cooldown = maxf(0.0, party_chatter_hit_cooldown - delta)
	party_chatter_enemy_seen_cooldown = maxf(0.0, party_chatter_enemy_seen_cooldown - delta)
	_update_party_chatter_lifecycle(delta)


func update_blocking_state() -> void:
	if runtime_recruit_event_active:
		return
	if not runtime_external_blocking:
		return
	clear_queue()


func update_enemy_seen_chatter(field_enemies: Array[FieldEnemy], camera_rect: Rect2) -> void:
	if runtime_recruit_event_active or runtime_external_blocking:
		return
	if party_chatter_enemy_seen_cooldown > 0.0:
		return
	if party_chatter_cooldown > 0.0:
		return

	var visible_enemy_count: int = 0
	for enemy in field_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if camera_rect.has_point(enemy.global_position):
			visible_enemy_count += 1

	if visible_enemy_count < 4:
		return
	if randf() > 0.28:
		return

	var speaker_member: PartyMember = _pick_random_party_member_for_chatter()
	var speaker_id: String = speaker_member.hero_id if speaker_member != null else ""
	var line: String = _get_field_chatter_line("enemy_many", speaker_id, PARTY_CHATTER_ENEMY_SEEN_LINES)
	var reply: String = _get_field_chatter_line("enemy_many_reply", "", PARTY_CHATTER_ENEMY_SEEN_REPLY_LINES)
	show_party_chatter_exchange("", line, reply, Color(1.0, 0.95, 0.75, 1.0), Color(0.92, 0.98, 1.0, 1.0))
	party_chatter_enemy_seen_cooldown = randf_range(4.0, 7.0)
	party_chatter_cooldown = 1.1


func on_hero_attacked(hero_id: String) -> void:
	if _is_battle_chatter_context():
		return
	if runtime_paused:
		return
	if runtime_recruit_event_active or runtime_external_blocking:
		return
	if party_chatter_attack_cooldown > 0.0 or party_chatter_cooldown > 0.0:
		return
	if randf() > 0.55:
		return

	var line_trigger: String = "attack"
	var reply_trigger: String = "attack_reply"
	if randf() < 0.35:
		line_trigger = "skill"
		reply_trigger = "skill_reply"

	var fallback_line_pool: Array[String] = PARTY_CHATTER_SKILL_LINES if line_trigger == "skill" else PARTY_CHATTER_ATTACK_LINES
	var fallback_reply_pool: Array[String] = PARTY_CHATTER_SKILL_REPLY_LINES if reply_trigger == "skill_reply" else PARTY_CHATTER_ATTACK_REPLY_LINES
	var line: String = _get_field_chatter_line(line_trigger, hero_id, fallback_line_pool)
	var reply: String = _get_field_chatter_line(reply_trigger, "", fallback_reply_pool)
	show_party_chatter_exchange(hero_id, line, reply, Color(0.85, 1.0, 0.85, 1.0), Color(0.9, 0.96, 1.0, 1.0))
	party_chatter_attack_cooldown = randf_range(0.9, 1.5)
	party_chatter_cooldown = 0.7


func on_hero_damaged(hero_id: String) -> void:
	if _is_battle_chatter_context():
		return
	if runtime_paused:
		return
	if runtime_recruit_event_active or runtime_external_blocking:
		return
	if party_chatter_hit_cooldown > 0.0 or party_chatter_cooldown > 0.0:
		return
	if randf() > 0.72:
		return

	var line: String = _get_field_chatter_line("damaged", hero_id, PARTY_CHATTER_HIT_LINES)
	var reply: String = _get_field_chatter_line("damaged_reply", "", PARTY_CHATTER_HIT_REPLY_LINES)
	show_party_chatter_exchange(hero_id, line, reply, Color(1.0, 0.85, 0.85, 1.0), Color(0.9, 1.0, 0.9, 1.0))
	party_chatter_hit_cooldown = randf_range(1.0, 1.8)
	party_chatter_cooldown = 0.7


func show_party_chatter(hero_id: String, text: String, color: Color = Color(0.95, 0.95, 1.0, 1.0)) -> void:
	if text.is_empty():
		return
	var speaker: PartyMember = _find_party_member_by_hero_id(hero_id)
	if not _is_party_member_alive_for_chatter(speaker):
		speaker = null
	if speaker == null:
		var members: Array[PartyMember] = _get_alive_party_members_for_chatter()
		if members.is_empty():
			return
		speaker = members[randi() % members.size()]
	if speaker == null or not is_instance_valid(speaker):
		return

	_enqueue_party_chatter(speaker, text, color)


func show_party_chatter_exchange(
	hero_id: String,
	first_text: String,
	second_text: String,
	first_color: Color = Color(0.95, 0.95, 1.0, 1.0),
	second_color: Color = Color(0.95, 0.95, 1.0, 1.0)
) -> void:
	var first_speaker: PartyMember = _find_party_member_by_hero_id(hero_id)
	if not _is_party_member_alive_for_chatter(first_speaker):
		first_speaker = null
	if first_speaker == null:
		var members: Array[PartyMember] = _get_alive_party_members_for_chatter()
		if members.is_empty():
			return
		first_speaker = members[randi() % members.size()]
	_enqueue_party_chatter(first_speaker, first_text, first_color)

	if second_text.is_empty():
		return
	var second_speaker: PartyMember = _get_other_party_member_for_chatter(first_speaker)
	if second_speaker == null:
		return
	_enqueue_party_chatter(second_speaker, second_text, second_color)


func show_party_chatter_on_node(
	speaker: Node2D,
	text: String,
	color: Color = Color(0.95, 0.95, 1.0, 1.0)
) -> void:
	if speaker == null or not is_instance_valid(speaker):
		return
	if text.is_empty():
		return

	party_chatter_is_showing = true

	var bubble: PanelContainer = _create_party_chatter_bubble(speaker, text, color)
	if bubble == null:
		return
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.z_index = field_world_effect_z + 100
	bubble.position = Vector2.ZERO

	ensure_overlay()
	if party_chatter_root == null or not is_instance_valid(party_chatter_root):
		return
	party_chatter_root.add_child(bubble)
	active_party_chatter_speaker = speaker
	active_party_chatter_bubble = bubble
	active_party_chatter_time_left = bubble_hold_time + bubble_fade_time
	_position_party_chatter_bubble(speaker, bubble)
	bubble.modulate.a = 1.0


func update_active_bubble_position(active_battles: Dictionary) -> void:
	if active_party_chatter_speaker == null or not is_instance_valid(active_party_chatter_speaker):
		return
	if active_party_chatter_bubble == null or not is_instance_valid(active_party_chatter_bubble):
		return
	_position_party_chatter_bubble(active_party_chatter_speaker, active_party_chatter_bubble)
	_resolve_battle_window_overlap_with_chatter(active_battles)


func _enqueue_party_chatter(speaker: PartyMember, text: String, color: Color) -> void:
	if runtime_paused:
		return
	if runtime_recruit_event_active or runtime_external_blocking:
		return
	if not _is_party_member_alive_for_chatter(speaker):
		return
	if text.is_empty():
		return
	party_chatter_queue.append({
		"speaker": speaker,
		"text": text,
		"color": color,
	})
	_try_show_next_party_chatter()


func _try_show_next_party_chatter() -> void:
	if runtime_paused:
		return
	if runtime_recruit_event_active or runtime_external_blocking:
		return
	if party_chatter_is_showing:
		return
	while not party_chatter_queue.is_empty():
		var entry: Dictionary = party_chatter_queue.pop_front()
		var speaker_any: Variant = entry.get("speaker", null)
		if speaker_any == null or not is_instance_valid(speaker_any):
			continue
		var speaker: PartyMember = speaker_any as PartyMember
		if not _is_party_member_alive_for_chatter(speaker):
			continue
		var text: String = str(entry.get("text", ""))
		if text.is_empty():
			continue
		var color: Color = entry.get("color", Color(0.95, 0.95, 1.0, 1.0)) as Color
		show_party_chatter_on_node(speaker, text, color)
		return


func _on_party_chatter_bubble_finished(bubble: PanelContainer) -> void:
	if bubble != null and is_instance_valid(bubble):
		bubble.queue_free()
	active_party_chatter_speaker = null
	active_party_chatter_bubble = null
	active_party_chatter_time_left = 0.0
	party_chatter_is_showing = false
	_try_show_next_party_chatter()


func _position_party_chatter_bubble(speaker: Node2D, bubble: PanelContainer) -> void:
	if host == null:
		return
	if speaker == null or not is_instance_valid(speaker):
		return
	if bubble == null or not is_instance_valid(bubble):
		return

	var sprite_top_y: float = -16.0
	var sprite: AnimatedSprite2D = speaker.get_node_or_null("AnimatedSprite2D")
	if sprite == null:
		for child in speaker.get_children():
			if child is AnimatedSprite2D:
				sprite = child as AnimatedSprite2D
				break
	if sprite != null and is_instance_valid(sprite) and sprite.sprite_frames != null:
		var anim_name: StringName = sprite.animation
		var frame_idx: int = sprite.frame
		if sprite.sprite_frames.has_animation(anim_name):
			var tex: Texture2D = sprite.sprite_frames.get_frame_texture(anim_name, frame_idx)
			if tex != null:
				sprite_top_y = -float(tex.get_height()) * absf(sprite.scale.y) * 0.5

	var lift: float = bubble_extra_lift
	var extra_offset: Vector2 = Vector2.ZERO
	if speaker is PartyMember:
		var member: PartyMember = speaker as PartyMember
		if member != null:
			lift = member.get_chatter_bubble_extra_lift()
			extra_offset = member.get_chatter_bubble_offset()
	var gap: float = 10.0 + lift
	var screen_pos: Vector2 = host.get_viewport().get_canvas_transform() * speaker.global_position
	var x: float = screen_pos.x - bubble.size.x * 0.5 + extra_offset.x
	var y: float = screen_pos.y + sprite_top_y - gap - bubble.size.y + extra_offset.y
	bubble.position = Vector2(x, y)


func _create_party_chatter_bubble(_speaker: Node2D, text: String, color: Color) -> PanelContainer:
	var bubble_scene_res: PackedScene = load("res://scenes/ui/SpeechBubble.tscn") as PackedScene
	if bubble_scene_res != null:
		var node: Node = bubble_scene_res.instantiate()
		var bubble_scene: PanelContainer = node as PanelContainer
		if bubble_scene != null:
			if bubble_scene.has_method("configure"):
				bubble_scene.call("configure", text, color)
			else:
				var scene_label: Label = bubble_scene.get_node_or_null("TextLabel") as Label
				if scene_label != null:
					scene_label.text = text
			return bubble_scene
		if node != null and is_instance_valid(node):
			node.queue_free()

	var fallback := PanelContainer.new()
	var bubble_style := StyleBoxFlat.new()
	bubble_style.bg_color = Color(1.0, 1.0, 1.0, 0.96)
	bubble_style.border_width_left = 1
	bubble_style.border_width_top = 1
	bubble_style.border_width_right = 1
	bubble_style.border_width_bottom = 1
	bubble_style.border_color = Color(0.0, 0.0, 0.0, 1.0)
	bubble_style.corner_radius_top_left = 4
	bubble_style.corner_radius_top_right = 4
	bubble_style.corner_radius_bottom_left = 4
	bubble_style.corner_radius_bottom_right = 4
	bubble_style.content_margin_left = 6
	bubble_style.content_margin_right = 6
	bubble_style.content_margin_top = 3
	bubble_style.content_margin_bottom = 3
	fallback.add_theme_stylebox_override("panel", bubble_style)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 1.0))
	label.add_theme_constant_override("line_spacing", 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size = Vector2(132.0, 0.0)
	fallback.add_child(label)
	return fallback


func _resolve_battle_window_overlap_with_chatter(active_battles: Dictionary) -> void:
	if host == null:
		return
	if active_party_chatter_bubble == null or not is_instance_valid(active_party_chatter_bubble):
		return
	var bubble_size: Vector2 = active_party_chatter_bubble.size
	if bubble_size.x <= 0.0 or bubble_size.y <= 0.0:
		return
	var bubble_rect := Rect2(active_party_chatter_bubble.position, bubble_size)
	var viewport_size: Vector2 = host.get_viewport_rect().size
	var threshold_w: float = bubble_rect.size.x * 0.5

	for battle_id_any in active_battles.keys():
		var battle_id: int = int(battle_id_any)
		var battle_data: Dictionary = active_battles.get(battle_id, {})
		var window_any: Variant = battle_data.get("window", null)
		if window_any == null or not is_instance_valid(window_any):
			continue
		var window: Control = window_any as Control
		if window == null:
			continue
		var window_size: Vector2 = window.size
		if window_size.x <= 0.0 or window_size.y <= 0.0:
			window_size = window.custom_minimum_size
		if window_size.x <= 0.0 or window_size.y <= 0.0:
			continue
		var win_rect := Rect2(window.global_position, window_size)
		var overlap: Rect2 = bubble_rect.intersection(win_rect)
		if overlap.size.x <= threshold_w:
			continue

		var bubble_cx: float = bubble_rect.position.x + bubble_rect.size.x * 0.5
		var win_cx: float = win_rect.position.x + win_rect.size.x * 0.5
		var dir_sign: float = -1.0 if win_cx <= bubble_cx else 1.0
		var shift_x: float = overlap.size.x + 18.0
		var new_x: float = window.global_position.x + dir_sign * shift_x
		new_x = clampf(new_x, -window_size.x + 40.0, viewport_size.x - 40.0)
		var new_y: float = clampf(window.global_position.y, 0.0, viewport_size.y - 30.0)
		var target_pos := Vector2(new_x, new_y)
		if window.global_position.distance_to(target_pos) < 2.0:
			continue

		var prev_target: Vector2 = window.get_meta("chatter_push_target", Vector2.INF) as Vector2
		if prev_target != Vector2.INF and prev_target.distance_to(target_pos) < 2.0:
			continue
		window.set_meta("chatter_push_target", target_pos)

		var prev_tween: Variant = window.get_meta("chatter_push_tween", null)
		if prev_tween != null and prev_tween is Tween:
			var tw_prev: Tween = prev_tween as Tween
			if tw_prev != null and tw_prev.is_valid():
				tw_prev.kill()

		var tw := window.create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(window, "global_position", target_pos, 0.16)
		window.set_meta("chatter_push_tween", tw)


func _update_party_chatter_lifecycle(delta: float) -> void:
	if active_party_chatter_bubble == null or not is_instance_valid(active_party_chatter_bubble):
		return
	if not party_chatter_is_showing:
		return
	active_party_chatter_time_left = maxf(0.0, active_party_chatter_time_left - delta)
	if active_party_chatter_time_left <= bubble_fade_time:
		var alpha: float = active_party_chatter_time_left / bubble_fade_time if bubble_fade_time > 0.0 else 0.0
		active_party_chatter_bubble.modulate.a = clampf(alpha, 0.0, 1.0)
	else:
		active_party_chatter_bubble.modulate.a = 1.0
	if active_party_chatter_time_left <= 0.0:
		_on_party_chatter_bubble_finished(active_party_chatter_bubble)


func _find_party_member_by_hero_id(hero_id: String) -> PartyMember:
	if hero_id.is_empty():
		return null
	if runtime_party_leader != null and is_instance_valid(runtime_party_leader) and runtime_party_leader.hero_id == hero_id:
		return runtime_party_leader
	for follower in runtime_party_followers:
		if follower == null or not is_instance_valid(follower):
			continue
		if follower.hero_id == hero_id:
			return follower
	return null


func _get_alive_party_members_for_chatter() -> Array[PartyMember]:
	var members: Array[PartyMember] = []
	if _is_party_member_alive_for_chatter(runtime_party_leader):
		members.append(runtime_party_leader)
	for follower in runtime_party_followers:
		if _is_party_member_alive_for_chatter(follower):
			members.append(follower)
	return members


func _is_party_member_alive_for_chatter(member: PartyMember) -> bool:
	if member == null or not is_instance_valid(member):
		return false
	if member.hero_id.is_empty():
		return true
	if PartyManager == null:
		return true
	var hero: Hero = PartyManager.get_hero_by_id(member.hero_id)
	if hero == null:
		return true
	return not hero.is_dead


func _get_other_party_member_for_chatter(exclude_member: PartyMember) -> PartyMember:
	var members: Array[PartyMember] = _get_alive_party_members_for_chatter()
	var candidates: Array[PartyMember] = []
	for member in members:
		if member == exclude_member:
			continue
		candidates.append(member)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func _pick_random_party_member_for_chatter() -> PartyMember:
	var members: Array[PartyMember] = _get_alive_party_members_for_chatter()
	if members.is_empty():
		return null
	return members[randi() % members.size()]


func _get_field_chatter_line(trigger: String, hero_id: String, fallback_pool: Array[String]) -> String:
	if DialogueManager != null and DialogueManager.has_method("get_field_line"):
		var line: String = str(DialogueManager.call("get_field_line", trigger, hero_id))
		if not line.is_empty():
			return line
	if fallback_pool.is_empty():
		return ""
	return fallback_pool[randi() % fallback_pool.size()]


func _is_battle_chatter_context() -> bool:
	if BattleManager == null:
		return false
	return BattleManager.get_active_battle_count() > 0
