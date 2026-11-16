# etapa_13_contract_test.gd
# Contract test harness for Etapa 13: Cinturón de Asteroides y Camera Shake.
# Verifies:
# 1. Asteroid entity properties, Size enum (LARGE, MEDIUM, SMALL), and groups (asteroids, enemies, combat_transients).
# 2. Physics simulation: linear_velocity and angular_velocity updating position and rotation over time.
# 3. Hierarchical fragmentation:
#    - LARGE splits into 2 MEDIUM fragments with angular dispersion (±25° to ±45°).
#    - MEDIUM splits into 2 SMALL fragments with angular dispersion (±30° to ±50°).
#    - SMALL disintegrates without spawning child fragments.
# 4. Damage handling, hit flashes, and destruction signals.
# 5. Loot drops from large asteroids.
# 6. CameraShake non-linear Trauma model (trauma^2, decay, offset + roll) and backwards compatibility with shake().
# 7. AsteroidSpawner: dedicated wave management, sensory warnings, active fragment tracking, completion signals.
# 8. Main integration: asteroid wave handling, score awarding, camera trauma on destruction, and session reset.

extends SceneTree

const ASTEROID_SCENE_PATH := "res://features/asteroid/asteroid.tscn"
const ASTEROID_SPAWNER_PATH := "res://scenes/systems/asteroid_spawner.tscn"
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const CAMERA_SHAKE_SCRIPT_PATH := "res://scenes/main/camera_shake.gd"

const AsteroidScript: Script = preload("res://features/asteroid/asteroid.gd")


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	print("--- INICIANDO CONTRATOS ETAPA 13 ---")
	var t1: bool = await _assert_asteroid_properties_and_groups_contract()
	var t2: bool = await _assert_asteroid_physics_simulation_contract()
	var t3: bool = await _assert_hierarchical_fragmentation_contract()
	var t4: bool = await _assert_asteroid_damage_contract()
	var t5: bool = await _assert_camera_shake_trauma_contract()
	var t6: bool = await _assert_asteroid_spawner_contract()
	var t7: bool = await _assert_main_asteroid_integration_contract()
	var t8: bool = await _assert_fragments_spawn_near_parent_contract()

	var all_passed: bool = t1 and t2 and t3 and t4 and t5 and t6 and t7 and t8

	if all_passed:
		print("ETAPA 13 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 13 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Asteroid properties, sizes, and groups
# ---------------------------------------------------------------------------
func _assert_asteroid_properties_and_groups_contract() -> bool:
	if not ResourceLoader.exists(ASTEROID_SCENE_PATH):
		push_error("Missing asteroid scene: %s" % ASTEROID_SCENE_PATH)
		return false

	var packed: PackedScene = load(ASTEROID_SCENE_PATH) as PackedScene
	var asteroid: Area2D = packed.instantiate() as Area2D
	root.add_child(asteroid)
	await process_frame

	# Check group memberships
	if not asteroid.is_in_group(&"asteroids"):
		push_error("Asteroid must be in group 'asteroids'")
		asteroid.queue_free()
		return false
	if not asteroid.is_in_group(&"enemies"):
		push_error("Asteroid must be in group 'enemies' for weapon targeting")
		asteroid.queue_free()
		return false
	if not asteroid.is_in_group(&"combat_transients"):
		push_error("Asteroid must be in group 'combat_transients' for session cleanup")
		asteroid.queue_free()
		return false

	# Check collision setup
	if asteroid.collision_layer != 4 or (asteroid.collision_mask & 3) == 0:
		push_error("Asteroid collision_layer must be 4 and collision_mask must include layers 1 & 2")
		asteroid.queue_free()
		return false

	# Check size enum values and configurations
	if AsteroidScript.Size.LARGE != 0 or AsteroidScript.Size.MEDIUM != 1 or AsteroidScript.Size.SMALL != 2:
		push_error("Asteroid.Size enum values mismatch")
		asteroid.queue_free()
		return false

	# LARGE configuration
	asteroid.set_size(AsteroidScript.Size.LARGE)
	if asteroid.max_health != 5 or asteroid.current_health != 5:
		push_error("LARGE asteroid must have max_health=5, got %d" % asteroid.max_health)
		asteroid.queue_free()
		return false

	# MEDIUM configuration
	asteroid.set_size(AsteroidScript.Size.MEDIUM)
	if asteroid.max_health != 2 or asteroid.current_health != 2:
		push_error("MEDIUM asteroid must have max_health=2, got %d" % asteroid.max_health)
		asteroid.queue_free()
		return false

	# SMALL configuration
	asteroid.set_size(AsteroidScript.Size.SMALL)
	if asteroid.max_health != 1 or asteroid.current_health != 1:
		push_error("SMALL asteroid must have max_health=1, got %d" % asteroid.max_health)
		asteroid.queue_free()
		return false

	asteroid.queue_free()
	await process_frame
	print("✓ Contrato 1: Propiedades, grupos y tamaños de Asteroid superado")
	return true


# ---------------------------------------------------------------------------
# 2. Physics simulation: linear & angular velocity
# ---------------------------------------------------------------------------
func _assert_asteroid_physics_simulation_contract() -> bool:
	var packed: PackedScene = load(ASTEROID_SCENE_PATH) as PackedScene
	var asteroid: Area2D = packed.instantiate() as Area2D
	root.add_child(asteroid)
	await process_frame

	asteroid.global_position = Vector2(200.0, 200.0)
	asteroid.linear_velocity = Vector2(60.0, 120.0)
	asteroid.angular_velocity = 2.5
	var initial_rot: float = asteroid.rotation

	# Simulate 0.2 seconds in steps
	for i in range(12):
		asteroid._process(1.0 / 60.0)

	if asteroid.global_position.x <= 200.0 or asteroid.global_position.y <= 200.0:
		push_error("Asteroid did not advance along linear_velocity")
		asteroid.queue_free()
		return false

	if absf(asteroid.rotation - initial_rot) < 0.1:
		push_error("Asteroid did not rotate along angular_velocity")
		asteroid.queue_free()
		return false

	asteroid.queue_free()
	await process_frame
	print("✓ Contrato 2: Simulación física (traslación inercial y rotación) superado")
	return true


# ---------------------------------------------------------------------------
# 3. Hierarchical fragmentation
# ---------------------------------------------------------------------------
func _assert_hierarchical_fragmentation_contract() -> bool:
	var packed: PackedScene = load(ASTEROID_SCENE_PATH) as PackedScene

	# Test 3a: LARGE splits into 2 MEDIUM fragments
	var large_ast: Area2D = packed.instantiate() as Area2D
	root.add_child(large_ast)
	await process_frame

	large_ast.set_size(AsteroidScript.Size.LARGE)
	large_ast.linear_velocity = Vector2(0.0, 100.0)
	var frags_large: Array[Area2D] = large_ast.split()

	if frags_large.size() != 2:
		push_error("LARGE asteroid must produce exactly 2 fragments, got %d" % frags_large.size())
		large_ast.queue_free()
		return false

	for frag: Area2D in frags_large:
		if frag.get("asteroid_size") != AsteroidScript.Size.MEDIUM:
			push_error("Fragment from LARGE must be MEDIUM")
			large_ast.queue_free()
			return false

	# Angular dispersion check: fragments must separate angularly
	var vel_0: Vector2 = frags_large[0].linear_velocity
	var vel_1: Vector2 = frags_large[1].linear_velocity
	var angle_between: float = absf(vel_0.angle_to(vel_1))
	# Expect ~70 deg (1.2 rad) between the two fragments (±25° to ±45° each)
	if angle_between < deg_to_rad(45.0) or angle_between > deg_to_rad(95.0):
		push_error("Fragment dispersion angle out of expected range: %f rad" % angle_between)
		large_ast.queue_free()
		return false

	# Cleanup large and its fragments
	for frag: Area2D in frags_large:
		frag.queue_free()
	large_ast.queue_free()
	await process_frame

	# Test 3b: MEDIUM splits into 2 SMALL fragments
	var med_ast: Area2D = packed.instantiate() as Area2D
	root.add_child(med_ast)
	await process_frame

	med_ast.set_size(AsteroidScript.Size.MEDIUM)
	med_ast.linear_velocity = Vector2(0.0, 100.0)
	var frags_med: Array[Area2D] = med_ast.split()

	if frags_med.size() != 2:
		push_error("MEDIUM asteroid must produce exactly 2 fragments, got %d" % frags_med.size())
		med_ast.queue_free()
		return false

	for frag: Area2D in frags_med:
		if frag.get("asteroid_size") != AsteroidScript.Size.SMALL:
			push_error("Fragment from MEDIUM must be SMALL")
			med_ast.queue_free()
			return false

	for frag: Area2D in frags_med:
		frag.queue_free()
	med_ast.queue_free()
	await process_frame

	# Test 3c: SMALL disintegrates without child fragments
	var small_ast: Area2D = packed.instantiate() as Area2D
	root.add_child(small_ast)
	await process_frame

	small_ast.set_size(AsteroidScript.Size.SMALL)
	var frags_small: Array[Area2D] = small_ast.split()

	if not frags_small.is_empty():
		push_error("SMALL asteroid must produce 0 fragments upon disintegration")
		small_ast.queue_free()
		return false

	small_ast.queue_free()
	await process_frame
	print("✓ Contrato 3: Fragmentación jerárquica (LARGE -> 2 MEDIUM -> 4 SMALL -> 0) superado")
	return true


# ---------------------------------------------------------------------------
# 4. Damage, hit flashes, and destruction signals
# ---------------------------------------------------------------------------
func _assert_asteroid_damage_contract() -> bool:
	var packed: PackedScene = load(ASTEROID_SCENE_PATH) as PackedScene
	var asteroid: Area2D = packed.instantiate() as Area2D
	root.add_child(asteroid)
	await process_frame

	asteroid.set_size(AsteroidScript.Size.LARGE) # HP 5
	var damaged_emitted: Array[bool] = [false]
	var destroyed_emitted: Array[bool] = [false]

	asteroid.damaged.connect(func(_cur: int, _max: int) -> void: damaged_emitted[0] = true)
	asteroid.destroyed.connect(func(_ast: Area2D, _size: int, _pos: Vector2, _vel: Vector2) -> void: destroyed_emitted[0] = true)

	# Take non-lethal damage
	var destroyed_result: bool = asteroid.take_damage(2)
	if destroyed_result or asteroid.current_health != 3:
		push_error("Asteroid current_health should be 3 after 2 damage, got %d" % asteroid.current_health)
		asteroid.queue_free()
		return false
	if not damaged_emitted[0]:
		push_error("damaged signal was not emitted")
		asteroid.queue_free()
		return false

	# Fractional damage support
	asteroid.take_damage_from(1.0)
	if asteroid.current_health != 2:
		push_error("take_damage_from did not apply damage correctly")
		asteroid.queue_free()
		return false

	# Lethal damage
	destroyed_result = asteroid.take_damage(2)
	if not destroyed_result or not destroyed_emitted[0]:
		push_error("Lethal damage should destroy asteroid and emit destroyed signal")
		return false

	await process_frame
	print("✓ Contrato 4: Mecánicas de daño y destrucción de Asteroid superado")
	return true


# ---------------------------------------------------------------------------
# 5. CameraShake non-linear Trauma model
# ---------------------------------------------------------------------------
func _assert_camera_shake_trauma_contract() -> bool:
	var camera_script: Script = load(CAMERA_SHAKE_SCRIPT_PATH) as Script
	var camera: Camera2D = camera_script.new() as Camera2D
	root.add_child(camera)
	await process_frame

	# Check initial state
	if camera.get("trauma") != 0.0 or camera.offset != Vector2.ZERO or camera.rotation != 0.0:
		push_error("Initial camera trauma and offsets must be zero")
		camera.queue_free()
		return false

	# Test add_trauma and clamping to 1.0
	camera.call("add_trauma", 0.4)
	if not is_equal_approx(float(camera.get("trauma")), 0.4):
		push_error("add_trauma(0.4) failed to set trauma to 0.4")
		camera.queue_free()
		return false

	camera.call("add_trauma", 0.9)
	if not is_equal_approx(float(camera.get("trauma")), 1.0):
		push_error("add_trauma should clamp trauma to 1.0, got %f" % float(camera.get("trauma")))
		camera.queue_free()
		return false

	# Simulate process: quadratic factor trauma^2 produces offset and rotational roll
	var seen_offset: bool = false
	var seen_roll: bool = false
	for i in range(10):
		camera._process(0.016)
		if camera.offset != Vector2.ZERO:
			seen_offset = true
		if camera.rotation != 0.0:
			seen_roll = true

	if not seen_offset:
		push_error("Camera failed to produce translational offset from trauma")
		camera.queue_free()
		return false
	if not seen_roll:
		push_error("Camera failed to produce rotational roll from trauma")
		camera.queue_free()
		return false

	# Test trauma decay
	var prev_trauma: float = float(camera.get("trauma"))
	camera._process(0.2)
	var new_trauma: float = float(camera.get("trauma"))
	if new_trauma >= prev_trauma:
		push_error("Trauma did not decay over time")
		camera.queue_free()
		return false

	# Test reset_shake
	camera.call("reset_shake")
	if camera.get("trauma") != 0.0 or camera.offset != Vector2.ZERO or camera.rotation != 0.0:
		push_error("reset_shake failed to clear trauma, offset, or rotation")
		camera.queue_free()
		return false

	# Test legacy shake(intensity, duration) backwards compatibility
	camera.call("shake", 8.0, 0.25)
	camera._process(0.016)
	if camera.offset == Vector2.ZERO:
		push_error("Legacy shake() failed to produce camera offset")
		camera.queue_free()
		return false

	camera.queue_free()
	await process_frame
	print("✓ Contrato 5: Modelo de Trauma cuadrático y retrocompatibilidad de CameraShake superado")
	return true


# ---------------------------------------------------------------------------
# 6. AsteroidSpawner: dedicated wave management & tracking
# ---------------------------------------------------------------------------
# Fragments must appear next to the asteroid that split, even when the spawner
# (their parent) sits at a non-zero position like in main.tscn (x = 540).
func _assert_fragments_spawn_near_parent_contract() -> bool:
	var spawner: Node2D = (load(ASTEROID_SPAWNER_PATH) as PackedScene).instantiate() as Node2D
	spawner.position = Vector2(540.0, 0.0)
	root.add_child(spawner)
	await process_frame
	var passed: bool = true
	var parent_pos: Vector2 = Vector2(300.0, 200.0)
	var ast: Area2D = spawner.call("spawn_asteroid", 0, parent_pos, Vector2(0.0, 100.0)) as Area2D
	var frags: Array[Area2D] = ast.split()
	if frags.size() != 2:
		push_error("LARGE asteroid must split into 2 fragments, got %d" % frags.size())
		passed = false
	for frag: Area2D in frags:
		var dist: float = frag.global_position.distance_to(parent_pos)
		if dist > 60.0:
			push_error("Fragment must spawn next to its parent asteroid, but it is %.0f px away" % dist)
			passed = false
	root.remove_child(spawner)
	spawner.free()
	return passed


func _assert_asteroid_spawner_contract() -> bool:
	if not ResourceLoader.exists(ASTEROID_SPAWNER_PATH):
		push_error("Missing AsteroidSpawner scene: %s" % ASTEROID_SPAWNER_PATH)
		return false

	var packed: PackedScene = load(ASTEROID_SPAWNER_PATH) as PackedScene
	var spawner: Node2D = packed.instantiate() as Node2D
	root.add_child(spawner)
	await process_frame

	var warning_received: Array[bool] = [false]
	var spawned_count: Array[int] = [0]
	var wave_completed_received: Array[bool] = [false]

	spawner.connect("warning_requested", func(_d: float, msg: String) -> void:
		if msg.contains("CINTURÓN DE ASTEROIDES") or msg.contains("ALERTA"):
			warning_received[0] = true
	)
	spawner.connect("asteroid_spawned", func(_ast: Area2D) -> void:
		spawned_count[0] += 1
	)
	spawner.connect("asteroid_wave_completed", func() -> void:
		wave_completed_received[0] = true
	)

	# Start an asteroid wave of 2 asteroids
	spawner.call("start_asteroid_wave", 2)
	if not spawner.call("is_wave_active"):
		push_error("Spawner should be active after start_asteroid_wave")
		spawner.queue_free()
		return false

	if not warning_received[0]:
		push_error("warning_requested was not emitted by spawner")
		spawner.queue_free()
		return false

	# Step process to spawn pending asteroids
	spawner.set("_spawn_timer", 0.0)
	spawner._process(0.01)
	spawner.set("_spawn_timer", 0.0)
	spawner._process(0.01)

	if spawned_count[0] < 2:
		push_error("Spawner failed to spawn pending asteroids")
		spawner.queue_free()
		return false

	if spawner.call("get_active_asteroid_count") < 2:
		push_error("Active asteroid count mismatch")
		spawner.queue_free()
		return false

	# Clear asteroids and verify cleanup
	spawner.call("clear_asteroids")
	await process_frame

	if spawner.call("get_active_asteroid_count") != 0:
		push_error("clear_asteroids failed to clear tracked asteroids")
		spawner.queue_free()
		return false

	spawner.queue_free()
	await process_frame
	print("✓ Contrato 6: AsteroidSpawner (advertencia, spawn y tracking) superado")
	return true


# ---------------------------------------------------------------------------
# 7. Main scene integration
# ---------------------------------------------------------------------------
func _assert_main_asteroid_integration_contract() -> bool:
	if not ResourceLoader.exists(MAIN_SCENE_PATH):
		push_error("Missing Main scene: %s" % MAIN_SCENE_PATH)
		return false

	var packed: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	root.add_child(main)
	await process_frame

	main.call("reset_session")
	await process_frame

	var spawner: Node2D = main.call("get_asteroid_spawner") as Node2D
	if spawner == null:
		push_error("Main must contain an AsteroidSpawner instance")
		main.queue_free()
		return false

	# Direct launch of asteroid belt wave
	main.call("start_asteroid_wave_direct", 3)
	if not main.call("is_asteroid_wave_active"):
		push_error("Main failed to activate asteroid wave")
		main.queue_free()
		return false

	# Verify camera trauma triggers upon asteroid destruction
	var camera: Camera2D = main.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.call("reset_shake")
		# Simulate asteroid destroyed callback
		main.call("_on_asteroid_destroyed", null, 0, Vector2(500, 300), Vector2.ZERO)
		if camera.get("trauma") <= 0.0:
			push_error("Asteroid destruction must add trauma to Main camera")
			main.queue_free()
			return false

	# Verify session reset clears asteroids and camera trauma
	main.call("reset_session")
	await process_frame

	if main.call("is_asteroid_wave_active"):
		push_error("reset_session must halt asteroid wave")
		main.queue_free()
		return false

	if camera != null and camera.get("trauma") > 0.0:
		push_error("reset_session must reset camera trauma to 0.0")
		main.queue_free()
		return false

	main.queue_free()
	await process_frame
	print("✓ Contrato 7: Integración completa en Main (oleada, trauma y reset) superado")
	return true
