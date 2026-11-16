# etapa_10_contract_test.gd
# Contract test harness for Etapa 10: Medallones Neón, Niveles 1-15 y Riesgo/Recompensa.
# Verifies:
# 1. LootDrop enum types (Medallions, Power Atom, Recovery Capsule) and lifetime countdown.
# 2. Player weapon level scaling, tactical dilemma (upgrade vs switch/reset), power atom, and death penalty.
# 3. Scaled firing patterns for Ion Blaster, Missile, and Laser width across levels 1 to 15.
# 4. Extra life milestone rewards per 1,000,000 points in Main.
# 5. HUD weapon level text and glowing neon pips synchronization.
# 6. Main integration: medallion collection, death capsule spawn, and session reset.

extends SceneTree

const PLAYER_PATH := "res://features/player/player.tscn"
const LOOT_PATH := "res://features/loot/loot_drop.tscn"
const HUD_PATH := "res://scenes/ui/hud.tscn"
const MAIN_PATH := "res://scenes/main/main.tscn"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var loot_contract_passed: bool = await _assert_loot_contract()
	var player_dilemma_passed: bool = await _assert_player_dilemma_contract()
	var firing_patterns_passed: bool = await _assert_firing_patterns_contract()
	var blaster_coverage_passed: bool = await _assert_blaster_lateral_coverage_contract()
	var laser_high_level_passed: bool = await _assert_laser_high_level_power_contract()
	var hud_contract_passed: bool = await _assert_hud_contract()
	var extra_life_passed: bool = await _assert_extra_life_contract()
	var main_integration_passed: bool = await _assert_main_integration_contract()

	var all_passed: bool = (
		loot_contract_passed
		and player_dilemma_passed
		and firing_patterns_passed
		and blaster_coverage_passed
		and laser_high_level_passed
		and hud_contract_passed
		and extra_life_passed
		and main_integration_passed
	)

	if all_passed:
		print("ETAPA 10 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 10 CONTRACT TESTS: FAILURES DETECTED")

	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. LootDrop Types and Lifetime Contract
# ---------------------------------------------------------------------------

func _assert_loot_contract() -> bool:
	if not ResourceLoader.exists(LOOT_PATH):
		push_error("Missing LootDrop scene: %s" % LOOT_PATH)
		return false

	var packed: PackedScene = load(LOOT_PATH) as PackedScene
	var loot: LootDrop = packed.instantiate() as LootDrop
	root.add_child(loot)
	await process_frame

	var passed: bool = true

	# Verify enum keys exist
	if not ("MEDALLION_BLASTER" in LootDrop.Type):
		push_error("LootDrop.Type missing MEDALLION_BLASTER")
		passed = false
	if ("MEDALLION_SPREAD" in LootDrop.Type):
		push_error("LootDrop.Type should not contain MEDALLION_SPREAD")
		passed = false
	if not ("MEDALLION_MISSILE" in LootDrop.Type):
		push_error("LootDrop.Type missing MEDALLION_MISSILE")
		passed = false
	if not ("MEDALLION_LASER" in LootDrop.Type):
		push_error("LootDrop.Type missing MEDALLION_LASER")
		passed = false
	if not ("POWER_ATOM" in LootDrop.Type):
		push_error("LootDrop.Type missing POWER_ATOM")
		passed = false
	if not ("RECOVERY_CAPSULE" in LootDrop.Type):
		push_error("LootDrop.Type missing RECOVERY_CAPSULE")
		passed = false

	# Test custom lifetime configuration
	loot.configure(LootDrop.Type.MEDALLION_BLASTER, Vector2(100, 100), null, 5.0)
	if loot.get_lifetime() != 5.0:
		push_error("LootDrop configure custom_lifetime failed: got %f expected 5.0" % loot.get_lifetime())
		passed = false

	# Test default recovery capsule lifetime = 3.0
	loot.configure(LootDrop.Type.RECOVERY_CAPSULE, Vector2(100, 100), null, 0.0)
	if loot.get_lifetime() != 3.0:
		push_error("Recovery capsule must default to 3.0s lifetime, got %f" % loot.get_lifetime())
		passed = false

	# Test colors
	var c_blaster: Color = loot.call(&"_get_type_glow_color")
	if c_blaster != Color(0.2, 0.6, 1.0) and loot.get_type() == LootDrop.Type.RECOVERY_CAPSULE:
		pass # Verified below per type

	loot.configure(LootDrop.Type.MEDALLION_BLASTER, Vector2.ZERO)
	if loot.call(&"_get_type_glow_color") != Color(0.2, 0.6, 1.0):
		push_error("MEDALLION_BLASTER glow color mismatch")
		passed = false

	loot.configure(LootDrop.Type.MEDALLION_MISSILE, Vector2.ZERO)
	if loot.call(&"_get_type_glow_color") != Color(1.0, 0.55, 0.1):
		push_error("MEDALLION_MISSILE glow color mismatch")
		passed = false

	loot.configure(LootDrop.Type.MEDALLION_LASER, Vector2.ZERO)
	if loot.call(&"_get_type_glow_color") != Color(1.0, 0.2, 0.25):
		push_error("MEDALLION_LASER glow color mismatch")
		passed = false

	loot.configure(LootDrop.Type.POWER_ATOM, Vector2.ZERO)
	if loot.call(&"_get_type_glow_color") != Color(1.0, 0.85, 0.2):
		push_error("POWER_ATOM glow color mismatch")
		passed = false

	loot.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 2. Player Tactical Dilemma & Level Progression Contract
# ---------------------------------------------------------------------------

func _assert_player_dilemma_contract() -> bool:
	if not ResourceLoader.exists(PLAYER_PATH):
		push_error("Missing Player scene: %s" % PLAYER_PATH)
		return false

	var packed: PackedScene = load(PLAYER_PATH) as PackedScene
	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame

	var passed: bool = true

	# Initial level must be 1
	if player.get_weapon_level() != 1:
		push_error("Initial weapon_level must be 1, got %d" % player.get_weapon_level())
		passed = false

	# Signal emission on set_weapon_level
	var last_emitted_level: Array[int] = [-1]
	player.weapon_level_changed.connect(func(lvl: int) -> void: last_emitted_level[0] = lvl)

	player.set_weapon_level(3)
	if player.get_weapon_level() != 3 or last_emitted_level[0] != 3:
		push_error("set_weapon_level failed to set or emit level 3")
		passed = false

	# Clamping between 1 and 15
	player.set_weapon_level(10)
	if player.get_weapon_level() != 10:
		push_error("set_weapon_level(10) must return 10, got %d" % player.get_weapon_level())
		passed = false

	player.set_weapon_level(15)
	if player.get_weapon_level() != 15:
		push_error("set_weapon_level(15) must return 15, got %d" % player.get_weapon_level())
		passed = false

	player.set_weapon_level(20)
	if player.get_weapon_level() != 15:
		push_error("set_weapon_level(20) must clamp to 15, got %d" % player.get_weapon_level())
		passed = false

	player.set_weapon_level(-2)
	if player.get_weapon_level() != 1:
		push_error("set_weapon_level(-2) must clamp to 1, got %d" % player.get_weapon_level())
		passed = false

	# Same medallion -> level upgrade (+1) up to 15
	player.set_weapon(0) # BLASTER
	player.set_weapon_level(1)
	player.apply_medallion(0)
	if player.get_weapon_level() != 2:
		push_error("apply_medallion with same weapon must upgrade level to 2, got %d" % player.get_weapon_level())
		passed = false

	for i in range(20):
		player.apply_medallion(0)
	if player.get_weapon_level() != 15:
		push_error("apply_medallion must cap at level 15, got %d" % player.get_weapon_level())
		passed = false

	# Different medallion -> Chicken Invaders model: switches weapon and preserves weapon level
	player.apply_medallion(1) # MISSILE
	if player.get_weapon() != 1 or player.get_weapon_level() != 15:
		push_error("apply_medallion with different weapon must switch to MISSILE and preserve level 15 (got weapon %d, level %d)" % [player.get_weapon(), player.get_weapon_level()])
		passed = false

	# Power atom -> upgrades level (+1) without changing current weapon
	player.set_weapon_level(2)
	player.apply_power_atom()
	if player.get_weapon() != 1 or player.get_weapon_level() != 3:
		push_error("apply_power_atom must preserve weapon (1) and increment level to 3 (got %d)" % player.get_weapon_level())
		passed = false

	# Death penalty: penalize_weapon_on_death
	player.set_weapon_level(4)
	var lost: int = player.penalize_weapon_on_death()
	if lost != 1 or player.get_weapon_level() != 3:
		push_error("penalize_weapon_on_death must reduce 4 to 3 and return 1 (got %d lost, %d level)" % [lost, player.get_weapon_level()])
		passed = false

	player.set_weapon_level(1)
	lost = player.penalize_weapon_on_death()
	if lost != 0 or player.get_weapon_level() != 1:
		push_error("penalize_weapon_on_death at level 1 must return 0 and keep level 1 (got %d lost, %d level)" % [lost, player.get_weapon_level()])
		passed = false

	player.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 3. Firing Patterns Across Weapon Levels
# ---------------------------------------------------------------------------

func _assert_firing_patterns_contract() -> bool:
	var packed: PackedScene = load(PLAYER_PATH) as PackedScene
	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame

	var passed: bool = true

	# Test Blaster bullet counts: Level 1..15 -> [1..10, 11, 12, 13, 14, 15]
	player.set_weapon(0) # BLASTER
	var expected_blaster_counts: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
	var blaster_damage_by_level: Dictionary = {}
	for lvl: int in range(1, 16):
		player.set_weapon_level(lvl)
		var pre_children: Array[Node] = root.get_children()
		player.simulate_shot()
		var spawned_bullets: Array[Node] = []
		for child: Node in root.get_children():
			if not (child in pre_children):
				spawned_bullets.append(child)
		if spawned_bullets.size() != expected_blaster_counts[lvl - 1]:
			push_error("Blaster level %d expected %d bullets, spawned %d" % [lvl, expected_blaster_counts[lvl - 1], spawned_bullets.size()])
			passed = false
		if not spawned_bullets.is_empty():
			blaster_damage_by_level[lvl] = int(spawned_bullets[0].get("damage"))

		# Direction checks: levels 1-3 all straight (direction.x == 0), level 4+ has diagonals (direction.x != 0)
		var has_diagonal: bool = false
		for b: Node in spawned_bullets:
			if "direction" in b:
				var dir: Vector2 = b.get("direction") as Vector2
				if absf(dir.x) > 0.001:
					has_diagonal = true
		if lvl < 4 and has_diagonal:
			push_error("Blaster level %d should only fire straight bullets, but diagonal was detected" % lvl)
			passed = false
		elif lvl >= 4 and not has_diagonal:
			push_error("Blaster level %d must have at least one diagonal projectile" % lvl)
			passed = false
		_cleanup_bullets()

	if int(blaster_damage_by_level.get(15, 0)) <= int(blaster_damage_by_level.get(10, 0)):
		push_error("Blaster L15 projectile damage must exceed L10 (L15 %d, L10 %d)" % [int(blaster_damage_by_level.get(15, 0)), int(blaster_damage_by_level.get(10, 0))])
		passed = false

	# Test Missile counts: Level 1..15 -> [1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8]
	player.set_weapon(1) # MISSILE
	var expected_missile_counts: Array[int] = [1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8]
	for lvl: int in range(1, 16):
		player.set_weapon_level(lvl)
		var pre_count: int = root.get_child_count()
		player.simulate_shot()
		var spawned: int = root.get_child_count() - pre_count
		if spawned != expected_missile_counts[lvl - 1]:
			push_error("Missile level %d expected %d missiles, spawned %d" % [lvl, expected_missile_counts[lvl - 1], spawned])
			passed = false
		_cleanup_bullets()

	# Test Laser scaling
	player.set_weapon(2) # LASER
	player.set_weapon_level(1)
	var beam: Area2D = player.call(&"_ensure_laser_beam")
	if beam == null:
		push_error("Laser beam Area2D missing")
		passed = false
	else:
		var width_lvl1: float = float(beam.get("beam_width"))
		player.set_weapon_level(10)
		var width_lvl10: float = float(beam.get("beam_width"))
		if width_lvl10 <= width_lvl1:
			push_error("Laser beam_width must scale with level (lvl1: %f, lvl10: %f)" % [width_lvl1, width_lvl10])
			passed = false
		var dps_lvl10: float = float(beam.get("damage_per_second"))
		player.set_weapon_level(15)
		var dps_lvl15: float = float(beam.get("damage_per_second"))
		if dps_lvl15 <= dps_lvl10:
			push_error("Laser DPS must grow from L10 to L15 (L10: %f, L15: %f)" % [dps_lvl10, dps_lvl15])
			passed = false

	# Preserve: levels 1-10 keep the original heat and missile cooldown; 11-15 reuse the L10 heat.
	player.set_weapon(0) # BLASTER
	player.set_weapon_level(1)
	if absf(player.get_heat_per_second(0) - 10.0) > 0.001:
		push_error("Blaster L1 heat per second must stay 10.0, got %f" % player.get_heat_per_second(0))
		passed = false
	player.set_weapon_level(10)
	if absf(player.get_heat_per_second(0) - 12.5) > 0.001:
		push_error("Blaster L10 heat per second must stay 12.5, got %f" % player.get_heat_per_second(0))
		passed = false
	player.set_weapon_level(15)
	if absf(player.get_heat_per_second(0) - 12.5) > 0.001:
		push_error("Blaster L15 heat per second must reuse L10 value 12.5, got %f" % player.get_heat_per_second(0))
		passed = false

	player.set_weapon(1) # MISSILE
	var cooldown_expected: Dictionary = {1: 0.55, 10: 0.35, 15: 0.28}
	for lvl: int in [1, 10, 15]:
		player.set_weapon_level(lvl)
		player.simulate_shot()
		var cooldown_timer: Timer = player.get_node("ShootCooldown") as Timer
		if absf(cooldown_timer.wait_time - float(cooldown_expected[lvl])) > 0.001:
			push_error("Missile L%d cooldown expected %f, got %f" % [lvl, float(cooldown_expected[lvl]), cooldown_timer.wait_time])
			passed = false
		_cleanup_bullets()

	player.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 3b. Ion Blaster lateral coverage (high levels) and Laser power above L10
# ---------------------------------------------------------------------------

## Public metric: horizontal position of a projectile after 300 px of vertical travel.
## Projectiles move along (sin(a), -cos(a)), so x300 = offset_x + 300 * tan(a).
const COVERAGE_TRAVEL_PX: float = 300.0
const CENTER_BAND_PX: float = 40.0


## Fires one blaster volley and returns [x300, angle_deg] per projectile, relative to the ship.
func _collect_blaster_volley(player: CharacterBody2D) -> Array[Vector2]:
	var pre_children: Array[Node] = root.get_children()
	player.simulate_shot()
	var volley: Array[Vector2] = []
	for child: Node in root.get_children():
		if child in pre_children or not (child is Area2D):
			continue
		var dir: Vector2 = child.get("direction") as Vector2
		var offset_x: float = (child as Area2D).global_position.x - player.global_position.x
		var tan_angle: float = dir.x / maxf(-dir.y, 0.0001)
		var x300: float = offset_x + COVERAGE_TRAVEL_PX * tan_angle
		volley.append(Vector2(x300, rad_to_deg(atan2(dir.x, -dir.y))))
		child.free()
	return volley


func _assert_blaster_lateral_coverage_contract() -> bool:
	var packed: PackedScene = load(PLAYER_PATH) as PackedScene
	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	player.global_position = Vector2(500.0, 800.0)
	player.set_weapon(0) # BLASTER

	var passed: bool = true
	# Level -> [expected shots, minimum |x300| required on each side]
	var cases: Dictionary = {10: [10, 140.0], 15: [15, 180.0]}
	for lvl: int in [10, 15]:
		var expected_count: int = int(cases[lvl][0])
		var min_side: float = float(cases[lvl][1])
		player.set_weapon_level(lvl)
		var volley: Array[Vector2] = _collect_blaster_volley(player)
		if volley.size() != expected_count:
			push_error("Blaster L%d coverage: expected %d shots, got %d" % [lvl, expected_count, volley.size()])
			passed = false
			continue

		var center_count: int = 0
		var max_left: float = 0.0
		var max_right: float = 0.0
		var max_angle: float = 0.0
		var xs: Array[float] = []
		for shot: Vector2 in volley:
			if absf(shot.x) <= CENTER_BAND_PX:
				center_count += 1
			max_left = minf(max_left, shot.x)
			max_right = maxf(max_right, shot.x)
			max_angle = maxf(max_angle, absf(shot.y))
			xs.append(shot.x)

		var center_share: float = float(center_count) / float(expected_count)
		if center_share > 0.35 + 0.0001:
			push_error("Blaster L%d: at most 35%% of shots may be central (|x300| <= 40), got %d of %d" % [lvl, center_count, expected_count])
			passed = false
		if absf(max_left) < min_side or max_right < min_side:
			push_error("Blaster L%d: needs shots on both sides with |x300| >= %.0f (left %.1f, right %.1f)" % [lvl, min_side, max_left, max_right])
			passed = false
		if max_angle > 45.0 + 0.001:
			push_error("Blaster L%d: max angle must be <= 45 deg, got %.2f" % [lvl, max_angle])
			passed = false

		# Mirror symmetry: sorted x300 values must equal their negated reversed list.
		xs.sort()
		for i: int in range(xs.size()):
			if absf(xs[i] + xs[xs.size() - 1 - i]) > 0.5:
				push_error("Blaster L%d: pattern must be mirror-symmetric (x300 %.1f vs %.1f)" % [lvl, xs[i], xs[xs.size() - 1 - i]])
				passed = false
				break

	player.queue_free()
	await process_frame
	return passed


func _assert_laser_high_level_power_contract() -> bool:
	var packed: PackedScene = load(PLAYER_PATH) as PackedScene
	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	player.set_weapon(2) # LASER

	var passed: bool = true
	var expected_dps: Dictionary = {9: 18.5, 10: 20.5, 11: 25.0, 15: 43.0}
	var widths: Dictionary = {}
	for lvl: int in [9, 10, 11, 15]:
		player.set_weapon_level(lvl)
		var beam: Area2D = player.call(&"_ensure_laser_beam") as Area2D
		if beam == null:
			push_error("Laser beam missing at L%d" % lvl)
			passed = false
			break
		var dps: float = float(beam.get("damage_per_second"))
		widths[lvl] = float(beam.get("beam_width"))
		if absf(dps - float(expected_dps[lvl])) > 0.001:
			push_error("Laser L%d DPS expected %.2f, got %.2f" % [lvl, float(expected_dps[lvl]), dps])
			passed = false

	if widths.has(15) and widths.has(10):
		if float(widths[15]) <= float(widths[10]):
			push_error("Laser L15 beam_width must exceed L10 (L15 %.2f, L10 %.2f)" % [float(widths[15]), float(widths[10])])
			passed = false
		if absf(float(widths[15]) - 38.8) > 0.001:
			push_error("Laser L15 beam_width expected 38.8, got %.2f" % float(widths[15]))
			passed = false

	player.queue_free()
	await process_frame
	return passed


func _cleanup_bullets() -> void:
	for child: Node in root.get_children():
		if child.is_in_group(&"player_bullets") or child.is_in_group(&"combat_transients") or child.name.begins_with("Bullet") or child.name.begins_with("Spread") or child.name.begins_with("Missile"):
			child.queue_free()


# ---------------------------------------------------------------------------
# 4. HUD Diegetic & Clean Minimalist Interface Contract
# ---------------------------------------------------------------------------

func _assert_hud_contract() -> bool:
	if not ResourceLoader.exists(HUD_PATH):
		push_error("Missing HUD scene: %s" % HUD_PATH)
		return false

	var packed: PackedScene = load(HUD_PATH) as PackedScene
	var hud: CanvasLayer = packed.instantiate() as CanvasLayer
	root.add_child(hud)
	await process_frame

	var passed: bool = true

	# Chicken Invaders diegetic HUD: WeaponLevelContainer and WeaponSelectorContainer are removed.
	if hud.get_node_or_null("WeaponSelectorContainer") != null:
		push_error("HUD should not contain obsolete WeaponSelectorContainer")
		passed = false
	if hud.get_node_or_null("WeaponLevelContainer") != null:
		push_error("HUD should not contain obsolete WeaponLevelContainer; weapon power is diegetic")
		passed = false

	# API methods must exist for backwards compatibility without error
	if not hud.has_method(&"set_weapon_level") or not hud.has_method(&"set_active_weapon"):
		push_error("HUD missing backward compatible set_weapon_level or set_active_weapon methods")
		passed = false
	else:
		hud.set_weapon_level(4, 0)
		hud.set_active_weapon(2)

	# Essential combat HUD elements must remain active
	if hud.find_child("LivesLabel", true, false) == null:
		push_error("HUD missing LivesLabel")
		passed = false
	if hud.find_child("ScoreLabel", true, false) == null:
		push_error("HUD missing ScoreLabel")
		passed = false
	if hud.find_child("WaveLabel", true, false) == null:
		push_error("HUD missing WaveLabel")
		passed = false
	if hud.find_child("HeatContainer", true, false) == null:
		push_error("HUD missing HeatContainer")
		passed = false

	hud.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 5. Extra Life Milestone Contract
# ---------------------------------------------------------------------------

func _assert_extra_life_contract() -> bool:
	if not ResourceLoader.exists(MAIN_PATH):
		push_error("Missing Main scene: %s" % MAIN_PATH)
		return false

	var packed: PackedScene = load(MAIN_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	root.add_child(main)
	await process_frame

	var passed: bool = true

	# Reset session to clean state
	main.reset_session()
	var initial_lives: int = int(main.get("lives"))

	# Cross 1,000,000 threshold
	main.set("score", 1_050_000)
	main.call(&"_check_score_milestones")
	var new_lives: int = int(main.get("lives"))
	if new_lives != initial_lives + 1:
		push_error("Reaching 1M points must award +1 life (initial %d, got %d)" % [initial_lives, new_lives])
		passed = false

	# Check duplicate check does not double-award
	main.call(&"_check_score_milestones")
	if int(main.get("lives")) != new_lives:
		push_error("Re-checking same score milestone should not duplicate extra lives")
		passed = false

	# Cross 2,000,000 threshold
	main.set("score", 2_100_000)
	main.call(&"_check_score_milestones")
	if int(main.get("lives")) != initial_lives + 2:
		push_error("Reaching 2M points must award +2 total extra lives")
		passed = false

	main.queue_free()
	await process_frame
	return passed


# ---------------------------------------------------------------------------
# 6. Main Integration Contract: Medallions, Death Recovery Capsule, Reset
# ---------------------------------------------------------------------------

func _assert_main_integration_contract() -> bool:
	var packed: PackedScene = load(MAIN_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	root.add_child(main)
	await process_frame

	var passed: bool = true
	main.reset_session()

	var player: CharacterBody2D = main.get_node_or_null("Player") as CharacterBody2D
	if player == null:
		push_error("Main missing Player node")
		passed = false
		main.queue_free()
		return false

	# Test collecting Medallions upgrades player
	player.set_weapon(0)
	player.set_weapon_level(1)
	main.call(&"_on_loot_collected", LootDrop.Type.MEDALLION_BLASTER)
	if player.get_weapon_level() != 2:
		push_error("Main _on_loot_collected(MEDALLION_BLASTER) failed to upgrade player to level 2 (got %d)" % player.get_weapon_level())
		passed = false

	# Test Power Atom
	main.call(&"_on_loot_collected", LootDrop.Type.POWER_ATOM)
	if player.get_weapon_level() != 3:
		push_error("Main _on_loot_collected(POWER_ATOM) failed to upgrade player to level 3 (got %d)" % player.get_weapon_level())
		passed = false

	# Test player damage generates Recovery Capsule when level > 1
	var pre_child_count: int = main.get_child_count()
	main.call(&"_on_player_damage_requested")
	# Level should be penalized from 3 to 2
	if player.get_weapon_level() != 2:
		push_error("Player level after death must be penalized to 2, got %d" % player.get_weapon_level())
		passed = false

	# Check for spawned recovery capsule
	var found_capsule: bool = false
	for child: Node in main.get_children():
		if child is LootDrop and (child as LootDrop).get_type() == LootDrop.Type.RECOVERY_CAPSULE:
			found_capsule = true
			if (child as LootDrop).get_lifetime() != 3.0:
				push_error("Spawned recovery capsule must have 3.0s lifetime")
				passed = false
			break

	if not found_capsule:
		push_error("Main must spawn a RECOVERY_CAPSULE when player dies with level > 1")
		passed = false

	# Test reset_session resets weapon level to 1
	main.reset_session()
	if player.get_weapon_level() != 1:
		push_error("reset_session must reset weapon_level to 1, got %d" % player.get_weapon_level())
		passed = false

	main.queue_free()
	await process_frame
	return passed
