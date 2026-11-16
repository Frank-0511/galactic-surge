# etapa_11_contract_test.gd
# Contract test harness for Etapa 11: Simulación Física: Cargas de Plasma y Balística.
# Verifies:
# 1. EnemyBullet scene contract: Area2D, layer 8, mask 1, groups, signals player_hit and detonated.
# 2. VectorMath analytical ballistics formulas: calculate_ballistic_position, velocity, and launch_velocity.
# 3. Physical parabolic simulation: continuous gravity acceleration (v_y(t) > v_y0) and curvature.
# 4. Luminous residual trail point accumulation during projectile movement.
# 5. Cluster fragmentation: mid-air detonation and generation of 3 fan-spread submunitions under gravity.
# 6. Detonation states on ground contact and player impact with collision disablement.
# 7. Enemy integration: tactical variant assignment (Direct, Parabolic, Cluster) and enrage escalation.

extends SceneTree

const BULLET_PATH := "res://features/enemy/enemy_bullet.tscn"
const ENEMY_PATH := "res://features/enemy/enemy.tscn"
const VectorMathScript: Script = preload("res://core/math/vector_math.gd")


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var bullet_contract_passed: bool = await _assert_bullet_contract()
	var math_ballistics_passed: bool = _assert_math_ballistics()
	var parabolic_sim_passed: bool = await _assert_parabolic_simulation()
	var trail_contract_passed: bool = await _assert_trail_accumulation()
	var cluster_passed: bool = await _assert_cluster_fragmentation()
	var detonation_passed: bool = await _assert_detonation_contract()
	var enemy_integration_passed: bool = await _assert_enemy_integration()

	var all_passed: bool = (
		bullet_contract_passed
		and math_ballistics_passed
		and parabolic_sim_passed
		and trail_contract_passed
		and cluster_passed
		and detonation_passed
		and enemy_integration_passed
	)

	if all_passed:
		print("ETAPA 11 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 11 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Bullet Scene & Structure Contract
# ---------------------------------------------------------------------------

func _assert_bullet_contract() -> bool:
	if not ResourceLoader.exists(BULLET_PATH):
		push_error("Missing enemy bullet scene: %s" % BULLET_PATH)
		return false

	var packed: PackedScene = load(BULLET_PATH) as PackedScene
	var bullet: Area2D = packed.instantiate() as Area2D
	if bullet == null:
		push_error("EnemyBullet root node must be Area2D")
		return false

	var passed: bool = true

	# Collision layer 8, mask 1
	if bullet.collision_layer != 8:
		push_error("EnemyBullet collision layer must be 8, got %d" % bullet.collision_layer)
		passed = false
	if bullet.collision_mask != 1:
		push_error("EnemyBullet collision mask must be 1, got %d" % bullet.collision_mask)
		passed = false

	# Groups
	if not bullet.is_in_group(&"combat_transients"):
		push_error("EnemyBullet must belong to 'combat_transients' group")
		passed = false
	if not bullet.is_in_group(&"enemy_bullets"):
		push_error("EnemyBullet must belong to 'enemy_bullets' group")
		passed = false

	# Signals
	if not bullet.has_signal(&"player_hit"):
		push_error("EnemyBullet missing signal: player_hit")
		passed = false
	if not bullet.has_signal(&"detonated"):
		push_error("EnemyBullet missing signal: detonated")
		passed = false

	# Public methods
	for method_name: StringName in [&"is_detonating", &"get_trail_points", &"get_plasma_variant", &"set_plasma_variant"]:
		if not bullet.has_method(method_name):
			push_error("EnemyBullet missing public method: %s" % method_name)
			passed = false

	# Properties
	var expected_props: Array[String] = [
		"speed", "plasma_variant", "initial_velocity", "ballistic_gravity", "velocity",
		"cluster_fuse_time", "submunition_count", "submunition_spread_angle", "submunition_lifetime"
	]
	for prop: String in expected_props:
		if not (prop in bullet):
			push_error("EnemyBullet missing exported property: %s" % prop)
			passed = false

	bullet.free()
	return passed


# ---------------------------------------------------------------------------
# 2. VectorMath Analytical Ballistics Contract
# ---------------------------------------------------------------------------

func _assert_math_ballistics() -> bool:
	var passed: bool = true

	var origin: Vector2 = Vector2(100.0, 200.0)
	var v0: Vector2 = Vector2(50.0, -30.0)
	var g: float = 400.0
	var t: float = 1.5

	# calculate_ballistic_position: r(t) = r0 + v0*t + 0.5*g*t^2
	# x = 100 + 50 * 1.5 = 175
	# y = 200 + (-30)*1.5 + 0.5*400*(1.5*1.5) = 200 - 45 + 450 = 605
	var pos: Vector2 = VectorMathScript.calculate_ballistic_position(origin, v0, g, t)
	if absf(pos.x - 175.0) > 0.001 or absf(pos.y - 605.0) > 0.001:
		push_error("VectorMath.calculate_ballistic_position failed: got %s expected (175, 605)" % pos)
		passed = false

	# calculate_ballistic_velocity: v(t) = v0 + (0, g*t)
	# vx = 50, vy = -30 + 400 * 1.5 = 570
	var vel: Vector2 = VectorMathScript.calculate_ballistic_velocity(v0, g, t)
	if absf(vel.x - 50.0) > 0.001 or absf(vel.y - 570.0) > 0.001:
		push_error("VectorMath.calculate_ballistic_velocity failed: got %s expected (50, 570)" % vel)
		passed = false

	# calculate_ballistic_launch_velocity: solves initial v0 to hit target at flight_time T
	var target: Vector2 = Vector2(350.0, 700.0)
	var flight_time: float = 2.0
	var launch_v: Vector2 = VectorMathScript.calculate_ballistic_launch_velocity(origin, target, g, flight_time)
	var simulated_target: Vector2 = VectorMathScript.calculate_ballistic_position(origin, launch_v, g, flight_time)
	if simulated_target.distance_to(target) > 0.01:
		push_error("VectorMath.calculate_ballistic_launch_velocity missed target: got %s expected %s" % [simulated_target, target])
		passed = false

	return passed


# ---------------------------------------------------------------------------
# 3. Physical Parabolic Simulation Contract
# ---------------------------------------------------------------------------

func _assert_parabolic_simulation() -> bool:
	var packed: PackedScene = load(BULLET_PATH) as PackedScene
	var bullet: Area2D = packed.instantiate() as Area2D
	root.add_child(bullet)
	await process_frame

	var passed: bool = true

	# Set parabolic mode
	bullet.set("plasma_variant", 1) # PARABOLIC
	bullet.set("ballistic_gravity", 400.0)
	bullet.set("velocity", Vector2(80.0, -50.0))
	bullet.global_position = Vector2(200.0, 200.0)

	var v_y_initial: float = bullet.get("velocity").y

	# Simulate 10 frames of 0.05s (total 0.5s)
	for _frame in range(10):
		bullet._process(0.05)

	var v_y_after: float = bullet.get("velocity").y
	# v_y should have increased due to gravity: -50 + 400 * 0.5 = 150.0
	if v_y_after <= v_y_initial:
		push_error("Parabolic bullet did not accelerate vertically under gravity: v0=%f, v_after=%f" % [v_y_initial, v_y_after])
		passed = false

	if absf(v_y_after - 150.0) > 2.0:
		push_error("Parabolic vertical velocity mismatch: got %f expected ~150.0" % v_y_after)
		passed = false

	# Check horizontal position moved at constant speed: 80 * 0.5 = 40 px
	if absf(bullet.global_position.x - 240.0) > 2.0:
		push_error("Parabolic horizontal motion inconsistent: got x=%f expected ~240.0" % bullet.global_position.x)
		passed = false

	root.remove_child(bullet)
	bullet.free()
	return passed


# ---------------------------------------------------------------------------
# 4. Luminous Trail Accumulation Contract
# ---------------------------------------------------------------------------

func _assert_trail_accumulation() -> bool:
	var packed: PackedScene = load(BULLET_PATH) as PackedScene
	var bullet: Area2D = packed.instantiate() as Area2D
	root.add_child(bullet)
	await process_frame

	var passed: bool = true

	bullet.global_position = Vector2(300.0, 300.0)
	bullet.set("plasma_variant", 1)
	bullet.set("velocity", Vector2(50.0, 200.0))

	# Advance several frames to accumulate trail points
	for _i in range(8):
		bullet.global_position += Vector2(5.0, 20.0)
		bullet._process(0.03)

	var trail_points: Array[Vector2] = bullet.get_trail_points()
	if trail_points.size() < 3:
		push_error("Trail points failed to accumulate during motion: count=%d" % trail_points.size())
		passed = false

	# Verify trail points are distinct and trace back behind the bullet
	if trail_points.size() >= 2:
		var last_pt: Vector2 = trail_points[-1]
		var first_pt: Vector2 = trail_points[0]
		if last_pt.distance_to(first_pt) < 10.0:
			push_error("Trail points do not reflect spatial movement distance")
			passed = false

	root.remove_child(bullet)
	bullet.free()
	return passed


# ---------------------------------------------------------------------------
# 5. Cluster Fragmentation Contract
# ---------------------------------------------------------------------------

func _assert_cluster_fragmentation() -> bool:
	var container: Node2D = Node2D.new()
	root.add_child(container)
	await process_frame

	var packed: PackedScene = load(BULLET_PATH) as PackedScene
	var cluster_bullet: Area2D = packed.instantiate() as Area2D
	cluster_bullet.set("plasma_variant", 2) # CLUSTER
	cluster_bullet.set("cluster_fuse_time", 0.1)
	cluster_bullet.set("velocity", Vector2(0.0, 150.0))
	cluster_bullet.set("ballistic_gravity", 320.0)
	container.add_child(cluster_bullet)
	cluster_bullet.global_position = Vector2(400.0, 300.0)
	await process_frame

	var passed: bool = true

	# Advance time past fuse time (0.15s)
	cluster_bullet._process(0.06)
	cluster_bullet._process(0.06)
	cluster_bullet._process(0.06)

	# Cluster parent should now be detonating
	if not cluster_bullet.is_detonating():
		push_error("Cluster parent must be detonating after fuse expiration")
		passed = false

	# Container should contain the 3 spawned submunitions
	var submunitions: Array[Area2D] = []
	for child: Node in container.get_children():
		if child is Area2D and child != cluster_bullet:
			submunitions.append(child as Area2D)

	if submunitions.size() != 3:
		push_error("Cluster must spawn exactly 3 submunitions, got %d" % submunitions.size())
		passed = false
	else:
		# Check submunition properties
		var min_vx: float = 9999.0
		var max_vx: float = -9999.0
		for sub: Area2D in submunitions:
			var sub_variant: int = sub.get("plasma_variant")
			if sub_variant != 3: # CLUSTER_SUBMUNITION
				push_error("Submunition must have variant CLUSTER_SUBMUNITION (3), got %d" % sub_variant)
				passed = false
			var sub_g: float = sub.get("ballistic_gravity")
			if sub_g < 300.0:
				push_error("Submunition must inherit ballistic gravity, got %f" % sub_g)
				passed = false
			var vx: float = sub.get("velocity").x
			min_vx = minf(min_vx, vx)
			max_vx = maxf(max_vx, vx)

		# Fan spread check: velocities should diverge laterally (-30°, 0°, +30°)
		if max_vx - min_vx < 40.0:
			push_error("Submunitions do not exhibit fan spread velocity divergence: min_vx=%f, max_vx=%f" % [min_vx, max_vx])
			passed = false

	root.remove_child(container)
	container.free()
	return passed


# ---------------------------------------------------------------------------
# 6. Detonation Contract (Ground & Player Impact)
# ---------------------------------------------------------------------------

func _assert_detonation_contract() -> bool:
	var packed: PackedScene = load(BULLET_PATH) as PackedScene
	var passed: bool = true

	# Test 6A: Ground detonation
	var ground_bullet: Area2D = packed.instantiate() as Area2D
	root.add_child(ground_bullet)
	await process_frame

	var ground_detonated: Dictionary = {"called": false, "is_ground": false}
	ground_bullet.detonated.connect(func(is_g: bool) -> void:
		ground_detonated["called"] = true
		ground_detonated["is_ground"] = is_g
	)

	# Place bullet past the bottom viewport border
	var vp_height: float = ground_bullet.get_viewport_rect().size.y
	ground_bullet.global_position = Vector2(300.0, vp_height + 2.0)
	ground_bullet._process(0.016)

	if not ground_bullet.is_detonating():
		push_error("Bullet must initiate detonation upon touching ground/viewport bottom")
		passed = false
	if not ground_detonated["called"] or not ground_detonated["is_ground"]:
		push_error("Bullet must emit detonated(true) when impacting ground")
		passed = false

	# Verify monitoring deactivated
	if ground_bullet.monitoring:
		# Could be deferred; wait 1 frame
		await process_frame
		if ground_bullet.monitoring:
			push_error("Detonating bullet must disable collision monitoring")
			passed = false

	root.remove_child(ground_bullet)
	ground_bullet.free()

	# Test 6B: Player impact detonation
	var impact_bullet: Area2D = packed.instantiate() as Area2D
	root.add_child(impact_bullet)
	await process_frame

	var hit_data: Dictionary = {"hit": false}
	impact_bullet.player_hit.connect(func(_p: Node2D) -> void: hit_data["hit"] = true)

	var dummy_player: CharacterBody2D = CharacterBody2D.new()
	dummy_player.add_to_group(&"player")
	root.add_child(dummy_player)

	impact_bullet._on_body_entered(dummy_player)

	if not hit_data["hit"]:
		push_error("Bullet must emit player_hit when colliding with player")
		passed = false
	if not impact_bullet.is_detonating():
		push_error("Bullet must enter detonation state upon impacting player")
		passed = false

	root.remove_child(dummy_player)
	dummy_player.free()
	root.remove_child(impact_bullet)
	impact_bullet.free()

	return passed


# ---------------------------------------------------------------------------
# 7. Enemy Integration Contract
# ---------------------------------------------------------------------------

func _assert_enemy_integration() -> bool:
	if not ResourceLoader.exists(ENEMY_PATH):
		push_error("Missing enemy scene: %s" % ENEMY_PATH)
		return false

	var enemy_packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var enemy: Area2D = enemy_packed.instantiate() as Area2D
	root.add_child(enemy)
	await process_frame

	var passed: bool = true

	# Check forced variant API
	if not enemy.has_method(&"set_forced_bullet_variant"):
		push_error("Enemy missing set_forced_bullet_variant method")
		passed = false
	if not enemy.has_method(&"get_forced_bullet_variant"):
		push_error("Enemy missing get_forced_bullet_variant method")
		passed = false

	# Test firing Parabolic variant
	enemy.call(&"set_forced_bullet_variant", 1) # PARABOLIC
	var bullet_p: Area2D = null
	var bullet_scene: PackedScene = load(BULLET_PATH) as PackedScene
	bullet_p = bullet_scene.instantiate() as Area2D
	enemy.call(&"_configure_bullet", bullet_p)

	if bullet_p.get("plasma_variant") != 1:
		push_error("Enemy failed to configure PARABOLIC variant on bullet")
		passed = false
	if bullet_p.get("ballistic_gravity") != 380.0:
		push_error("Enemy PARABOLIC bullet must have ballistic_gravity=380.0, got %f" % bullet_p.get("ballistic_gravity"))
		passed = false
	bullet_p.free()

	# Test firing Cluster variant
	enemy.call(&"set_forced_bullet_variant", 2) # CLUSTER
	var bullet_c: Area2D = bullet_scene.instantiate() as Area2D
	enemy.call(&"_configure_bullet", bullet_c)

	if bullet_c.get("plasma_variant") != 2:
		push_error("Enemy failed to configure CLUSTER variant on bullet")
		passed = false
	if bullet_c.get("ballistic_gravity") != 320.0:
		push_error("Enemy CLUSTER bullet must have ballistic_gravity=320.0, got %f" % bullet_c.get("ballistic_gravity"))
		passed = false
	bullet_c.free()

	# Test Enrage distribution escalation
	enemy.call(&"set_forced_bullet_variant", -1)
	enemy.call(&"set_enraged", true)

	var complex_count: int = 0
	var samples: int = 100
	for _i in range(samples):
		var b: Area2D = bullet_scene.instantiate() as Area2D
		enemy.call(&"_configure_bullet", b)
		var v: int = b.get("plasma_variant")
		if v == 1 or v == 2: # PARABOLIC or CLUSTER
			complex_count += 1
		b.free()

	# Enraged should have ~80% complex ballistic variants (at least 60% with margin)
	if complex_count < 60:
		push_error("Enraged enemy should heavily favor ballistic variants, got %d / %d" % [complex_count, samples])
		passed = false

	root.remove_child(enemy)
	enemy.free()
	return passed
