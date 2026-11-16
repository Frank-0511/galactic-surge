# hull_fragment.gd
# Purely visual hull debris spawned when an enemy is destroyed. It flies outward
# with light drag, spins slowly, fades to transparent over its lifetime and then
# releases itself. It has no collision and does not touch gameplay or scoring.

extends Node2D

const DRAG: float = 2.2
const SPIN_MIN: float = 2.0
const SPIN_MAX: float = 5.0
const BASE_SIZE: float = 6.0

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 0.6
var color: Color = Color(1.0, 1.0, 1.0)

var _elapsed: float = 0.0
var _spin: float = 0.0
var _points: PackedVector2Array = PackedVector2Array()


func configure(initial_velocity: Vector2, duration: float, fragment_color: Color) -> void:
	velocity = initial_velocity
	lifetime = maxf(duration, 0.01)
	color = fragment_color


func _ready() -> void:
	_spin = randf_range(SPIN_MIN, SPIN_MAX) * (1.0 if randf() < 0.5 else -1.0)
	var size_scale: float = randf_range(0.7, 1.3)
	var sides: int = randi_range(3, 4)
	_points.resize(sides)
	for side_index: int in sides:
		var angle: float = TAU * float(side_index) / float(sides) + randf_range(-0.3, 0.3)
		_points[side_index] = Vector2.from_angle(angle) * BASE_SIZE * size_scale
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	velocity *= maxf(0.0, 1.0 - DRAG * delta)
	position += velocity * delta
	rotation += _spin * delta
	queue_redraw()
	if _elapsed >= lifetime:
		queue_free()


func _draw() -> void:
	if _points.size() < 3:
		return
	var progress: float = clampf(_elapsed / lifetime, 0.0, 1.0)
	var fill: Color = Color(color.r, color.g, color.b, color.a * (1.0 - progress))
	draw_colored_polygon(_points, fill)
