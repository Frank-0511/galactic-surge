# asteroid_motion.gd
# Inertial movement of one Asteroid: advances position and spin each frame, ticks the hit-flash
# timer and despawns the rock once it leaves the viewport bounds.
# Owned by Asteroid through _asteroid; state and exports stay on Asteroid.

extends RefCounted

var _asteroid: Asteroid


func _init(asteroid: Asteroid) -> void:
	_asteroid = asteroid


## Advances one frame of linear and angular motion, then despawns when far out of bounds.
func advance(delta: float) -> void:
	_asteroid.global_position += _asteroid.linear_velocity * delta
	_asteroid.rotation += _asteroid.angular_velocity * delta

	if _asteroid._hit_flash_timer > 0.0:
		_asteroid._hit_flash_timer = maxf(_asteroid._hit_flash_timer - delta, 0.0)
		_asteroid.queue_redraw()

	# Despawn when far beyond viewport bounds
	var max_y: float = 1200.0
	if _asteroid.is_inside_tree():
		var vp: Rect2 = _asteroid.get_viewport_rect()
		if vp.size.y > 0.0:
			max_y = vp.end.y + 160.0
	var pos: Vector2 = _asteroid.global_position
	if pos.y > max_y or pos.y < -300.0 or pos.x < -300.0 or pos.x > 1400.0:
		_asteroid.queue_free()
