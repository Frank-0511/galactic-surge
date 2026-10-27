# camera_shake.gd
# Static combat camera that adds dynamic screen shake.
# Supports both:
# 1. Advanced non-linear Trauma model (Squirrel Eiserloh model: trauma in [0, 1],
#    quadratic decay trauma^2, translational offset and rotational roll).
# 2. Legacy linear shake(intensity, duration) for backwards compatibility.

class_name CameraShake
extends Camera2D

## Trauma value in range [0.0, 1.0].
@export_range(0.0, 1.0, 0.01) var trauma: float = 0.0

## Rate at which trauma decreases per second.
@export var trauma_decay: float = 1.4

## Maximum translational shake offset in pixels when trauma is 1.0.
@export var max_offset: Vector2 = Vector2(24.0, 24.0)

## Maximum rotational shake (roll) in radians when trauma is 1.0.
@export var max_roll: float = 0.08

## Exponent that governs non-linear shake perception (2.0 = quadratic).
@export var trauma_exponent: float = 2.0

## Legacy shake state
var _time_left: float = 0.0
var _duration: float = 0.0
var _intensity: float = 0.0


## Increases trauma by amount, clamped to 1.0.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## High-impact shake helper applying trauma directly.
func shake_heavy(intensity: float = 0.5, _duration: float = 0.0) -> void:
	add_trauma(intensity)


## Starts (or refreshes, if stronger) a legacy shake of the given intensity in
## pixels lasting duration seconds. Maintained for backwards compatibility.
func shake(intensity: float, duration: float) -> void:
	if intensity < _intensity and _time_left > 0.0:
		return
	_intensity = intensity
	_duration = duration
	_time_left = duration


## Instantly resets all shake offsets, rolls, and trauma.
func reset_shake() -> void:
	trauma = 0.0
	_time_left = 0.0
	_duration = 0.0
	_intensity = 0.0
	offset = Vector2.ZERO
	rotation = 0.0


func _process(delta: float) -> void:
	var has_trauma: bool = trauma > 0.0
	var has_legacy: bool = _time_left > 0.0

	if not has_trauma and not has_legacy:
		if offset != Vector2.ZERO or rotation != 0.0:
			offset = Vector2.ZERO
			rotation = 0.0
		return

	var trauma_offset: Vector2 = Vector2.ZERO
	var trauma_roll: float = 0.0

	if has_trauma:
		var shake_factor: float = pow(trauma, trauma_exponent)
		trauma_offset = Vector2(
			randf_range(-1.0, 1.0) * max_offset.x * shake_factor,
			randf_range(-1.0, 1.0) * max_offset.y * shake_factor
		)
		trauma_roll = randf_range(-1.0, 1.0) * max_roll * shake_factor
		trauma = maxf(trauma - trauma_decay * delta, 0.0)

	var legacy_offset: Vector2 = Vector2.ZERO
	if has_legacy:
		_time_left = maxf(_time_left - delta, 0.0)
		var falloff: float = _time_left / _duration if _duration > 0.0 else 0.0
		legacy_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _intensity * falloff

	offset = trauma_offset + legacy_offset
	rotation = trauma_roll
