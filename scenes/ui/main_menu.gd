# main_menu.gd
# Presents the initial navigation options and emits user intent to Main.
# Lets the player pick the session difficulty (Etapa 18) before play.

extends CanvasLayer

const DS := preload("res://scripts/systems/difficulty_settings.gd")

signal play_requested
signal quit_requested

## Tier chosen in the menu; read by Main when play_requested fires and fixed for the session.
var selected_difficulty: int = DS.Tier.COMMANDER

@onready var _high_score_label: Label = $Control/HighScoreLabel
@onready var _title_label: Label = $Control/TitleLabel
@onready var _difficulty_button: Button = $Control/DificultadButton


func _ready() -> void:
	_start_title_glow()
	_refresh_difficulty_text()


func show_menu() -> void:
	visible = true
	$Control/PlayButton.grab_focus()


func set_high_score(value: int) -> void:
	_high_score_label.text = "Mejor puntaje: %d" % value


func _on_play_button_pressed() -> void:
	play_requested.emit()


# Cycles CADET -> COMMANDER -> ELITE -> CADET.
func _on_dificultad_button_pressed() -> void:
	selected_difficulty = (selected_difficulty + 1) % DS.Tier.size()
	_refresh_difficulty_text()


func _refresh_difficulty_text() -> void:
	_difficulty_button.text = "DIFICULTAD: %s" % DS.get_tier_name(selected_difficulty).to_upper()


func _on_quit_button_pressed() -> void:
	quit_requested.emit()


# Purely cosmetic breathing glow on the title label; does not affect layout,
# text or any gameplay-facing state.
func _start_title_glow() -> void:
	var tween: Tween = create_tween()
	tween.set_loops()
	tween.tween_property(_title_label, "modulate:a", 0.78, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_title_label, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
