# laser_beam.gd
# Continuous Chicken Invaders-style beam: stops at the first enemy, drains its
# health over time, and grows thicker and deadlier per power level.
# Keeps the public contract (exports, signals, state, power and firing API). Targeting, damage
# ticks, geometry and drawing live in laser_beam_*.gd modules owned through their _beam reference.

extends Area2D

const SESSION_STATS := preload("res://core/session/session_stats.gd")
const TargetingModule: GDScript = preload("res://features/bullet/laser_beam_targeting.gd")
const DamageModule: GDScript = preload("res://features/bullet/laser_beam_damage.gd")
const GeometryModule: GDScript = preload("res://features/bullet/laser_beam_geometry.gd")
const DrawModule: GDScript = preload("res://features/bullet/laser_beam_draw.gd")

## Emitted whenever the laser ticks damage on an enemy.
signal enemy_hit(enemy: Area2D)

## Time interval in seconds between consecutive damage ticks.
@export var damage_tick_rate: float = 0.12

## Legacy/informative tick damage value (maintained for contract backwards-compatibility).
@export var damage_per_tick: int = 1

## Continuous damage per second applied to the first enemy in the path.
@export var damage_per_second: float = 2.5

## Ship that owns this beam; targets record it for kill attribution (Etapa 20).
var shooter: Node = null

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
var _hit_registered: bool = false

var _targeting: RefCounted = TargetingModule.new(self)
var _damage: RefCounted = DamageModule.new(self)
var _geometry: RefCounted = GeometryModule.new(self)
var _visuals: RefCounted = DrawModule.new(self)

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	if _collision_shape == null:
		_collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if _collision_shape != null and _collision_shape.shape != null:
		_collision_shape.shape = _collision_shape.shape.duplicate()
	_update_firing_state()
	if not is_firing:
		_geometry.reset_to_default_beam()


func _process(delta: float) -> void:
	if not is_firing:
		return

	_time += delta
	_tick_timer += delta

	_geometry.update_beam_geometry()

	if _tick_timer >= damage_tick_rate:
		_tick_timer -= damage_tick_rate
		_damage.apply_damage_tick()

	queue_redraw()


## Beam width in pixels for a power level: levels 1-10 keep the original curve; above 10 the beam gains extra width.
static func width_for_level(level: int) -> float:
	return 4.0 + 2.2 * float(mini(level, 10) - 1) + 3.0 * float(maxi(level - 10, 0))


func set_power_level(level: int) -> void:
	_power_level = clampi(level, 1, 15)
	beam_width = width_for_level(_power_level)
	damage_per_second = 2.5 + 2.0 * float(mini(_power_level, 10) - 1) + 4.5 * float(maxi(_power_level - 10, 0))
	damage_per_tick = 1 + int(_power_level >= 5) + int(_power_level >= 9) + int(_power_level >= 13)
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
		# Each continuous beam activation is one projectile: one shot, one hit at most.
		_hit_registered = false
		SESSION_STATS.register_shot()

	if is_firing:
		_geometry.update_beam_geometry()
	else:
		_geometry.reset_to_default_beam()

	queue_redraw()


func is_beam() -> bool:
	return true


## Current reach of the beam in pixels (the network sync reads it to replicate the laser).
func get_active_length() -> float:
	return _active_length


func _update_firing_state() -> void:
	visible = is_firing
	monitoring = is_firing
	monitorable = is_firing


func _on_area_entered(_area: Area2D) -> void:
	# Continuous beam applies sustained DPS exclusively in _apply_damage_tick().
	pass


func _draw() -> void:
	_visuals.draw_beam()
