# enemy_spawner_slots.gd
# Slot bookkeeping of the enemy formation: deterministic assignment of tactical variants to slot
# indices, the live position of each enemy (base slot plus formation shift), and the cubic Bézier
# fly-in path that brings each enemy from off-screen to its slot. Owned by EnemySpawner through _spawner.

extends RefCounted

const EnemyVariants: Script = preload("res://features/enemy/enemy_variants.gd")

var _spawner: Node2D


func _init(spawner: Node2D) -> void:
	_spawner = spawner


## Deterministically maps slot indices to variant ids. Each variant is spread
## across the formation with a fixed stride so wave layouts are reproducible.
func assign_variant_slots(variants: Dictionary, slot_count: int) -> Dictionary:
	var assigned: Dictionary = {}
	if slot_count <= 0:
		return assigned
	var order: int = 0
	for key: Variant in variants.keys():
		var id: StringName = StringName(String(key))
		if not EnemyVariants.has_variant(id) or id == EnemyVariants.STANDARD:
			continue
		var count: int = mini(int(variants[key]), slot_count - assigned.size())
		var stride: int = maxi(1, slot_count / maxi(count, 1))
		var cursor: int = (order * 5 + 2) % slot_count
		for _n: int in range(count):
			var guard: int = 0
			while assigned.has(cursor) and guard < slot_count:
				cursor = (cursor + 1) % slot_count
				guard += 1
			assigned[cursor] = id
			cursor = (cursor + stride) % slot_count
		order += 1
	return assigned


func get_enemy_slot_position(enemy: Area2D) -> Vector2:
	if _spawner._enemy_base_slots.has(enemy):
		return _spawner._enemy_base_slots[enemy] + _spawner._formation_shift
	return enemy.global_position


func generate_bezier_points(trajectory: String, slot_pos: Vector2, index: int, vp_rect: Rect2) -> Array[Vector2]:
	var p0: Vector2
	var p1: Vector2
	var p2: Vector2
	var p3: Vector2 = slot_pos

	var vp_w: float = vp_rect.size.x
	var vp_h: float = vp_rect.size.y
	var center_x: float = vp_rect.get_center().x

	match trajectory.to_lower():
		"swoop_left":
			p0 = Vector2(vp_rect.position.x - 100.0, vp_rect.position.y - 60.0)
			p1 = Vector2(vp_rect.position.x + vp_w * 0.25, vp_rect.position.y + vp_h * 0.45)
			p2 = Vector2(slot_pos.x - 80.0, slot_pos.y + 120.0)
		"swoop_right":
			p0 = Vector2(vp_rect.end.x + 100.0, vp_rect.position.y - 60.0)
			p1 = Vector2(vp_rect.end.x - vp_w * 0.25, vp_rect.position.y + vp_h * 0.45)
			p2 = Vector2(slot_pos.x + 80.0, slot_pos.y + 120.0)
		"pincer":
			if (index % 2) == 0:
				p0 = Vector2(vp_rect.position.x - 120.0, slot_pos.y + 40.0)
				p1 = Vector2(vp_rect.position.x + vp_w * 0.4, vp_rect.position.y + 80.0)
				p2 = Vector2(slot_pos.x - 60.0, slot_pos.y - 40.0)
			else:
				p0 = Vector2(vp_rect.end.x + 120.0, slot_pos.y + 40.0)
				p1 = Vector2(vp_rect.end.x - vp_w * 0.4, vp_rect.position.y + 80.0)
				p2 = Vector2(slot_pos.x + 60.0, slot_pos.y - 40.0)
		"cross_dive":
			if (index % 2) == 0:
				p0 = Vector2(vp_rect.position.x + vp_w * 0.1, vp_rect.position.y - 120.0)
				p1 = Vector2(vp_rect.end.x - 80.0, vp_rect.position.y + vp_h * 0.4)
				p2 = Vector2(slot_pos.x + 60.0, slot_pos.y + 90.0)
			else:
				p0 = Vector2(vp_rect.end.x - vp_w * 0.1, vp_rect.position.y - 120.0)
				p1 = Vector2(vp_rect.position.x + 80.0, vp_rect.position.y + vp_h * 0.4)
				p2 = Vector2(slot_pos.x - 60.0, slot_pos.y + 90.0)
		"center_loop":
			p0 = Vector2(center_x, vp_rect.position.y - 120.0)
			var side: float = -1.0 if slot_pos.x < center_x else 1.0
			p1 = Vector2(center_x + side * (vp_w * 0.2), vp_rect.position.y + vp_h * 0.45)
			p2 = Vector2(slot_pos.x + side * 40.0, slot_pos.y + 100.0)
		_:
			p0 = Vector2(slot_pos.x, vp_rect.position.y - 100.0)
			p1 = Vector2(slot_pos.x, vp_rect.position.y + 50.0)
			p2 = Vector2(slot_pos.x, slot_pos.y - 40.0)

	return [p0, p1, p2, p3]
