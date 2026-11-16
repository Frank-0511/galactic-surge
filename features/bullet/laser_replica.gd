# laser_replica.gd
# Visual-only laser of a remote ship on the client (Etapa 20 T36, S2): the host's beam drawn from the host's
# origin to the host's length, with the same colour layers as LaserBeam (without the contact effects).
# An Area2D with monitoring, monitorable and collisions off: it never hits, damages, scores or costs heat.
# Created and driven by net_sync_laser.gd.

extends Area2D

const LaserBeamScript: GDScript = preload("res://features/bullet/laser_beam.gd")

## Reach of the replica in pixels, as the host reported it.
var length: float = 0.0
## Beam width in pixels for the host's power level.
var width: float = 4.0
## Host power level of the replicated beam (1 to 15).
var level: int = 1

var _time: float = 0.0


func _ready() -> void:
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	queue_redraw()


## Shows the host's beam from origin (global position) with its reach and power level.
func show_beam(origin: Vector2, beam_length: float, power_level: int) -> void:
	global_position = origin
	length = maxf(beam_length, 0.0)
	level = clampi(power_level, 1, 15)
	width = LaserBeamScript.width_for_level(level)
	visible = true
	queue_redraw()


## Hides the replica (the host stopped firing, or the match ended).
func hide_beam() -> void:
	visible = false


func _draw() -> void:
	var pulse: float = 0.8 + 0.2 * sin(_time * 24.0)
	var beam_start: Vector2 = Vector2.ZERO
	var beam_end: Vector2 = Vector2(0.0, -length)
	if level >= 7:
		draw_line(beam_start, beam_end, Color(0.3, 0.9, 1.0, 0.15 * pulse), width * 2.4)
	draw_line(beam_start, beam_end, Color(0.75, 0.15, 1.0, 0.22 * pulse), width * 1.8)
	draw_line(beam_start, beam_end, Color(0.15, 0.85, 1.0, 0.65 * pulse), width * 0.9)
	draw_line(beam_start, beam_end, Color(0.95, 1.0, 1.0, 0.95), maxf(width * 0.35, 1.5))
	draw_circle(beam_start, 6.0 * pulse, Color(0.2, 0.9, 1.0, 0.8))
	draw_circle(beam_start, 3.5, Color(1.0, 1.0, 1.0, 0.95))
	draw_circle(beam_end, 5.0 * pulse, Color(0.8, 0.25, 1.0, 0.7))
	draw_circle(beam_end, 2.5, Color(1.0, 1.0, 1.0, 0.9))
