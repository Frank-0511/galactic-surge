# asteroid_shape.gd
# Collision circle and procedural jagged outline of one Asteroid: builds the CollisionShape2D child,
# resizes its radius for each Size and generates the polygon and internal facet lines.
# Owned by Asteroid through _asteroid; state and exports stay on Asteroid.

extends RefCounted

var _asteroid: Asteroid


func _init(asteroid: Asteroid) -> void:
	_asteroid = asteroid


## Ensures a CollisionShape2D child exists and gives it a circle matching the current size.
func setup_collision_shape() -> void:
	if _asteroid._collision_shape == null:
		_asteroid._collision_shape = _asteroid.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _asteroid._collision_shape == null:
		_asteroid._collision_shape = CollisionShape2D.new()
		_asteroid._collision_shape.name = "CollisionShape2D"
		_asteroid.add_child(_asteroid._collision_shape)

	var radius: float = Asteroid.SIZES[_asteroid.asteroid_size]["radius"]
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	_asteroid._collision_shape.shape = circle


## Applies a new collision radius, reusing the existing circle when there is one.
func apply_collision_radius(radius: float) -> void:
	if _asteroid._collision_shape == null:
		_asteroid._collision_shape = _asteroid.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _asteroid._collision_shape != null and _asteroid._collision_shape.shape is CircleShape2D:
		(_asteroid._collision_shape.shape as CircleShape2D).radius = radius
	elif _asteroid._collision_shape != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = radius
		_asteroid._collision_shape.shape = circle


## Generates a stylized, jagged polygon around the collision radius.
func generate_procedural_shape() -> void:
	_asteroid._polygon_points.clear()
	_asteroid._facet_lines.clear()

	var radius: float = Asteroid.SIZES[_asteroid.asteroid_size]["radius"]
	var vertex_count: int = 12 if _asteroid.asteroid_size == Asteroid.Size.LARGE else (10 if _asteroid.asteroid_size == Asteroid.Size.MEDIUM else 8)
	var angle_step: float = TAU / float(vertex_count)

	# Deterministic pseudo-random variation based on radius and vertex index
	for i: int in range(vertex_count):
		var base_angle: float = i * angle_step
		var jitter_angle: float = base_angle + sin(float(i * 3 + int(radius))) * 0.12
		var var_radius: float = radius * (0.82 + 0.36 * absf(sin(float(i * 7 + int(radius) * 2))))
		_asteroid._polygon_points.append(Vector2(cos(jitter_angle), sin(jitter_angle)) * var_radius)

	# Generate 2 internal facet lines for depth
	if vertex_count >= 8:
		var p0: Vector2 = _asteroid._polygon_points[1]
		var p_mid: Vector2 = Vector2.ZERO + Vector2(sin(float(radius)), cos(float(radius))) * (radius * 0.25)
		var p1: Vector2 = _asteroid._polygon_points[vertex_count / 2]
		_asteroid._facet_lines.append(PackedVector2Array([p0, p_mid, p1]))
