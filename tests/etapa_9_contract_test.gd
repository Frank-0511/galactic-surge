# etapa_9_contract_test.gd
# Contract test harness for Etapa 9: Descensos Dinámicos y Escalada Temporal.
# Verifies:
# 1. Enemy states (FORMATION, FLY_IN, DIVING, RETURNING) and signals (dive_started, returned_to_formation).
# 2. Banking tilt rotation within ~15-20 deg (0.26 - 0.35 rad) during dive maneuver.
# 3. EnemySpawner dive triggering (1-on-1 and pairs) and decoupling from formation bounds/movement.
# 4. Return to formation logic, slot convergence, and formation_rejoined signal.
# 5. Enrage temporal countdown escalation, speed/fire-rate multiplier, and state sync.
# 6. Main scene integration and state reset on wave transition.

extends SceneTree

const ENEMY_PATH := "res://scenes/entities/enemy/enemy.tscn"
const SPAWNER_PATH := "res://scenes/systems/enemy_spawner.tscn"
const MAIN_PATH := "res://scenes/main/main.tscn"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var enemy_states_passed: bool = await _assert_enemy_states_and_signals_contract()
	var banking_tilt_passed: bool = await _assert_banking_tilt_contract()
	var spawner_dives_passed: bool = await _assert_spawner_dives_contract()
	var return_passed: bool = await _assert_return_to_formation_contract()
	var enrage_passed: bool = await _assert_enrage_escalation_contract()
	var main_integration_passed: bool = await _assert_main_enrage_integration_contract()

	var all_passed: bool = (
		enemy_states_passed
		and banking_tilt_passed
		and spawner_dives_passed
		and return_passed
		and enrage_passed
		and main_integration_passed
	)

	if all_passed:
		print("ETAPA 9 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 9 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Enemy States and Signals Contract
# ---------------------------------------------------------------------------

func _assert_enemy_states_and_signals_contract() -> bool:
	if not ResourceLoader.exists(ENEMY_PATH):
		push_error("Missing Enemy scene: %s" % ENEMY_PATH)
		return false

	var packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var enemy: Area2D = packed.instantiate() as Area2D
	root.add_child(enemy)
	await process_frame

	var passed: bool = true

	# Check signals
	if not enemy.has_signal(&"dive_started"):
		push_error("Enemy missing signal: dive_started")
		passed = false
	if not enemy.has_signal(&"returned_to_formation"):
		push_error("Enemy missing signal: returned_to_formation")
		passed = false

	# Initial state
	if not enemy.call("is_in_formation"):
		push_error("Enemy must be in FORMATION state by default")
		passed = false
	if enemy.call("is_diving"):
		push_error("Enemy is_diving must be false initially")
		passed = false
	if enemy.call("is_returning"):
		push_error("Enemy is_returning must be false initially")
		passed = false

	# Test dive_started signal and transition
	var dive_started_emitted: Array[bool] = [false]
	enemy.connect(&"dive_started", func() -> void: dive_started_emitted[0] = true)

	enemy.call("start_dive", Vector2(540.0, 850.0), 2.0, "swoop")
	if not dive_started_emitted[0]:
		push_error("Enemy must emit dive_started on start_dive")
		passed = false
	if not enemy.call("is_diving"):
		push_error("Enemy is_diving must be true after start_dive")
		passed = false
	if enemy.call("is_in_formation"):
		push_error("Enemy is_in_formation must be false while diving")
		passed = false

	# Test return_to_slot transition
	var dummy_getter: Callable = func() -> Vector2: return Vector2(300.0, 150.0)
	enemy.call("return_to_slot", dummy_getter, 1.5)
	if not enemy.call("is_returning"):
		push_error("Enemy is_returning must be true after return_to_slot")
		passed = false
	if enemy.call("is_diving"):
		push_error("Enemy is_diving must be false while returning")
		passed = false
	if enemy.call("is_in_formation"):
		push_error("Enemy is_in_formation must be false while returning")
		passed = false

	root.remove_child(enemy)
	enemy.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 2. Banking Tilt Contract (~15-20 deg / ~0.26 - 0.35 rad)
# ---------------------------------------------------------------------------

func _assert_banking_tilt_contract() -> bool:
	var packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var enemy: Area2D = packed.instantiate() as Area2D
	root.add_child(enemy)
	await process_frame

	var passed: bool = true

	# Position enemy on the left, swoop target far right
	enemy.global_position = Vector2(250.0, 120.0)
	enemy.call("start_dive", Vector2(750.0, 850.0), 2.0, "swoop")

	# Advance to peak of lateral turn (t ~ 0.25 to 0.40)
	enemy.call("_process", 0.5)

	var tilt: float = absf(enemy.rotation)
	var min_expected_rad: float = deg_to_rad(15.0) - 0.02 # ~0.24 rad tolerance
	var max_expected_rad: float = deg_to_rad(20.0) + 0.02 # ~0.37 rad tolerance

	if tilt < min_expected_rad or tilt > max_expected_rad:
		push_error("Enemy banking tilt was %f rad (%.1f deg); expected within 15-20 deg (0.26-0.35 rad)" % [tilt, rad_to_deg(tilt)])
		passed = false

	# Opposite direction dive
	enemy.global_position = Vector2(800.0, 120.0)
	enemy.call("start_dive", Vector2(200.0, 850.0), 2.0, "swoop")
	enemy.call("_process", 0.5)

	var tilt_opp: float = enemy.rotation
	if tilt_opp > 0.0:
		push_error("Enemy banking tilt must be negative when swooping leftwards, got %f" % tilt_opp)
		passed = false
	if absf(tilt_opp) < min_expected_rad or absf(tilt_opp) > max_expected_rad:
		push_error("Enemy leftward banking tilt was %f rad; expected within 15-20 deg" % absf(tilt_opp))
		passed = false

	root.remove_child(enemy)
	enemy.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 3. Spawner Dive Triggering and Decoupling Contract
# ---------------------------------------------------------------------------

func _assert_spawner_dives_contract() -> bool:
	if not ResourceLoader.exists(SPAWNER_PATH):
		push_error("Missing Spawner scene: %s" % SPAWNER_PATH)
		return false

	var packed: PackedScene = load(SPAWNER_PATH) as PackedScene
	var spawner: Node2D = packed.instantiate() as Node2D
	root.add_child(spawner)
	await process_frame

	var passed: bool = true

	# Check exports and signals
	if absf(float(spawner.get("enrage_time")) - 35.0) > 0.01:
		push_error("EnemySpawner enrage_time must default to 35.0, got %f" % float(spawner.get("enrage_time")))
		passed = false
	if not spawner.has_signal(&"enrage_triggered"):
		push_error("EnemySpawner missing signal: enrage_triggered")
		passed = false
	if not spawner.has_signal(&"enemy_dived"):
		push_error("EnemySpawner missing signal: enemy_dived")
		passed = false
	if not spawner.has_signal(&"formation_rejoined"):
		push_error("EnemySpawner missing signal: formation_rejoined")
		passed = false

	spawner.call("set_formation_layout", Vector2(540.0, 120.0), 120.0)
	spawner.set("fly_in_enabled", false)
	spawner.call("spawn_formation")

	# Test 1-on-1 dive trigger
	var attackers_1: Array[Area2D] = []
	var res_1: Variant = spawner.call("trigger_dive", 1)
	if res_1 is Array:
		for item: Variant in res_1:
			if item is Area2D:
				attackers_1.append(item as Area2D)

	if attackers_1.size() != 1:
		push_error("trigger_dive(1) must return exactly 1 attacker, got %d" % attackers_1.size())
		passed = false
	elif not attackers_1[0].call("is_diving"):
		push_error("Attacker 1 must have is_diving() == true")
		passed = false

	# Test 2-on-2 (pair) dive trigger
	var attackers_2: Array[Area2D] = []
	var res_2: Variant = spawner.call("trigger_dive", 2)
	if res_2 is Array:
		for item: Variant in res_2:
			if item is Area2D:
				attackers_2.append(item as Area2D)

	if attackers_2.size() != 2:
		push_error("trigger_dive(2) must return exactly 2 attackers, got %d" % attackers_2.size())
		passed = false
	else:
		if not attackers_2[0].call("is_diving") or not attackers_2[1].call("is_diving"):
			push_error("Both attackers in pair dive must have is_diving() == true")
			passed = false

	# Verify decoupling: diving enemy at extreme edge must NOT trigger formation bounce
	if not attackers_1.is_empty():
		var diving_enemy: Area2D = attackers_1[0]
		diving_enemy.global_position = Vector2(5.0, 900.0) # Far to the left

		# Find an enemy still in formation
		var in_formation_enemy: Area2D = null
		for child: Node in spawner.get_children():
			if child is Area2D and child.has_method(&"is_in_formation") and child.call("is_in_formation"):
				in_formation_enemy = child as Area2D
				break

		if in_formation_enemy != null:
			var initial_y: float = in_formation_enemy.position.y
			# Process frame for spawner
			spawner.call("_process", 0.016)
			# Formation should NOT have bounced downwards due to the diving enemy
			if absf(in_formation_enemy.position.y - initial_y) > 0.001:
				push_error("Formation must not bounce downwards because of a diving enemy's position")
				passed = false

	spawner.call("clear_formation")
	root.remove_child(spawner)
	spawner.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 4. Return to Formation Contract
# ---------------------------------------------------------------------------

func _assert_return_to_formation_contract() -> bool:
	var packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var enemy: Area2D = packed.instantiate() as Area2D
	root.add_child(enemy)
	await process_frame

	var passed: bool = true

	var target_slot: Vector2 = Vector2(420.0, 180.0)
	var slot_getter: Callable = func() -> Vector2: return target_slot

	enemy.global_position = Vector2(420.0, -30.0)
	enemy.call("return_to_slot", slot_getter, 1.0)

	var rejoined_emitted: Array[bool] = [false]
	enemy.connect(&"returned_to_formation", func() -> void: rejoined_emitted[0] = true)

	if not enemy.call("is_returning"):
		push_error("Enemy is_returning must be true after return_to_slot")
		passed = false

	# Fast forward return duration
	enemy.call("_process", 1.05)

	if not rejoined_emitted[0]:
		push_error("Enemy must emit returned_to_formation when return duration finishes")
		passed = false
	if not enemy.call("is_in_formation"):
		push_error("Enemy is_in_formation must be true after returning")
		passed = false
	if enemy.call("is_returning"):
		push_error("Enemy is_returning must be false after returning")
		passed = false
	if not enemy.global_position.is_equal_approx(target_slot):
		push_error("Enemy global_position must match target slot after returning, got %s" % enemy.global_position)
		passed = false
	if absf(enemy.rotation) > 0.001:
		push_error("Enemy rotation must reset to 0.0 after returning, got %f" % enemy.rotation)
		passed = false

	root.remove_child(enemy)
	enemy.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 5. Enrage Escalation Contract
# ---------------------------------------------------------------------------

func _assert_enrage_escalation_contract() -> bool:
	var packed: PackedScene = load(SPAWNER_PATH) as PackedScene
	var spawner: Node2D = packed.instantiate() as Node2D
	root.add_child(spawner)
	await process_frame

	var passed: bool = true

	spawner.set("fly_in_enabled", false)
	spawner.set("enrage_time", 5.0)
	spawner.call("spawn_formation")

	var enrage_signal_emitted: Array[bool] = [false]
	spawner.connect(&"enrage_triggered", func() -> void: enrage_signal_emitted[0] = true)

	if spawner.call("is_enraged"):
		push_error("Spawner is_enraged must be false initially")
		passed = false

	var initial_speed: float = float(spawner.get("formation_speed"))

	# Fast forward past enrage threshold
	spawner.call("_process", 6.0)

	if not enrage_signal_emitted[0]:
		push_error("EnemySpawner must emit enrage_triggered when wave time exceeds enrage_time")
		passed = false
	if not spawner.call("is_enraged"):
		push_error("Spawner is_enraged must be true after threshold")
		passed = false

	var enraged_speed: float = float(spawner.get("formation_speed"))
	if enraged_speed <= initial_speed:
		push_error("Spawner formation_speed must increase when enraged (got %f, was %f)" % [enraged_speed, initial_speed])
		passed = false

	# Verify member enemies are enraged and have accelerated fire cooldowns
	for child: Node in spawner.get_children():
		if child is Area2D and child.has_method(&"is_enraged"):
			if not child.call("is_enraged"):
				push_error("All living enemies must have is_enraged() == true after spawner enrages")
				passed = false
				break

	spawner.call("clear_formation")
	root.remove_child(spawner)
	spawner.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 6. Main Enrage Integration Contract
# ---------------------------------------------------------------------------

func _assert_main_enrage_integration_contract() -> bool:
	if not ResourceLoader.exists(MAIN_PATH):
		push_error("Missing Main scene: %s" % MAIN_PATH)
		return false

	var packed: PackedScene = load(MAIN_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	root.add_child(main)
	await process_frame

	var passed: bool = true

	main.call("start_session")

	var spawner: Node2D = main.get_node_or_null("EnemySpawner") as Node2D
	if spawner == null:
		push_error("Main scene missing EnemySpawner")
		passed = false
	else:
		# Fast-forward past fly-in
		for child: Node in spawner.get_children():
			if child.has_method("_process"):
				child.call("_process", 5.0)

		# Trigger enrage
		spawner.set("enrage_time", 2.0)
		spawner.call("_process", 3.0)

		if not spawner.call("is_enraged"):
			push_error("Main EnemySpawner should be enraged")
			passed = false

		# Simulate wave cleared and next wave
		main.call("_on_wave_cleared", 0)
		await process_frame

		# Wave announcement completes -> starts next wave
		main.call("_on_wave_announcement_finished")
		await process_frame

		# Next wave should reset enraged state
		if spawner.call("is_enraged"):
			push_error("Next wave must reset is_enraged to false")
			passed = false

	main.call("return_to_main_menu")
	root.remove_child(main)
	main.queue_free()
	return passed
