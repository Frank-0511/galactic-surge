# enemy_bullet.gd
# Projectile fired by enemies. Features physical simulation, ballistic parabolas,
# cluster fragmentation, luminous trails, and ground/impact detonation.

extends Area2D

## Emitted once when this projectile hits the player.
signal player_hit(player: Node2D)

## Emitted when this projectile detonates (on ground or mid-air/impact).
signal detonated(is_ground: bool)

## Tactical plasma projectile variants.
enum PlasmaVariant {
	DIRECT,
	PARABOLIC,
	CLUSTER,
	CLUSTER_SUBMUNITION,
}

const BULLET_SCENE_PATH: String = "res://scenes/entities/enemy/enemy_bullet.tscn"
const MAX_TRAIL_POINTS: int = 12

## Active plasma variant.
@export var plasma_variant: PlasmaVariant = PlasmaVariant.DIRECT

## Movement speed in pixels per second (for DIRECT or fallback initial speed).
@export var speed: float = 350.0

## Initial velocity assigned at launch.
@export var initial_velocity: Vector2 = Vector2.ZERO

## Custom ballistic gravity acceleration in pixels per second squared (downward on y).
## Note: Area2D defines built-in 'gravity' (default 980.0); ballistic_gravity allows explicit tuning.
@export var ballistic_gravity: float = 0.0:
	set(val):
		ballistic_gravity = val
		gravity = val

## Current physical velocity vector.
@export var velocity: Vector2 = Vector2.ZERO

## Fuse countdown time in seconds before a CLUSTER projectile splits.
@export var cluster_fuse_time: float = 0.55

## Number of submunitions spawned upon cluster detonation.
@export var submunition_count: int = 3

## Fan angle between submunitions in radians (30 degrees).
@export var submunition_spread_angle: float = deg_to_rad(30.0)

## Maximum lifetime in seconds for submunitions before self-detonation.
@export var submunition_lifetime: float = 2.5

var _has_hit: bool = false
var _is_detonating: bool = false
var _detonation_timer: float = 0.0
var _detonation_duration: float = 0.14
var _max_detonation_radius: float = 22.0
var _detonation_is_ground: bool = false

var _elapsed_flight_time: float = 0.0
var _trail_points: Array[Vector2] = []
var _trail_record_interval: float = 0.02
var _trail_timer: float = 0.0


func _ready() -> void:
	if plasma_variant == PlasmaVariant.DIRECT:
		ballistic_gravity = 0.0
		gravity = 0.0
	elif ballistic_gravity != 0.0:
		gravity = ballistic_gravity
	elif gravity != 0.0 and gravity != 980.0:
		ballistic_gravity = gravity

	if velocity.is_zero_approx():
		if not initial_velocity.is_zero_approx():
			velocity = initial_velocity
		elif plasma_variant == PlasmaVariant.DIRECT:
			velocity = Vector2(0.0, speed)
	if _trail_points.is_empty():
		_trail_points.append(global_position)


## Returns the active gravity acceleration used for ballistic simulation.
func get_effective_gravity() -> float:
	if plasma_variant == PlasmaVariant.DIRECT:
		return 0.0
	if ballistic_gravity != 0.0:
		return ballistic_gravity
	if gravity != 980.0:
		return gravity
	return 0.0


func _process(delta: float) -> void:
	if _is_detonating:
		_detonation_timer += delta
		queue_redraw()
		if _detonation_timer >= _detonation_duration:
			queue_free()
		return

	_elapsed_flight_time += delta

	# Ensure velocity is initialized
	if velocity.is_zero_approx():
		if not initial_velocity.is_zero_approx():
			velocity = initial_velocity
		elif plasma_variant == PlasmaVariant.DIRECT:
			velocity = Vector2(0.0, speed)

	# Physical ballistic simulation
	if plasma_variant == PlasmaVariant.DIRECT:
		position += velocity * delta
	else:
		velocity.y += get_effective_gravity() * delta
		position += velocity * delta

	# Trail point tracking
	_trail_timer += delta
	if _trail_timer >= _trail_record_interval:
		_trail_timer = 0.0
		if _trail_points.is_empty() or _trail_points[-1].distance_squared_to(global_position) > 1.0:
			_trail_points.append(global_position)
			if _trail_points.size() > MAX_TRAIL_POINTS:
				_trail_points.pop_front()

	# Cluster fuse timer
	if plasma_variant == PlasmaVariant.CLUSTER:
		if _elapsed_flight_time >= cluster_fuse_time:
			_split_cluster()
			return

	# Submunition lifetime limit
	if plasma_variant == PlasmaVariant.CLUSTER_SUBMUNITION:
		if _elapsed_flight_time >= submunition_lifetime:
			_detonate(false)
			return

	# Screen boundary check (Ground impact at viewport bottom)
	var vp_rect: Rect2 = get_viewport_rect() if is_inside_tree() else Rect2(0, 0, 1080, 960)
	if position.y >= vp_rect.size.y:
		_detonate(true)
		return

	# Off-screen lateral cleanup
	if position.x < -150.0 or position.x > vp_rect.size.x + 150.0 or position.y < -200.0:
		queue_free()
		return

	queue_redraw()


func _split_cluster() -> void:
	if _is_detonating:
		return

	var parent_node: Node = get_parent()
	if parent_node != null and is_inside_tree():
		var bullet_scene: PackedScene = load(BULLET_SCENE_PATH) as PackedScene
		var base_dir: Vector2 = velocity.normalized() if not velocity.is_zero_approx() else Vector2.DOWN
		var base_speed: float = maxf(velocity.length() * 0.95, 260.0)
		var effective_g: float = maxf(get_effective_gravity(), 320.0)

		for i: int in range(submunition_count):
			var sub: Area2D = null
			if bullet_scene != null:
				sub = bullet_scene.instantiate() as Area2D
			else:
				sub = duplicate() as Area2D

			if sub != null:
				sub.plasma_variant = PlasmaVariant.CLUSTER_SUBMUNITION
				sub.ballistic_gravity = effective_g
				sub.gravity = effective_g
				var angle_offset: float = (float(i) - float(submunition_count - 1) / 2.0) * submunition_spread_angle
				var sub_dir: Vector2 = base_dir.rotated(angle_offset)
				sub.velocity = sub_dir * base_speed
				sub.initial_velocity = sub.velocity
				parent_node.add_child(sub)
				sub.global_position = global_position

	_detonate(false)


func _detonate(is_ground: bool = false) -> void:
	if _is_detonating:
		return
	_is_detonating = true
	_detonation_is_ground = is_ground
	_detonation_timer = 0.0
	velocity = Vector2.ZERO
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	detonated.emit(is_ground)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _has_hit or _is_detonating or not body.is_in_group("player"):
		return
	_has_hit = true
	player_hit.emit(body)
	_detonate(false)


func is_detonating() -> bool:
	return _is_detonating


func get_trail_points() -> Array[Vector2]:
	return _trail_points.duplicate()


func get_plasma_variant() -> PlasmaVariant:
	return plasma_variant


func set_plasma_variant(variant: PlasmaVariant) -> void:
	plasma_variant = variant


func _get_variant_color() -> Color:
	match plasma_variant:
		PlasmaVariant.DIRECT:
			return Color(1.0, 0.35, 0.1)
		PlasmaVariant.PARABOLIC:
			return Color(1.0, 0.75, 0.15)
		PlasmaVariant.CLUSTER:
			return Color(0.2, 0.95, 0.8)
		PlasmaVariant.CLUSTER_SUBMUNITION:
			return Color(1.0, 0.88, 0.25)
		_:
			return Color.ORANGE_RED


func _draw() -> void:
	var variant_color: Color = _get_variant_color()

	if _is_detonating:
		var t: float = clampf(_detonation_timer / _detonation_duration, 0.0, 1.0)
		var cur_radius: float = lerpf(6.0, _max_detonation_radius, t)
		var alpha: float = 1.0 - t
		draw_circle(Vector2.ZERO, cur_radius, Color(variant_color.r, variant_color.g, variant_color.b, alpha * 0.35))
		draw_arc(Vector2.ZERO, cur_radius, 0.0, TAU, 28, Color(variant_color.r, variant_color.g, variant_color.b, alpha * 0.9), 2.2)
		draw_circle(Vector2.ZERO, maxf(1.0, (1.0 - t) * 5.0), Color(1.0, 1.0, 1.0, alpha * 0.95))
		return

	# 1. Residual luminous trail
	var trail_count: int = _trail_points.size()
	for i: int in range(trail_count):
		var pt: Vector2 = _trail_points[i]
		var local_pt: Vector2 = to_local(pt) if is_inside_tree() else (pt - global_position)
		var factor: float = float(i + 1) / float(trail_count + 1)
		var radius: float = lerpf(1.2, 3.2, factor)
		var trail_alpha: float = factor * 0.45
		draw_circle(local_pt, radius, Color(variant_color.r, variant_color.g, variant_color.b, trail_alpha))
		if i > 0:
			var prev_pt: Vector2 = _trail_points[i - 1]
			var prev_local_pt: Vector2 = to_local(prev_pt) if is_inside_tree() else (prev_pt - global_position)
			draw_line(prev_local_pt, local_pt, Color(variant_color.r, variant_color.g, variant_color.b, trail_alpha * 0.7), radius * 1.5)

	# 2. Main projectile body
	draw_circle(Vector2.ZERO, 6.0, Color(variant_color.r, variant_color.g, variant_color.b, 0.35))
	match plasma_variant:
		PlasmaVariant.DIRECT:
			draw_rect(Rect2(-2, -6, 4, 12), Color.ORANGE_RED)
			draw_rect(Rect2(-1, -4, 2, 8), Color(1.0, 0.9, 0.7, 0.9))
		PlasmaVariant.PARABOLIC:
			draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.75, 0.15))
			draw_circle(Vector2.ZERO, 2.0, Color(1.0, 1.0, 0.8))
		PlasmaVariant.CLUSTER:
			var diamond: PackedVector2Array = PackedVector2Array([
				Vector2(0, -6), Vector2(5, 0), Vector2(0, 6), Vector2(-5, 0)
			])
			draw_colored_polygon(diamond, Color(0.2, 0.95, 0.8))
			draw_circle(Vector2.ZERO, 2.5, Color(1.0, 1.0, 1.0))
		PlasmaVariant.CLUSTER_SUBMUNITION:
			draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.85, 0.2))
			draw_circle(Vector2.ZERO, 1.5, Color(1.0, 1.0, 0.9))
