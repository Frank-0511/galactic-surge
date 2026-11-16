# asteroid.gd
# Simulates an inertial space rock with linear velocity and angular spin.
# Features hierarchical fragmentation upon destruction:
# LARGE -> 2 MEDIUM -> 4 SMALL -> 0 (disintegrates).
# Belongs to groups "asteroids", "enemies", "combat_transients" for seamless
# integration with all player weapons and cleanup routines.
# Behaviour lives in sibling modules asteroid_*.gd, each owned through _asteroid; exports, signals,
# constants, state and the scene-connected collision callbacks stay here.

class_name Asteroid
extends Area2D

const ShapeModule: GDScript = preload("res://scenes/entities/asteroid/asteroid_shape.gd")
const FragmentationModule: GDScript = preload("res://scenes/entities/asteroid/asteroid_fragmentation.gd")
const MotionModule: GDScript = preload("res://scenes/entities/asteroid/asteroid_motion.gd")
const VisualsModule: GDScript = preload("res://scenes/entities/asteroid/asteroid_visuals.gd")
const DamageModule: GDScript = preload("res://scenes/entities/asteroid/asteroid_damage.gd")

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

## Host-given network id (Etapa 20 T4); 0 when not networked.
var net_id: int = 0
## Client replica (Etapa 20 T4): no motion of its own, no collision, no damage; the host decides all of it.
var replica: bool = false:
	set(value):
		replica = value
		monitoring = not value
		monitorable = not value

var _destroyed: bool = false
var _hit_flash_timer: float = 0.0
var _polygon_points: PackedVector2Array = PackedVector2Array()
var _facet_lines: Array[PackedVector2Array] = []

@onready var _collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

var _shape: RefCounted = ShapeModule.new(self)
var _fragmentation: RefCounted = FragmentationModule.new(self)
var _motion: RefCounted = MotionModule.new(self)
var _visuals: RefCounted = VisualsModule.new(self)
var _damage: RefCounted = DamageModule.new(self)


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

	_shape.setup_collision_shape()
	_shape.generate_procedural_shape()
	queue_redraw()


## Configures the size, collision radius, and health of the asteroid.
func set_size(new_size: Size) -> void:
	asteroid_size = new_size
	var cfg: Dictionary = SIZES[asteroid_size]
	max_health = cfg["hp"]
	current_health = max_health

	_shape.apply_collision_radius(cfg["radius"])
	_shape.generate_procedural_shape()
	queue_redraw()


func _process(delta: float) -> void:
	if replica:
		return
	_motion.advance(delta)


## Accepts damage, reducing current_health. Triggers destroy() if depleted.
func take_damage(amount: int = 1) -> bool:
	if replica:
		return false
	return _damage.take_damage(amount)


## Fractional damage interface for laser beams and splash damage.
func take_damage_from(amount: float, _travel_direction: Vector2 = Vector2.ZERO) -> bool:
	if replica:
		return false
	return _damage.take_damage_from(amount)


## Signals continuous weapons (like LaserBeam) that this target takes fractional ticks.
func supports_fractional_damage() -> bool:
	return true


## Instantiates two child fragments with divergent angular velocity (see asteroid_fragmentation.gd).
func split() -> Array[Area2D]:
	return _fragmentation.split()


## Destroys the asteroid, triggering fragmentation and emitting destroyed.
func destroy() -> void:
	_damage.destroy()


func _on_body_entered(body: Node2D) -> void:
	if replica:
		return
	PhysicsSafe.begin_callback()
	_damage.on_body_entered(body)
	PhysicsSafe.end_callback()


func _on_area_entered(area: Area2D) -> void:
	if replica:
		return
	PhysicsSafe.begin_callback()
	_damage.on_area_entered(area)
	PhysicsSafe.end_callback()


func _draw() -> void:
	_visuals.draw_asteroid()
