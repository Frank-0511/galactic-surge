# hud.gd
# Displays the current player lives, score, wave, and mission completion state.

extends CanvasLayer

signal lives_changed(lives: int)
signal score_changed(score: int)
signal wave_changed(wave: int)

@onready var _lives_label: Label = $Margin/LivesLabel
@onready var _score_label: Label = $Margin/ScoreLabel
@onready var _wave_label: Label = $Margin/WaveLabel
@onready var _mission_complete_label: Label = $MissionCompleteLabel


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
