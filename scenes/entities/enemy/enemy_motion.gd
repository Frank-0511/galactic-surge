# enemy_motion.gd
# Entrance and movement of one Enemy: the cubic Bezier fly-in (Stage 8), the dive swoop and the
# return to the formation slot (Stage 9), with their start/cancel entry points. Owned by Enemy
# through _enemy.

extends RefCounted

const VectorMath: Script = preload("res://scripts/math/vector_math.gd")

## Fly-in entrance curve parameters.
var _fly_in_p0: Vector2 = Vector2.ZERO
var _fly_in_p1: Vector2 = Vector2.ZERO
var _fly_in_p2: Vector2 = Vector2.ZERO
var _fly_in_p3: Vector2 = Vector2.ZERO
var _fly_in_duration: float = 1.0
var _fly_in_elapsed: float = 0.0
var _fly_in_delay: float = 0.0

## Dynamic dive parameters.
var _dive_p0: Vector2 = Vector2.ZERO
var _dive_p1: Vector2 = Vector2.ZERO
var _dive_p2: Vector2 = Vector2.ZERO
var _dive_p3: Vector2 = Vector2.ZERO
var _dive_duration: float = 2.0
var _dive_elapsed: float = 0.0

## Return to formation parameters.
var _return_start_pos: Vector2 = Vector2.ZERO
var _return_duration: float = 1.6
var _return_elapsed: float = 0.0

var _enemy: Area2D


func _init(enemy: Area2D) -> void:
	_enemy = enemy


func start_fly_in(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, duration: float, delay: float = 0.0) -> void:
	_fly_in_p0 = p0
	_fly_in_p1 = p1
	_fly_in_p2 = p2
	_fly_in_p3 = p3
	_fly_in_duration = maxf(duration, 0.001)
	_fly_in_delay = maxf(delay, 0.0)
	_fly_in_elapsed = 0.0
	_enemy._is_flying_in = true
	_enemy._state = _enemy.State.FLY_IN
	_enemy.global_position = p0
	if _enemy._shoot_cooldown != null:
		_enemy._shoot_cooldown.stop()


func cancel_fly_in() -> void:
	if _enemy._state != _enemy.State.FLY_IN and not _enemy._is_flying_in:
		return
	_enemy._is_flying_in = false
	_enemy._state = _enemy.State.FORMATION
	_enemy.global_position = _fly_in_p3
	_enemy.rotation = 0.0
	_enemy._weapons.schedule_next_shot()


func start_dive(target_pos: Vector2, duration: float = 2.0, _dive_type: String = "swoop", slot_getter: Callable = Callable()) -> void:
	if slot_getter.is_valid():
		_enemy._slot_getter = slot_getter
	_enemy._state = _enemy.State.DIVING
	_enemy._is_flying_in = false
	_dive_duration = maxf(duration, 0.001)
	_dive_elapsed = 0.0

	var p0: Vector2 = _enemy.global_position
	# Determine swoop lateral curvature
	var side: float = 1.0 if target_pos.x >= p0.x else -1.0
	if absf(target_pos.x - p0.x) < 40.0:
		side = 1.0 if p0.x <= 540.0 else -1.0

	_dive_p0 = p0
	_dive_p1 = p0 + Vector2(side * 220.0, 160.0)
	_dive_p2 = Vector2(target_pos.x + side * 140.0, target_pos.y - 120.0)
	_dive_p3 = Vector2(target_pos.x - side * 80.0, 1040.0)

	_enemy.dive_started.emit()


func return_to_slot(slot_getter: Callable, duration: float = 1.6) -> void:
	_enemy._state = _enemy.State.RETURNING
	_enemy._is_flying_in = false
	_enemy._slot_getter = slot_getter
	_return_start_pos = _enemy.global_position
	_return_duration = maxf(duration, 0.001)
	_return_elapsed = 0.0


func process_fly_in(delta: float) -> void:
	_fly_in_elapsed += delta
	if _fly_in_elapsed >= _fly_in_delay:
		var effective_t: float = (_fly_in_elapsed - _fly_in_delay) / _fly_in_duration
		var t: float = clampf(effective_t, 0.0, 1.0)
		_enemy.global_position = VectorMath.cubic_bezier(_fly_in_p0, _fly_in_p1, _fly_in_p2, _fly_in_p3, t)
		var deriv: Vector2 = VectorMath.cubic_bezier_derivative(_fly_in_p0, _fly_in_p1, _fly_in_p2, _fly_in_p3, t)
		_enemy.rotation = clampf(deriv.x * 0.0015, -0.45, 0.45) * (1.0 - t)
		if t >= 1.0:
			_enemy._state = _enemy.State.FORMATION
			_enemy._is_flying_in = false
			_enemy.rotation = 0.0
			_enemy.global_position = _fly_in_p3
			_enemy._weapons.schedule_next_shot()
			_enemy.fly_in_completed.emit()


func process_diving(delta: float) -> void:
	_dive_elapsed += delta
	var t: float = clampf(_dive_elapsed / _dive_duration, 0.0, 1.0)
	_enemy.global_position = VectorMath.cubic_bezier(_dive_p0, _dive_p1, _dive_p2, _dive_p3, t)
	var deriv: Vector2 = VectorMath.cubic_bezier_derivative(_dive_p0, _dive_p1, _dive_p2, _dive_p3, t)

	# Banking tilt ~15-20 deg (+/- 0.2618 to 0.3491 rad) based on lateral derivative
	var max_tilt: float = deg_to_rad(20.0)
	var min_tilt: float = deg_to_rad(15.0)
	if absf(deriv.x) > 30.0:
		var factor: float = clampf(absf(deriv.x) / 350.0, 0.0, 1.0)
		_enemy.rotation = signf(deriv.x) * lerpf(min_tilt, max_tilt, factor)
	else:
		_enemy.rotation = signf(deriv.x) * min_tilt * (absf(deriv.x) / 30.0)

	if t >= 1.0:
		if _enemy._slot_getter.is_valid():
			var vp_rect: Rect2 = _enemy.get_viewport_rect() if _enemy.is_inside_tree() else Rect2(0, 0, 1080, 960)
			if _enemy.global_position.y > vp_rect.size.y * 0.9:
				_enemy.global_position.y = -30.0
				_enemy.global_position.x = clampf(_enemy.global_position.x, 60.0, vp_rect.size.x - 60.0)
			return_to_slot(_enemy._slot_getter, 2.0 if not _enemy._is_enraged else 1.5)
		else:
			_enemy._state = _enemy.State.FORMATION
			_enemy.rotation = 0.0
			_enemy._weapons.schedule_next_shot()
			_enemy.returned_to_formation.emit()


func process_returning(delta: float) -> void:
	_return_elapsed += delta
	var t: float = clampf(_return_elapsed / _return_duration, 0.0, 1.0)
	var target_slot: Vector2 = _enemy._slot_getter.call() if _enemy._slot_getter.is_valid() else _return_start_pos
	var smooth_t: float = smoothstep(0.0, 1.0, t)
	_enemy.global_position = _return_start_pos.lerp(target_slot, smooth_t)

	var return_dx: float = (target_slot.x - _return_start_pos.x)
	var max_tilt: float = deg_to_rad(20.0)
	var min_tilt: float = deg_to_rad(15.0)
	if absf(return_dx) > 30.0:
		var factor: float = clampf(absf(return_dx) / 300.0, 0.0, 1.0)
		_enemy.rotation = signf(return_dx) * lerpf(min_tilt, max_tilt, factor) * (1.0 - smooth_t)
	else:
		_enemy.rotation = 0.0

	if t >= 1.0 or (t > 0.8 and _enemy.global_position.distance_to(target_slot) < 6.0):
		_enemy.global_position = target_slot
		_enemy.rotation = 0.0
		_enemy._state = _enemy.State.FORMATION
		_enemy._weapons.schedule_next_shot()
		_enemy.returned_to_formation.emit()
