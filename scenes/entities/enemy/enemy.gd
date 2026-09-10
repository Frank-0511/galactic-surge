# enemy.gd
# Enemy ship that shoots downward and reports collisions to its formation spawner.

extends Area2D

## Emitted once when the enemy has been destroyed.
signal destroyed(enemy: Area2D)

## Emitted when this enemy makes direct contact with the player.
signal player_contacted(player: Node2D)

## Minimum delay in seconds before a shot.
@export var min_shoot_cooldown: float = 1.25

## Maximum delay in seconds before a shot.
@export var max_shoot_cooldown: float = 2.5

## Projectile scene instantiated by this enemy.
@export var enemy_bullet_scene: PackedScene

@onready var _shoot_cooldown: Timer = $ShootCooldown

var _destroyed: bool = false

## Local clock and per-instance offset used only to animate a subtle idle
## breathing pulse, so a whole formation doesn't blink in perfect unison.
var _time: float = 0.0
var _pulse_offset: float = 0.0


func _ready() -> void:
	_pulse_offset = randf_range(0.0, TAU)
	_schedule_next_shot()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func destroy() -> void:
	if _destroyed:
		return
	_destroyed = true
	destroyed.emit(self)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Player bullets occupy collision layer 2, which is part of this Area2D mask.
	if _destroyed or (area.collision_layer & 2) == 0:
		return
	destroy()


func _on_body_entered(body: Node2D) -> void:
	if _destroyed or not body.is_in_group("player"):
		return
	player_contacted.emit(body)
	destroy()


func _on_shoot_cooldown_timeout() -> void:
	if _destroyed:
		return
	if enemy_bullet_scene != null:
		var enemy_bullet: Node2D = enemy_bullet_scene.instantiate() as Node2D
		if enemy_bullet != null:
			get_tree().current_scene.add_child(enemy_bullet)
			enemy_bullet.global_position = global_position + Vector2(0, 20)
	_schedule_next_shot()


func _schedule_next_shot() -> void:
	_shoot_cooldown.start(randf_range(min_shoot_cooldown, max_shoot_cooldown))


func _draw() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.0 + _pulse_offset)

	# Toxic ambient glow separates the alien silhouette from the starfield.
	draw_circle(Vector2.ZERO, 16.0 + 2.0 * pulse, Color(0.45, 1.0, 0.35, 0.07 + 0.05 * pulse))

	# Soft hover shadow beneath the carapace suggests it floats rather than flies.
	draw_circle(Vector2(0, 13), 8.0, Color(0.35, 0.95, 0.3, 0.10 + 0.06 * pulse))

	# Compact beetle-like carapace replaces the old swept-wing fighter silhouette.
	var carapace: PackedVector2Array = PackedVector2Array([
		Vector2(-8, -10), Vector2(0, -12), Vector2(8, -10),
		Vector2(10, 1), Vector2(6, 9), Vector2(0, 11), Vector2(-6, 9), Vector2(-10, 1),
	])
	draw_colored_polygon(carapace, Color(0.22, 0.05, 0.32))
	var carapace_outline: PackedVector2Array = carapace.duplicate()
	carapace_outline.append(carapace[0])
	draw_polyline(carapace_outline, Color(0.55, 1.0, 0.4), 1.5)

	# Crab-like pincer claws give the alien a distinct, non-jet profile.
	var claw_l: PackedVector2Array = PackedVector2Array([
		Vector2(-9, -3), Vector2(-17, -6), Vector2(-21, -9),
		Vector2(-16, -1), Vector2(-21, 4), Vector2(-16, 5), Vector2(-10, 2),
	])
	var claw_r: PackedVector2Array = PackedVector2Array([
		Vector2(9, -3), Vector2(17, -6), Vector2(21, -9),
		Vector2(16, -1), Vector2(21, 4), Vector2(16, 5), Vector2(10, 2),
	])
	draw_colored_polygon(claw_l, Color(0.28, 0.06, 0.4))
	draw_colored_polygon(claw_r, Color(0.28, 0.06, 0.4))
	var claw_l_outline: PackedVector2Array = claw_l.duplicate()
	claw_l_outline.append(claw_l[0])
	var claw_r_outline: PackedVector2Array = claw_r.duplicate()
	claw_r_outline.append(claw_r[0])
	draw_polyline(claw_l_outline, Color(0.6, 1.0, 0.45), 1.25)
	draw_polyline(claw_r_outline, Color(0.6, 1.0, 0.45), 1.25)

	# Twin antennae keep a whisper of the old sensor pair, now bioluminescent.
	draw_line(Vector2(-3, -11), Vector2(-4.5, -17), Color(0.65, 1.0, 0.5), 1.2)
	draw_line(Vector2(3, -11), Vector2(4.5, -17), Color(0.65, 1.0, 0.5), 1.2)
	draw_circle(Vector2(-4.5, -17), 1.2, Color(0.7, 1.0, 0.45, 0.9))
	draw_circle(Vector2(4.5, -17), 1.2, Color(0.7, 1.0, 0.45, 0.9))

	# Pulsing central eye reads as a clear, readable focal point at a glance.
	draw_circle(Vector2(0, -1), 4.0, Color(0.55, 1.0, 0.35, 0.3 + 0.2 * pulse))
	draw_circle(Vector2(0, -1), 2.0, Color(0.9, 1.0, 0.55, 0.8 + 0.2 * pulse))

	# Three thin wriggling legs suggest a hovering, skittering gait.
	for i in range(3):
		var leg_x: float = (i - 1) * 4.0
		var wag: float = sin(_time * 6.0 + _pulse_offset + i) * 1.5
		draw_line(Vector2(leg_x, 9), Vector2(leg_x + wag, 15), Color(0.5, 0.95, 0.4, 0.8), 1.1)
