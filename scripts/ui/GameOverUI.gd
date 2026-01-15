# scripts/ui/GameOverUI.gd
extends Panel

signal restart_requested
signal quit_requested

@onready var title_label = $VBoxContainer/Title
@onready var stats_label = $VBoxContainer/Stats
@onready var restart_button = $VBoxContainer/RestartButton
@onready var quit_button = $VBoxContainer/QuitButton

var is_victory: bool = false

func _ready():
	print("[GameOverUI] Created")
	
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	
	# 게임 일시정지
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_game_over():
	is_victory = false
	
	if title_label:
		title_label.text = "💀 GAME OVER 💀"
		title_label.add_theme_color_override("font_color", Color.RED)
	
	show_stats()
	spawn_animation()

func show_victory():
	is_victory = true
	
	if title_label:
		title_label.text = "🎉 VICTORY! 🎉"
		title_label.add_theme_color_override("font_color", Color.GOLD)
	
	show_stats()
	spawn_animation()

func show_stats():
	if not stats_label:
		return
	
	var stats_text = ""
	stats_text += "━━━━━━━━━━━━━━━━━\n\n"
	stats_text += "📊 최종 기록\n\n"
	stats_text += "⚔️ 처치한 적: %d\n" % GameManager.total_kills
	stats_text += "💰 획득 골드: %d\n" % GameManager.total_gold_earned
	stats_text += "📦 획득 아이템: %d\n" % GameManager.total_items_found
	stats_text += "📈 최종 레벨: %d\n" % GameManager.party_level
	stats_text += "🏰 도달 스테이지: %d\n" % StageManager.current_stage
	stats_text += "\n"
	
	# 플레이 시간
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		var minutes = int(hud.game_time) / 60
		var seconds = int(hud.game_time) % 60
		stats_text += "⏱️ 플레이 시간: %02d:%02d\n" % [minutes, seconds]
	
	stats_text += "\n━━━━━━━━━━━━━━━━━"
	
	stats_label.text = stats_text

func spawn_animation():
	# 등장 애니메이션
	modulate.a = 0
	scale = Vector2(0.5, 0.5)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	tween.tween_property(self, "scale", Vector2(1, 1), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _on_restart_pressed():
	print("[GameOverUI] Restart")
	get_tree().paused = false
	restart_requested.emit()
	
	# 게임 리셋
	GameManager.reset_game()
	StageManager.reset()
	
	# 씬 재로드
	get_tree().reload_current_scene()

func _on_quit_pressed():
	print("[GameOverUI] Quit")
	get_tree().paused = false
	quit_requested.emit()
	get_tree().quit()
