extends CharacterBody2D
class_name PartyLeader
## 파티 리더: 플레이어 조작, 팔로워들이 따라옴
## 스프라이트 위에 HP바 + ATB바 표시 (씬에서 참조)
## 공격 시 머리 위 아이콘 이펙트

signal moved(new_position: Vector2)
signal direction_changed(facing_right: bool)

@export var move_speed: float = 80.0

var facing_right: bool = false
var position_history: Array[Vector2] = []
var history_max_size: int = 100
var hero_id: String = ""
var hero_data: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $StatusBars/HPBar
@onready var atb_bar: ProgressBar = $StatusBars/ATBBar

# 공격 이펙트용
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
	position_history.append(global_position)
	_create_attack_icon()
	
	# BattleManager ATB 시그널 연결
	if BattleManager:
		BattleManager.hero_atb_changed.connect(_on_hero_atb_changed)
		BattleManager.hero_attacked.connect(_on_hero_attacked)


func _physics_process(_delta: float) -> void:
	var input_dir := _get_input_direction()
	
	if input_dir != Vector2.ZERO:
		velocity = input_dir * move_speed
		_update_facing(input_dir.x)
		_record_position()
	else:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 0.5)
	
	move_and_slide()
	
	# HP 바 업데이트
	_update_hp_bar()


func _create_attack_icon() -> void:
	## 공격 이펙트용 아이콘 생성
	attack_icon = Label.new()
	attack_icon.text = "⚔️"
	attack_icon.add_theme_font_size_override("font_size", 16)
	attack_icon.position = Vector2(-8, -32)
	attack_icon.z_index = 20
	attack_icon.visible = false
	add_child(attack_icon)


func _on_hero_attacked(attacked_hero_id: String) -> void:
	## 이 영웅이 공격했을 때 이펙트 재생
	if attacked_hero_id == hero_id:
		_play_attack_effect()


func _play_attack_effect() -> void:
	## 검 휘두르는 이펙트
	if not attack_icon:
		return
	
	# 직업에 맞는 아이콘
	var class_id: String = hero_data.get("class_id", "warrior")
	attack_icon.text = ATTACK_ICONS.get(class_id, "⚔️")
	
	# 방향에 따라 시작 위치/각도 설정
	var start_x: float = -12.0 if not facing_right else 12.0
	var end_x: float = 12.0 if not facing_right else -12.0
	var start_rot: float = -45.0 if not facing_right else 45.0
	var end_rot: float = 45.0 if not facing_right else -45.0
	
	attack_icon.position = Vector2(start_x, -28)
	attack_icon.rotation_degrees = start_rot
	attack_icon.visible = true
	attack_icon.modulate = Color.WHITE
	
	# 휘두르는 애니메이션
	var tween = create_tween()
	tween.set_parallel(true)
	
	# 호 그리며 이동 (위로 갔다가 내려옴)
	tween.tween_property(attack_icon, "position:x", end_x, 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(attack_icon, "position:y", -35, 0.07).set_ease(Tween.EASE_OUT)
	tween.tween_property(attack_icon, "rotation_degrees", end_rot, 0.15).set_ease(Tween.EASE_OUT)
	
	# 0.07초 후 아래로
	tween.chain().tween_property(attack_icon, "position:y", -28, 0.08).set_ease(Tween.EASE_IN)
	
	# 페이드 아웃
	tween.chain().tween_property(attack_icon, "modulate:a", 0.0, 0.1)
	tween.chain().tween_callback(func(): attack_icon.visible = false)


func _update_hp_bar() -> void:
	if not hp_bar or hero_id.is_empty():
		return
	
	var hero: Hero = PartyManager.get_hero_by_id(hero_id)
	if hero:
		var percent: float = float(hero.current_hp) / float(hero.get_max_hp()) * 100.0
		hp_bar.value = percent
		
		# HP 낮으면 색상 변경
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
		
		# ATB가 거의 찼을 때 색상 변경
		var fill_style: StyleBoxFlat = atb_bar.get_theme_stylebox("fill").duplicate()
		if value >= 0.9:
			fill_style.bg_color = Color(1.0, 1.0, 0.5)
		else:
			fill_style.bg_color = Color(1.0, 0.8, 0.2)
		atb_bar.add_theme_stylebox_override("fill", fill_style)


func _get_input_direction() -> Vector2:
	var dir := Vector2.ZERO
	dir.x = Input.get_axis("ui_left", "ui_right")
	dir.y = Input.get_axis("ui_up", "ui_down")
	return dir.normalized()


func _update_facing(x_direction: float) -> void:
	var was_facing_right := facing_right
	
	if x_direction > 0.1:
		facing_right = true
		sprite.flip_h = true
	elif x_direction < -0.1:
		facing_right = false
		sprite.flip_h = false
	
	if was_facing_right != facing_right:
		direction_changed.emit(facing_right)


func _record_position() -> void:
	if position_history.is_empty() or global_position.distance_to(position_history[-1]) > 4.0:
		position_history.append(global_position)
		moved.emit(global_position)
		
		while position_history.size() > history_max_size:
			position_history.pop_front()


func get_position_at_offset(offset: int) -> Vector2:
	var index := position_history.size() - 1 - (offset * 10)
	index = clampi(index, 0, position_history.size() - 1)
	return position_history[index]


func get_facing_right() -> bool:
	return facing_right


func setup_hero(hero: RefCounted) -> void:
	if hero == null:
		return
	
	hero_id = hero.id
	hero_data = {
		"id": hero.id,
		"name": hero.hero_name,
		"class_id": hero.class_id
	}
	
	if SpriteManager:
		var tex: Texture2D = SpriteManager.get_hero_field_sprite(hero_id)
		if tex:
			sprite.texture = tex
			sprite.scale = Vector2(1, 1)
	
	var label: Label = get_node_or_null("Label")
	if label:
		label.text = hero.hero_name.substr(0, 2)
	
	# 초기 HP 업데이트
	_update_hp_bar()
