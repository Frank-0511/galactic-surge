# power_up.gd
# Transient pickup that falls downward, detects the Player, and emits its type.
# Does not modify the player, score, waves or session state; Main coordinates that.

class_name PowerUp
extends Area2D

enum Type { DOUBLE_SHOT, SHIELD }

signal collected(power_up_type: Type)

## Fall speed in pixels per second.
@export var fall_speed: float = 120.0

## Vertical margin beyond which the pickup auto-frees.
const DESPAWN_MARGIN: float = 64.0

var _type: Type = Type.DOUBLE_SHOT
var _collected: bool = false
var _configured: bool = false

## Local clock used only to animate the pickup's glow and shield spin.
var _time: float = 0.0

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	position.y += fall_speed * delta
	_time += delta
	queue_redraw()
	# Auto-free when below the visible viewport.
	var viewport_height: float = get_viewport_rect().size.y
	if global_position.y > viewport_height + DESPAWN_MARGIN:
		queue_free()


func configure(power_up_type: int, spawn_position: Vector2) -> void:
	_type = power_up_type as Type
	global_position = spawn_position
	_configured = true
	_time = 0.0
	queue_redraw()


func get_type() -> Type:
	return _type


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if body.is_in_group(&"player"):
		_collected = true
		collected.emit(_type)
		queue_free()


func _draw() -> void:
	# A soft pulsing halo makes the drop read as a pickup from a distance,
	# and a gentle bob/scale on arrival keeps it from feeling static.
	var halo_pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
	var halo_color: Color = Color(0.95, 0.2, 0.85, 0.12 + 0.08 * halo_pulse) \
		if _type == Type.DOUBLE_SHOT else Color(0.35, 0.9, 1.0, 0.12 + 0.08 * halo_pulse)
	draw_circle(Vector2.ZERO, 15.0 + 3.0 * halo_pulse, halo_color)

	match _type:
		Type.DOUBLE_SHOT:
			_draw_double_shot()
		Type.SHIELD:
			_draw_shield()


func _draw_double_shot() -> void:
	# Two magenta chevrons representing the double-shot upgrade, with a
	# small synchronized pulse so they feel active while falling.
	var pulse: float = 1.0 + 0.08 * sin(_time * 6.0)
	var color: Color = Color(0.95, 0.2, 0.85, 0.9)
	var chevron_offset: float = 7.0 * pulse
	for offset_x: float in [-chevron_offset, chevron_offset]:
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(offset_x - 6, -8), Vector2(offset_x, 0), Vector2(offset_x + 6, -8),
		])
		draw_polyline(pts, color, 2.0, true)
		var pts2: PackedVector2Array = PackedVector2Array([
			Vector2(offset_x - 6, 2), Vector2(offset_x, 10), Vector2(offset_x + 6, 2),
		])
		draw_polyline(pts2, color, 2.0, true)


func _draw_shield() -> void:
	# A cyan ring representing the shield upgrade. A short bright arc slowly
	# orbits the ring so the icon reads as "shielded" rather than static.
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(0.35, 0.9, 1.0, 0.55), 2.0, true)
	var sweep_start: float = fmod(_time * 1.6, TAU)
	draw_arc(Vector2.ZERO, 14.0, sweep_start, sweep_start + 1.4, 16, Color(0.75, 1.0, 1.0, 0.95), 3.0, true)
