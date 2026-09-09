# wave_announcement.gd
# CanvasLayer that displays a wave-transition announcement for a fixed duration.
# Emits announcement_finished when done; does not start waves itself.

class_name WaveAnnouncement
extends CanvasLayer

signal announcement_finished

## Duration in seconds the announcement stays visible before finishing.
@export var display_duration: float = 1.5

## Generation counter to invalidate stale timer callbacks.
var _generation: int = 0
var _active_generation: int = -1

@onready var _wave_label: Label = $Control/WaveLabel
@onready var _radar_label: Label = $Control/RadarLabel
@onready var _ready_label: Label = $Control/ReadyLabel
@onready var _display_timer: Timer = $DisplayTimer


func _ready() -> void:
	_display_timer.one_shot = true
	_display_timer.timeout.connect(_on_display_timer_timeout)
	visible = false


func show_announcement(next_wave: int, phrase: String) -> void:
	_generation += 1
	_active_generation = _generation
	_wave_label.text = "NIVEL %d · OLEADA %d" % [next_wave, next_wave]
	_radar_label.text = phrase
	_ready_label.text = "¡PREPÁRATE!"
	visible = true
	if display_duration <= 0.0:
		# Use a frame-based coroutine so the announcement stays visible for at
		# least one full frame before finishing, even with zero duration.
		_finish_after_frame()
	else:
		_display_timer.wait_time = display_duration
		_display_timer.start()


func _finish_after_frame() -> void:
	var gen: int = _active_generation
	# Keep the first frame as the observation window. The second frame gives the
	# main controller time to receive the signal and create the next formation
	# before the following test/gameplay observation.
	await get_tree().process_frame
	await get_tree().process_frame
	if gen != _generation:
		return
	visible = false
	announcement_finished.emit()


func cancel_announcement() -> void:
	_generation += 1
	_display_timer.stop()
	visible = false


func _on_display_timer_timeout() -> void:
	if _active_generation != _generation:
		return
	visible = false
	announcement_finished.emit()
