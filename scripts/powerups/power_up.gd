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

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	position.y += fall_speed * delta
	# Auto-free when below the visible viewport.
	var viewport_height: float = get_viewport_rect().size.y
	if global_position.y > viewport_height + DESPAWN_MARGIN:
		queue_free()


func configure(power_up_type: int, spawn_position: Vector2) -> void:
	_type = power_up_type as Type
	global_position = spawn_position
	_configured = true
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
	match _type:
		Type.DOUBLE_SHOT:
			_draw_double_shot()
		Type.SHIELD:
			_draw_shield()


func _draw_double_shot() -> void:
	# Two magenta chevrons representing the double-shot upgrade.
	var color: Color = Color(0.95, 0.2, 0.85, 0.9)
	var chevron_offset: float = 7.0
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
	# A cyan ring representing the shield upgrade.
	draw_arc(Vector2.ZERO, 14.0, 0.0, TAU, 32, Color(0.35, 0.9, 1.0, 0.9), 2.5, true)
