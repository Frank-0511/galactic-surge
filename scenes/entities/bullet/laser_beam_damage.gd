# laser_beam_damage.gd
# Damage ticks of the continuous beam: sustained damage to the current target, the integer-health
# buffer for Boss-style targets, and the single hit registered per activation. Owned by LaserBeam
# through _beam; the tick timer, damage buffer, hit flag and signals stay on LaserBeam.

extends RefCounted

const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")

var _beam: Area2D


func _init(beam: Area2D) -> void:
	_beam = beam


## Applies one damage tick to the current target: fractional, integer-buffered or destroy-only.
func apply_damage_tick() -> void:
	if not _beam.is_firing or not _beam.is_inside_tree():
		return
	var target: Area2D = _beam._current_target_enemy
	if not is_instance_valid(target) or not target.is_inside_tree() or (target.get("_destroyed") == true):
		return
	var amount: float = _beam.damage_per_second * _beam.damage_tick_rate
	_beam.enemy_hit.emit(target)
	if _beam.shooter != null:
		target.set("last_attacker", _beam.shooter)
	if target.has_method(&"supports_fractional_damage"):
		target.call(&"take_damage", amount)
		register_hit_once()
	elif target.has_method(&"take_damage"):
		# Integer-health targets (Boss): accumulate until a whole point is reached.
		_beam._fractional_damage_buffer += amount
		var whole: int = int(floor(_beam._fractional_damage_buffer))
		if whole > 0:
			_beam._fractional_damage_buffer -= float(whole)
			target.call(&"take_damage", whole)
			register_hit_once()
	elif target.has_method(&"destroy"):
		target.call(&"destroy")
		register_hit_once()


## Counts the beam's single hit for this activation the first time it damages an enemy.
func register_hit_once() -> void:
	if _beam._hit_registered:
		return
	_beam._hit_registered = true
	SESSION_STATS.register_hit()
