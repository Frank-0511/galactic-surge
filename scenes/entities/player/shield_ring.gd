# shield_ring.gd
# Visual indicator for the Player shield. Draws a cyan ring without external assets.

extends Node2D

const RING_RADIUS: float = 26.0
const RING_WIDTH: float = 2.0
const RING_COLOR: Color = Color(0.35, 0.9, 1.0, 0.85)


func _draw() -> void:
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 48, RING_COLOR, RING_WIDTH, true)
