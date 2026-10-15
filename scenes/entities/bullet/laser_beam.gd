# laser_beam.gd
# Continuous Chicken Invaders-style beam: stops at the first enemy, drains its
# health over time, and grows thicker and deadlier per power level.

extends Area2D

## Emitted whenever the laser ticks damage on an enemy.
signal enemy_hit(enemy: Area2D)

## Time interval in seconds between consecutive damage ticks.
@export var damage_tick_rate: float = 0.12

## Legacy/informative tick damage value (maintained for contract backwards-compatibility).
@export var damage_per_tick: int = 1

## Continuous damage per second applied to the first enemy in the path.
@export var damage_per_second: float = 2.5

## Minimum horizontal corridor used to detect targets (keeps thin beams aimable).
@export var min_hit_corridor: float = 14.0

## Whether the beam is active and applying damage.
@export var is_firing: bool = false

## Total default reach of the beam in pixels upwards (base contract default).
@export var beam_length: float = 420.0

## Effective width of the beam corridor in pixels.
@export var beam_width: float = 4.0

var _power_level: int = 1
var _tick_timer: float = 0.0
var _fractional_damage_buffer: float = 0.0
var _time: float = 0.0
var _active_length: float = 420.0
var _current_target_enemy: Area2D = null

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape != null and _collision_shape.shape != null:
		_collision_shape.shape = _collision_shape.shape.duplicate()
	_update_firing_state()
	if not is_firing:
		_reset_to_default_beam()


func _process(delta: float) -> void:
	if not is_firing:
		return

	_time += delta
	_tick_timer += delta

	_update_beam_geometry()

	if _tick_timer >= damage_tick_rate:
		_tick_timer -= damage_tick_rate
		_apply_damage_tick()

	queue_redraw()


func set_power_level(level: int) -> void:
	_power_level = clampi(level, 1, 10)
	beam_width = 4.0 + 2.2 * float(_power_level - 1)
	damage_per_second = 2.5 + 2.0 * float(_power_level - 1)
	damage_per_tick = 1 + int(_power_level >= 5) + int(_power_level >= 9)
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape != null and _collision_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = _collision_shape.shape as RectangleShape2D
		rect_shape.size.x = beam_width
	queue_redraw()


func set_firing(firing: bool) -> void:
	if is_firing == firing:
		return
	is_firing = firing
	_update_firing_state()
	_tick_timer = 0.0
	_fractional_damage_buffer = 0.0

	if is_firing:
		_update_beam_geometry()
	else:
		_reset_to_default_beam()

	queue_redraw()


func is_beam() -> bool:
	return true


func _update_firing_state() -> void:
	visible = is_firing
	monitoring = is_firing
	monitorable = is_firing


func _reset_to_default_beam() -> void:
	_active_length = beam_length
	_current_target_enemy = null
	_tick_timer = 0.0
	_fractional_damage_buffer = 0.0
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape != null and _collision_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = _collision_shape.shape as RectangleShape2D
		rect_shape.size.x = beam_width
		rect_shape.size.y = beam_length
		_collision_shape.position = Vector2(0.0, -beam_length * 0.5)


func _find_closest_enemy_in_path() -> Area2D:
	if not is_inside_tree():
		return null

	var enemies: Array[Node] = get_tree().get_nodes_in_group(&"enemies")
	var closest_enemy: Area2D = null
	var min_distance: float = INF

	for node: Node in enemies:
		if not is_instance_valid(node) or not (node is Area2D):
			continue
		var enemy: Area2D = node as Area2D
		if not enemy.is_inside_tree() or enemy.is_queued_for_deletion():
			continue
		if (enemy.get("_destroyed") == true):
			continue

		# Must be ahead of or at the laser emitter (with a slight 10px margin)
		if enemy.global_position.y > global_position.y + 10.0:
			continue

		var enemy_half_w: float = _get_enemy_half_width(enemy)
		var half_beam: float = maxf(beam_width, min_hit_corridor) * 0.5
		if absf(enemy.global_position.x - global_position.x) > (half_beam + enemy_half_w):
			continue

		var dist: float = global_position.y - enemy.global_position.y
		if dist < min_distance:
			min_distance = dist
			closest_enemy = enemy

	return closest_enemy


func _get_enemy_half_width(enemy: Area2D) -> float:
	var scale_factor: float = absf(enemy.scale.x)
	if scale_factor < 0.001:
		scale_factor = 1.0

	for child: Node in enemy.get_children():
		if child is CollisionShape2D:
			var cs: CollisionShape2D = child as CollisionShape2D
			if cs.shape != null:
				if cs.shape is RectangleShape2D:
					return (cs.shape as RectangleShape2D).size.x * 0.5 * scale_factor
				elif cs.shape is CircleShape2D:
					return (cs.shape as CircleShape2D).radius * scale_factor
				elif cs.shape is CapsuleShape2D:
					return (cs.shape as CapsuleShape2D).radius * scale_factor

	return 24.0


func _update_beam_geometry() -> void:
	if not is_inside_tree():
		return

	var target: Area2D = _find_closest_enemy_in_path()
	var prev_target: Area2D = _current_target_enemy

	if target != null:
		if prev_target != target:
			_tick_timer = 0.0
			_fractional_damage_buffer = 0.0
		_current_target_enemy = target
		_active_length = maxf(20.0, global_position.y - target.global_position.y)
	else:
		if prev_target != null:
			_tick_timer = 0.0
			_fractional_damage_buffer = 0.0
		_current_target_enemy = null
		var default_top: float = 0.0
		if get_viewport() != null:
			default_top = get_viewport().get_visible_rect().position.y
		_active_length = maxf(beam_length, (global_position.y - default_top) + 40.0)

	_update_collision_shape()


func _update_collision_shape() -> void:
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape != null and _collision_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = _collision_shape.shape as RectangleShape2D
		rect_shape.size.x = beam_width
		rect_shape.size.y = _active_length
		_collision_shape.position = Vector2(0.0, -_active_length * 0.5)


func _apply_damage_tick() -> void:
	if not is_firing or not is_inside_tree():
		return
	var target: Area2D = _current_target_enemy
	if not is_instance_valid(target) or not target.is_inside_tree() or (target.get("_destroyed") == true):
		return
	var amount: float = damage_per_second * damage_tick_rate
	enemy_hit.emit(target)
	if target.has_method(&"supports_fractional_damage"):
		target.call(&"take_damage", amount)
	elif target.has_method(&"take_damage"):
		# Integer-health targets (Boss): accumulate until a whole point is reached.
		_fractional_damage_buffer += amount
		var whole: int = int(floor(_fractional_damage_buffer))
		if whole > 0:
			_fractional_damage_buffer -= float(whole)
			target.call(&"take_damage", whole)
	elif target.has_method(&"destroy"):
		target.call(&"destroy")


func _on_area_entered(_area: Area2D) -> void:
	# Continuous beam applies sustained DPS exclusively in _apply_damage_tick().
	pass


func _draw() -> void:
	if not is_firing:
		return

	var pulse: float = 0.8 + 0.2 * sin(_time * 24.0)
	var beam_start: Vector2 = Vector2.ZERO
	var beam_end: Vector2 = Vector2(0.0, -_active_length)

	# 0. Outer harmonic aura for high power levels
	if _power_level >= 7:
		draw_line(beam_start, beam_end, Color(0.3, 0.9, 1.0, 0.15 * pulse), beam_width * 2.4)

	# 1. Outer broad atmospheric glow (magenta/purple)
	draw_line(beam_start, beam_end, Color(0.75, 0.15, 1.0, 0.22 * pulse), beam_width * 1.8)

	# 2. Main neon cyan envelope
	draw_line(beam_start, beam_end, Color(0.15, 0.85, 1.0, 0.65 * pulse), beam_width * 0.9)

	# 3. Blinding white-hot core
	draw_line(beam_start, beam_end, Color(0.95, 1.0, 1.0, 0.95), maxf(beam_width * 0.35, 1.5))

	# 4. Emitter muzzle flare
	draw_circle(beam_start, 6.0 * pulse, Color(0.2, 0.9, 1.0, 0.8))
	draw_circle(beam_start, 3.5, Color(1.0, 1.0, 1.0, 0.95))

	# 5. Contact point: Thermal impact on enemy hull vs tip dissipation in deep space
	if is_instance_valid(_current_target_enemy) and _current_target_enemy.is_inside_tree() and not (_current_target_enemy.get("_destroyed") == true):
		var impact_radius: float = beam_width * 1.1 * pulse + 3.0

		# Broad crimson-amber plasma bloom
		draw_circle(beam_end, impact_radius * 1.6, Color(1.0, 0.25, 0.1, 0.4 * pulse))

		# Bright neon amber thermal ring
		draw_circle(beam_end, impact_radius, Color(1.0, 0.65, 0.1, 0.85 * pulse))

		# Blinding white-hot contact core
		draw_circle(beam_end, impact_radius * 0.45, Color(1.0, 1.0, 0.95, 0.95))

		# Arc to enemy center if slightly offset
		var enemy_local: Vector2 = to_local(_current_target_enemy.global_position)
		if beam_end.distance_squared_to(enemy_local) > 4.0:
			draw_line(beam_end, enemy_local, Color(1.0, 0.8, 0.3, 0.65 * pulse), 1.5)

		# Plasma sparks bursting from contact point
		for i in range(5):
			var spark_angle: float = (_time * 20.0) + float(i) * (TAU / 5.0)
			var spark_dist: float = (impact_radius + 5.0) * (0.65 + 0.35 * sin(_time * 28.0 + float(i) * 1.7))
			var spark_pos: Vector2 = beam_end + Vector2(cos(spark_angle), sin(spark_angle)) * spark_dist
			draw_circle(spark_pos, 2.0, Color(1.0, 0.85, 0.25, 0.9))
			draw_line(beam_end, spark_pos, Color(1.0, 0.45, 0.1, 0.55), 1.0)
	else:
		# Tip dissipation flare in deep space
		draw_circle(beam_end, 5.0 * pulse, Color(0.8, 0.25, 1.0, 0.7))
		draw_circle(beam_end, 2.5, Color(1.0, 1.0, 1.0, 0.9))
