# laser_beam.gd
# Continuous high-energy focused laser beam attached to the player ship.
# Applies tick-based damage to all overlapping enemies along its 420px reach.

extends Area2D

## Emitted whenever the laser ticks damage on an enemy.
signal enemy_hit(enemy: Area2D)

## Time interval in seconds between consecutive damage ticks.
@export var damage_tick_rate: float = 0.12

## Damage dealt per tick to each overlapping enemy.
@export var damage_per_tick: int = 1

## Whether the beam is active and applying damage.
@export var is_firing: bool = false

## Total reach of the beam in pixels upwards.
@export var beam_length: float = 420.0

## Effective width of the beam corridor in pixels.
@export var beam_width: float = 12.0

var _power_level: int = 1
var _tick_timer: float = 0.0
var _time: float = 0.0
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func set_power_level(level: int) -> void:
	_power_level = clampi(level, 1, 5)
	beam_width = 10.0 + float(_power_level) * 3.0
	damage_per_tick = 1 + int(_power_level >= 4)
	if _collision_shape != null and _collision_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = _collision_shape.shape as RectangleShape2D
		rect_shape.size.x = beam_width
	queue_redraw()



func _ready() -> void:
	_update_firing_state()


func _process(delta: float) -> void:
	if not is_firing:
		return

	_time += delta
	_tick_timer += delta

	if _tick_timer >= damage_tick_rate:
		_tick_timer = 0.0
		_apply_damage_tick()

	queue_redraw()


func set_firing(firing: bool) -> void:
	if is_firing == firing:
		return
	is_firing = firing
	_update_firing_state()
	_tick_timer = 0.0
	queue_redraw()


func is_beam() -> bool:
	return true


func _update_firing_state() -> void:
	visible = is_firing
	monitoring = is_firing
	monitorable = is_firing


func _apply_damage_tick() -> void:
	if not is_firing or not is_inside_tree() or not monitoring:
		return

	var targets: Array[Area2D] = get_overlapping_areas()
	for target: Area2D in targets:
		if not is_instance_valid(target) or not target.is_inside_tree():
			continue
		if target.is_in_group(&"enemies"):
			enemy_hit.emit(target)
			if target.has_method(&"take_damage"):
				target.call(&"take_damage", damage_per_tick)
			elif target.has_method(&"destroy"):
				target.call(&"destroy")


func _on_area_entered(area: Area2D) -> void:
	if not is_firing or not area.is_in_group(&"enemies"):
		return
	# Instant tick when enemy enters beam path
	enemy_hit.emit(area)
	if area.has_method(&"take_damage"):
		area.call(&"take_damage", damage_per_tick)
	elif area.has_method(&"destroy"):
		area.call(&"destroy")


func _draw() -> void:
	if not is_firing:
		return

	var pulse: float = 0.8 + 0.2 * sin(_time * 24.0)
	var beam_start: Vector2 = Vector2.ZERO
	var beam_end: Vector2 = Vector2(0.0, -beam_length)

	# 1. Outer broad atmospheric glow (magenta/purple)
	draw_line(beam_start, beam_end, Color(0.75, 0.15, 1.0, 0.22 * pulse), beam_width * 1.8)

	# 2. Main neon cyan envelope
	draw_line(beam_start, beam_end, Color(0.15, 0.85, 1.0, 0.65 * pulse), beam_width * 0.9)

	# 3. Blinding white-hot core
	draw_line(beam_start, beam_end, Color(0.95, 1.0, 1.0, 0.95), beam_width * 0.35)

	# 4. Emitter muzzle flare
	draw_circle(beam_start, 6.0 * pulse, Color(0.2, 0.9, 1.0, 0.8))
	draw_circle(beam_start, 3.5, Color(1.0, 1.0, 1.0, 0.95))

	# 5. Beam tip dissipation flare
	draw_circle(beam_end, 5.0 * pulse, Color(0.8, 0.25, 1.0, 0.7))
	draw_circle(beam_end, 2.5, Color(1.0, 1.0, 1.0, 0.9))
