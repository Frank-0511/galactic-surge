# game_over.gd
# Presents the end-of-session state and asks Main to start a clean retry.

extends CanvasLayer

signal retry_requested


func show_game_over(final_score: int = 0) -> void:
	$Control/FinalScoreLabel.text = "Score final: %d" % final_score
	visible = true
	$Control/RetryButton.grab_focus()


func _on_retry_button_pressed() -> void:
	retry_requested.emit()
