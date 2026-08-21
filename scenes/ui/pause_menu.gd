# pause_menu.gd
# Presents paused-session navigation options and emits user intent to Main.

extends CanvasLayer

signal resume_requested
signal main_menu_requested


func show_menu() -> void:
	visible = true
	$Control/ResumeButton.grab_focus()


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
