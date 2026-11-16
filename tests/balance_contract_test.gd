# balance_contract_test.gd
# Contract test harness for enemy health, continuous Chicken Invaders-style laser,
# weapon overheat timing calibration, and progressive wave difficulty curves.
# Verifies:
# 1. Enemy health, damaged signal, fractional damage support, and destruction threshold.
# 2. Continuous laser non-instantaneous DPS behaviour.
# 3. Continuous laser stopping at first enemy without penetrating columns.
# 4. Laser beam thickness and DPS scaling monotonically from Level 1 to 10.
# 5. Spawner wave difficulty curve: no cluster bullets before wave 4, monotonic fire rates, probability sums.
# 6. Enemy bullet configuration honoring custom wave mixes.
# 7. Weapon overheat sustained fire duration calibrated to target CI timings.

extends SceneTree

const ENEMY_PATH := "res://features/enemy/enemy.tscn"
const LASER_PATH := "res://features/bullet/laser_beam.tscn"
const SPAWNER_PATH := "res://features/spawning/enemy_spawner.tscn"
const BULLET_PATH := "res://features/enemy/enemy_bullet.tscn"
const PLAYER_PATH := "res://features/player/player.tscn"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var enemy_health_passed: bool = await _assert_enemy_health_contract()
	var laser_dps_passed: bool = await _assert_laser_dps_contract()
	var laser_column_passed: bool = await _assert_laser_column_contract()
	var laser_scaling_passed: bool = await _assert_laser_scaling_contract()
	var difficulty_curve_passed: bool = await _assert_difficulty_curve_contract()
	var bullet_mix_passed: bool = await _assert_bullet_mix_contract()
	var overheat_timing_passed: bool = await _assert_overheat_timing_contract()

	var all_passed: bool = (
		enemy_health_passed
		and laser_dps_passed
		and laser_column_passed
		and laser_scaling_passed
		and difficulty_curve_passed
		and bullet_mix_passed
		and overheat_timing_passed
	)

	if all_passed:
		print("BALANCE CONTRACT TESTS: ALL PASSED")
	else:
		push_error("BALANCE CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Enemy Health and Damage Contract
# ---------------------------------------------------------------------------

func _assert_enemy_health_contract() -> bool:
	if not ResourceLoader.exists(ENEMY_PATH):
		push_error("Missing scene: %s" % ENEMY_PATH)
		return false

	var packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var enemy: Area2D = packed.instantiate() as Area2D
	if enemy == null:
		push_error("Enemy root must be Area2D")
		return false

	root.add_child(enemy)
	await process_frame
	var passed: bool = true

	if not enemy.has_method(&"take_damage"):
		push_error("Enemy missing take_damage method")
		passed = false

	if not enemy.has_method(&"supports_fractional_damage") or not bool(enemy.call(&"supports_fractional_damage")):
		push_error("Enemy must support fractional damage")
		passed = false

	if absf(float(enemy.get("max_health")) - 1.0) > 0.001 or absf(float(enemy.get("health")) - 1.0) > 0.001:
		push_error("Enemy max_health and initial health must be 1.0")
		passed = false

	var damage_events: Array[Dictionary] = []
	enemy.connect(&"damaged", func(cur: float, max_h: float) -> void:
		damage_events.append({"cur": cur, "max": max_h})
	)

	var destroyed_events: Array[Area2D] = []
	enemy.destroyed.connect(func(e: Area2D) -> void:
		destroyed_events.append(e)
	)

	# Fractional hit 0.4: health should drop to ~0.6 and not be destroyed
	enemy.call(&"take_damage", 0.4)
	if absf(float(enemy.get("health")) - 0.6) > 0.01:
		push_error("Enemy health after 0.4 damage expected 0.6, got %f" % float(enemy.get("health")))
		passed = false

	if damage_events.is_empty() or absf(damage_events[-1]["cur"] - 0.6) > 0.01:
		push_error("damaged signal not emitted with correct current health")
		passed = false

	if bool(enemy.get("_destroyed")):
		push_error("Enemy should remain alive after taking 0.4 damage out of 1.0 HP")
		passed = false

	# Finishing hit 0.6: health reaches 0.0 and destroys enemy
	enemy.call(&"take_damage", 0.6)
	if destroyed_events.is_empty():
		push_error("Enemy destroyed signal was not emitted upon reaching 0 HP")
		passed = false

	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 2. Continuous Laser Non-Instantaneous DPS Contract
# ---------------------------------------------------------------------------

func _assert_laser_dps_contract() -> bool:
	var laser_packed: PackedScene = load(LASER_PATH) as PackedScene
	var enemy_packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var laser: Area2D = laser_packed.instantiate() as Area2D
	var enemy: Area2D = enemy_packed.instantiate() as Area2D

	root.add_child(laser)
	root.add_child(enemy)
	await process_frame

	var passed: bool = true
	laser.global_position = Vector2(400.0, 600.0)
	enemy.global_position = Vector2(400.0, 400.0)

	laser.call(&"set_power_level", 1)
	laser.call(&"set_firing", true)

	# Simulate 0.30 seconds (6 steps of 0.05s).
	# At 2.5 DPS, total damage in 0.3s is 2 ticks of 0.30 = 0.60 HP. Enemy must be damaged (~0.40 HP) but still alive.
	for _i in range(6):
		laser._process(0.05)

	var hp_mid: float = float(enemy.get("health"))
	if hp_mid >= 1.0:
		push_error("Enemy should take continuous laser damage over 0.3s, health remained %f" % hp_mid)
		passed = false
	elif hp_mid <= 0.0 or bool(enemy.get("_destroyed")):
		push_error("Enemy was destroyed too fast by Level 1 laser (instant kill regression)")
		passed = false

	# Simulate 1.0 additional second (20 steps of 0.05s) -> total 1.3s, enough to deplete 1.0 HP at 2.5 DPS (~0.40s needed)
	for _i in range(20):
		laser._process(0.05)

	if not bool(enemy.get("_destroyed")):
		push_error("Enemy should be destroyed after 1.3s of continuous Level 1 laser fire")
		passed = false

	laser.call(&"set_firing", false)
	laser.queue_free()
	if is_instance_valid(enemy):
		enemy.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 3. Continuous Laser Column Penetration Barrier Contract
# ---------------------------------------------------------------------------

func _assert_laser_column_contract() -> bool:
	var laser_packed: PackedScene = load(LASER_PATH) as PackedScene
	var enemy_packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var laser: Area2D = laser_packed.instantiate() as Area2D
	var e1: Area2D = enemy_packed.instantiate() as Area2D
	var e2: Area2D = enemy_packed.instantiate() as Area2D
	var e3: Area2D = enemy_packed.instantiate() as Area2D

	root.add_child(laser)
	root.add_child(e1)
	root.add_child(e2)
	root.add_child(e3)
	await process_frame

	var passed: bool = true
	laser.global_position = Vector2(350.0, 600.0)
	e1.global_position = Vector2(350.0, 480.0) # closest
	e2.global_position = Vector2(350.0, 360.0) # middle
	e3.global_position = Vector2(350.0, 240.0) # rear

	laser.call(&"set_power_level", 1)
	laser.call(&"set_firing", true)

	# Fire for 0.50 seconds in 0.05s steps (10 steps).
	# At 2.5 DPS and 0.12s tick rate, Enemy 1 (1.0 HP) receives 4 ticks of 0.30 HP and dies at step 10.
	# Enemy 2 and Enemy 3 must remain untouched behind Enemy 1 without penetration damage.
	for _i in range(10):
		laser._process(0.05)

	var destroyed_count: int = 0
	if bool(e1.get("_destroyed")):
		destroyed_count += 1
	if bool(e2.get("_destroyed")):
		destroyed_count += 1
	if bool(e3.get("_destroyed")):
		destroyed_count += 1

	if destroyed_count != 1:
		push_error("Laser must destroy only the first enemy in column, destroyed %d enemies" % destroyed_count)
		passed = false

	var e2_hp: float = float(e2.get("health"))
	var e3_hp: float = float(e3.get("health"))
	if absf(e2_hp - 1.0) > 0.01:
		push_error("Second enemy behind front enemy took premature damage, health is %f" % e2_hp)
		passed = false
	if absf(e3_hp - 1.0) > 0.01:
		push_error("Third enemy in column took penetration damage, health is %f" % e3_hp)
		passed = false

	laser.call(&"set_firing", false)
	laser.queue_free()
	if is_instance_valid(e1): e1.queue_free()
	if is_instance_valid(e2): e2.queue_free()
	if is_instance_valid(e3): e3.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 4. Laser Width and DPS Level Scaling Contract
# ---------------------------------------------------------------------------

func _assert_laser_scaling_contract() -> bool:
	var laser_packed: PackedScene = load(LASER_PATH) as PackedScene
	var laser: Area2D = laser_packed.instantiate() as Area2D
	root.add_child(laser)
	await process_frame

	var passed: bool = true
	var prev_width: float = 0.0
	var prev_dps: float = 0.0

	for lvl in range(1, 11):
		laser.call(&"set_power_level", lvl)
		var w: float = float(laser.get("beam_width"))
		var dps: float = float(laser.get("damage_per_second"))

		if lvl > 1:
			if w <= prev_width:
				push_error("beam_width failed monotonic increase at level %d" % lvl)
				passed = false
			if dps <= prev_dps:
				push_error("damage_per_second failed monotonic increase at level %d" % lvl)
				passed = false

		prev_width = w
		prev_dps = dps

	laser.call(&"set_power_level", 1)
	if float(laser.get("beam_width")) > 5.0:
		push_error("Level 1 laser beam_width should be thin (<= 5.0 px), got %f" % float(laser.get("beam_width")))
		passed = false

	laser.call(&"set_power_level", 10)
	if float(laser.get("beam_width")) < 20.0:
		push_error("Level 10 laser beam_width should be thick (>= 20.0 px), got %f" % float(laser.get("beam_width")))
		passed = false
	if float(laser.get("damage_per_second")) < 7.0:
		push_error("Level 10 laser DPS should be high (>= 7.0), got %f" % float(laser.get("damage_per_second")))
		passed = false

	laser.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 5. Spawner Wave Difficulty Curve Contract
# ---------------------------------------------------------------------------

func _assert_difficulty_curve_contract() -> bool:
	var spawner_packed: PackedScene = load(SPAWNER_PATH) as PackedScene
	var spawner: Node2D = spawner_packed.instantiate() as Node2D
	root.add_child(spawner)
	await process_frame

	var passed: bool = true
	var total_waves: int = int(spawner.call(&"get_total_waves"))
	if total_waves != 10:
		push_error("Spawner expected 10 waves, got %d" % total_waves)
		passed = false

	# Waves 0..2 (waves 1-3) must have 0% cluster projectiles in normal mix
	for w in range(3):
		var cfg: Dictionary = spawner.call(&"get_wave_config", w)
		var mix: Array = cfg.get("bullet_mix", [])
		if mix.size() < 3 or float(mix[2]) > 0.0:
			push_error("Wave %d should have 0 cluster bullets, got %s" % [w + 1, str(mix)])
			passed = false

	# Wave 9 (wave 10) must include cluster projectiles (> 0)
	var final_cfg: Dictionary = spawner.call(&"get_wave_config", 9)
	var final_mix: Array = final_cfg.get("bullet_mix", [])
	if final_mix.size() < 3 or float(final_mix[2]) <= 0.0:
		push_error("Wave 10 must have cluster bullets, got %s" % str(final_mix))
		passed = false

	# All mixes must sum to 1.0 (normal and enraged)
	for w in range(total_waves):
		var cfg: Dictionary = spawner.call(&"get_wave_config", w)
		var norm: Array = cfg.get("bullet_mix", [])
		var enr: Array = cfg.get("enraged_bullet_mix", [])
		var norm_sum: float = float(norm[0]) + float(norm[1]) + float(norm[2])
		var enr_sum: float = float(enr[0]) + float(enr[1]) + float(enr[2])
		if absf(norm_sum - 1.0) > 0.002:
			push_error("Wave %d normal bullet mix does not sum to 1.0: %f" % [w + 1, norm_sum])
			passed = false
		if absf(enr_sum - 1.0) > 0.002:
			push_error("Wave %d enraged bullet mix does not sum to 1.0: %f" % [w + 1, enr_sum])
			passed = false

	# Fire rate scale should be monotonically non-increasing (slower to faster fire cooldowns)
	for w in range(1, total_waves):
		var prev_scale: float = float(spawner.call(&"get_wave_config", w - 1).get("fire_rate_scale", 1.0))
		var cur_scale: float = float(spawner.call(&"get_wave_config", w).get("fire_rate_scale", 1.0))
		if cur_scale > prev_scale + 0.001:
			push_error("Wave %d fire_rate_scale (%f) increased relative to wave %d (%f)" % [w + 1, cur_scale, w, prev_scale])
			passed = false

	spawner.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 6. Enemy Bullet Mix Configuration Contract
# ---------------------------------------------------------------------------

func _assert_bullet_mix_contract() -> bool:
	var enemy_packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var bullet_packed: PackedScene = load(BULLET_PATH) as PackedScene
	var enemy: Area2D = enemy_packed.instantiate() as Area2D
	root.add_child(enemy)
	await process_frame

	var passed: bool = true
	# Set Wave 1 mix: 100% direct, 0% parabolic, 0% cluster
	enemy.call(&"set_bullet_mix", [1.0, 0.0, 0.0], [0.8, 0.2, 0.0])

	var cluster_count: int = 0
	var parabolic_count: int = 0
	var direct_count: int = 0

	for _i in range(100):
		var bullet: Area2D = bullet_packed.instantiate() as Area2D
		enemy.call(&"_configure_bullet", bullet)
		var v: int = int(bullet.get("plasma_variant"))
		if v == 2:
			cluster_count += 1
		elif v == 1:
			parabolic_count += 1
		elif v == 0:
			direct_count += 1
		bullet.free()

	if cluster_count > 0:
		push_error("Wave 1 enemy configuration generated cluster bullets: %d" % cluster_count)
		passed = false
	if parabolic_count > 0:
		push_error("Wave 1 normal enemy generated parabolic bullets: %d" % parabolic_count)
		passed = false
	if direct_count != 100:
		push_error("Wave 1 normal enemy expected 100 direct bullets, got %d" % direct_count)
		passed = false

	# Enrage wave 1: should have 0 cluster and ~20% parabolic
	enemy.call(&"set_enraged", true)
	var enraged_cluster: int = 0
	for _i in range(100):
		var bullet: Area2D = bullet_packed.instantiate() as Area2D
		enemy.call(&"_configure_bullet", bullet)
		if int(bullet.get("plasma_variant")) == 2:
			enraged_cluster += 1
		bullet.free()

	if enraged_cluster > 0:
		push_error("Wave 1 enraged enemy generated cluster bullets: %d" % enraged_cluster)
		passed = false

	enemy.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 7. Weapon Overheat Timing Calibration Contract
# ---------------------------------------------------------------------------

func _assert_overheat_timing_contract() -> bool:
	var player_packed: PackedScene = load(PLAYER_PATH) as PackedScene
	var player: CharacterBody2D = player_packed.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame

	var passed: bool = true

	# Test targets: [Weapon enum, level, target_seconds]
	# BLASTER: L1=10.0s, L10=8.0s
	# MISSILE: L1=9.0s, L10=7.5s
	# LASER: L1=8.0s, L10=10.0s
	var test_cases: Array = [
		{"weapon": 0, "level": 1, "target": 10.0},
		{"weapon": 0, "level": 10, "target": 8.0},
		{"weapon": 1, "level": 1, "target": 9.0},
		{"weapon": 1, "level": 10, "target": 7.5},
		{"weapon": 2, "level": 1, "target": 8.0},
		{"weapon": 2, "level": 10, "target": 10.0},
	]

	var dt: float = 0.05
	for tc: Dictionary in test_cases:
		var w: int = int(tc["weapon"])
		var lvl: int = int(tc["level"])
		var target_s: float = float(tc["target"])

		player.call(&"set_weapon", w)
		player.call(&"set_weapon_level", lvl)
		player.call(&"reset_heat")

		var heat_per_sec: float = float(player.call(&"_get_heat_per_second", w))
		var elapsed: float = 0.0

		while not bool(player.get("is_overheated")) and elapsed < 15.0:
			player.call(&"add_heat", heat_per_sec * dt)
			elapsed += dt

		if absf(elapsed - target_s) > 0.35:
			push_error("Weapon %d level %d overheat time expected %.1fs, simulated %.2fs" % [w, lvl, target_s, elapsed])
			passed = false

		if w == 0 and lvl == 1 and elapsed < 9.5:
			push_error("Blaster Level 1 overheated prematurely (< 9.5s): %.2fs" % elapsed)
			passed = false

	player.queue_free()
	await process_frame
	return passed
