# Contract harness for the Etapa 2 combat scenes.
extends SceneTree

func _init() -> void:
	var passed: bool = true
	passed = _assert_scene("res://scenes/entities/enemy/enemy.tscn") and passed
	passed = _assert_scene("res://scenes/entities/enemy/enemy_bullet.tscn") and passed
	passed = _assert_collision_contract(
		"res://scenes/entities/bullet/bullet.tscn", 2, 4, "enemy_hit"
	) and passed
	passed = _assert_collision_contract(
		"res://scenes/entities/enemy/enemy_bullet.tscn", 8, 1, "player_hit"
	) and passed
	passed = _assert_scene("res://scenes/systems/enemy_spawner.tscn") and passed
	passed = _assert_scene("res://scenes/ui/game_over.tscn") and passed
	quit(0 if passed else 1)

func _assert_scene(path: String) -> bool:
	if load(path) == null:
		push_error("Missing scene: %s" % path)
		return false
	return true


func _assert_collision_contract(
	path: String, expected_layer: int, expected_mask: int, expected_signal: String
) -> bool:
	var packed_scene: PackedScene = load(path) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % path)
		return false
	var projectile: Area2D = packed_scene.instantiate() as Area2D
	if projectile == null:
		push_error("Scene root must be Area2D: %s" % path)
		return false
	var passed: bool = true
	if projectile.collision_layer != expected_layer:
		push_error("Unexpected collision layer for %s" % path)
		passed = false
	if projectile.collision_mask != expected_mask:
		push_error("Unexpected collision mask for %s" % path)
		passed = false
	if not projectile.has_signal(expected_signal):
		push_error("Missing signal %s for %s" % [expected_signal, path])
		passed = false
	projectile.free()
	return passed
