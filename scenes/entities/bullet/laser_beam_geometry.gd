# laser_beam_geometry.gd
# Beam geometry: the idle default reach, the active length that stops at the first enemy or at the
# top of the viewport, and the collision rectangle that follows it. Owned by LaserBeam through _beam;
# exports, width, damage state and the target finder stay on LaserBeam.

extends RefCounted

var _beam: Area2D


func _init(beam: Area2D) -> void:
	_beam = beam


## Restores the idle beam: default length, no target, cleared tick state and default collision rectangle.
func reset_to_default_beam() -> void:
	_beam._active_length = _beam.beam_length
	_beam._current_target_enemy = null
	_beam._tick_timer = 0.0
	_beam._fractional_damage_buffer = 0.0
	if _beam._collision_shape == null:
		_beam._collision_shape = _beam.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _beam._collision_shape != null and _beam._collision_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = _beam._collision_shape.shape as RectangleShape2D
		rect_shape.size.x = _beam.beam_width
		rect_shape.size.y = _beam.beam_length
		_beam._collision_shape.position = Vector2(0.0, -_beam.beam_length * 0.5)


## Re-targets the beam and resizes it to reach the closest enemy, or the top of the viewport.
func update_beam_geometry() -> void:
	if not _beam.is_inside_tree():
		return

	var target: Area2D = _beam._targeting.find_closest_enemy_in_path()
	var prev_target: Area2D = _beam._current_target_enemy

	if target != null:
		if prev_target != target:
			_beam._tick_timer = 0.0
			_beam._fractional_damage_buffer = 0.0
		_beam._current_target_enemy = target
		_beam._active_length = maxf(20.0, _beam.global_position.y - target.global_position.y)
	else:
		if prev_target != null:
			_beam._tick_timer = 0.0
			_beam._fractional_damage_buffer = 0.0
		_beam._current_target_enemy = null
		var default_top: float = 0.0
		if _beam.get_viewport() != null:
			default_top = _beam.get_viewport().get_visible_rect().position.y
		_beam._active_length = maxf(_beam.beam_length, (_beam.global_position.y - default_top) + 40.0)

	update_collision_shape()


## Sizes the collision rectangle to the active length, anchored at the emitter.
func update_collision_shape() -> void:
	if _beam._collision_shape == null:
		_beam._collision_shape = _beam.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _beam._collision_shape != null and _beam._collision_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = _beam._collision_shape.shape as RectangleShape2D
		rect_shape.size.x = _beam.beam_width
		rect_shape.size.y = _beam._active_length
		_beam._collision_shape.position = Vector2(0.0, -_beam._active_length * 0.5)
