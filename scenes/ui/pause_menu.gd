# pause_menu.gd
# Presents paused-session navigation options and emits user intent to Main.

extends CanvasLayer

signal resume_requested
signal main_menu_requested

@onready var _mute_button: CheckButton = $Control/MuteButton

const _MASTER_BUS: String = "Master"


func show_menu() -> void:
	visible = true
	_mute_button.button_pressed = AudioServer.is_bus_mute(AudioServer.get_bus_index(_MASTER_BUS))
	$Control/ResumeButton.grab_focus()


func _on_resume_button_pressed() -> void:
	resume_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()


func _on_mute_button_toggled(toggled_on: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index(_MASTER_BUS), toggled_on)
