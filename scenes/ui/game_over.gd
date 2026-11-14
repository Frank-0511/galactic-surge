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

const STAT_FONT_SIZE: int = 16
const STAT_TEXT_COLOR: Color = Color(0.85, 0.92, 1.0, 1.0)

@onready var _new_record_label: Label = $Control/Content/NewRecordLabel
@onready var _final_score_label: Label = $Control/Content/FinalScoreLabel
@onready var _accuracy_label: Label = $Control/Content/StatsCard/StatsMargin/StatsBox/AccuracyLabel
@onready var _accuracy_bar: ProgressBar = $Control/Content/StatsCard/StatsMargin/StatsBox/AccuracyBar
@onready var _kills_grid: GridContainer = $Control/Content/StatsCard/StatsMargin/StatsBox/KillsGrid
@onready var _retry_button: Button = $Control/Content/RetryButton


func show_game_over(final_score: int = 0, is_new_record: bool = false) -> void:
	_final_score_label.text = "Score final: %d" % final_score
	_new_record_label.visible = is_new_record
	visible = true
	_retry_button.grab_focus()


## Shows shot accuracy (percent) and kills per enemy type for the finished session.
## Kills render as a two-column grid: enemy name left, count right-aligned.
func show_session_stats(accuracy: float, kills_by_type: Dictionary) -> void:
	_accuracy_label.text = "Precisión: %d%%" % roundi(accuracy)
	_accuracy_bar.value = clampf(accuracy, 0.0, 100.0)
	for old_child: Node in _kills_grid.get_children():
		_kills_grid.remove_child(old_child)
		old_child.queue_free()
	for entry: Array in ENEMY_DISPLAY_NAMES:
		var count: int = int(kills_by_type.get(entry[0], 0))
		_kills_grid.add_child(_make_stat_label(entry[1], HORIZONTAL_ALIGNMENT_LEFT))
		_kills_grid.add_child(_make_stat_label(str(count), HORIZONTAL_ALIGNMENT_RIGHT))


func _make_stat_label(text: String, alignment: HorizontalAlignment) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", STAT_FONT_SIZE)
	label.add_theme_color_override("font_color", STAT_TEXT_COLOR)
	return label


func _on_retry_button_pressed() -> void:
	retry_requested.emit()


func _on_main_menu_button_pressed() -> void:
	main_menu_requested.emit()
