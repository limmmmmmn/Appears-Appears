extends Node
## SpriteManager: 스프라이트 로드 및 캐싱

const HERO_PATH := "res://assets/sprites/heroes/"
const ENEMY_PATH := "res://assets/sprites/enemies/"
const EFFECT_PATH := "res://assets/sprites/effects/"
const UI_PATH := "res://assets/sprites/ui/"

# 캐시
var _hero_sprites: Dictionary = {}
var _hero_sprite_frames: Dictionary = {}  # SpriteFrames 캐시
var _enemy_sprites: Dictionary = {}
var _effect_sprites: Dictionary = {}

# 플레이스홀더 색상 (스프라이트 없을 때)
var _placeholder_colors: Dictionary = {
	"warrior": Color(0.8, 0.2, 0.2),    # 빨강
	"mage": Color(0.2, 0.2, 0.8),       # 파랑
	"cleric": Color(0.9, 0.9, 0.5),     # 노랑
	"thief": Color(0.5, 0.2, 0.5),      # 보라
	"archer": Color(0.2, 0.7, 0.2),     # 초록
	"knight": Color(0.5, 0.5, 0.5),     # 회색
	"enemy": Color(0.8, 0.3, 0.3),      # 적 기본
	"elite": Color(0.8, 0.5, 0.2),      # 엘리트 주황
	"boss": Color(0.6, 0.1, 0.1),       # 보스 암적
}


func _ready() -> void:
	pass


#region 영웅 스프라이트
func get_hero_field_sprite(hero_id: String) -> Texture2D:
	## 영웅 필드 스프라이트 로드
	var cache_key: String = hero_id + "_field"
	if _hero_sprites.has(cache_key):
		return _hero_sprites[cache_key]
	
	var hero_data: Dictionary = DataManager.get_hero(hero_id)
	var sprite_name: String = str(hero_data.get("sprite_field", hero_id + "_field"))
	var path: String = HERO_PATH + sprite_name + ".png"
	
	var texture: Texture2D = _load_texture(path)
	if texture:
		_hero_sprites[cache_key] = texture
		return texture
	
	# 플레이스홀더 생성 및 캐시
	var class_id: String = str(hero_data.get("class_id", "warrior"))
	var placeholder: Texture2D = _create_placeholder(class_id, 24)
	_hero_sprites[cache_key] = placeholder
	return placeholder


func get_hero_face_sprite(hero_id: String) -> Texture2D:
	## 영웅 페이스칩 스프라이트 로드
	var cache_key: String = hero_id + "_face"
	if _hero_sprites.has(cache_key):
		return _hero_sprites[cache_key]
	
	var hero_data: Dictionary = DataManager.get_hero(hero_id)
	var sprite_name: String = str(hero_data.get("sprite_face", hero_id + "_face"))
	var path: String = HERO_PATH + sprite_name + ".png"
	
	var texture: Texture2D = _load_texture(path)
	if texture:
		_hero_sprites[cache_key] = texture
		return texture
	
	# 플레이스홀더 생성 및 캐시
	var class_id: String = str(hero_data.get("class_id", "warrior"))
	var placeholder: Texture2D = _create_placeholder(class_id, 32)
	_hero_sprites[cache_key] = placeholder
	return placeholder


func get_hero_sprite_frames(hero_id: String) -> SpriteFrames:
	## 영웅 스프라이트시트에서 SpriteFrames 생성 (4방향 걷기 애니메이션)
	## 스프라이트시트 구조: 48x96 (3열 x 4행, 각 프레임 16x24)
	## Row 0: Down, Row 1: Left, Row 2: Right, Row 3: Up
	
	if _hero_sprite_frames.has(hero_id):
		return _hero_sprite_frames[hero_id]
	
	var hero_data_dict: Dictionary = DataManager.get_hero(hero_id)
	var sprite_name: String = str(hero_data_dict.get("sprite_field", hero_id + "_field"))
	var path: String = HERO_PATH + sprite_name + ".png"
	
	var texture: Texture2D = _load_texture(path)
	if not texture:
		# 플레이스홀더 SpriteFrames 생성
		var placeholder_frames: SpriteFrames = _create_placeholder_sprite_frames(hero_id)
		_hero_sprite_frames[hero_id] = placeholder_frames
		return placeholder_frames
	
	# SpriteFrames 생성
	var sprite_frames := SpriteFrames.new()
	
	# 스프라이트시트 설정
	const FRAME_WIDTH: int = 16
	const FRAME_HEIGHT: int = 24
	const COLS: int = 3
	const FPS: float = 8.0
	
	# 방향별 애니메이션 (행 순서: down, left, right, up)
	var directions: Array[String] = ["down", "left", "right", "up"]
	
	for row in range(4):
		var anim_name: String = "walk_" + directions[row]
		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, FPS)
		sprite_frames.set_animation_loop(anim_name, true)
		
		# 각 방향별 3프레임 추가
		for col in range(COLS):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(
				col * FRAME_WIDTH,
				row * FRAME_HEIGHT,
				FRAME_WIDTH,
				FRAME_HEIGHT
			)
			sprite_frames.add_frame(anim_name, atlas)
	
	_hero_sprite_frames[hero_id] = sprite_frames
	return sprite_frames


func _create_placeholder_sprite_frames(hero_id: String) -> SpriteFrames:
	## 플레이스홀더 SpriteFrames 생성
	var hero_data_dict: Dictionary = DataManager.get_hero(hero_id)
	var class_id: String = str(hero_data_dict.get("class_id", "warrior"))
	var color: Color = _placeholder_colors.get(class_id, Color(0.5, 0.5, 0.5))
	
	# 16x24 플레이스홀더 이미지 생성
	var image := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	image.fill(color)
	
	# 테두리 추가
	var border_color := color.darkened(0.3)
	for x in range(16):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, 23, border_color)
	for y in range(24):
		image.set_pixel(0, y, border_color)
		image.set_pixel(15, y, border_color)
	
	var placeholder_texture := ImageTexture.create_from_image(image)
	
	# SpriteFrames 생성
	var sprite_frames := SpriteFrames.new()
	var directions: Array[String] = ["down", "left", "right", "up"]
	
	for direction in directions:
		var anim_name: String = "walk_" + direction
		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, 8.0)
		sprite_frames.set_animation_loop(anim_name, true)
		# 같은 프레임 3번 추가 (정적)
		for i in range(3):
			sprite_frames.add_frame(anim_name, placeholder_texture)
	
	return sprite_frames
#endregion


#region 적 스프라이트
func get_enemy_sprite(enemy_id: String) -> Texture2D:
	## 적 스프라이트 로드 (필드 + 전투 겸용)
	if _enemy_sprites.has(enemy_id):
		return _enemy_sprites[enemy_id]
	
	var enemy_data: Dictionary = DataManager.get_enemy(enemy_id)
	var sprite_name: String = str(enemy_data.get("sprite", enemy_id))
	var path: String = ENEMY_PATH + sprite_name + ".png"
	
	var texture: Texture2D = _load_texture(path)
	if texture:
		_enemy_sprites[enemy_id] = texture
		return texture
	
	# 플레이스홀더 생성 및 캐시
	var enemy_type: String = str(enemy_data.get("type", "normal"))
	var placeholder_key: String = "enemy"
	if enemy_type == "elite":
		placeholder_key = "elite"
	elif enemy_type == "boss":
		placeholder_key = "boss"
	
	var placeholder: Texture2D = _create_placeholder(placeholder_key, 32)
	_enemy_sprites[enemy_id] = placeholder
	return placeholder
#endregion


#region 이펙트 스프라이트
func get_effect_sprite(effect_name: String) -> Texture2D:
	## 이펙트 스프라이트 로드
	if _effect_sprites.has(effect_name):
		return _effect_sprites[effect_name]
	
	var path: String = EFFECT_PATH + effect_name + ".png"
	var texture: Texture2D = _load_texture(path)
	
	if texture:
		_effect_sprites[effect_name] = texture
		return texture
	
	# 플레이스홀더 생성 및 캐시
	var placeholder: Texture2D = _create_placeholder("enemy", 16)
	_effect_sprites[effect_name] = placeholder
	return placeholder


func get_alert_icon() -> Texture2D:
	return get_effect_sprite("alert_icon")
#endregion


# 이미 경고한 경로 추적
var _warned_paths: Dictionary = {}


#region 유틸리티
func _load_texture(path: String) -> Texture2D:
	## 텍스처 안전하게 로드
	if not ResourceLoader.exists(path):
		# 같은 경로에 대해 한 번만 경고
		if not _warned_paths.has(path):
			_warned_paths[path] = true
			push_warning("[SpriteManager] 스프라이트 없음: " + path)
		return null
	
	var resource = load(path)
	if resource is Texture2D:
		return resource
	
	if not _warned_paths.has(path):
		_warned_paths[path] = true
		push_warning("[SpriteManager] 유효하지 않은 텍스처: " + path)
	return null


func _create_placeholder(type_key: String, size: int) -> ImageTexture:
	## 플레이스홀더 이미지 생성
	var color: Color = _placeholder_colors.get(type_key, Color(0.5, 0.5, 0.5))
	
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	
	# 테두리 추가
	var border_color := color.darkened(0.3)
	for x in range(size):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, size - 1, border_color)
	for y in range(size):
		image.set_pixel(0, y, border_color)
		image.set_pixel(size - 1, y, border_color)
	
	return ImageTexture.create_from_image(image)


func clear_cache() -> void:
	## 캐시 클리어
	_hero_sprites.clear()
	_hero_sprite_frames.clear()
	_enemy_sprites.clear()
	_effect_sprites.clear()
#endregion
