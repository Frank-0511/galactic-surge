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

	# Despawn when far beyond viewport bounds (the live viewport, or 1080x1040 outside the tree)
	var vp: Rect2 = _asteroid.get_viewport_rect() if _asteroid.is_inside_tree() and _asteroid.get_viewport_rect().size.y > 0.0 else Rect2(0.0, 0.0, 1080.0, 1040.0)
	if is_outside_cull(_asteroid.global_position, vp):
		_asteroid.queue_free()


## Pure: true when an asteroid is far beyond the viewport on any side and can be despawned.
static func is_outside_cull(pos: Vector2, vp: Rect2) -> bool:
	return pos.y > vp.end.y + 160.0 or pos.y < -300.0 or pos.x < -300.0 or pos.x > vp.end.x + 320.0
