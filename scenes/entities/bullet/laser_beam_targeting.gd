# laser_beam_targeting.gd
# Target selection for the continuous beam: the closest live enemy inside the beam corridor and
# ahead of the emitter. Owned by LaserBeam through _beam; beam width, corridor and state stay on LaserBeam.

extends RefCounted

var _beam: Area2D


func _init(beam: Area2D) -> void:
	_beam = beam


## Returns the closest live enemy the beam can reach, or null when none is inside the corridor.
func find_closest_enemy_in_path() -> Area2D:
	if not _beam.is_inside_tree():
		return null

	var enemies: Array[Node] = _beam.get_tree().get_nodes_in_group(&"enemies")
	var closest_enemy: Area2D = null
	var min_distance: float = INF

	for node: Node in enemies:
		if not is_instance_valid(node) or not (node is Area2D):
			continue
		var enemy: Area2D = node as Area2D
		if not enemy.is_inside_tree() or enemy.is_queued_for_deletion():
			continue
		if (enemy.get("_destroyed") == true):
			continue

		# Must be ahead of or at the laser emitter (with a slight 10px margin)
		if enemy.global_position.y > _beam.global_position.y + 10.0:
			continue

		var enemy_half_w: float = get_enemy_half_width(enemy)
		var half_beam: float = maxf(_beam.beam_width, _beam.min_hit_corridor) * 0.5
		if absf(enemy.global_position.x - _beam.global_position.x) > (half_beam + enemy_half_w):
			continue

		var dist: float = _beam.global_position.y - enemy.global_position.y
		if dist < min_distance:
			min_distance = dist
			closest_enemy = enemy

	return closest_enemy


## Half the horizontal size of the enemy's first collision shape, scaled; 24 px when it has none.
func get_enemy_half_width(enemy: Area2D) -> float:
	var scale_factor: float = absf(enemy.scale.x)
	if scale_factor < 0.001:
		scale_factor = 1.0

	for child: Node in enemy.get_children():
		if child is CollisionShape2D:
			var cs: CollisionShape2D = child as CollisionShape2D
			if cs.shape != null:
				if cs.shape is RectangleShape2D:
					return (cs.shape as RectangleShape2D).size.x * 0.5 * scale_factor
				elif cs.shape is CircleShape2D:
					return (cs.shape as CircleShape2D).radius * scale_factor
				elif cs.shape is CapsuleShape2D:
					return (cs.shape as CapsuleShape2D).radius * scale_factor

	return 24.0
