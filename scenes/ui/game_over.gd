# game_over.gd
# Presents the end-of-session state and asks Main to start a clean retry.

extends CanvasLayer

signal retry_requested
signal main_menu_requested

const ENEMY_DISPLAY_NAMES: Array[Array] = [
	[&"standard", "Caza"],
	[&"scout_drone", "Dron explorador"],
	[&"armored_fighter", "Caza acorazado"],
	[&"suicide_interceptor", "Interceptor suicida"],
	[&"assault_frigate", "Fragata de asalto"],
]

@onready var _new_record_label: Label = $Control/NewRecordLabel
@onready var _stats_label: Label = $Control/StatsLabel


func show_game_over(final_score: int = 0, is_new_record: bool = false) -> void:
	$Control/FinalScoreLabel.text = "Score final: %d" % final_score
	_new_record_label.visible = is_new_record
	visible = true
	$Control/RetryButton.grab_focus()


## Shows shot accuracy (percent) and kills per enemy type for the finished session.
func show_session_stats(accuracy: float, kills_by_type: Dictionary) -> void:
	var lines: PackedStringArray = PackedStringArray(["PRECISIÓN: %d%%" % roundi(accuracy)])
	for entry: Array in ENEMY_DISPLAY_NAMES:
		var count: int = int(kills_by_type.get(entry[0], 0))
		lines.append("%s: %d" % [entry[1], count])
	_stats_label.text = "\n".join(lines)


func _on_retry_button_pressed() -> void:
	retry_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
