# shield_ring.gd
# Visual indicator for the Player shield. Draws a ring without external assets;
# the color and thickness change with the shield level (1 cyan, 2 gold, 3 magenta).

extends Node2D

const RING_RADIUS: float = 26.0
const RING_WIDTH: float = 2.0
const LEVEL_COLORS: Array[Color] = [
	Color(0.35, 0.9, 1.0, 0.85),
	Color(1.0, 0.82, 0.25, 0.9),
	Color(1.0, 0.3, 0.8, 0.95),
]

var _level: int = 1


## Sets the shield level (1-3) and redraws the ring in that level's color.
func set_level(level: int) -> void:
	_level = clampi(level, 1, LEVEL_COLORS.size())
	queue_redraw()


func get_ring_color() -> Color:
	return LEVEL_COLORS[_level - 1]


func _draw() -> void:
	draw_arc(Vector2.ZERO, RING_RADIUS, 0.0, TAU, 48, get_ring_color(), RING_WIDTH + float(_level - 1), true)
