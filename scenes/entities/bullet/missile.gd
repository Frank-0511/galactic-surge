# missile.gd
# Guided homing missile fired by the player. Accelerates toward high speed,
# seeks the nearest enemy or boss, and delivers high explosive impact damage plus a
# small area splash whose radius grows with the weapon level (Stage 12.5, ADR 010).

extends Area2D

const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")

## Emitted once when this missile hits an enemy target.
signal enemy_hit(enemy: Area2D)

## Initial movement speed in pixels per second.
@export var speed: float = 280.0

## Maximum flight speed in pixels per second.
@export var max_speed: float = 580.0

## Turning agility in radians per second.
@export var turn_rate: float = 3.5

## Damage dealt on impact.
@export var damage: int = 3

## Radius in pixels of the splash applied to neighbours of the impacted enemy.
@export var explosion_radius: float = 36.0

## Fraction of the direct damage applied to neighbours inside the explosion radius.
@export_range(0.0, 1.0, 0.05) var splash_ratio: float = 0.5

var _current_speed: float = 280.0
var _has_hit: bool = false
var damage_applied: bool = false
var _time: float = 0.0
var _target: Node2D = null


## Scales damage (3 + level / 2) and splash radius (36 px at L1, 90 px at L10, capped at 110 px above L10) by weapon level.
func set_power_level(level: int) -> void:
	var clamped: int = clampi(level, 1, 15)
	damage = 3 + clamped / 2
	explosion_radius = 36.0 + 6.0 * float(clamped - 1)
	if clamped > 10:
		explosion_radius = minf(explosion_radius, 110.0)


func set_target(new_target: Variant) -> void:
	if is_instance_valid(new_target) and new_target is Node2D:
		_target = new_target as Node2D
	else:
		_target = null


func get_target() -> Node2D:
	if _is_target_valid(_target):
		return _target
	return null


## Current velocity vector (used by enemy AI to dodge slow projectiles).
func get_projectile_velocity() -> Vector2:
	return Vector2.UP.rotated(rotation) * _current_speed


func _is_target_valid(t: Variant) -> bool:
	if not is_instance_valid(t) or not (t is Node2D):
		return false
	var node: Node2D = t as Node2D
	return node.is_inside_tree() and not node.is_queued_for_deletion() and node.get("_destroyed") != true


func _ready() -> void:
	_current_speed = speed


func _process(delta: float) -> void:
	_time += delta

	# Smoothly accelerate from initial speed toward max_speed.
	_current_speed = move_toward(_current_speed, max_speed, 350.0 * delta)

	# Target acquisition: track nearest alive enemy in tree, retarget dynamically if current dies.
	if not _is_target_valid(_target):
		_target = _find_nearest_target()

	if _is_target_valid(_target):
		var to_target: Vector2 = _target.global_position - global_position
		if to_target.length_squared() > 1.0:
			var desired_angle: float = Vector2.UP.angle_to(to_target)
			rotation = rotate_toward(rotation, desired_angle, turn_rate * delta)

	# Move forward along current facing direction.
	var forward: Vector2 = Vector2.UP.rotated(rotation)
	global_position += forward * _current_speed * delta

	# Destroy when moving well beyond screen bounds.
	var max_x: float = 1200.0
	var max_y: float = 1080.0
	if is_inside_tree():
		var vp: Rect2 = get_viewport_rect()
		if vp.size.x > 0.0:
			max_x = vp.end.x + 100.0
			max_y = vp.end.y + 100.0
	if global_position.y < -100.0 or global_position.y > max_y or global_position.x < -100.0 or global_position.x > max_x:
		queue_free()

	queue_redraw()


func _find_nearest_target() -> Node2D:
	if not is_inside_tree() or get_tree() == null:
		return null
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemies")
	var nearest: Node2D = null
	var min_dist_sq: float = INF
	for node: Node in enemies:
		if not _is_target_valid(node):
			continue
		var enemy: Node2D = node as Node2D
		var d_sq: float = global_position.distance_squared_to(enemy.global_position)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq
			nearest = enemy
	return nearest


func _on_area_entered(area: Area2D) -> void:
	if _has_hit or not is_instance_valid(area) or not area.is_in_group(&"enemies"):
		return
	if area.get("_destroyed") == true or area.is_queued_for_deletion():
		return
	_has_hit = true
	enemy_hit.emit(area)

	if not damage_applied:
		damage_applied = true
		if area.has_method(&"take_damage_from"):
			area.call(&"take_damage_from", float(damage), Vector2.UP.rotated(rotation))
			SESSION_STATS.register_hit()
		elif area.has_method(&"take_damage"):
			area.call(&"take_damage", damage)
			SESSION_STATS.register_hit()
		elif area.has_method(&"destroy"):
			area.call(&"destroy")
			SESSION_STATS.register_hit()
		_apply_splash(area)

	queue_free()


## Damages other living enemies within explosion_radius at splash_ratio of the direct damage.
## Frontal deflectors still apply because the hit goes through take_damage_from().
func _apply_splash(direct_target: Area2D) -> void:
	if not is_inside_tree() or get_tree() == null or explosion_radius <= 0.0:
		return
	var splash_damage: float = float(damage) * splash_ratio
	if splash_damage <= 0.0:
		return
	var radius_sq: float = explosion_radius * explosion_radius
	var travel: Vector2 = Vector2.UP.rotated(rotation)
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		if node == direct_target or not _is_target_valid(node):
			continue
		var neighbour: Node2D = node as Node2D
		if global_position.distance_squared_to(neighbour.global_position) > radius_sq:
			continue
		if neighbour.has_method(&"take_damage_from"):
			neighbour.call(&"take_damage_from", splash_damage, travel)


func _draw() -> void:
	# Lead-gray ("plomo") missile with a few accents: orange tip, one stripe, small flame.
	var flicker: float = 0.8 + 0.2 * sin(_time * 20.0)
	var gray: Color = Color(0.55, 0.60, 0.68)
	var gray_dark: Color = Color(0.32, 0.36, 0.44)
	var accent: Color = Color(1.0, 0.55, 0.1)

	# Exhaust flame.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3, 11), Vector2(0, 11 + 8.0 * flicker), Vector2(3, 11),
	]), Color(1.0, 0.65, 0.2, 0.85))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1.4, 11), Vector2(0, 11 + 4.0 * flicker), Vector2(1.4, 11),
	]), Color(1.0, 0.95, 0.6, 0.95))

	# Fins (darker gray).
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4, 3), Vector2(-8, 11), Vector2(-4, 9),
	]), gray_dark)
	draw_colored_polygon(PackedVector2Array([
		Vector2(4, 3), Vector2(8, 11), Vector2(4, 9),
	]), gray_dark)

	# Main body.
	draw_rect(Rect2(-4, -6, 8, 17), gray)
	# Slight shading on one side for volume.
	draw_rect(Rect2(1.5, -6, 2.5, 17), gray_dark)

	# Nose cone with orange tip.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -13), Vector2(-4, -6), Vector2(4, -6),
	]), gray_dark)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -13), Vector2(-1.8, -9.5), Vector2(1.8, -9.5),
	]), accent)

	# Single accent stripe.
	draw_rect(Rect2(-4, 1, 8, 2), accent)
