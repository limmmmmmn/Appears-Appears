extends CharacterBody2D
class_name PartyLeader
## 파티 리더: 플레이어 조작
## 히스토리 기반으로 팔로워 위치 제공

signal direction_changed(facing_right: bool)

@export var move_speed: float = 80.0

var facing_right: bool = false
var current_direction: String = "down"
var hero_id: String = ""
var hero_data: Dictionary = {}

# 위치 히스토리
var position_history: Array[Vector2] = []
const HISTORY_SIZE: int = 200
const FOLLOWER_OFFSET: int = 8  # 팔로워 간 인덱스 간격 (조절용)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $StatusBars/HPBar
@onready var atb_bar: ProgressBar = $StatusBars/ATBBar

var attack_icon: Label = null
const ATTACK_ICONS: Dictionary = {
	"warrior": "⚔️",
	"knight": "🗡️",
	"thief": "🔪",
	"archer": "🏹",
	"mage": "✨",
	"cleric": "✝️"
}


func _ready() -> void:
	add_to_group("party_leader")
	add_to_group("party")
	_create_attack_icon()
	
	z_index = 100
	
	# 히스토리 초기화 - 뒤쪽으로 간격 두고 채움 (뱀 형태 유지)
	for i in HISTORY_SIZE:
		var follower_num: int = i / FOLLOWER_OFFSET  # 몇 번째 팔로워 위치인지
		var offset_y: float = follower_num * 18.0  # 18픽셀 간격
		position_history.append(global_position + Vector2(0, offset_y))
	
	if BattleManager:
		BattleManager.hero_atb_changed.connect(_on_hero_atb_changed)
		BattleManager.hero_attacked.connect(_on_hero_attacked)


func _physics_process(_delta: float) -> void:
	var input_dir := _get_input_direction()
	
	if input_dir != Vector2.ZERO:
		velocity = input_dir * move_speed
		_update_direction(input_dir)
		_play_walk_animation()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 0.5)
		_play_idle_animation()
	
	move_and_slide()
	
	# 매 프레임 히스토리 기록
	_record_position()
	_update_hp_bar()


func _record_position() -> void:
	# 맨 앞에 현재 위치 추가, 맨 뒤 제거
	position_history.push_front(global_position)
	if position_history.size() > HISTORY_SIZE:
		position_history.pop_back()


func get_position_at_offset(offset: int) -> Vector2:
	## 팔로워가 위치할 곳 반환 (offset: 1, 2, 3...)
	var index: int = offset * FOLLOWER_OFFSET
	index = clampi(index, 0, position_history.size() - 1)
	return position_history[index]


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	dir.x = Input.get_axis("ui_left", "ui_right")
	dir.y = Input.get_axis("ui_up", "ui_down")
	return dir.normalized()


func _update_direction(input_dir: Vector2) -> void:
	var was_facing_right := facing_right
	
	if abs(input_dir.x) > abs(input_dir.y):
		if input_dir.x > 0:
			current_direction = "right"
			facing_right = true
		else:
			current_direction = "left"
			facing_right = false
	else:
		if input_dir.y > 0:
			current_direction = "down"
		else:
			current_direction = "up"
		if input_dir.x > 0.1:
			facing_right = true
		elif input_dir.x < -0.1:
			facing_right = false
	
	if was_facing_right != facing_right:
		direction_changed.emit(facing_right)


func _play_walk_animation() -> void:
	if not animated_sprite:
		return
	var anim_name := "walk_" + current_direction
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
			animated_sprite.play(anim_name)


func _play_idle_animation() -> void:
	if not animated_sprite:
		return
	var anim_name := "walk_" + current_direction
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(anim_name):
		animated_sprite.stop()
		animated_sprite.animation = anim_name
		animated_sprite.frame = 1


func _create_attack_icon() -> void:
	attack_icon = Label.new()
	attack_icon.text = "⚔️"
	attack_icon.add_theme_font_size_override("font_size", 16)
	attack_icon.position = Vector2(-8, -32)
	attack_icon.z_index = 20
	attack_icon.visible = false
	add_child(attack_icon)


func _on_hero_attacked(attacked_hero_id: String) -> void:
	if attacked_hero_id == hero_id:
		_play_attack_effect()


func _play_attack_effect() -> void:
	if not attack_icon:
		return
	
	var class_id: String = hero_data.get("class_id", "warrior")
	attack_icon.text = ATTACK_ICONS.get(class_id, "⚔️")
	
	var start_x: float = -12.0 if not facing_right else 12.0
	var end_x: float = 12.0 if not facing_right else -12.0
	var start_rot: float = -45.0 if not facing_right else 45.0
	var end_rot: float = 45.0 if not facing_right else -45.0
	
	attack_icon.position = Vector2(start_x, -28)
	attack_icon.rotation_degrees = start_rot
	attack_icon.visible = true
	attack_icon.modulate = Color.WHITE
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(attack_icon, "position:x", end_x, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(attack_icon, "position:y", -35, 0.07).set_ease(Tween.EASE_OUT)
	tween.tween_property(attack_icon, "rotation_degrees", end_rot, 0.15).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(attack_icon, "position:y", -28, 0.08).set_ease(Tween.EASE_IN)
	tween.chain().tween_property(attack_icon, "modulate:a", 0.0, 0.1)
	tween.chain().tween_callback(func(): attack_icon.visible = false)


func _update_hp_bar() -> void:
	if not hp_bar or hero_id.is_empty():
		return
	
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero:
		var percent: float = float(hero.current_hp) / float(hero.get_max_hp()) * 100.0
		hp_bar.value = percent
		
		var fill_style: StyleBoxFlat = hp_bar.get_theme_stylebox("fill").duplicate()
		if percent <= 25:
			fill_style.bg_color = Color(0.9, 0.2, 0.2)
		elif percent <= 50:
			fill_style.bg_color = Color(0.9, 0.7, 0.2)
		else:
			fill_style.bg_color = Color(0.2, 0.8, 0.2)
		hp_bar.add_theme_stylebox_override("fill", fill_style)


func _on_hero_atb_changed(changed_hero_id: String, value: float) -> void:
	if changed_hero_id == hero_id and atb_bar:
		atb_bar.value = value * 100.0
		
		var fill_style: StyleBoxFlat = atb_bar.get_theme_stylebox("fill").duplicate()
		if value >= 0.9:
			fill_style.bg_color = Color(1.0, 1.0, 0.5)
		else:
			fill_style.bg_color = Color(1.0, 0.8, 0.2)
		atb_bar.add_theme_stylebox_override("fill", fill_style)


func get_facing_right() -> bool:
	return facing_right


func get_current_direction() -> String:
	return current_direction


func setup_hero(hero: RefCounted) -> void:
	if hero == null:
		return
	
	hero_id = hero.id
	hero_data = {
		"id": hero.id,
		"name": hero.hero_name,
		"class_id": hero.class_id
	}
	
	if SpriteManager and animated_sprite:
		var sprite_frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero_id)
		if sprite_frames:
			animated_sprite.sprite_frames = sprite_frames
			animated_sprite.play("walk_down")
			animated_sprite.stop()
			animated_sprite.frame = 1
	
	var label: Label = get_node_or_null("Label")
	if label:
		label.text = hero.hero_name.substr(0, 2)
	
	_update_hp_bar()
