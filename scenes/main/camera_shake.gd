# camera_shake.gd
# Static combat camera that adds a brief, decaying random offset on demand
# (player damage, nearby enemy kills) for extra hit feedback.

extends Camera2D

var _time_left: float = 0.0
var _duration: float = 0.0
var _intensity: float = 0.0


## Starts (or refreshes, if stronger) a shake of the given intensity in
## pixels lasting `duration` seconds.
func shake(intensity: float, duration: float) -> void:
	if intensity < _intensity and _time_left > 0.0:
		return
	_intensity = intensity
	_duration = duration
	_time_left = duration


func _process(delta: float) -> void:
	if _time_left <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_time_left = maxf(_time_left - delta, 0.0)
	var falloff: float = _time_left / _duration if _duration > 0.0 else 0.0
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _intensity * falloff
