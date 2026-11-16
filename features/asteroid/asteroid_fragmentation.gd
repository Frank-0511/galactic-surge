# asteroid_fragmentation.gd
# Hierarchical split of one Asteroid: LARGE -> 2 MEDIUM, MEDIUM -> 2 SMALL, SMALL -> none.
# Spawns the child fragments next to the parent with divergent velocity and spin.
# Owned by Asteroid through _asteroid; state and exports stay on Asteroid.

extends RefCounted

var _asteroid: Asteroid


func _init(asteroid: Asteroid) -> void:
	_asteroid = asteroid


## Instantiates two child fragments with divergent angular velocity.
## LARGE -> 2 MEDIUM (±35° dispersion, ~1.3x speed).
## MEDIUM -> 2 SMALL (±40° dispersion, ~1.4x speed).
## SMALL -> [] (disintegrates without fragments).
func split() -> Array[Area2D]:
	var fragments: Array[Area2D] = []
	if _asteroid.asteroid_size == Asteroid.Size.SMALL:
		return fragments

	var next_size: Asteroid.Size = Asteroid.Size.MEDIUM if _asteroid.asteroid_size == Asteroid.Size.LARGE else Asteroid.Size.SMALL
	var dispersion_angle_deg: float = 35.0 if _asteroid.asteroid_size == Asteroid.Size.LARGE else 42.0
	var speed_multiplier: float = 1.30 if _asteroid.asteroid_size == Asteroid.Size.LARGE else 1.40

	var base_dir: Vector2 = _asteroid.linear_velocity.normalized()
	if base_dir.length_squared() < 0.1:
		base_dir = Vector2.DOWN
	var base_speed: float = maxf(_asteroid.linear_velocity.length() * speed_multiplier, 120.0)

	var angles: Array[float] = [-deg_to_rad(dispersion_angle_deg), deg_to_rad(dispersion_angle_deg)]
	var spins: Array[float] = [-2.2, 2.2]

	var asteroid_scene: PackedScene = load("res://features/asteroid/asteroid.tscn") as PackedScene
	if asteroid_scene == null:
		return fragments

	var parent_container: Node = _asteroid.get_parent()

	for i: int in range(2):
		var frag: Asteroid = asteroid_scene.instantiate() as Asteroid
		if frag == null:
			continue
		frag.set_size(next_size)

		var frag_dir: Vector2 = base_dir.rotated(angles[i])
		var offset_dist: float = Asteroid.SIZES[_asteroid.asteroid_size]["radius"] * 0.45
		frag.linear_velocity = frag_dir * base_speed
		frag.angular_velocity = spins[i]
		frag.rotation = _asteroid.rotation + angles[i]

		if parent_container != null:
			PhysicsSafe.add_child_safe(parent_container, frag)
		# Set after insertion: global_position outside the tree is treated as local,
		# which would offset the fragment by its parent's own position.
		PhysicsSafe.set_global_position_safe(frag, _asteroid.global_position + frag_dir * offset_dist)

		fragments.append(frag)
		_asteroid.fragment_spawned.emit(frag)

	return fragments
