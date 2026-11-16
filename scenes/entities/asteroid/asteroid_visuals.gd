# asteroid_visuals.gd
# Draws one Asteroid: solid rock body, glowing outline, internal facet cracks, hit flash and the
# golden loot core. Called from Asteroid._draw(); owned by Asteroid through _asteroid.

extends RefCounted

var _asteroid: Asteroid


func _init(asteroid: Asteroid) -> void:
	_asteroid = asteroid


## Draws the rock for the current size, hit-flash state and loot flag.
func draw_asteroid() -> void:
	if _asteroid._polygon_points.is_empty():
		return

	var cfg: Dictionary = Asteroid.SIZES[_asteroid.asteroid_size]
	var outline_col: Color = cfg["outline_color"]
	var inner_col: Color = cfg["inner_color"]

	if _asteroid._hit_flash_timer > 0.0:
		inner_col = Color(0.9, 0.95, 1.0, 0.95)
		outline_col = Color.WHITE

	# Draw solid rock body
	_asteroid.draw_colored_polygon(_asteroid._polygon_points, inner_col)

	# Draw closed glowing outline
	var closed_loop: PackedVector2Array = _asteroid._polygon_points.duplicate()
	closed_loop.append(_asteroid._polygon_points[0])
	_asteroid.draw_polyline(closed_loop, outline_col, 2.5)

	# Draw internal faceted cracks
	for facet: PackedVector2Array in _asteroid._facet_lines:
		_asteroid.draw_polyline(facet, outline_col * Color(1.0, 1.0, 1.0, 0.45), 1.2)

	# If high-value asteroid containing loot, draw subtle pulsating golden core
	if _asteroid.contains_loot:
		_asteroid.draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.85, 0.2, 0.85))
		_asteroid.draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 12, Color(1.0, 0.85, 0.2, 0.5), 1.5)
