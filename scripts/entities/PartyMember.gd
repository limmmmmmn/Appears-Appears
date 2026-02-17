extends CharacterBody2D
class_name PartyMember
## 파티 멤버: 리더/팔로워 통합
## JRPG 스네이크 무브먼트 - 리더가 지나간 길을 따라감

@export var move_speed: float = 60.0

var is_leader: bool = false
var member_index: int = 0  # 0=리더, 1,2,3=팔로워
var hero_id: String = ""
var hero_data: Dictionary = {}

var facing_right: bool = false
var current_direction: String = "down"

# 보스전 모드 (이동 정지)
var is_in_boss_battle: bool = false

# 잠시 멈춤 (적 조우 시)
var is_stunned: bool = false
var stun_timer: float = 0.0

# 스네이크 무브먼트용
var path_history: Array[Vector2] = []  # 리더만 사용
var leader_ref: PartyMember = null  # 팔로워만 사용
const PATH_RECORD_DISTANCE: float = 4.0  # 몇 픽셀마다 기록할지
const FOLLOW_DISTANCE: float = 24.0  # 팔로워 간 거리

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var hp_bar: ProgressBar = $StatusBars/HPBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("party")


func _physics_process(delta: float) -> void:
	_apply_dead_visual()

	# 보스전 중에는 이동 정지
	if is_in_boss_battle:
		velocity = Vector2.ZERO
		_play_idle_animation()
		return

	# 잠시 멈춤 처리 (적 조우 시)
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0:
			is_stunned = false
		velocity = Vector2.ZERO
		_play_idle_animation()
		return

	if is_leader:
		_process_leader(delta)
	else:
		_process_follower(delta)
	
	_update_hp_bar()


#=============================================================================
# 리더 로직
#=============================================================================
func _process_leader(_delta: float) -> void:
	# WASD + 방향키 입력 체크
	var input_dir := Vector2.ZERO

	# WASD 입력
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1

	# 방향키도 지원
	input_dir.x += Input.get_axis("ui_left", "ui_right")
	input_dir.y += Input.get_axis("ui_up", "ui_down")

	input_dir = input_dir.normalized()

	# 키보드 입력이 있으면 이동
	if input_dir != Vector2.ZERO:
		velocity = input_dir * move_speed
		_update_direction(input_dir)
		_play_walk_animation()
		move_and_slide()
		_record_path()
		return

	# 입력 없음 - 대기
	velocity = Vector2.ZERO
	_play_idle_animation()


func set_boss_battle_mode(enabled: bool) -> void:
	## 보스전 모드 설정 (이동 정지/복귀)
	is_in_boss_battle = enabled
	if enabled:
		velocity = Vector2.ZERO


func brief_pause(duration: float = 0.15) -> void:
	## 잠시 멈춤 (적 조우 시 호출)
	is_stunned = true
	stun_timer = duration
	velocity = Vector2.ZERO


func _record_path() -> void:
	## 일정 거리 이동할 때마다 경로 기록
	if path_history.is_empty():
		path_history.append(global_position)
		return
	
	if global_position.distance_to(path_history[0]) >= PATH_RECORD_DISTANCE:
		path_history.push_front(global_position)
		
		# 히스토리 크기 제한
		var max_size: int = 500
		while path_history.size() > max_size:
			path_history.pop_back()


func get_path_position(distance: float) -> Vector2:
	## 리더로부터 특정 거리만큼 떨어진 경로 위치 반환
	if path_history.is_empty():
		return global_position
	
	var accumulated: float = 0.0
	var prev_pos: Vector2 = global_position
	
	for pos in path_history:
		var segment: float = prev_pos.distance_to(pos)
		
		if accumulated + segment >= distance:
			# 이 세그먼트 안에 목표 지점이 있음
			var remaining: float = distance - accumulated
			var t: float = remaining / segment if segment > 0 else 0.0
			return prev_pos.lerp(pos, t)
		
		accumulated += segment
		prev_pos = pos
	
	# 히스토리 끝까지 갔으면 마지막 위치
	return path_history[-1] if path_history.size() > 0 else global_position


#=============================================================================
# 팔로워 로직
#=============================================================================
func _process_follower(_delta: float) -> void:
	if not is_instance_valid(leader_ref):
		return
	
	# 리더로부터의 목표 거리 계산
	var target_distance: float = FOLLOW_DISTANCE * member_index
	var target_pos: Vector2 = leader_ref.get_path_position(target_distance)
	
	# 현재 위치에서 목표까지 얼마나 이동해야 하는지
	var to_target: Vector2 = target_pos - global_position
	var move_distance: float = to_target.length()
	
	# 목표 위치로 이동
	global_position = target_pos
	
	# 움직였으면 걷기 애니메이션
	if move_distance > 0.5:
		_update_direction(to_target)
		_play_walk_animation()
	else:
		_play_idle_animation()


#=============================================================================
# 공통 함수
#=============================================================================
func _update_direction(dir: Vector2) -> void:
	if dir.length() < 0.1:
		return
	
	if abs(dir.x) > abs(dir.y):
		current_direction = "right" if dir.x > 0 else "left"
		facing_right = dir.x > 0
	else:
		current_direction = "down" if dir.y > 0 else "up"


func _play_walk_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if not sprite:
		return
	var anim_name := "walk_" + current_direction
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name or not sprite.is_playing():
			sprite.play(anim_name)


func _play_idle_animation() -> void:
	var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
	if not sprite:
		return
	var anim_name := "walk_" + current_direction
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation == anim_name and not sprite.is_playing():
			return
		sprite.stop()
		sprite.animation = anim_name
		sprite.frame = 1


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


func _apply_dead_visual() -> void:
	if hero_id.is_empty():
		return
	var hero: Hero = PartyManager.get_hero_by_id(hero_id) if PartyManager else null
	var is_dead_now: bool = hero != null and hero.is_dead

	if animated_sprite and is_instance_valid(animated_sprite):
		if is_dead_now:
			animated_sprite.modulate = Color(0.45, 0.45, 0.45, 0.9)
		else:
			animated_sprite.modulate = Color(1, 1, 1, 1)

	if hp_bar and is_instance_valid(hp_bar):
		if is_dead_now:
			hp_bar.modulate = Color(0.6, 0.6, 0.6, 0.85)
		else:
			hp_bar.modulate = Color(1, 1, 1, 1)


func get_current_direction() -> String:
	return current_direction


func get_facing_right() -> bool:
	return facing_right


#=============================================================================
# 셋업
#=============================================================================
func setup_as_leader(hero: RefCounted, start_pos: Vector2) -> void:
	is_leader = true
	member_index = 0
	global_position = start_pos
	z_index = 100
	
	add_to_group("party_leader")
	
	# 카메라 활성화 (리더만)
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera:
		camera.enabled = true
	
	# 초기 경로 히스토리 (뒤쪽으로 줄 세우기)
	for i in range(100):
		path_history.append(start_pos + Vector2(0, i * PATH_RECORD_DISTANCE))
	
	_setup_hero_data(hero)


func setup_as_follower(hero: RefCounted, leader: PartyMember, index: int) -> void:
	is_leader = false
	member_index = index
	leader_ref = leader
	z_index = 100 - index
	
	add_to_group("party_follower")
	
	# 초기 위치
	global_position = leader.get_path_position(FOLLOW_DISTANCE * index)
	
	# 초기 방향을 리더와 맞춤
	current_direction = leader.current_direction
	facing_right = leader.facing_right
	
	_setup_hero_data(hero)


func _setup_hero_data(hero: RefCounted) -> void:
	if hero == null:
		print("[PartyMember] hero가 null!")
		return
	
	hero_id = hero.id
	hero_data = {
		"id": hero.id,
		"name": hero.hero_name,
		"class_id": hero.class_id
	}
	
	# animated_sprite 가져오기 (여러 방법 시도)
	var sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
	if sprite == null:
		sprite = animated_sprite
	
	if sprite == null:
		push_error("[PartyMember] AnimatedSprite2D를 찾을 수 없음!")
		return
	
	if SpriteManager:
		var sprite_frames: SpriteFrames = SpriteManager.get_hero_sprite_frames(hero_id)
		if sprite_frames:
			sprite.sprite_frames = sprite_frames
			sprite.animation = "walk_" + current_direction
			sprite.play()
			sprite.stop()
			sprite.frame = 1
		else:
			push_error("[PartyMember] SpriteFrames를 가져올 수 없음: " + hero_id)
	else:
		push_error("[PartyMember] SpriteManager가 없음!")
	
	_update_hp_bar()
