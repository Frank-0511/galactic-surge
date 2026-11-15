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

## Maximum horizontal distance in pixels the camera may drift from home while following.
@export var follow_max_offset: float = 120.0

## Position smoothing speed used while following a target.
@export var follow_smoothing_speed: float = 5.0

## Legacy shake state
var _time_left: float = 0.0
var _duration: float = 0.0
var _intensity: float = 0.0

## Follow state (Etapa 16): tracks a target on X only, clamped around the home position.
var _follow_target: Node2D = null
var _follow_home: Vector2 = Vector2.ZERO


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


## Starts following target on X, clamped to follow_max_offset around the current position.
## Y is never followed. Smoothing glides the camera toward the target.
func begin_follow(target: Node2D) -> void:
	_follow_target = target
	_follow_home = position
	position_smoothing_enabled = true
	position_smoothing_speed = follow_smoothing_speed


## Stops following and returns the camera to its home position.
func end_follow() -> void:
	_follow_target = null
	_follow_candidates = []
	position = _follow_home


## Ships the belt camera may follow; the target is re-picked every frame (Etapa 20).
var _follow_candidates: Array = []


func set_follow_candidates(nodes: Array) -> void:
	_follow_candidates = nodes


## Living ship to follow: the only visible one, or when both live, the one moving more sideways.
static func pick_follow_target(candidates: Array) -> Node2D:
	var best: Node2D = null
	var best_speed: float = -1.0
	for candidate: Variant in candidates:
		var ship: Node2D = candidate as Node2D
		if ship == null or not ship.visible:
			continue
		var speed: float = absf(ship.get("velocity").x) if "velocity" in ship else 0.0
		if speed > best_speed:
			best_speed = speed
			best = ship
	return best


## Instantly resets all shake offsets, rolls, and trauma.
func reset_shake() -> void:
	trauma = 0.0
	_time_left = 0.0
	_duration = 0.0
	_intensity = 0.0
	offset = Vector2.ZERO
	rotation = 0.0


func _process(delta: float) -> void:
	if not _follow_candidates.is_empty():
		_follow_target = pick_follow_target(_follow_candidates)
	if is_instance_valid(_follow_target):
		var drift: float = clampf(_follow_target.global_position.x - _follow_home.x, -follow_max_offset, follow_max_offset)
		position = Vector2(_follow_home.x + drift, _follow_home.y)

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
