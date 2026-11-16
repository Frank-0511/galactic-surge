# laser_beam_draw.gd
# Visual layers of the continuous beam: harmonic aura, neon envelope, white-hot core, muzzle flare,
# then either the thermal contact point with plasma sparks or the deep-space tip flare.
# Owned by LaserBeam through _beam and called from its _draw(); state and exports stay on LaserBeam.

extends RefCounted

var _beam: Area2D


func _init(beam: Area2D) -> void:
	_beam = beam


## Draws every beam layer; nothing is drawn while the beam is idle.
func draw_beam() -> void:
	if not _beam.is_firing:
		return

	var pulse: float = 0.8 + 0.2 * sin(_beam._time * 24.0)
	var beam_start: Vector2 = Vector2.ZERO
	var beam_end: Vector2 = Vector2(0.0, -_beam._active_length)

	# 0. Outer harmonic aura for high power levels
	if _beam._power_level >= 7:
		_beam.draw_line(beam_start, beam_end, Color(0.3, 0.9, 1.0, 0.15 * pulse), _beam.beam_width * 2.4)

	# 1. Outer broad atmospheric glow (magenta/purple)
	_beam.draw_line(beam_start, beam_end, Color(0.75, 0.15, 1.0, 0.22 * pulse), _beam.beam_width * 1.8)

	# 2. Main neon cyan envelope
	_beam.draw_line(beam_start, beam_end, Color(0.15, 0.85, 1.0, 0.65 * pulse), _beam.beam_width * 0.9)

	# 3. Blinding white-hot core
	_beam.draw_line(beam_start, beam_end, Color(0.95, 1.0, 1.0, 0.95), maxf(_beam.beam_width * 0.35, 1.5))

	# 4. Emitter muzzle flare
	_beam.draw_circle(beam_start, 6.0 * pulse, Color(0.2, 0.9, 1.0, 0.8))
	_beam.draw_circle(beam_start, 3.5, Color(1.0, 1.0, 1.0, 0.95))

	# 5. Contact point: Thermal impact on enemy hull vs tip dissipation in deep space
	if is_instance_valid(_beam._current_target_enemy) and _beam._current_target_enemy.is_inside_tree() and not (_beam._current_target_enemy.get("_destroyed") == true):
		_draw_contact(beam_end, pulse)
	else:
		# Tip dissipation flare in deep space
		_beam.draw_circle(beam_end, 5.0 * pulse, Color(0.8, 0.25, 1.0, 0.7))
		_beam.draw_circle(beam_end, 2.5, Color(1.0, 1.0, 1.0, 0.9))


## Draws the thermal impact on the targeted enemy: plasma bloom, amber ring, hot core, arc and sparks.
func _draw_contact(beam_end: Vector2, pulse: float) -> void:
	var impact_radius: float = _beam.beam_width * 1.1 * pulse + 3.0

	# Broad crimson-amber plasma bloom
	_beam.draw_circle(beam_end, impact_radius * 1.6, Color(1.0, 0.25, 0.1, 0.4 * pulse))

	# Bright neon amber thermal ring
	_beam.draw_circle(beam_end, impact_radius, Color(1.0, 0.65, 0.1, 0.85 * pulse))

	# Blinding white-hot contact core
	_beam.draw_circle(beam_end, impact_radius * 0.45, Color(1.0, 1.0, 0.95, 0.95))

	# Arc to enemy center if slightly offset
	var enemy_local: Vector2 = _beam.to_local(_beam._current_target_enemy.global_position)
	if beam_end.distance_squared_to(enemy_local) > 4.0:
		_beam.draw_line(beam_end, enemy_local, Color(1.0, 0.8, 0.3, 0.65 * pulse), 1.5)

	# Plasma sparks bursting from contact point
	for i in range(5):
		var spark_angle: float = (_beam._time * 20.0) + float(i) * (TAU / 5.0)
		var spark_dist: float = (impact_radius + 5.0) * (0.65 + 0.35 * sin(_beam._time * 28.0 + float(i) * 1.7))
		var spark_pos: Vector2 = beam_end + Vector2(cos(spark_angle), sin(spark_angle)) * spark_dist
		_beam.draw_circle(spark_pos, 2.0, Color(1.0, 0.85, 0.25, 0.9))
		_beam.draw_line(beam_end, spark_pos, Color(1.0, 0.45, 0.1, 0.55), 1.0)
