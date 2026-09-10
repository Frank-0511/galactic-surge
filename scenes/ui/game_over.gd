# game_over.gd
# Presents the end-of-session state and asks Main to start a clean retry.

extends CanvasLayer

signal retry_requested
signal main_menu_requested

@onready var _new_record_label: Label = $Control/NewRecordLabel


func show_game_over(final_score: int = 0, is_new_record: bool = false) -> void:
	$Control/FinalScoreLabel.text = "Score final: %d" % final_score
	_new_record_label.visible = is_new_record
	visible = true
	$Control/RetryButton.grab_focus()


func _on_retry_button_pressed() -> void:
	retry_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
