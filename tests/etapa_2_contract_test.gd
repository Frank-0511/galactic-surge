# Contract harness for the Etapa 2 combat scenes.
extends SceneTree

func _init() -> void:
	var passed: bool = true
	passed = _assert_player_contract() and passed
	passed = _assert_scene("res://scenes/entities/enemy/enemy.tscn") and passed
	passed = _assert_scene("res://scenes/entities/enemy/enemy_bullet.tscn") and passed
	passed = _assert_collision_contract(
		"res://scenes/entities/bullet/bullet.tscn", 2, 4, "enemy_hit"
	) and passed
	passed = _assert_collision_contract(
		"res://scenes/entities/enemy/enemy_bullet.tscn", 8, 1, "player_hit"
	) and passed
	passed = _assert_enemy_contract() and passed
	passed = _assert_enemy_projectile_contract() and passed
	passed = _assert_enemy_spawner_contract() and passed
	passed = _assert_scene("res://scenes/systems/enemy_spawner.tscn") and passed
	passed = _assert_scene("res://scenes/ui/game_over.tscn") and passed
	quit(0 if passed else 1)


func _assert_player_contract() -> bool:
	var packed_scene: PackedScene = load("res://scenes/entities/player/player.tscn") as PackedScene
	if packed_scene == null:
		push_error("Missing scene: res://scenes/entities/player/player.tscn")
		return false
	var player: CharacterBody2D = packed_scene.instantiate() as CharacterBody2D
	if player == null:
		push_error("Player scene root must be CharacterBody2D")
		return false
	var passed: bool = true
	if player.collision_layer != 1 or player.collision_mask != 12:
		push_error("Player collision layer/mask must be 1/12")
		passed = false
	if not player.is_in_group("player"):
		push_error("Player must belong to the player group")
		passed = false
	if player.get_node_or_null("InvulnerabilityTimer") == null:
		push_error("Player missing InvulnerabilityTimer")
		passed = false
	if player.get_node_or_null("BlinkTimer") == null:
		push_error("Player missing BlinkTimer")
		passed = false
	for method_name: String in ["take_damage", "respawn", "set_gameplay_enabled"]:
		if not player.has_method(method_name):
			push_error("Player missing public method: %s" % method_name)
			passed = false
	player.free()
	return passed

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


func _assert_enemy_contract() -> bool:
	var packed_scene: PackedScene = load("res://scenes/entities/enemy/enemy.tscn") as PackedScene
	if packed_scene == null:
		push_error("Missing scene: res://scenes/entities/enemy/enemy.tscn")
		return false
	var enemy: Area2D = packed_scene.instantiate() as Area2D
	if enemy == null:
		push_error("Enemy scene root must be Area2D")
		return false
	var passed: bool = true
	if enemy.collision_layer != 4 or enemy.collision_mask != 3:
		push_error("Enemy collision layer/mask must be 4/3")
		passed = false
	if not enemy.is_in_group("enemies"):
		push_error("Enemy must belong to the enemies group")
		passed = false
	if not enemy.has_method("destroy"):
		push_error("Enemy missing public method: destroy")
		passed = false
	if not enemy.has_signal("destroyed"):
		push_error("Enemy missing signal: destroyed")
		passed = false
	if enemy.get_node_or_null("ShootCooldown") == null:
		push_error("Enemy missing ShootCooldown")
		passed = false
	enemy.free()
	return passed


func _assert_enemy_projectile_contract() -> bool:
	var enemy_source: String = FileAccess.get_file_as_string("res://scenes/entities/enemy/enemy.gd")
	var passed: bool = true
	if not enemy_source.contains("get_tree().current_scene.add_child(enemy_bullet)"):
		push_error("EnemyBullet must be added to the current scene")
		passed = false
	if not enemy_source.contains("enemy_bullet.global_position = global_position + Vector2(0, 20)"):
		push_error("EnemyBullet must use Enemy global position plus its spawn offset")
		passed = false
	return passed


func _assert_enemy_spawner_contract() -> bool:
	var packed_scene: PackedScene = load("res://scenes/systems/enemy_spawner.tscn") as PackedScene
	if packed_scene == null:
		push_error("Missing scene: res://scenes/systems/enemy_spawner.tscn")
		return false
	var spawner: Node2D = packed_scene.instantiate() as Node2D
	if spawner == null:
		push_error("EnemySpawner scene root must be Node2D")
		return false
	var passed: bool = true
	var expected_exports: Dictionary = {
		"rows": 3,
		"columns": 6,
		"horizontal_spacing": 72.0,
		"vertical_spacing": 64.0,
		"formation_speed": 80.0,
		"descent_distance": 32.0,
	}
	for property_name: String in expected_exports:
		if spawner.get(property_name) != expected_exports[property_name]:
			push_error("EnemySpawner %s has an unexpected default" % property_name)
			passed = false
	for method_name: String in ["spawn_formation", "stop"]:
		if not spawner.has_method(method_name):
			push_error("EnemySpawner missing public method: %s" % method_name)
			passed = false
	if not spawner.has_signal("enemy_contacted_player"):
		push_error("EnemySpawner missing signal: enemy_contacted_player")
		passed = false
	passed = _assert_formation_edge_contract() and passed
	spawner.spawn_formation()
	if _count_formation_enemies(spawner) != 18:
		push_error("EnemySpawner must create exactly 18 enemies")
		passed = false
	spawner.spawn_formation()
	if _count_formation_enemies(spawner) != 18:
		push_error("EnemySpawner must replace its formation with exactly 18 enemies")
		passed = false
	spawner.free()
	return passed


func _assert_formation_edge_contract() -> bool:
	var spawner_source: String = FileAccess.get_file_as_string("res://scenes/systems/enemy_spawner.gd")
	var passed: bool = true
	if not spawner_source.contains("const ENEMY_HALF_WIDTH: float = 18.0"):
		push_error("EnemySpawner must define the Enemy half-width as 18 px")
		passed = false
	if not spawner_source.contains("enemy.global_position.x - ENEMY_HALF_WIDTH"):
		push_error("EnemySpawner left viewport edge must include the Enemy half-width")
		passed = false
	if not spawner_source.contains("enemy.global_position.x + ENEMY_HALF_WIDTH"):
		push_error("EnemySpawner right viewport edge must include the Enemy half-width")
		passed = false
	return passed


func _count_formation_enemies(spawner: Node2D) -> int:
	var enemy_count: int = 0
	for child: Node in spawner.get_children():
		if child is Area2D and child.is_in_group("enemies"):
			enemy_count += 1
	return enemy_count
