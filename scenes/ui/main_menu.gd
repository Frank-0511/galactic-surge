# main_menu.gd
# Presents the initial navigation options and emits user intent to Main.

extends CanvasLayer

signal play_requested
signal quit_requested

@onready var _high_score_label: Label = $Control/HighScoreLabel
@onready var _title_label: Label = $Control/TitleLabel


func _ready() -> void:
	_start_title_glow()


func show_menu() -> void:
	visible = true
	$Control/PlayButton.grab_focus()


func set_high_score(value: int) -> void:
	_high_score_label.text = "Mejor puntaje: %d" % value


func _on_play_button_pressed() -> void:
	play_requested.emit()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()


# Purely cosmetic breathing glow on the title label; does not affect layout,
# text or any gameplay-facing state.
func _start_title_glow() -> void:
	var tween: Tween = create_tween()
	tween.set_loops()
	tween.tween_property(_title_label, "modulate:a", 0.78, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_title_label, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
