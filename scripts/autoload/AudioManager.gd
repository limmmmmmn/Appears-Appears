extends Node
## AudioManager.gd
## 오디오 관리 싱글톤 - BGM, SFX 재생

# ===== 오디오 플레이어 =====
var bgm_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX_PLAYERS = 8

# ===== 볼륨 설정 =====
var master_volume: float = 1.0
var bgm_volume: float = 0.7
var sfx_volume: float = 0.8

# ===== 현재 재생 중인 BGM =====
var current_bgm: String = ""

# ===== 오디오 경로 =====
const BGM_PATH = "res://assets/audio/bgm/"
const SFX_PATH = "res://assets/audio/sfx/"

# ===== 캐시된 오디오 =====
var _bgm_cache: Dictionary = {}
var _sfx_cache: Dictionary = {}


func _ready() -> void:
	_setup_audio_players()
	_connect_signals()
	_load_volume_settings()


func _setup_audio_players() -> void:
	# BGM 플레이어
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Master"
	add_child(bgm_player)
	
	# SFX 플레이어 풀
	for i in range(MAX_SFX_PLAYERS):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		sfx_players.append(player)


func _connect_signals() -> void:
	EventBus.play_bgm.connect(_on_play_bgm)
	EventBus.stop_bgm.connect(_on_stop_bgm)
	EventBus.play_sfx.connect(_on_play_sfx)


func _load_volume_settings() -> void:
	# DataManager에서 설정 로드
	if DataManager.is_loaded:
		var config = DataManager.get_config()
		if config.has("audio"):
			master_volume = config["audio"].get("master_volume", 1.0)
			bgm_volume = config["audio"].get("bgm_volume", 0.7)
			sfx_volume = config["audio"].get("sfx_volume", 0.8)
	
	_apply_volumes()


func _apply_volumes() -> void:
	bgm_player.volume_db = linear_to_db(master_volume * bgm_volume)
	for player in sfx_players:
		player.volume_db = linear_to_db(master_volume * sfx_volume)


# ===== BGM 재생 =====
func play_bgm(track_name: String, fade_in: float = 0.5) -> void:
	if track_name == current_bgm and bgm_player.playing:
		return
	
	var stream = _load_bgm(track_name)
	if stream == null:
		print("[AudioManager] BGM not found: ", track_name)
		return
	
	current_bgm = track_name
	bgm_player.stream = stream
	bgm_player.volume_db = linear_to_db(0.0)
	bgm_player.play()
	
	# 페이드 인
	var tween = create_tween()
	tween.tween_property(bgm_player, "volume_db", 
		linear_to_db(master_volume * bgm_volume), fade_in)


func stop_bgm(fade_out: float = 0.5) -> void:
	if not bgm_player.playing:
		return
	
	var tween = create_tween()
	tween.tween_property(bgm_player, "volume_db", linear_to_db(0.0), fade_out)
	tween.tween_callback(bgm_player.stop)
	current_bgm = ""


func pause_bgm() -> void:
	bgm_player.stream_paused = true


func resume_bgm() -> void:
	bgm_player.stream_paused = false


# ===== SFX 재생 =====
func play_sfx(sfx_name: String, pitch_variation: float = 0.0) -> void:
	var stream = _load_sfx(sfx_name)
	if stream == null:
		print("[AudioManager] SFX not found: ", sfx_name)
		return
	
	# 사용 가능한 플레이어 찾기
	var player = _get_available_sfx_player()
	if player == null:
		return
	
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.play()


func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	# 모든 플레이어가 사용 중이면 첫 번째 것 재사용
	return sfx_players[0]


# ===== 오디오 로드 =====
func _load_bgm(track_name: String) -> AudioStream:
	if _bgm_cache.has(track_name):
		return _bgm_cache[track_name]
	
	var path = BGM_PATH + track_name
	if not path.ends_with(".ogg") and not path.ends_with(".mp3") and not path.ends_with(".wav"):
		path += ".ogg"
	
	if ResourceLoader.exists(path):
		var stream = load(path)
		_bgm_cache[track_name] = stream
		return stream
	
	return null


func _load_sfx(sfx_name: String) -> AudioStream:
	if _sfx_cache.has(sfx_name):
		return _sfx_cache[sfx_name]
	
	var path = SFX_PATH + sfx_name
	if not path.ends_with(".ogg") and not path.ends_with(".mp3") and not path.ends_with(".wav"):
		path += ".wav"
	
	if ResourceLoader.exists(path):
		var stream = load(path)
		_sfx_cache[sfx_name] = stream
		return stream
	
	return null


# ===== 볼륨 조절 =====
func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()


func set_bgm_volume(value: float) -> void:
	bgm_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()


# ===== 시그널 핸들러 =====
func _on_play_bgm(track_name: String) -> void:
	play_bgm(track_name)


func _on_stop_bgm() -> void:
	stop_bgm()


func _on_play_sfx(sfx_name: String) -> void:
	play_sfx(sfx_name)


# ===== 게임 이벤트 사운드 =====
func play_battle_start() -> void:
	play_sfx("battle_start")


func play_attack() -> void:
	play_sfx("attack", 0.1)


func play_hit() -> void:
	play_sfx("hit", 0.1)


func play_critical() -> void:
	play_sfx("critical")


func play_heal() -> void:
	play_sfx("heal")


func play_victory() -> void:
	play_sfx("victory")


func play_defeat() -> void:
	play_sfx("defeat")


func play_level_up() -> void:
	play_sfx("level_up")


func play_item_get() -> void:
	play_sfx("item_get")


func play_menu_select() -> void:
	play_sfx("menu_select")


func play_menu_cancel() -> void:
	play_sfx("menu_cancel")
