# game_over.gd
# Presents the end-of-session state and asks Main to start a clean retry.

extends CanvasLayer

signal retry_requested


func show_game_over() -> void:
	visible = true
	$Control/RetryButton.grab_focus()


func _on_retry_button_pressed() -> void:
	retry_requested.emit()
