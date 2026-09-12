# Contract harness for the Etapa 2 combat scenes.
extends SceneTree

func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
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
	passed = _assert_game_over_contract() and passed
	passed = _assert_main_session_contract() and passed
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


func _assert_game_over_contract() -> bool:
	var packed_scene: PackedScene = load("res://scenes/ui/game_over.tscn") as PackedScene
	if packed_scene == null:
		push_error("Missing scene: res://scenes/ui/game_over.tscn")
		return false
	var game_over: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if game_over == null:
		push_error("GameOver scene root must be CanvasLayer")
		return false
	var passed: bool = true
	if game_over.visible:
		push_error("GameOver must start hidden")
		passed = false
	if game_over.get_node_or_null("Control/RetryButton") == null:
		push_error("GameOver missing Control/RetryButton")
		passed = false
	if not game_over.has_signal("retry_requested"):
		push_error("GameOver missing signal: retry_requested")
		passed = false
	var retry_state: Dictionary = {"emitted": false}
	game_over.retry_requested.connect(func() -> void: retry_state["emitted"] = true)
	game_over.call("_on_retry_button_pressed")
	if not retry_state["emitted"]:
		push_error("GameOver must emit retry_requested when RetryButton is pressed")
		passed = false
	game_over.free()
	return passed


func _assert_main_session_contract() -> bool:
	var main_source: String = FileAccess.get_file_as_string("res://scenes/main/main.gd")
	var packed_scene: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("Missing scene: res://scenes/main/main.tscn")
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	if main == null:
		push_error("Main scene root must be Node2D")
		return false
	root.add_child(main)
	var passed: bool = true
	if main.get_node_or_null("EnemySpawner") == null:
		push_error("Main missing EnemySpawner child")
		passed = false
	if main.get_node_or_null("GameOver") == null:
		push_error("Main missing GameOver child")
		passed = false
	passed = _assert_initial_formation_viewport(main) and passed
	if not main_source.contains("const STARTING_LIVES: int = 3"):
		push_error("Main must declare STARTING_LIVES as 3")
		passed = false
	# Player must spawn at the GameLayout position, not at the historical 600x800 origin.
	main.call("start_session")
	var layout: GameLayout = GameLayout.new()
	layout.configure(main.get_viewport().get_visible_rect().size)
	var expected_spawn: Vector2 = layout.get_player_spawn_position()
	var player: Node2D = main.get_node_or_null("Player") as Node2D
	if player != null and player.global_position != expected_spawn:
		push_error("Player must spawn at the GameLayout position %s, got %s" % [expected_spawn, player.global_position])
		passed = false
	# Player horizontal center must match the viewport center, not the historical 300.
	if player != null and not is_equal_approx(player.global_position.x, main.get_viewport().get_visible_rect().get_center().x):
		push_error("Main must apply GameLayout before starting the session, player x=%f" % player.global_position.x)
		passed = false
	root.remove_child(main)
	main.free()
	return passed


func _assert_initial_formation_viewport(main: Node2D) -> bool:
	var spawner: Node2D = main.get_node_or_null("EnemySpawner") as Node2D
	if spawner == null:
		return false
	# Derive formation geometry from the viewport via GameLayout.
	var layout: GameLayout = GameLayout.new()
	layout.configure(main.get_viewport().get_visible_rect().size)
	var formation_origin: Vector2 = layout.get_enemy_formation_origin()
	if spawner.has_method("set_formation_layout"):
		spawner.call("set_formation_layout", formation_origin, formation_origin.y)
	if "fly_in_enabled" in spawner:
		spawner.set("fly_in_enabled", false)
	spawner.spawn_formation()
	var enemies: Array[Area2D] = _get_formation_enemies(spawner)
	if enemies.size() != 18:
		push_error("Main must start with exactly 18 formation enemies")
		return false
	var min_center_x: float = enemies[0].global_position.x
	var max_center_x: float = min_center_x
	var left_edge: float = enemies[0].global_position.x - 18.0
	var right_edge: float = enemies[0].global_position.x + 18.0
	for enemy: Area2D in enemies:
		min_center_x = minf(min_center_x, enemy.global_position.x)
		max_center_x = maxf(max_center_x, enemy.global_position.x)
		left_edge = minf(left_edge, enemy.global_position.x - 18.0)
		right_edge = maxf(right_edge, enemy.global_position.x + 18.0)
	var passed: bool = true
	var viewport_width: float = main.get_viewport().get_visible_rect().size.x
	if left_edge < 0.0:
		push_error("Initial formation left edge must be inside the viewport")
		passed = false
	if right_edge > viewport_width:
		push_error("Initial formation right edge must be inside the viewport")
		passed = false
	var expected_center: float = formation_origin.x
	if absf((left_edge + right_edge) / 2.0 - expected_center) > 0.01:
		push_error("Initial formation center must be near x=%f" % expected_center)
		passed = false
	var expected_leftmost: float = expected_center - (6 - 1) / 2.0 * 72.0
	var expected_rightmost: float = expected_center + (6 - 1) / 2.0 * 72.0
	if absf(min_center_x - expected_leftmost) > 0.01:
		push_error("Initial formation leftmost center must be x=%f" % expected_leftmost)
		passed = false
	if absf(max_center_x - expected_rightmost) > 0.01:
		push_error("Initial formation rightmost center must be x=%f" % expected_rightmost)
		passed = false
	var expected_left_edge: float = expected_leftmost - 18.0
	var expected_right_edge: float = expected_rightmost + 18.0
	if absf(left_edge - expected_left_edge) > 0.01 or absf(right_edge - expected_right_edge) > 0.01:
		push_error("Initial formation edges must be x=%f and x=%f" % [expected_left_edge, expected_right_edge])
		passed = false
	for row: int in 3:
		for column: int in range(1, 6):
			var enemy_index: int = row * 6 + column
			var previous_enemy: Area2D = enemies[enemy_index - 1]
			var current_enemy: Area2D = enemies[enemy_index]
			if absf(current_enemy.global_position.x - previous_enemy.global_position.x - 72.0) > 0.01:
				push_error("Formation enemies must keep 72 px horizontal spacing per row")
				passed = false
	var initial_positions: Array[Vector2] = []
	for enemy: Area2D in enemies:
		initial_positions.append(enemy.global_position)
	spawner._process(0.016)
	for enemy_index: int in enemies.size():
		var enemy: Area2D = enemies[enemy_index]
		var initial_position: Vector2 = initial_positions[enemy_index]
		if absf(enemy.global_position.y - initial_position.y) > 0.01:
			push_error("Initial formation frame must not descend")
			passed = false
		if absf(enemy.global_position.x - initial_position.x - 1.28) > 0.01:
			push_error("Initial formation frame must advance every enemy 1.28 px horizontally")
			passed = false
	return passed


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
	return _get_formation_enemies(spawner).size()


func _get_formation_enemies(spawner: Node2D) -> Array[Area2D]:
	var enemies: Array[Area2D] = []
	for child: Node in spawner.get_children():
		if child is Area2D and child.is_in_group("enemies"):
			enemies.append(child as Area2D)
	return enemies
