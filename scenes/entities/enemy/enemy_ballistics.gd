# enemy_ballistics.gd
# Bullet configuration of one Enemy: picks the plasma variant (direct, parabolic or cluster) from
# the forced value or the normal/enraged mix, and sets the launch velocity and gravity of the
# spawned bullet. Owned by Enemy through _enemy.

extends RefCounted

const PlayerShip: Script = preload("res://scenes/entities/player/player.gd")
const VectorMath: Script = preload("res://scripts/math/vector_math.gd")

## Optional forced bullet variant for testing/scripting (-1 for standard probability).
var _forced_bullet_variant: int = -1

## Probabilities [direct, parabolic, cluster] for normal state. Empty = legacy defaults.
var _bullet_mix: Array = []

## Probabilities [direct, parabolic, cluster] when enraged. Empty = legacy defaults.
var _enraged_bullet_mix: Array = []

var _enemy: Area2D


func _init(enemy: Area2D) -> void:
	_enemy = enemy


## Sets the normal and enraged [direct, parabolic, cluster] probabilities.
func set_bullet_mix(normal_mix: Array, enraged_mix: Array) -> void:
	_bullet_mix = normal_mix.duplicate()
	_enraged_bullet_mix = enraged_mix.duplicate()


func set_forced_variant(variant: int) -> void:
	_forced_bullet_variant = variant


func get_forced_variant() -> int:
	return _forced_bullet_variant


## Configures physical ballistic properties and plasma variant for spawned bullets.
func configure_bullet(bullet: Node2D) -> void:
	if not ("plasma_variant" in bullet):
		return

	var variant: int = _forced_bullet_variant
	if variant < 0:
		var roll: float = randf()
		var mix: Array = _enraged_bullet_mix if _enemy._is_enraged else _bullet_mix
		if mix.size() >= 3:
			var cluster_p: float = float(mix[2])
			var parabolic_p: float = float(mix[1])
			if roll < cluster_p:
				variant = 2 # CLUSTER
			elif roll < (cluster_p + parabolic_p):
				variant = 1 # PARABOLIC
			else:
				variant = 0 # DIRECT
		else:
			if _enemy._is_enraged:
				# Enraged enemies favor complex ballistic artillery
				if roll < 0.35:
					variant = 2 # CLUSTER
				elif roll < 0.80:
					variant = 1 # PARABOLIC
				else:
					variant = 0 # DIRECT
			else:
				# Standard formation enemies
				if roll < 0.15:
					variant = 2 # CLUSTER
				elif roll < 0.50:
					variant = 1 # PARABOLIC
				else:
					variant = 0 # DIRECT

	bullet.set("plasma_variant", variant)

	match variant:
		0: # DIRECT
			bullet.set("ballistic_gravity", 0.0)
			bullet.set("gravity", 0.0)
			bullet.set("velocity", Vector2(0.0, bullet.get("speed") if "speed" in bullet else 350.0))
		1: # PARABOLIC
			bullet.set("ballistic_gravity", 380.0)
			bullet.set("gravity", 380.0)
			var target_pos: Vector2 = Vector2.ZERO
			var has_target: bool = false
			if _enemy.is_inside_tree():
				var player: Node2D = PlayerShip.first_alive_ship(_enemy.get_tree())
				if player != null and is_instance_valid(player):
					target_pos = player.global_position
					has_target = true
			if has_target:
				var spawn_pos: Vector2 = _enemy.global_position + Vector2(0, 20)
				var flight_time: float = randf_range(1.1, 1.5)
				var launch_vel: Vector2 = VectorMath.calculate_ballistic_launch_velocity(
					spawn_pos, target_pos, 380.0, flight_time
				)
				launch_vel.x = clampf(launch_vel.x, -220.0, 220.0)
				bullet.set("velocity", launch_vel)
				bullet.set("initial_velocity", launch_vel)
			else:
				var lateral_vx: float = randf_range(-140.0, 140.0)
				var launch_vel: Vector2 = Vector2(lateral_vx, randf_range(40.0, 100.0))
				bullet.set("velocity", launch_vel)
				bullet.set("initial_velocity", launch_vel)
		2: # CLUSTER
			bullet.set("ballistic_gravity", 320.0)
			bullet.set("gravity", 320.0)
			var lateral_vx: float = randf_range(-90.0, 90.0)
			var launch_vel: Vector2 = Vector2(lateral_vx, randf_range(80.0, 140.0))
			bullet.set("velocity", launch_vel)
			bullet.set("initial_velocity", launch_vel)
			bullet.set("cluster_fuse_time", randf_range(0.5, 0.65))
