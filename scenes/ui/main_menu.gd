# main_menu.gd
# Presents the initial navigation options and emits user intent to Main.

extends CanvasLayer

signal play_requested
signal quit_requested

@onready var _high_score_label: Label = $Control/HighScoreLabel


func show_menu() -> void:
	visible = true
	$Control/PlayButton.grab_focus()


func set_high_score(value: int) -> void:
	_high_score_label.text = "Mejor puntaje: %d" % value


func _on_play_button_pressed() -> void:
	play_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()
