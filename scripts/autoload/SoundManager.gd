extends Node
## SoundManager: 효과음 및 BGM 재생 관리
## 오디오 파일이 없어도 에러 없이 동작 (파일 있으면 자동 재생)

# === 오디오 플레이어 풀 ===
var sfx_players: Array[AudioStreamPlayer] = []
var bgm_player: AudioStreamPlayer = null
const MAX_SFX_PLAYERS: int = 8

# === 볼륨 설정 ===
var master_volume: float = 1.0
var sfx_volume: float = 0.8
var bgm_volume: float = 0.6

# === 사운드 파일 경로 ===
const SOUND_PATH := "res://assets/audio/"

# 효과음 매핑
const SFX_FILES := {
	# 전투
	"hit": "hit.wav",
	"hit_crit": "hit_crit.wav",
	"slash": "slash.wav",
	"miss": "miss.wav",
	"magic": "magic.wav",
	"heal": "heal.wav",
	"death": "death.wav",
	"victory": "victory.wav",
	"defeat": "defeat.wav",
	
	# UI
	"select": "select.wav",
	"confirm": "confirm.wav",
	"cancel": "cancel.wav",
	"equip": "equip.wav",
	"item_get": "item_get.wav",
	"gold": "gold.wav",
	"level_up": "level_up.wav",
	
	# 필드
	"encounter": "encounter.wav",
	"step": "step.wav",
	"door": "door.wav",
}

# 로드된 사운드 캐시
var _sound_cache: Dictionary = {}


func _ready() -> void:
	_setup_audio_players()
	_preload_sounds()


func _setup_audio_players() -> void:
	## 오디오 플레이어 풀 생성
	# SFX 플레이어들
	for i in range(MAX_SFX_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(player)
		sfx_players.append(player)
	
	# BGM 플레이어
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "BGM" if AudioServer.get_bus_index("BGM") >= 0 else "Master"
	add_child(bgm_player)


func _preload_sounds() -> void:
	## 사운드 파일 프리로드 (있는 것만)
	for key in SFX_FILES:
		var path: String = SOUND_PATH + SFX_FILES[key]
		if ResourceLoader.exists(path):
			_sound_cache[key] = load(path)


#region 효과음 재생
func play_sfx(sound_name: String, volume_scale: float = 1.0) -> void:
	## 효과음 재생
	var stream: AudioStream = _get_sound(sound_name)
	if stream == null:
		return
	
	var player := _get_available_sfx_player()
	if player == null:
		return
	
	player.stream = stream
	player.volume_db = linear_to_db(sfx_volume * master_volume * volume_scale)
	player.play()


func _get_sound(sound_name: String) -> AudioStream:
	## 사운드 가져오기 (캐시 우선)
	if _sound_cache.has(sound_name):
		return _sound_cache[sound_name]
	
	# 캐시에 없으면 직접 로드 시도
	if SFX_FILES.has(sound_name):
		var path: String = SOUND_PATH + SFX_FILES[sound_name]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			_sound_cache[sound_name] = stream
			return stream
	
	return null


func _get_available_sfx_player() -> AudioStreamPlayer:
	## 사용 가능한 SFX 플레이어 반환
	for player in sfx_players:
		if not player.playing:
			return player
	# 전부 사용 중이면 첫 번째 것 재사용
	return sfx_players[0]
#endregion


#region 전투 사운드 헬퍼
func play_hit(is_crit: bool = false) -> void:
	## 타격 사운드
	if is_crit:
		play_sfx("hit_crit", 1.2)
	else:
		play_sfx("hit")


func play_slash(is_crit: bool = false) -> void:
	## 슬래시 이펙트 사운드
	play_sfx("slash", 1.2 if is_crit else 1.0)


func play_miss() -> void:
	## 회피 사운드
	play_sfx("miss", 0.8)


func play_magic() -> void:
	## 마법 사운드
	play_sfx("magic")


func play_heal() -> void:
	## 회복 사운드
	play_sfx("heal")


func play_death() -> void:
	## 적 사망 사운드
	play_sfx("death")


func play_victory() -> void:
	## 전투 승리
	play_sfx("victory", 1.0)


func play_defeat() -> void:
	## 전투 패배
	play_sfx("defeat", 1.0)


func play_encounter() -> void:
	## 적 조우
	play_sfx("encounter")
#endregion


#region UI 사운드 헬퍼
func play_select() -> void:
	play_sfx("select", 0.7)


func play_confirm() -> void:
	play_sfx("confirm")


func play_cancel() -> void:
	play_sfx("cancel", 0.8)


func play_equip() -> void:
	play_sfx("equip")


func play_item_get() -> void:
	play_sfx("item_get")


func play_gold() -> void:
	play_sfx("gold", 0.6)


func play_level_up() -> void:
	play_sfx("level_up", 1.2)
#endregion


#region BGM
func play_bgm(track_name: String, fade_duration: float = 0.5) -> void:
	## BGM 재생 (페이드 인)
	var path: String = SOUND_PATH + "bgm/" + track_name
	if not ResourceLoader.exists(path):
		return
	
	var stream: AudioStream = load(path)
	if stream == null:
		return
	
	if bgm_player.playing:
		# 페이드 아웃 후 전환
		var tween := create_tween()
		tween.tween_property(bgm_player, "volume_db", -40.0, fade_duration)
		tween.finished.connect(func():
			bgm_player.stream = stream
			bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)
			bgm_player.play()
		)
	else:
		bgm_player.stream = stream
		bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)
		bgm_player.play()


func stop_bgm(fade_duration: float = 0.5) -> void:
	## BGM 정지 (페이드 아웃)
	if not bgm_player.playing:
		return
	
	var tween := create_tween()
	tween.tween_property(bgm_player, "volume_db", -40.0, fade_duration)
	tween.finished.connect(func(): bgm_player.stop())
#endregion


#region 볼륨 설정
func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)


func set_bgm_volume(value: float) -> void:
	bgm_volume = clampf(value, 0.0, 1.0)
	if bgm_player.playing:
		bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)
#endregion
