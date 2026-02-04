extends Node
## SoundManager: 효과음 및 BGM 재생 관리
## 절차적 사운드 생성 지원 (파일 없이도 사운드 재생 가능)

# === 오디오 플레이어 풀 ===
var sfx_players: Array[AudioStreamPlayer] = []
var bgm_player: AudioStreamPlayer = null
const MAX_SFX_PLAYERS: int = 12

# === 볼륨 설정 ===
var master_volume: float = 1.0
var sfx_volume: float = 0.8
var bgm_volume: float = 0.6

# === 사운드 파일 경로 ===
const SOUND_PATH := "res://assets/audio/"

# === 절차적 사운드 설정 ===
const SAMPLE_RATE: int = 22050
const PROC_SOUNDS_ENABLED: bool = true  # 절차적 사운드 사용 여부

# 효과음 매핑 (파일 기반)
const SFX_FILES := {
	"hit": "hit.wav",
	"hit_crit": "hit_crit.wav",
	"slash": "slash.wav",
	"miss": "miss.wav",
	"magic": "magic.wav",
	"heal": "heal.wav",
	"death": "death.wav",
	"victory": "victory.wav",
	"defeat": "defeat.wav",
	"select": "select.wav",
	"confirm": "confirm.wav",
	"cancel": "cancel.wav",
	"equip": "equip.wav",
	"item_get": "item_get.wav",
	"gold": "gold.wav",
	"level_up": "level_up.wav",
	"encounter": "encounter.wav",
	"step": "step.wav",
	"door": "door.wav",
}

# 로드된 사운드 캐시
var _sound_cache: Dictionary = {}
# 절차적 생성 사운드 캐시
var _proc_sound_cache: Dictionary = {}


func _ready() -> void:
	_setup_audio_players()
	_preload_sounds()
	_generate_procedural_sounds()


func _setup_audio_players() -> void:
	for i in range(MAX_SFX_PLAYERS):
		var player := AudioStreamPlayer.new()
		player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		add_child(player)
		sfx_players.append(player)

	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "BGM" if AudioServer.get_bus_index("BGM") >= 0 else "Master"
	add_child(bgm_player)


func _preload_sounds() -> void:
	for key in SFX_FILES:
		var path: String = SOUND_PATH + SFX_FILES[key]
		if ResourceLoader.exists(path):
			_sound_cache[key] = load(path)


#region 절차적 사운드 생성
func _generate_procedural_sounds() -> void:
	## 클래스별 공격 사운드 절차적 생성
	if not PROC_SOUNDS_ENABLED:
		return

	# 용사: 묵직한 검 휘두르는 소리 (저음 + 스윙)
	_proc_sound_cache["atk_warrior"] = _create_warrior_sound()

	# 기사: 금속성 방패/검 충돌음
	_proc_sound_cache["atk_knight"] = _create_knight_sound()

	# 도적: 빠른 단검 찌르기
	_proc_sound_cache["atk_thief"] = _create_thief_sound()

	# 궁수: 활시위 퉁기는 소리
	_proc_sound_cache["atk_archer"] = _create_archer_sound()

	# 마법사: 마법 발사 (전자음 + 스파클)
	_proc_sound_cache["atk_mage"] = _create_mage_sound()

	# 성직자: 신성한 종소리
	_proc_sound_cache["atk_cleric"] = _create_cleric_sound()

	# 적 공격: 으르렁/타격
	_proc_sound_cache["atk_enemy"] = _create_enemy_sound()

	# 기본 사운드들
	_proc_sound_cache["hit"] = _create_hit_sound()
	_proc_sound_cache["slash"] = _create_slash_sound()
	_proc_sound_cache["heal"] = _create_heal_sound()
	_proc_sound_cache["death"] = _create_death_sound()


func _create_warrior_sound() -> AudioStreamWAV:
	## 용사: 묵직한 검격 (저주파 스윙 + 타격)
	var duration: float = 0.25
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_percussive(t, 0.02, 0.2)

		# 저음 스윙 (주파수 하강)
		var freq: float = lerp(180.0, 80.0, t / duration)
		var swing: float = sin(TAU * freq * t) * 0.6

		# 타격 노이즈
		var noise: float = (randf() - 0.5) * 0.4 * _envelope_percussive(t, 0.01, 0.08)

		var sample: float = (swing + noise) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_knight_sound() -> AudioStreamWAV:
	## 기사: 금속성 충돌 (메탈릭 링)
	var duration: float = 0.3
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_percussive(t, 0.005, 0.25)

		# 금속성 고조파
		var metal: float = 0.0
		metal += sin(TAU * 800.0 * t) * 0.3
		metal += sin(TAU * 1200.0 * t) * 0.25
		metal += sin(TAU * 2100.0 * t) * 0.15
		metal += sin(TAU * 3400.0 * t) * 0.1

		# 충돌 노이즈
		var impact: float = (randf() - 0.5) * 0.3 * _envelope_percussive(t, 0.002, 0.02)

		var sample: float = (metal + impact) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_thief_sound() -> AudioStreamWAV:
	## 도적: 빠른 단검 (고음 + 짧음)
	var duration: float = 0.12
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_percussive(t, 0.008, 0.1)

		# 날카로운 고음 (주파수 상승)
		var freq: float = lerp(600.0, 1800.0, t / duration)
		var stab: float = sin(TAU * freq * t) * 0.5

		# 공기 가르는 소리
		var whoosh: float = (randf() - 0.5) * 0.5 * _envelope_percussive(t, 0.005, 0.06)

		var sample: float = (stab + whoosh) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_archer_sound() -> AudioStreamWAV:
	## 궁수: 활시위 (퉁 + 화살 날아감)
	var duration: float = 0.2
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_percussive(t, 0.003, 0.15)

		# 시위 진동 (감쇠 진동)
		var string_freq: float = 220.0 * exp(-t * 8.0)
		var string_vib: float = sin(TAU * string_freq * t) * 0.5

		# 화살 날아가는 휘파람
		var arrow_freq: float = lerp(400.0, 800.0, t / duration)
		var arrow: float = sin(TAU * arrow_freq * t) * 0.3 * (1.0 - t / duration)

		var sample: float = (string_vib + arrow) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_mage_sound() -> AudioStreamWAV:
	## 마법사: 마법 발사 (스파클 + 전자음)
	var duration: float = 0.35
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_magic(t, duration)

		# 기본 톤 (상승)
		var base_freq: float = lerp(300.0, 600.0, t / duration)
		var tone: float = sin(TAU * base_freq * t) * 0.3

		# 스파클 (랜덤 고음 버스트)
		var sparkle: float = 0.0
		if randf() < 0.15:
			sparkle = sin(TAU * (1500.0 + randf() * 2000.0) * t) * 0.4

		# 워블 (진동)
		var wobble: float = sin(TAU * 8.0 * t) * 0.3
		var modulated: float = sin(TAU * (base_freq + wobble * 100.0) * t) * 0.25

		var sample: float = (tone + sparkle + modulated) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_cleric_sound() -> AudioStreamWAV:
	## 성직자: 신성한 종/차임 소리
	var duration: float = 0.4
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_bell(t, duration)

		# 종소리 고조파 (C5 코드 느낌)
		var bell: float = 0.0
		bell += sin(TAU * 523.0 * t) * 0.35  # C5
		bell += sin(TAU * 659.0 * t) * 0.25  # E5
		bell += sin(TAU * 784.0 * t) * 0.2   # G5
		bell += sin(TAU * 1046.0 * t) * 0.1  # C6

		# 부드러운 어택
		var soft: float = bell * (1.0 - exp(-t * 20.0))

		var sample: float = soft * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_enemy_sound() -> AudioStreamWAV:
	## 적 공격: 으르렁 + 둔탁한 타격
	var duration: float = 0.2
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_percussive(t, 0.015, 0.15)

		# 저음 으르렁
		var growl_freq: float = 80.0 + sin(TAU * 5.0 * t) * 20.0
		var growl: float = sin(TAU * growl_freq * t) * 0.4

		# 타격 노이즈
		var impact: float = (randf() - 0.5) * 0.6 * _envelope_percussive(t, 0.01, 0.05)

		# 왜곡
		var sample: float = (growl + impact) * env
		sample = clampf(sample * 1.5, -0.9, 0.9)  # 약간의 클리핑
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_hit_sound() -> AudioStreamWAV:
	## 기본 타격음
	var duration: float = 0.1
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_percussive(t, 0.005, 0.08)
		var noise: float = (randf() - 0.5) * 0.7
		var thump: float = sin(TAU * 100.0 * t) * 0.5
		var sample: float = (noise + thump) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_slash_sound() -> AudioStreamWAV:
	## 기본 슬래시
	var duration: float = 0.15
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_percussive(t, 0.01, 0.12)
		var freq: float = lerp(200.0, 500.0, t / duration)
		var swoosh: float = sin(TAU * freq * t) * 0.4
		var noise: float = (randf() - 0.5) * 0.4 * env
		var sample: float = (swoosh + noise) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_heal_sound() -> AudioStreamWAV:
	## 회복 사운드 (상승하는 차임)
	var duration: float = 0.5
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = _envelope_bell(t, duration)

		# 상승하는 아르페지오
		var phase: float = t / duration
		var freq: float = 400.0 + phase * 400.0
		var tone: float = sin(TAU * freq * t) * 0.3
		tone += sin(TAU * freq * 1.5 * t) * 0.2
		tone += sin(TAU * freq * 2.0 * t) * 0.15

		# 스파클
		var sparkle: float = 0.0
		if randf() < 0.1:
			sparkle = sin(TAU * (1000.0 + randf() * 1500.0) * t) * 0.25

		var sample: float = (tone + sparkle) * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


func _create_death_sound() -> AudioStreamWAV:
	## 사망 사운드 (하강 + 페이드)
	var duration: float = 0.4
	var samples := PackedByteArray()
	var num_samples: int = int(SAMPLE_RATE * duration)

	for i in range(num_samples):
		var t: float = float(i) / SAMPLE_RATE
		var env: float = 1.0 - (t / duration)

		# 하강하는 톤
		var freq: float = lerp(300.0, 80.0, t / duration)
		var tone: float = sin(TAU * freq * t) * 0.4

		# 노이즈
		var noise: float = (randf() - 0.5) * 0.3 * env

		var sample: float = (tone + noise) * env * env
		samples.append(_float_to_8bit(sample))

	return _create_wav_stream(samples)


# === 헬퍼 함수 ===
func _envelope_percussive(t: float, attack: float, decay: float) -> float:
	## 타악기형 엔벨로프
	if t < attack:
		return t / attack
	return exp(-(t - attack) / decay)


func _envelope_magic(t: float, duration: float) -> float:
	## 마법형 엔벨로프 (부드러운 상승 후 하강)
	var rise: float = 0.1
	var fall_start: float = 0.6
	if t < rise * duration:
		return t / (rise * duration)
	elif t < fall_start * duration:
		return 1.0
	else:
		return 1.0 - ((t - fall_start * duration) / ((1.0 - fall_start) * duration))


func _envelope_bell(t: float, duration: float) -> float:
	## 종소리형 엔벨로프 (빠른 어택 + 긴 디케이)
	var attack: float = 0.01
	if t < attack:
		return t / attack
	return exp(-(t - attack) * 3.0 / duration)


func _float_to_8bit(value: float) -> int:
	## -1.0~1.0 float를 0~255 8bit로 변환
	var clamped: float = clampf(value, -1.0, 1.0)
	return int((clamped + 1.0) * 127.5)


func _create_wav_stream(samples: PackedByteArray) -> AudioStreamWAV:
	## PackedByteArray로 AudioStreamWAV 생성
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = samples
	return stream
#endregion


#region 효과음 재생
func play_sfx(sound_name: String, volume_scale: float = 1.0) -> void:
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
	# 파일 캐시 우선
	if _sound_cache.has(sound_name):
		return _sound_cache[sound_name]

	# 절차적 사운드 캐시
	if _proc_sound_cache.has(sound_name):
		return _proc_sound_cache[sound_name]

	# 파일에서 로드 시도
	if SFX_FILES.has(sound_name):
		var path: String = SOUND_PATH + SFX_FILES[sound_name]
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			_sound_cache[sound_name] = stream
			return stream

	return null


func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	return sfx_players[0]
#endregion


#region 전투 사운드 헬퍼
func play_hit(is_crit: bool = false) -> void:
	if is_crit:
		play_sfx("hit", 1.3)
	else:
		play_sfx("hit")


func play_slash(is_crit: bool = false) -> void:
	play_sfx("slash", 1.2 if is_crit else 1.0)


func play_miss() -> void:
	# 미스는 조용한 휙 소리
	play_sfx("slash", 0.3)


func play_magic() -> void:
	play_sfx("atk_mage")


func play_heal() -> void:
	play_sfx("heal")


func play_death() -> void:
	play_sfx("death")


func play_victory() -> void:
	play_sfx("heal", 1.2)  # 임시로 힐 사운드 사용


func play_defeat() -> void:
	play_sfx("death", 1.2)


func play_encounter() -> void:
	play_sfx("atk_enemy", 0.8)


func play_attack(class_id: String, is_crit: bool = false) -> void:
	## 클래스별 공격 사운드
	var sound_key: String = "atk_" + class_id
	var volume: float = 1.3 if is_crit else 1.0
	play_sfx(sound_key, volume)


func play_enemy_attack() -> void:
	## 적 공격 사운드
	play_sfx("atk_enemy")
#endregion


#region UI 사운드 헬퍼
func play_select() -> void:
	play_sfx("atk_thief", 0.4)  # 짧은 찌르기 소리


func play_confirm() -> void:
	play_sfx("atk_cleric", 0.5)  # 종소리


func play_cancel() -> void:
	play_sfx("hit", 0.4)


func play_equip() -> void:
	play_sfx("atk_knight", 0.5)  # 금속 소리


func play_item_get() -> void:
	play_sfx("heal", 0.6)


func play_gold() -> void:
	play_sfx("atk_knight", 0.3)


func play_level_up() -> void:
	play_sfx("atk_cleric", 1.0)
#endregion


#region BGM
func play_bgm(track_name: String, fade_duration: float = 0.5) -> void:
	var path: String = SOUND_PATH + "bgm/" + track_name
	if not ResourceLoader.exists(path):
		return

	var stream: AudioStream = load(path)
	if stream == null:
		return

	if bgm_player.playing:
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
