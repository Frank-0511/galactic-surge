# starfield.gd
# Draws a deterministic two-layer star background without external assets.

extends Node2D

const FAR_STAR_COUNT: int = 36
const NEAR_STAR_COUNT: int = 24
const FAR_SPEED: float = 18.0
const NEAR_SPEED: float = 72.0
const RANDOM_SEED: int = 4_204_021

var _far_stars: Array[Vector2] = []
var _near_stars: Array[Vector2] = []


func _ready() -> void:
	reset_scroll()


func _process(delta: float) -> void:
	var viewport_rect: Rect2 = get_viewport_rect()
	_advance_layer(_far_stars, FAR_SPEED, delta, viewport_rect)
	_advance_layer(_near_stars, NEAR_SPEED, delta, viewport_rect)
	queue_redraw()


func reset_scroll() -> void:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = RANDOM_SEED
	var viewport_rect: Rect2 = get_viewport_rect()
	_far_stars = _generate_stars(random, FAR_STAR_COUNT, viewport_rect)
	_near_stars = _generate_stars(random, NEAR_STAR_COUNT, viewport_rect)
	queue_redraw()


func get_layer_count() -> int:
	return 2


func get_star_positions_for_test() -> Dictionary:
	return {
		"far": PackedVector2Array(_far_stars),
		"near": PackedVector2Array(_near_stars),
	}


func _draw() -> void:
	for position: Vector2 in _far_stars:
		draw_circle(position, 1.0, Color(0.62, 0.72, 0.94, 0.45))
	for position: Vector2 in _near_stars:
		draw_circle(position, 1.8, Color(0.86, 0.92, 1.0, 0.85))


func _generate_stars(random: RandomNumberGenerator, count: int, viewport_rect: Rect2) -> Array[Vector2]:
	var stars: Array[Vector2] = []
	for index: int in count:
		var x: float = random.randf_range(viewport_rect.position.x, viewport_rect.end.x)
		var y: float = random.randf_range(viewport_rect.position.y, viewport_rect.end.y)
		stars.append(Vector2(x, y))
	return stars


func _advance_layer(stars: Array[Vector2], speed: float, delta: float, viewport_rect: Rect2) -> void:
	for index: int in stars.size():
		var position: Vector2 = stars[index] + Vector2(0.0, speed * delta)
		if position.y > viewport_rect.end.y:
			position.y = viewport_rect.position.y
		stars[index] = position
