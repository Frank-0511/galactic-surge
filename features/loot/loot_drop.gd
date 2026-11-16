# loot_drop.gd
# Collectible loot item with autonomous fall, sine wave drift, player magnetism,
# and procedural vector rendering for 5 distinct powerup/score types.
# Behavior lives in sibling modules (loot_drop_*.gd) that read this node through _drop.

class_name LootDrop
extends Area2D

const MedallionModule: GDScript = preload("res://features/loot/loot_drop_medallion.gd")
const DrawModule: GDScript = preload("res://features/loot/loot_drop_draw.gd")

enum Type {
	SCORE,
	DOUBLE_SHOT,
	SHIELD,
	EXTRA_LIFE,
	BOMB,
	MEDALLION_BLASTER,
	MEDALLION_MISSILE,
	MEDALLION_LASER,
	POWER_ATOM,
	RECOVERY_CAPSULE,
}

signal collected(loot_type: Type, collector: Node2D)

@export var fall_speed: float = 120.0
@export var wave_amplitude: float = 26.0
@export var wave_frequency: float = 3.0
@export var magnet_radius: float = 150.0
@export var magnet_acceleration: float = 900.0
@export var lifetime: float = 0.0

var _type: Type = Type.SCORE
var _target: Node2D = null
var _velocity: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _collected: bool = false
var _painter: RefCounted

## Host-given network id (Etapa 20 T4); 0 when not networked.
var net_id: int = 0
## Client replica (Etapa 20 T4): no pickup, no magnet, no collision; the host decides the pickup.
var replica: bool = false:
	set(value):
		replica = value
		monitoring = not value
## Client replica: the ship (1 or 2) the host reports as the collector.
var collected_by: int = 0


func _init() -> void:
	_painter = DrawModule.new(self)


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_elapsed += delta

	# Lifetime countdown for temporary drops (such as death recovery capsules)
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			queue_free()
			return
		if lifetime <= 1.0:
			var blink: float = 0.25 + 0.75 * absf(sin(_elapsed * 20.0))
			modulate.a = blink
		else:
			modulate.a = 1.0

	# Viewport bounds despawn check
	var viewport_rect: Rect2 = get_viewport_rect()
	var max_y: float = viewport_rect.size.y if viewport_rect.size.y > 0.0 else 640.0
	if global_position.y > max_y + 50.0:
		queue_free()
		return

	# Horizontal wave velocity component: d/dt(A * sin(omega * t)) = A * omega * cos(omega * t)
	var wave_vx: float = wave_amplitude * wave_frequency * cos(_elapsed * wave_frequency)

	# Magnetism toward the nearest visible ship (Etapa 20); configured target is the fallback.
	var target: Node2D = null
	if is_inside_tree():
		target = nearest_ship(global_position, get_tree().get_nodes_in_group(&"player"))
	if target == null and _target != null and is_instance_valid(_target):
		target = _target
	if target != null and not replica:
		var to_target: Vector2 = target.global_position - global_position
		var dist: float = to_target.length()
		if dist <= magnet_radius and dist > 0.001:
			var dir: Vector2 = to_target / dist
			_velocity += dir * (magnet_acceleration * delta)

	var move_step: Vector2 = Vector2(wave_vx, fall_speed) + _velocity
	global_position += move_step * delta

	queue_redraw()


func configure(loot_type: int, spawn_position: Vector2, target: Node2D = null, custom_lifetime: float = 0.0) -> void:
	_type = loot_type as Type
	global_position = spawn_position
	_target = target
	_velocity = Vector2.ZERO
	_elapsed = 0.0
	_collected = false
	if custom_lifetime > 0.0:
		lifetime = custom_lifetime
	elif _type == Type.RECOVERY_CAPSULE:
		lifetime = 3.0
	else:
		lifetime = 0.0
	modulate.a = 1.0
	queue_redraw()


func get_type() -> Type:
	return _type


## Nearest visible ship to origin among candidates; null when none is visible (Etapa 20).
static func nearest_ship(origin: Vector2, candidates: Array) -> Node2D:
	var best: Node2D = null
	var best_distance: float = INF
	for candidate: Variant in candidates:
		var ship: Node2D = candidate as Node2D
		if ship == null or not ship.visible:
			continue
		var distance: float = origin.distance_squared_to(ship.global_position)
		if distance < best_distance:
			best_distance = distance
			best = ship
	return best


func get_lifetime() -> float:
	return lifetime


func _on_body_entered(body: Node2D) -> void:
	if _collected or replica:
		return
	if body.is_in_group(&"player") or body is CharacterBody2D:
		_collected = true
		collected.emit(_type, body)
		queue_free()


func _draw() -> void:
	_painter.draw_all()


func _get_type_glow_color() -> Color:
	return DrawModule.glow_color_for(_type)


## Paints the medallion of a weapon (0 blaster, 1 misil, 2 laser) on any CanvasItem.
## Delegates to loot_drop_medallion.gd; kept here because hud_icons.gd calls it by name.
static func paint_medallion(canvas: CanvasItem, weapon_type: int) -> void:
	MedallionModule.paint_medallion(canvas, weapon_type)
