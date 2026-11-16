# Contract harness for Etapa 8: Formaciones y Fly-In Bézier.
# Verifies:
# 1. VectorMath: cubic & quadratic Bézier, derivative, tangent angle, sampling.
# 2. FormationPatterns: enum types, string parser, slot calculation (GRID, V_SHAPE, ARC, DIAGONAL).
# 3. Enemy: fly-in execution, trajectory following, banking tilt, fly_in_completed signal, cancel.
# 4. EnemySpawner: 5-wave configurations with trajectories and patterns, fly-in tracking, fly_in_completed_all signal.
# 5. Starfield: speed multiplier, trigger_warp_boost tween acceleration.
# 6. Main integration: warp boost triggered on wave clear.
extends SceneTree

const ENEMY_PATH := "res://scenes/entities/enemy/enemy.tscn"
const SPAWNER_PATH := "res://scenes/systems/enemy_spawner.tscn"
const STARFIELD_PATH := "res://features/background/starfield.tscn"
const MAIN_PATH := "res://scenes/main/main.tscn"

const VectorMath: Script = preload("res://core/math/vector_math.gd")
const FormationPatterns: Script = preload("res://scripts/systems/formation_patterns.gd")


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var vmath_passed: bool = _assert_vector_math_contract()
	var patterns_passed: bool = _assert_formation_patterns_contract()
	var enemy_passed: bool = await _assert_enemy_fly_in_contract()
	var spawner_passed: bool = await _assert_spawner_contract()
	var starfield_passed: bool = await _assert_starfield_warp_contract()
	var main_passed: bool = await _assert_main_warp_integration_contract()
	var bounds_passed: bool = await _assert_main_formation_bounds_contract()

	var all_passed: bool = (
		vmath_passed
		and patterns_passed
		and enemy_passed
		and spawner_passed
		and starfield_passed
		and main_passed
		and bounds_passed
	)

	if all_passed:
		print("ETAPA 8 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 8 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. VectorMath Contract
# ---------------------------------------------------------------------------

func _assert_vector_math_contract() -> bool:
	var passed: bool = true

	# Cubic Bézier endpoints and midpoint
	var p0: Vector2 = Vector2(0.0, 0.0)
	var p1: Vector2 = Vector2(0.0, 100.0)
	var p2: Vector2 = Vector2(100.0, 100.0)
	var p3: Vector2 = Vector2(100.0, 0.0)

	var at_0: Vector2 = VectorMath.cubic_bezier(p0, p1, p2, p3, 0.0)
	if not at_0.is_equal_approx(p0):
		push_error("cubic_bezier at t=0.0 must equal p0, got %s" % at_0)
		passed = false

	var at_1: Vector2 = VectorMath.cubic_bezier(p0, p1, p2, p3, 1.0)
	if not at_1.is_equal_approx(p3):
		push_error("cubic_bezier at t=1.0 must equal p3, got %s" % at_1)
		passed = false

	var at_mid: Vector2 = VectorMath.cubic_bezier(p0, p1, p2, p3, 0.5)
	var expected_mid: Vector2 = Vector2(50.0, 75.0)
	if not at_mid.is_equal_approx(expected_mid):
		push_error("cubic_bezier at t=0.5 must equal (50, 75), got %s" % at_mid)
		passed = false

	# Clamping test
	var at_neg: Vector2 = VectorMath.cubic_bezier(p0, p1, p2, p3, -0.5)
	if not at_neg.is_equal_approx(p0):
		push_error("cubic_bezier at t=-0.5 must clamp to p0")
		passed = false

	var at_over: Vector2 = VectorMath.cubic_bezier(p0, p1, p2, p3, 1.5)
	if not at_over.is_equal_approx(p3):
		push_error("cubic_bezier at t=1.5 must clamp to p3")
		passed = false

	# Quadratic Bézier
	var q0: Vector2 = Vector2(0.0, 0.0)
	var q1: Vector2 = Vector2(50.0, 100.0)
	var q2: Vector2 = Vector2(100.0, 0.0)

	var q_at_0: Vector2 = VectorMath.quadratic_bezier(q0, q1, q2, 0.0)
	if not q_at_0.is_equal_approx(q0):
		push_error("quadratic_bezier at t=0.0 must equal q0")
		passed = false

	var q_at_1: Vector2 = VectorMath.quadratic_bezier(q0, q1, q2, 1.0)
	if not q_at_1.is_equal_approx(q2):
		push_error("quadratic_bezier at t=1.0 must equal q2")
		passed = false

	var q_at_mid: Vector2 = VectorMath.quadratic_bezier(q0, q1, q2, 0.5)
	var q_expected_mid: Vector2 = Vector2(50.0, 50.0)
	if not q_at_mid.is_equal_approx(q_expected_mid):
		push_error("quadratic_bezier at t=0.5 must equal (50, 50), got %s" % q_at_mid)
		passed = false

	# Cubic derivative
	var d_at_0: Vector2 = VectorMath.cubic_bezier_derivative(p0, p1, p2, p3, 0.0)
	var expected_d0: Vector2 = 3.0 * (p1 - p0)
	if not d_at_0.is_equal_approx(expected_d0):
		push_error("cubic_bezier_derivative at t=0.0 must equal 3*(p1-p0)")
		passed = false

	var d_at_1: Vector2 = VectorMath.cubic_bezier_derivative(p0, p1, p2, p3, 1.0)
	var expected_d1: Vector2 = 3.0 * (p3 - p2)
	if not d_at_1.is_equal_approx(expected_d1):
		push_error("cubic_bezier_derivative at t=1.0 must equal 3*(p3-p2)")
		passed = false

	# Tangent angle
	var angle_0: float = VectorMath.get_tangent_angle(p0, p1, p2, p3, 0.0)
	if absf(angle_0 - expected_d0.angle()) > 0.001:
		push_error("get_tangent_angle at t=0.0 must match derivative angle")
		passed = false

	# Sampling
	var sampled: PackedVector2Array = VectorMath.sample_cubic_path(p0, p1, p2, p3, 10)
	if sampled.size() != 11:
		push_error("sample_cubic_path with 10 segments must yield 11 points")
		passed = false
	elif not sampled[0].is_equal_approx(p0) or not sampled[10].is_equal_approx(p3):
		push_error("sample_cubic_path endpoints must match p0 and p3")
		passed = false

	return passed


# ---------------------------------------------------------------------------
# 2. FormationPatterns Contract
# ---------------------------------------------------------------------------

func _assert_formation_patterns_contract() -> bool:
	var passed: bool = true

	# String parsing
	if FormationPatterns.pattern_from_string("grid") != FormationPatterns.PatternType.GRID:
		push_error("pattern_from_string('grid') failed")
		passed = false
	if FormationPatterns.pattern_from_string("v_shape") != FormationPatterns.PatternType.V_SHAPE:
		push_error("pattern_from_string('v_shape') failed")
		passed = false
	if FormationPatterns.pattern_from_string("arc") != FormationPatterns.PatternType.ARC:
		push_error("pattern_from_string('arc') failed")
		passed = false
	if FormationPatterns.pattern_from_string("diagonal") != FormationPatterns.PatternType.DIAGONAL:
		push_error("pattern_from_string('diagonal') failed")
		passed = false

	var origin: Vector2 = Vector2(540.0, 120.0)
	var rows: int = 3
	var cols: int = 6
	var h_spacing: float = 72.0
	var v_spacing: float = 64.0

	# Test slot counts
	for p_type: int in [
		FormationPatterns.PatternType.GRID,
		FormationPatterns.PatternType.V_SHAPE,
		FormationPatterns.PatternType.ARC,
		FormationPatterns.PatternType.DIAGONAL,
	]:
		var slots: Array[Vector2] = FormationPatterns.calculate_slots(p_type, rows, cols, h_spacing, v_spacing, origin)
		if slots.size() != 18:
			push_error("calculate_slots must return 18 slots for 3x6 pattern %d" % p_type)
			passed = false

	# Test GRID geometry
	var grid_slots: Array[Vector2] = FormationPatterns.calculate_slots(
		FormationPatterns.PatternType.GRID, rows, cols, h_spacing, v_spacing, origin
	)
	var expected_col0_x: float = origin.x - (cols - 1) / 2.0 * h_spacing
	if absf(grid_slots[0].x - expected_col0_x) > 0.01:
		push_error("GRID slot (0,0) x expected %f, got %f" % [expected_col0_x, grid_slots[0].x])
		passed = false
	if absf(grid_slots[1].x - grid_slots[0].x - h_spacing) > 0.01:
		push_error("GRID slots must maintain h_spacing horizontally")
		passed = false
	if absf(grid_slots[cols].y - grid_slots[0].y - v_spacing) > 0.01:
		push_error("GRID rows must maintain v_spacing vertically")
		passed = false

	# Test V_SHAPE symmetry and chevron depth
	var v_slots: Array[Vector2] = FormationPatterns.calculate_slots(
		FormationPatterns.PatternType.V_SHAPE, rows, cols, h_spacing, v_spacing, origin
	)
	# For row 0: col 0 and col 5 must have equal Y; col 1 and col 4 must have equal Y
	if absf(v_slots[0].y - v_slots[5].y) > 0.01:
		push_error("V_SHAPE must be horizontally symmetric (col 0 vs col 5)")
		passed = false
	if absf(v_slots[1].y - v_slots[4].y) > 0.01:
		push_error("V_SHAPE must be horizontally symmetric (col 1 vs col 4)")
		passed = false
	# Center (cols 2 and 3) must be higher (lower Y) than flanks (col 0 and 5)
	if v_slots[2].y >= v_slots[0].y or v_slots[3].y >= v_slots[5].y:
		push_error("V_SHAPE center must advance forward relative to flanks")
		passed = false

	# Test ARC curvature and symmetry
	var arc_slots: Array[Vector2] = FormationPatterns.calculate_slots(
		FormationPatterns.PatternType.ARC, rows, cols, h_spacing, v_spacing, origin
	)
	if absf(arc_slots[0].y - arc_slots[5].y) > 0.01:
		push_error("ARC must be horizontally symmetric (col 0 vs col 5)")
		passed = false
	if absf(arc_slots[1].y - arc_slots[4].y) > 0.01:
		push_error("ARC must be horizontally symmetric (col 1 vs col 4)")
		passed = false
	if arc_slots[2].y >= arc_slots[0].y:
		push_error("ARC apex must lead ahead of flanks")
		passed = false

	# Test DIAGONAL monotonic stepped progression
	var diag_slots: Array[Vector2] = FormationPatterns.calculate_slots(
		FormationPatterns.PatternType.DIAGONAL, rows, cols, h_spacing, v_spacing, origin
	)
	for c: int in range(cols - 1):
		if diag_slots[c].y >= diag_slots[c + 1].y:
			push_error("DIAGONAL row 0 slots must strictly increase in Y across columns")
			passed = false

	return passed


# ---------------------------------------------------------------------------
# 3. Enemy Fly-In Contract
# ---------------------------------------------------------------------------

func _assert_enemy_fly_in_contract() -> bool:
	if not ResourceLoader.exists(ENEMY_PATH):
		push_error("Missing Enemy scene: %s" % ENEMY_PATH)
		return false

	var packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var enemy: Area2D = packed.instantiate() as Area2D
	root.add_child(enemy)
	await process_frame
	var passed: bool = true

	# Check signals & methods
	if not enemy.has_signal(&"fly_in_completed"):
		push_error("Enemy missing signal: fly_in_completed")
		passed = false
	for m: StringName in [&"start_fly_in", &"is_flying_in", &"cancel_fly_in"]:
		if not enemy.has_method(m):
			push_error("Enemy missing method: %s" % m)
			passed = false

	if enemy.call("is_flying_in"):
		push_error("Enemy must not be flying in by default")
		passed = false

	# Start fly in
	var p0: Vector2 = Vector2(-100.0, -100.0)
	var p1: Vector2 = Vector2(200.0, 400.0)
	var p2: Vector2 = Vector2(400.0, 500.0)
	var p3: Vector2 = Vector2(500.0, 200.0)

	var completed_emitted: Array[bool] = [false]
	enemy.connect(&"fly_in_completed", func() -> void: completed_emitted[0] = true)

	enemy.call("start_fly_in", p0, p1, p2, p3, 1.0, 0.0)
	if not enemy.call("is_flying_in"):
		push_error("Enemy is_flying_in() must return true after start_fly_in")
		passed = false
	if not enemy.global_position.is_equal_approx(p0):
		push_error("Enemy global_position must be p0 immediately after start_fly_in")
		passed = false

	# Halfway process
	enemy.call("_process", 0.5)
	if not enemy.call("is_flying_in"):
		push_error("Enemy should still be flying in at t=0.5")
		passed = false
	var expected_pos: Vector2 = VectorMath.cubic_bezier(p0, p1, p2, p3, 0.5)
	if not enemy.global_position.is_equal_approx(expected_pos):
		push_error("Enemy global_position at t=0.5 must match Bézier point")
		passed = false

	# Complete fly in
	enemy.call("_process", 0.6)
	if enemy.call("is_flying_in"):
		push_error("Enemy is_flying_in() must be false when t >= 1.0")
		passed = false
	if not enemy.global_position.is_equal_approx(p3):
		push_error("Enemy global_position must equal p3 at finish")
		passed = false
	if absf(enemy.rotation) > 0.001:
		push_error("Enemy rotation must reset to 0.0 at finish")
		passed = false
	if not completed_emitted[0]:
		push_error("Enemy must emit fly_in_completed on finish")
		passed = false

	# Test cancel_fly_in
	enemy.call("start_fly_in", p0, p1, p2, p3, 1.0, 0.0)
	enemy.call("cancel_fly_in")
	if enemy.call("is_flying_in") or not enemy.global_position.is_equal_approx(p3) or absf(enemy.rotation) > 0.001:
		push_error("cancel_fly_in must immediately reset to p3 with rotation 0 and is_flying_in false")
		passed = false

	root.remove_child(enemy)
	enemy.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 4. Spawner Contract
# ---------------------------------------------------------------------------

func _assert_spawner_contract() -> bool:
	if not ResourceLoader.exists(SPAWNER_PATH):
		push_error("Missing Spawner scene: %s" % SPAWNER_PATH)
		return false

	var packed: PackedScene = load(SPAWNER_PATH) as PackedScene
	var spawner: Node2D = packed.instantiate() as Node2D
	root.add_child(spawner)
	await process_frame
	var passed: bool = true

	# Exports and signals
	if not bool(spawner.get("fly_in_enabled")):
		push_error("EnemySpawner fly_in_enabled must default to true")
		passed = false
	if absf(float(spawner.get("fly_in_duration")) - 1.2) > 0.01:
		push_error("EnemySpawner fly_in_duration must default to 1.2")
		passed = false
	if not spawner.has_signal(&"fly_in_completed_all"):
		push_error("EnemySpawner missing signal: fly_in_completed_all")
		passed = false
	if not spawner.has_method(&"is_flying_in"):
		push_error("EnemySpawner missing method: is_flying_in")
		passed = false

	# Check 5 wave configurations
	var expected_trajectories: Array[String] = ["swoop_left", "pincer", "swoop_right", "cross_dive", "center_loop"]
	var expected_patterns: Array[String] = ["grid", "v_shape", "arc", "diagonal", "grid"]
	for w: int in range(5):
		var cfg: Dictionary = spawner.call("get_wave_config", w)
		if cfg.is_empty():
			push_error("EnemySpawner missing config for wave %d" % w)
			passed = false
			continue
		if String(cfg.get("formation_type", "")) != expected_patterns[w]:
			push_error("Wave %d formation_type expected %s, got %s" % [w, expected_patterns[w], cfg.get("formation_type")])
			passed = false
		if String(cfg.get("fly_in_trajectory", "")) != expected_trajectories[w]:
			push_error("Wave %d fly_in_trajectory expected %s, got %s" % [w, expected_trajectories[w], cfg.get("fly_in_trajectory")])
			passed = false

	# Test starting wave with fly-in
	spawner.call("start_wave", 0)
	if not spawner.call("is_flying_in"):
		push_error("EnemySpawner must be in flying_in state after start_wave with fly_in_enabled")
		passed = false

	var all_completed_emitted: Array[bool] = [false]
	spawner.connect(&"fly_in_completed_all", func() -> void: all_completed_emitted[0] = true)

	# Simulate process frames to complete fly-in
	var enemies: Array[Node] = spawner.get_children()
	for child: Node in enemies:
		if child is Area2D and child.has_method(&"cancel_fly_in"):
			child.call("_process", 5.0)

	await process_frame
	await process_frame

	if not all_completed_emitted[0]:
		push_error("EnemySpawner must emit fly_in_completed_all after all enemies finish fly-in")
		passed = false
	if spawner.call("is_flying_in"):
		push_error("EnemySpawner is_flying_in() must be false after fly-in completes")
		passed = false

	root.remove_child(spawner)
	spawner.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 5. Starfield Warp Boost Contract
# ---------------------------------------------------------------------------

func _assert_starfield_warp_contract() -> bool:
	if not ResourceLoader.exists(STARFIELD_PATH):
		push_error("Missing Starfield scene: %s" % STARFIELD_PATH)
		return false

	var packed: PackedScene = load(STARFIELD_PATH) as PackedScene
	var starfield: Node2D = packed.instantiate() as Node2D
	root.add_child(starfield)
	await process_frame
	var passed: bool = true

	if absf(float(starfield.get("speed_multiplier")) - 1.0) > 0.01:
		push_error("Starfield speed_multiplier must default to 1.0")
		passed = false
	if not starfield.has_method(&"trigger_warp_boost"):
		push_error("Starfield missing method: trigger_warp_boost")
		passed = false

	starfield.call("trigger_warp_boost", 0.2, 4.0)
	await process_frame
	await process_frame
	if float(starfield.get("speed_multiplier")) <= 1.0:
		push_error("Starfield speed_multiplier must accelerate above 1.0 during warp boost, got %f" % float(starfield.get("speed_multiplier")))
		passed = false

	root.remove_child(starfield)
	starfield.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 6. Main Warp Integration Contract
# ---------------------------------------------------------------------------

func _assert_main_warp_integration_contract() -> bool:
	if not ResourceLoader.exists(MAIN_PATH):
		push_error("Missing Main scene: %s" % MAIN_PATH)
		return false

	var packed: PackedScene = load(MAIN_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	root.add_child(main)
	await process_frame
	var passed: bool = true

	var starfield: Node2D = main.get_node_or_null("Starfield") as Node2D
	if starfield == null:
		push_error("Main scene missing Starfield child")
		passed = false
	else:
		main.call("start_session")
		main.call("_on_wave_cleared", 0)
		# Process a frame for tween to register
		await process_frame
		if float(starfield.get("speed_multiplier")) <= 1.0:
			push_error("Main _on_wave_cleared must trigger warp boost on Starfield")
			passed = false

	root.remove_child(main)
	main.queue_free()
	return passed


# ---------------------------------------------------------------------------
# 7. Main Formation Bounds & Stability Contract
# ---------------------------------------------------------------------------

func _assert_main_formation_bounds_contract() -> bool:
	if not ResourceLoader.exists(MAIN_PATH):
		return false

	var packed: PackedScene = load(MAIN_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	root.add_child(main)
	await process_frame

	main.call("start_session")
	var spawner: Node2D = main.get_node_or_null("EnemySpawner") as Node2D
	if spawner == null:
		push_error("Main missing EnemySpawner child in bounds contract")
		root.remove_child(main)
		main.queue_free()
		return false

	var enemies: Array[Node] = []
	for child: Node in spawner.get_children():
		if child is Area2D and child.is_in_group("enemies"):
			enemies.append(child)

	if enemies.is_empty():
		push_error("Main EnemySpawner must have enemies after start_session")
		root.remove_child(main)
		main.queue_free()
		return false

	# Fast forward fly-in for all enemies
	for enemy_node: Node in enemies:
		if enemy_node.has_method("_process"):
			enemy_node.call("_process", 5.0)

	await process_frame
	await process_frame

	var passed: bool = true
	var vp_rect: Rect2 = main.get_viewport().get_visible_rect()
	var initial_y: float = -1.0

	for enemy_node: Node in enemies:
		var enemy: Area2D = enemy_node as Area2D
		# All enemies must be strictly within viewport horizontally and in upper playfield
		if enemy.global_position.x < vp_rect.position.x or enemy.global_position.x > vp_rect.end.x:
			push_error("Enemy at global_position %s is outside horizontal viewport [0, %f]" % [enemy.global_position, vp_rect.end.x])
			passed = false
		if enemy.global_position.y < vp_rect.position.y or enemy.global_position.y > vp_rect.end.y * 0.6:
			push_error("Enemy at global_position %s is outside upper playfield [0, %f]" % [enemy.global_position, vp_rect.end.y * 0.6])
			passed = false

	if not enemies.is_empty() and enemies[0] is Area2D:
		initial_y = (enemies[0] as Area2D).position.y

	# Simulate 10 frames of spawner movement
	for frame_idx: int in range(10):
		spawner.call("_process", 0.016)

	if not enemies.is_empty() and enemies[0] is Area2D:
		var current_y: float = (enemies[0] as Area2D).position.y
		if absf(current_y - initial_y) > 32.0:
			push_error("Enemies must not rapidly descend off screen; initial y was %f, after 10 frames got %f" % [initial_y, current_y])
			passed = false

	root.remove_child(main)
	main.queue_free()
	return passed

