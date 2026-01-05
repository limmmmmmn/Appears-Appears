extends Node

# 마지막으로 소리가 재생된 시간을 기록 (중복 재생 방지)
var last_played_times: Dictionary = {}

func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
		
	var path = stream.resource_path
	var now = Time.get_ticks_msec() / 1000.0
	
	# 0.05초 이내에 같은 소리가 났다면 재생하지 않음
	if last_played_times.has(path):
		if now - last_played_times[path] < 0.05:
			return
			
	last_played_times[path] = now
	
	# 일회성 오디오 플레이어 생성 및 재생
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	add_child(player)
	player.play()
	
	# 재생 끝나면 메모리 해제
	player.finished.connect(player.queue_free)
