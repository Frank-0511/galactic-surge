# explosion_burst.gd
# Draws a brief deterministic-per-run geometric explosion and releases itself
# when finished. A quick white-hot flash gives way to an expanding shockwave,
# scattering debris fragments, and a trailing wisp of smoke.

class_name ExplosionBurst
extends Node2D

@export var duration: float = 0.32

var elapsed: float = 0.0
var _fragment_angles: PackedFloat32Array = PackedFloat32Array()

const FRAGMENT_COUNT: int = 12


func _ready() -> void:
	_fragment_angles.resize(FRAGMENT_COUNT)
	for fragment_index: int in FRAGMENT_COUNT:
		var base_angle: float = TAU * float(fragment_index) / float(FRAGMENT_COUNT)
		_fragment_angles[fragment_index] = base_angle + randf_range(-0.18, 0.18)
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	if elapsed >= duration:
		queue_free()


func _draw() -> void:
	var progress: float = clampf(elapsed / duration, 0.0, 1.0)
	var alpha: float = 1.0 - progress

	# Color cools from a white-hot flash to orange-red as the burst expands.
	var hot_color: Color = Color(1.0, 0.95, 0.75, alpha)
	var cool_color: Color = Color(0.95, 0.35, 0.1, alpha)
	var fragment_color: Color = hot_color.lerp(cool_color, progress)

	var inner_radius: float = lerpf(4.0, 16.0, progress)
	var outer_radius: float = lerpf(11.0, 40.0, progress)

	# Debris fragments streak outward and thin out as they cool.
	for fragment_index: int in _fragment_angles.size():
		var direction: Vector2 = Vector2.from_angle(_fragment_angles[fragment_index])
		draw_line(direction * inner_radius, direction * outer_radius, fragment_color, lerpf(3.2, 1.0, progress))

	# A fast expanding shockwave ring reads as the initial impact.
	var ring_radius: float = lerpf(6.0, 46.0, progress)
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 28, Color(1.0, 0.8, 0.4, alpha * 0.45), 2.0, true)

	# Bright core flash, shrinking as the energy disperses.
	draw_circle(Vector2.ZERO, lerpf(9.0, 2.0, progress), Color(1.0, 0.95, 0.8, alpha))

	# A faint trailing wisp of smoke lingers just before the burst fades out.
	if progress > 0.55:
		var smoke_progress: float = (progress - 0.55) / 0.45
		var smoke_alpha: float = smoke_progress * alpha
		for smoke_index: int in 4:
			var smoke_angle: float = TAU * float(smoke_index) / 4.0 + 0.4
			var smoke_pos: Vector2 = Vector2.from_angle(smoke_angle) * lerpf(10.0, 26.0, progress)
			draw_circle(smoke_pos, lerpf(3.0, 7.0, progress), Color(0.55, 0.53, 0.5, smoke_alpha * 0.4))
