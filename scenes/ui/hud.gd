# hud.gd
# Displays the current player lives, score, wave, and mission completion state.
# Emits semantic signals so Main can coordinate retries and menu navigation.

extends CanvasLayer

signal lives_changed(lives: int)
signal score_changed(score: int)
signal wave_changed(wave: int)
signal retry_mission_requested
signal main_menu_requested

@onready var _lives_label: Label = $Margin/LivesLabel
@onready var _score_label: Label = $Margin/ScoreLabel
@onready var _wave_label: Label = $Margin/WaveLabel
@onready var _mission_complete_label: Label = $MissionCompleteLabel
@onready var _retry_button: Button = $RetryButton
@onready var _main_menu_button: Button = $MainMenuButton


func set_lives(lives: int) -> void:
	_lives_label.text = "Vidas: %d" % lives
	lives_changed.emit(lives)


func set_score(score: int) -> void:
	_score_label.text = "Score: %d" % score
	score_changed.emit(score)


func set_wave(wave: int) -> void:
	_wave_label.text = "Oleada: %d" % wave
	wave_changed.emit(wave)


func show_mission_complete() -> void:
	_mission_complete_label.text = "Mision completada"
	_mission_complete_label.visible = true
	_retry_button.visible = true
	_main_menu_button.visible = true
	_retry_button.grab_focus()


func hide_mission_complete() -> void:
	_mission_complete_label.visible = false
	_retry_button.visible = false
	_main_menu_button.visible = false


func _on_retry_button_pressed() -> void:
	retry_mission_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
