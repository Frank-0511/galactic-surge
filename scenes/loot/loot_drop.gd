# loot_drop.gd
# Collectible loot item with autonomous fall, sine wave drift, player magnetism,
# and procedural vector rendering for 5 distinct powerup/score types.

class_name LootDrop
extends Area2D

enum Type { SCORE, DOUBLE_SHOT, SHIELD, EXTRA_LIFE, BOMB }

signal collected(loot_type: Type)

@export var fall_speed: float = 120.0
@export var wave_amplitude: float = 26.0
@export var wave_frequency: float = 3.0
@export var magnet_radius: float = 150.0
@export var magnet_acceleration: float = 900.0

var _type: Type = Type.SCORE
var _target: Node2D = null
var _velocity: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _collected: bool = false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_elapsed += delta

	# Viewport bounds despawn check
	var viewport_rect: Rect2 = get_viewport_rect()
	var max_y: float = viewport_rect.size.y if viewport_rect.size.y > 0.0 else 640.0
	if global_position.y > max_y + 50.0:
		queue_free()
		return

	# Horizontal wave velocity component: d/dt(A * sin(omega * t)) = A * omega * cos(omega * t)
	var wave_vx: float = wave_amplitude * wave_frequency * cos(_elapsed * wave_frequency)

	# Magnetism acceleration toward target when inside magnet_radius
	if _target != null and is_instance_valid(_target):
		var to_target: Vector2 = _target.global_position - global_position
		var dist: float = to_target.length()
		if dist <= magnet_radius and dist > 0.001:
			var dir: Vector2 = to_target / dist
			_velocity += dir * (magnet_acceleration * delta)

	var move_step: Vector2 = Vector2(wave_vx, fall_speed) + _velocity
	global_position += move_step * delta

	queue_redraw()


func configure(loot_type: int, spawn_position: Vector2, target: Node2D = null) -> void:
	_type = loot_type as Type
	global_position = spawn_position
	_target = target
	_velocity = Vector2.ZERO
	_elapsed = 0.0
	_collected = false
	queue_redraw()


func get_type() -> Type:
	return _type


func _on_body_entered(body: Node2D) -> void:
	if _collected:
		return
	if body.is_in_group(&"player") or body is CharacterBody2D:
		_collected = true
		collected.emit(_type)
		queue_free()


func _draw() -> void:
	# Subtle pulsing background halo for visibility against dark space
	var halo_pulse: float = 0.5 + 0.5 * sin(_elapsed * 4.0)
	var glow_color: Color = _get_type_glow_color()
	draw_circle(Vector2.ZERO, 15.0 + 2.5 * halo_pulse, Color(glow_color.r, glow_color.g, glow_color.b, 0.16 + 0.08 * halo_pulse))

	# High contrast backing disc and outer neon rim
	draw_circle(Vector2.ZERO, 12.0, Color(0.04, 0.06, 0.12, 0.85))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, glow_color, 1.5, true)

	match _type:
		Type.SCORE:
			_draw_score()
		Type.DOUBLE_SHOT:
			_draw_double_shot()
		Type.SHIELD:
			_draw_shield()
		Type.EXTRA_LIFE:
			_draw_extra_life()
		Type.BOMB:
			_draw_bomb()


func _get_type_glow_color() -> Color:
	match _type:
		Type.SCORE:
			return Color(1.0, 0.84, 0.0) # Yellow / Gold
		Type.DOUBLE_SHOT:
			return Color(0.0, 0.9, 1.0) # Cyan
		Type.SHIELD:
			return Color(0.0, 0.9, 0.46) # Emerald Green
		Type.EXTRA_LIFE:
			return Color(1.0, 0.09, 0.27) # Red / Magenta
		Type.BOMB:
			return Color(1.0, 0.57, 0.0) # Orange / Amber
		_:
			return Color.WHITE


func _draw_score() -> void:
	# Golden diamond star with glistening inner gleams
	var outer_diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)
	])
	var inner_diamond: PackedVector2Array = PackedVector2Array([
		Vector2(0, -4.5), Vector2(3.5, 0), Vector2(0, 4.5), Vector2(-3.5, 0)
	])
	draw_colored_polygon(outer_diamond, Color(1.0, 0.84, 0.0))
	draw_colored_polygon(inner_diamond, Color(1.0, 0.98, 0.7))
	# Subtle sparkle axes
	draw_line(Vector2(-9, 0), Vector2(9, 0), Color(1.0, 1.0, 0.85, 0.8), 1.0, true)
	draw_line(Vector2(0, -9), Vector2(0, 9), Color(1.0, 1.0, 0.85, 0.8), 1.0, true)


func _draw_double_shot() -> void:
	# Twin cyan chevrons representing dual blaster power
	var cyan: Color = Color(0.0, 0.9, 1.0)
	var left_chevron: PackedVector2Array = PackedVector2Array([
		Vector2(-7, 4), Vector2(-4, -5), Vector2(-1, 4)
	])
	var right_chevron: PackedVector2Array = PackedVector2Array([
		Vector2(1, 4), Vector2(4, -5), Vector2(7, 4)
	])
	draw_polyline(left_chevron, cyan, 2.2, true)
	draw_polyline(right_chevron, cyan, 2.2, true)
	draw_line(Vector2(-4, -4), Vector2(-4, 2), Color.WHITE, 1.2, true)
	draw_line(Vector2(4, -4), Vector2(4, 2), Color.WHITE, 1.2, true)


func _draw_shield() -> void:
	# Emerald concentric shield with rotating orbital arc
	var emerald: Color = Color(0.0, 0.9, 0.46)
	draw_arc(Vector2.ZERO, 7.5, 0.0, TAU, 24, Color(0.0, 0.9, 0.46, 0.6), 1.5, true)
	var sweep: float = fmod(_elapsed * 3.2, TAU)
	draw_arc(Vector2.ZERO, 7.5, sweep, sweep + 1.5, 12, Color(0.6, 1.0, 0.8), 2.5, true)
	var crest: PackedVector2Array = PackedVector2Array([
		Vector2(0, -4.5), Vector2(3.5, -2.5), Vector2(2.5, 2.5),
		Vector2(0, 4.5), Vector2(-2.5, 2.5), Vector2(-3.5, -2.5)
	])
	draw_colored_polygon(crest, emerald)
	draw_circle(Vector2.ZERO, 1.5, Color.WHITE)


func _draw_extra_life() -> void:
	# Vibrant red / magenta medical cross with white core
	var red: Color = Color(1.0, 0.09, 0.27)
	draw_rect(Rect2(-6.5, -2.5, 13.0, 5.0), red)
	draw_rect(Rect2(-2.5, -6.5, 5.0, 13.0), red)
	draw_rect(Rect2(-4.5, -1.2, 9.0, 2.4), Color(1.0, 0.92, 0.95))
	draw_rect(Rect2(-1.2, -4.5, 2.4, 9.0), Color(1.0, 0.92, 0.95))


func _draw_bomb() -> void:
	# Radiant orange detonator with radial spikes and bright core
	var orange: Color = Color(1.0, 0.57, 0.0)
	var base_angle: float = _elapsed * 1.8
	for i in range(8):
		var a: float = base_angle + i * (TAU / 8.0)
		var dir_v: Vector2 = Vector2(cos(a), sin(a))
		draw_line(dir_v * 5.5, dir_v * 9.5, orange, 1.8, true)
	draw_circle(Vector2.ZERO, 5.0, orange)
	draw_circle(Vector2.ZERO, 2.2, Color(1.0, 0.95, 0.8))
