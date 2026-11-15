# asteroid.gd
# Simulates an inertial space rock with linear velocity and angular spin.
# Features hierarchical fragmentation upon destruction:
# LARGE -> 2 MEDIUM -> 4 SMALL -> 0 (disintegrates).
# Belongs to groups "asteroids", "enemies", "combat_transients" for seamless
# integration with all player weapons and cleanup routines.

class_name Asteroid
extends Area2D

enum Size {
	LARGE = 0,
	MEDIUM = 1,
	SMALL = 2,
}

const SIZES: Dictionary = {
	Size.LARGE: {
		"radius": 48.0,
		"hp": 5,
		"score": 150,
		"trauma": 0.35,
		"outline_color": Color(0.25, 0.85, 1.0),
		"inner_color": Color(0.04, 0.08, 0.16, 0.92),
	},
	Size.MEDIUM: {
		"radius": 28.0,
		"hp": 2,
		"score": 75,
		"trauma": 0.20,
		"outline_color": Color(0.35, 0.75, 1.0),
		"inner_color": Color(0.05, 0.07, 0.14, 0.92),
	},
	Size.SMALL: {
		"radius": 14.0,
		"hp": 1,
		"score": 30,
		"trauma": 0.10,
		"outline_color": Color(0.50, 0.70, 0.95),
		"inner_color": Color(0.06, 0.08, 0.13, 0.92),
	},
}

## Emitted when destroyed by weapons or impact.
signal destroyed(asteroid: Area2D, size: int, pos: Vector2, vel: Vector2)

## Last ship that damaged this asteroid; kill points go to it (Etapa 20, kill attribution).
var last_attacker: Node = null

## Emitted upon physical collision with the player ship.
signal player_contacted(player: Node2D)

## Emitted whenever health is reduced.
signal damaged(current: int, max_hp: int)

## Emitted when a child fragment is generated.
signal fragment_spawned(fragment: Area2D)

@export var asteroid_size: Size = Size.LARGE
@export var max_health: int = 5
@export var current_health: int = 5
@export var linear_velocity: Vector2 = Vector2.ZERO
@export var angular_velocity: float = 0.0
@export var contains_loot: bool = false
@export var loot_type: int = -1

var _destroyed: bool = false
var _hit_flash_timer: float = 0.0
var _polygon_points: PackedVector2Array = PackedVector2Array()
var _facet_lines: Array[PackedVector2Array] = []

@onready var _collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D


func _ready() -> void:
	add_to_group(&"asteroids")
	add_to_group(&"enemies")
	add_to_group(&"combat_transients")

	collision_layer = 4
	collision_mask = 3 # Layer 1: Player (CharacterBody2D), Layer 2: Player Bullets (Area2D)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	_setup_collision_shape()
	_generate_procedural_shape()
	queue_redraw()


func _setup_collision_shape() -> void:
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape == null:
		_collision_shape = CollisionShape2D.new()
		_collision_shape.name = "CollisionShape2D"
		add_child(_collision_shape)

	var radius: float = SIZES[asteroid_size]["radius"]
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	_collision_shape.shape = circle


## Configures the size, collision radius, and health of the asteroid.
func set_size(new_size: Size) -> void:
	asteroid_size = new_size
	var cfg: Dictionary = SIZES[asteroid_size]
	max_health = cfg["hp"]
	current_health = max_health

	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape != null and _collision_shape.shape is CircleShape2D:
		(_collision_shape.shape as CircleShape2D).radius = cfg["radius"]
	elif _collision_shape != null:
		var circle: CircleShape2D = CircleShape2D.new()
		circle.radius = cfg["radius"]
		_collision_shape.shape = circle

	_generate_procedural_shape()
	queue_redraw()


## Generates a stylized, jagged polygon around the collision radius.
func _generate_procedural_shape() -> void:
	_polygon_points.clear()
	_facet_lines.clear()

	var radius: float = SIZES[asteroid_size]["radius"]
	var vertex_count: int = 12 if asteroid_size == Size.LARGE else (10 if asteroid_size == Size.MEDIUM else 8)
	var angle_step: float = TAU / float(vertex_count)

	# Deterministic pseudo-random variation based on radius and vertex index
	for i: int in range(vertex_count):
		var base_angle: float = i * angle_step
		var jitter_angle: float = base_angle + sin(float(i * 3 + int(radius))) * 0.12
		var var_radius: float = radius * (0.82 + 0.36 * absf(sin(float(i * 7 + int(radius) * 2))))
		_polygon_points.append(Vector2(cos(jitter_angle), sin(jitter_angle)) * var_radius)

	# Generate 2 internal facet lines for depth
	if vertex_count >= 8:
		var p0: Vector2 = _polygon_points[1]
		var p_mid: Vector2 = Vector2.ZERO + Vector2(sin(float(radius)), cos(float(radius))) * (radius * 0.25)
		var p1: Vector2 = _polygon_points[vertex_count / 2]
		_facet_lines.append(PackedVector2Array([p0, p_mid, p1]))


func _process(delta: float) -> void:
	global_position += linear_velocity * delta
	rotation += angular_velocity * delta

	if _hit_flash_timer > 0.0:
		_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
		queue_redraw()

	# Despawn when far beyond viewport bounds
	var max_y: float = 1200.0
	if is_inside_tree():
		var vp: Rect2 = get_viewport_rect()
		if vp.size.y > 0.0:
			max_y = vp.end.y + 160.0
	if global_position.y > max_y or global_position.y < -300.0 or global_position.x < -300.0 or global_position.x > 1400.0:
		queue_free()


## Accepts damage, reducing current_health. Triggers destroy() if depleted.
func take_damage(amount: int = 1) -> bool:
	if _destroyed or amount <= 0:
		return false

	current_health = maxi(0, current_health - amount)
	_hit_flash_timer = 0.08
	damaged.emit(current_health, max_health)
	queue_redraw()

	if current_health <= 0:
		destroy()
		return true
	return false


## Fractional damage interface for laser beams and splash damage.
func take_damage_from(amount: float, _travel_direction: Vector2 = Vector2.ZERO) -> bool:
	var rounded_damage: int = maxi(1, int(round(amount)))
	return take_damage(rounded_damage)


## Signals continuous weapons (like LaserBeam) that this target takes fractional ticks.
func supports_fractional_damage() -> bool:
	return true


## Instantiates two child fragments with divergent angular velocity.
## LARGE -> 2 MEDIUM (±35° dispersion, ~1.3x speed).
## MEDIUM -> 2 SMALL (±40° dispersion, ~1.4x speed).
## SMALL -> [] (disintegrates without fragments).
func split() -> Array[Area2D]:
	var fragments: Array[Area2D] = []
	if asteroid_size == Size.SMALL:
		return fragments

	var next_size: Size = Size.MEDIUM if asteroid_size == Size.LARGE else Size.SMALL
	var dispersion_angle_deg: float = 35.0 if asteroid_size == Size.LARGE else 42.0
	var speed_multiplier: float = 1.30 if asteroid_size == Size.LARGE else 1.40

	var base_dir: Vector2 = linear_velocity.normalized()
	if base_dir.length_squared() < 0.1:
		base_dir = Vector2.DOWN
	var base_speed: float = maxf(linear_velocity.length() * speed_multiplier, 120.0)

	var angles: Array[float] = [-deg_to_rad(dispersion_angle_deg), deg_to_rad(dispersion_angle_deg)]
	var spins: Array[float] = [-2.2, 2.2]

	var asteroid_scene: PackedScene = load("res://scenes/entities/asteroid/asteroid.tscn") as PackedScene
	if asteroid_scene == null:
		return fragments

	var parent_container: Node = get_parent()

	for i: int in range(2):
		var frag: Asteroid = asteroid_scene.instantiate() as Asteroid
		if frag == null:
			continue
		frag.set_size(next_size)

		var frag_dir: Vector2 = base_dir.rotated(angles[i])
		var offset_dist: float = SIZES[asteroid_size]["radius"] * 0.45
		frag.linear_velocity = frag_dir * base_speed
		frag.angular_velocity = spins[i]
		frag.rotation = rotation + angles[i]

		if parent_container != null:
			parent_container.add_child(frag)
		# Set after add_child: global_position outside the tree is treated as local,
		# which would offset the fragment by its parent's own position.
		frag.global_position = global_position + frag_dir * offset_dist

		fragments.append(frag)
		fragment_spawned.emit(frag)

	return fragments


## Destroys the asteroid, triggering fragmentation and emitting destroyed.
func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true

	destroyed.emit(self, int(asteroid_size), global_position, linear_velocity)
	split()
	queue_free()


func _on_body_entered(body: Node2D) -> void:
	if _destroyed:
		return
	if body.is_in_group(&"player"):
		# Damage is applied by the listener (Main) through player_contacted,
		# so the player is hit exactly once per collision.
		player_contacted.emit(body)
		destroy()


func _on_area_entered(area: Area2D) -> void:
	if _destroyed:
		return
	# Beams handle their own tick rate and damage application
	if area.has_method(&"is_beam"):
		return
	# Projectiles that apply their own damage handle it themselves
	if "damage_applied" in area or "damage" in area:
		return
	# Generic bullet contact
	if area.collision_layer & 2 != 0 or area.is_in_group(&"bullets"):
		take_damage(1)


func _draw() -> void:
	if _polygon_points.is_empty():
		return

	var cfg: Dictionary = SIZES[asteroid_size]
	var outline_col: Color = cfg["outline_color"]
	var inner_col: Color = cfg["inner_color"]

	if _hit_flash_timer > 0.0:
		inner_col = Color(0.9, 0.95, 1.0, 0.95)
		outline_col = Color.WHITE

	# Draw solid rock body
	draw_colored_polygon(_polygon_points, inner_col)

	# Draw closed glowing outline
	var closed_loop: PackedVector2Array = _polygon_points.duplicate()
	closed_loop.append(_polygon_points[0])
	draw_polyline(closed_loop, outline_col, 2.5)

	# Draw internal faceted cracks
	for facet: PackedVector2Array in _facet_lines:
		draw_polyline(facet, outline_col * Color(1.0, 1.0, 1.0, 0.45), 1.2)

	# If high-value asteroid containing loot, draw subtle pulsating golden core
	if contains_loot:
		draw_circle(Vector2.ZERO, 5.0, Color(1.0, 0.85, 0.2, 0.85))
		draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 12, Color(1.0, 0.85, 0.2, 0.5), 1.5)
