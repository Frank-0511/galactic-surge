# boss_movement.gd
# Autonomous flight of the Boss: entrance glide, cruise (horizontal bounce, sinusoidal hover and
# banking tilt), dive maneuver (telegraph, steered descent, ascent) and the dive trigger.
# Owned by Boss through _boss; the movement state variables themselves stay on Boss.

extends RefCounted

var _boss: Area2D


func _init(boss: Area2D) -> void:
	_boss = boss


## Advances the movement state machine by delta seconds.
func update(delta: float) -> void:
	if _boss._state == _boss.MovementState.ENTERING:
		_update_entering(delta)
	elif _boss._state == _boss.MovementState.CRUISE:
		_update_cruise(delta)
	elif _boss._state == _boss.MovementState.DIVE_TELEGRAPH:
		_update_telegraph(delta)
	elif _boss._state == _boss.MovementState.DIVE_DESCENT:
		_update_descent(delta)
	elif _boss._state == _boss.MovementState.DIVE_ASCENT:
		_update_ascent(delta)


## Triggers a dive maneuver telegraph towards player position or current X.
func trigger_dive() -> void:
	if _boss._state != _boss.MovementState.CRUISE and _boss._state != _boss.MovementState.ENTERING:
		return
	_boss._state = _boss.MovementState.DIVE_TELEGRAPH
	_boss._telegraph_timer = 0.4 if _boss.is_enraged else 0.5
	var target_x: float = _boss.global_position.x
	var player: Node2D = _boss._attacks.get_player_node()
	if player != null:
		target_x = player.global_position.x
	_boss._dive_target = Vector2(clampf(target_x, _boss._left_margin, _boss._right_margin), dive_target_y(_viewport_rect()))


## Dive target Y (Etapa 21 T4), anchored to the viewport bottom. At 1080x960 it is the former fixed 760.
static func dive_target_y(viewport: Rect2) -> float:
	return viewport.end.y - 200.0


## Dive cap Y (Etapa 21 T4), anchored to the viewport bottom and kept above the dive target.
## At 1080x960 it is the former fixed 740.
static func dive_cap_y(viewport: Rect2) -> float:
	return viewport.end.y - 220.0


## Live viewport when inside the tree; outside it, the 1080x960 base viewport.
func _viewport_rect() -> Rect2:
	return GameLayout.playfield_of(_boss.get_viewport_rect()) if _boss.is_inside_tree() else Rect2(0.0, 0.0, 1080.0, 960.0)


func _update_entering(delta: float) -> void:
	_boss._is_entering = true
	_boss.global_position.y += 150.0 * delta
	_boss.rotation = lerpf(_boss.rotation, 0.0, delta * 5.0)
	if _boss.global_position.y >= _boss._base_y:
		_boss.global_position.y = _boss._base_y
		_boss._is_entering = false
		_boss._state = _boss.MovementState.CRUISE
		_boss._dive_cooldown = 3.0 if _boss.is_enraged else 5.0
		_boss._attacks.schedule_shoot(0.5 if _boss.is_enraged else 0.75)


func _update_cruise(delta: float) -> void:
	_boss._is_entering = false
	# 1. Horizontal movement with boundary bounce
	var speed: float = 190.0 if _boss.is_enraged else 140.0
	_boss.global_position.x += _boss._move_direction * speed * delta
	if _boss.global_position.x <= _boss._left_margin:
		_boss.global_position.x = _boss._left_margin
		_boss._move_direction = 1.0
	elif _boss.global_position.x >= _boss._right_margin:
		_boss.global_position.x = _boss._right_margin
		_boss._move_direction = -1.0

	# 2. Sinusoidal vertical oscillation around base_y
	var vertical_amp: float = 90.0 if _boss.is_enraged else 60.0
	var vertical_freq: float = 2.4 if _boss.is_enraged else 1.8
	_boss.global_position.y = _boss._base_y + sin(_boss._time * vertical_freq) * vertical_amp

	# 3. Dynamic banking tilt based on horizontal direction
	var target_tilt: float = clampf(_boss._move_direction * 0.25, -0.3, 0.3)
	_boss.rotation = lerpf(_boss.rotation, target_tilt, delta * 5.0)

	# 4. Dive maneuver cooldown
	_boss._dive_cooldown -= delta
	if _boss._dive_cooldown <= 0.0:
		trigger_dive()


func _update_telegraph(delta: float) -> void:
	_boss._is_entering = false
	_boss._telegraph_timer -= delta
	_boss.rotation = lerpf(_boss.rotation, 0.0, delta * 8.0)
	if _boss._telegraph_timer <= 0.0:
		_boss._state = _boss.MovementState.DIVE_DESCENT


func _update_descent(delta: float) -> void:
	_boss._is_entering = false
	var descent_speed: float = 540.0 if _boss.is_enraged else 420.0
	_boss.global_position.y += descent_speed * delta

	var diff_x: float = _boss._dive_target.x - _boss.global_position.x
	var steer_speed: float = clampf(diff_x * 3.5, -descent_speed * 0.75, descent_speed * 0.75)
	_boss.global_position.x += steer_speed * delta
	_boss.global_position.x = clampf(_boss.global_position.x, _boss._left_margin, _boss._right_margin)

	var dive_tilt: float = clampf((steer_speed / descent_speed) * 0.5, -0.4, 0.4)
	_boss.rotation = lerpf(_boss.rotation, dive_tilt, delta * 6.0)

	if _boss.global_position.y >= _boss._dive_target.y or _boss.global_position.y >= dive_cap_y(_viewport_rect()):
		_boss._state = _boss.MovementState.DIVE_ASCENT


func _update_ascent(delta: float) -> void:
	_boss._is_entering = false
	var ascent_speed: float = 320.0 if _boss.is_enraged else 260.0
	_boss.global_position.y -= ascent_speed * delta

	var speed_x: float = 140.0 if _boss.is_enraged else 100.0
	_boss.global_position.x += _boss._move_direction * speed_x * delta
	if _boss.global_position.x <= _boss._left_margin:
		_boss.global_position.x = _boss._left_margin
		_boss._move_direction = 1.0
	elif _boss.global_position.x >= _boss._right_margin:
		_boss.global_position.x = _boss._right_margin
		_boss._move_direction = -1.0

	var ascent_tilt: float = clampf(_boss._move_direction * 0.2, -0.3, 0.3)
	_boss.rotation = lerpf(_boss.rotation, ascent_tilt, delta * 5.0)

	if _boss.global_position.y <= _boss._base_y:
		_boss.global_position.y = _boss._base_y
		_boss._state = _boss.MovementState.CRUISE
		_boss._dive_cooldown = 3.0 if _boss.is_enraged else 5.0
