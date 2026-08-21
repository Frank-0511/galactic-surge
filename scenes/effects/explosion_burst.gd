# explosion_burst.gd
# Draws a brief deterministic geometric explosion and releases itself when finished.

class_name ExplosionBurst
extends Node2D

@export var duration: float = 0.25

var elapsed: float = 0.0


func _ready() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	if elapsed >= duration:
		queue_free()


func _draw() -> void:
	var progress: float = clampf(elapsed / duration, 0.0, 1.0)
	var alpha: float = 1.0 - progress
	var inner_radius: float = lerpf(5.0, 18.0, progress)
	var outer_radius: float = lerpf(13.0, 42.0, progress)
	var color: Color = Color(1.0, 0.62, 0.18, alpha)
	for fragment_index: int in 10:
		var angle: float = TAU * float(fragment_index) / 10.0
		var direction: Vector2 = Vector2.from_angle(angle)
		draw_line(direction * inner_radius, direction * outer_radius, color, 3.0)
	draw_circle(Vector2.ZERO, lerpf(8.0, 2.0, progress), Color(1.0, 0.9, 0.5, alpha))
