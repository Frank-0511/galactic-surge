# missile.gd
# Guided homing missile fired by the player. Accelerates toward high speed,
# seeks the nearest enemy or boss, and delivers high explosive impact damage.

extends Area2D

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

var _current_speed: float = 280.0
var _has_hit: bool = false
var damage_applied: bool = false
var _time: float = 0.0
var _target: Node2D = null


func _ready() -> void:
	_current_speed = speed


func _process(delta: float) -> void:
	_time += delta

	# Smoothly accelerate from initial speed toward max_speed.
	_current_speed = move_toward(_current_speed, max_speed, 350.0 * delta)

	# Target acquisition: track nearest alive enemy in tree.
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		_target = _find_nearest_target()

	if _target != null and is_instance_valid(_target) and _target.is_inside_tree():
		var to_target: Vector2 = _target.global_position - global_position
		if to_target.length_squared() > 1.0:
			var desired_angle: float = Vector2.UP.angle_to(to_target)
			rotation = rotate_toward(rotation, desired_angle, turn_rate * delta)

	# Move forward along current facing direction.
	var forward: Vector2 = Vector2.UP.rotated(rotation)
	position += forward * _current_speed * delta

	# Destroy when moving well beyond screen bounds.
	if position.y < -100.0 or position.y > 1060.0 or position.x < -100.0 or position.x > 820.0:
		queue_free()

	queue_redraw()


func _find_nearest_target() -> Node2D:
	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemies")
	var nearest: Node2D = null
	var min_dist_sq: float = INF
	for node: Node in enemies:
		if not is_instance_valid(node):
			continue
		var enemy: Node2D = node as Node2D
		if enemy == null or not enemy.is_inside_tree():
			continue
		var d_sq: float = global_position.distance_squared_to(enemy.global_position)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq
			nearest = enemy
	return nearest


func _on_area_entered(area: Area2D) -> void:
	if _has_hit or not area.is_in_group(&"enemies"):
		return
	_has_hit = true
	enemy_hit.emit(area)

	if not damage_applied:
		damage_applied = true
		if area.has_method(&"take_damage"):
			area.call(&"take_damage", damage)
		elif area.has_method(&"destroy"):
			area.call(&"destroy")

	queue_free()


func _draw() -> void:
	# Stylized rocket missile silhouette with warhead, fins, and pulsating exhaust flame.
	var flicker: float = 0.75 + 0.25 * sin(_time * 28.0)
	var flame_outer: PackedVector2Array = PackedVector2Array([
		Vector2(-2.5, 9), Vector2(0, 9 + 8.0 * flicker), Vector2(2.5, 9)
	])
	draw_colored_polygon(flame_outer, Color(1.0, 0.45, 0.1, 0.9))

	var flame_inner: PackedVector2Array = PackedVector2Array([
		Vector2(-1.2, 9), Vector2(0, 9 + 4.5 * flicker), Vector2(1.2, 9)
	])
	draw_colored_polygon(flame_inner, Color(1.0, 0.95, 0.35, 1.0))

	# Stabilizing delta fins at tail
	var fin_left: PackedVector2Array = PackedVector2Array([
		Vector2(-3, 3), Vector2(-7, 8), Vector2(-3, 7)
	])
	var fin_right: PackedVector2Array = PackedVector2Array([
		Vector2(3, 3), Vector2(7, 8), Vector2(3, 7)
	])
	draw_colored_polygon(fin_left, Color(0.3, 0.35, 0.45))
	draw_colored_polygon(fin_right, Color(0.3, 0.35, 0.45))
	draw_polyline(fin_left, Color(0.9, 0.4, 0.1), 1.0)
	draw_polyline(fin_right, Color(0.9, 0.4, 0.1), 1.0)

	# Main fuselage body
	draw_rect(Rect2(-3, -5, 6, 13), Color(0.9, 0.92, 0.96))
	# Accent hazard stripe
	draw_rect(Rect2(-3, -1, 6, 3), Color(1.0, 0.3, 0.15))

	# Conical aerodynamic warhead
	var warhead: PackedVector2Array = PackedVector2Array([
		Vector2(0, -12), Vector2(-3, -5), Vector2(3, -5)
	])
	draw_colored_polygon(warhead, Color(1.0, 0.25, 0.15))
	draw_circle(Vector2(0, -11), 1.2, Color(1.0, 0.8, 0.3))
