# etapa_12_5_contract_test.gd
# Contract test harness for Etapa 12.5: weapon evolution after the enemy AI update (ADR 010).
# Verifies:
# 1. Blaster damage per projectile scales with level (1 / 2 / 3) and volley damage is monotonic.
# 2. Missile damage and splash radius scale with level; splash hits neighbours at reduced damage.
# 3. Laser damage per second keeps scaling and bypasses the armored deflector.
# 4. Time-to-kill per tactical variant stays within target windows for every weapon.
# 5. Loot weights let the expected weapon level reach 5 around waves 5-6 without saturating before wave 10.

extends SceneTree

const PLAYER_PATH := "res://features/player/player.tscn"
const ENEMY_PATH := "res://features/enemy/enemy.tscn"
const MISSILE_PATH := "res://features/bullet/missile.tscn"
const LASER_PATH := "res://features/bullet/laser_beam.tscn"
const SPAWNER_PATH := "res://features/spawning/enemy_spawner.tscn"
const MAIN_SCRIPT_PATH := "res://scenes/main/main.gd"

const PLAYER_X: float = 500.0
const ENEMY_POS: Vector2 = Vector2(500.0, 200.0)
const BLASTER_COOLDOWN: float = 0.25
const LANE_HALF_WIDTH: float = 14.0
const COLLECTION_EFFICIENCY: float = 0.75


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var results: Array[bool] = [
		await _assert_blaster_damage_scaling(),
		await _assert_missile_scaling_and_splash(),
		await _assert_laser_scaling_and_deflector_bypass(),
		await _assert_time_to_kill_windows(),
		await _assert_loot_progression_pacing(),
	]
	var all_passed: bool = not results.has(false)
	if all_passed:
		print("ETAPA 12.5 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 12.5 CONTRACT TESTS: FAILURES DETECTED")
	quit(0 if all_passed else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition


func _make_player() -> Node2D:
	var player: Node2D = (load(PLAYER_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(player)
	player.global_position = Vector2(PLAYER_X, 800.0)
	return player


func _make_enemy(variant: StringName, pos: Vector2 = ENEMY_POS) -> Area2D:
	var enemy: Area2D = (load(ENEMY_PATH) as PackedScene).instantiate() as Area2D
	enemy.call(&"apply_variant", variant)
	root.add_child(enemy)
	enemy.global_position = pos
	return enemy


## Fires one player shot and returns the projectiles it added to the scene root.
func _fire_and_collect(player: Node2D) -> Array[Area2D]:
	var before: Array[Node] = root.get_children()
	player.call(&"simulate_shot")
	var spawned: Array[Area2D] = []
	for node: Node in root.get_children():
		if before.has(node) or not (node is Area2D):
			continue
		spawned.append(node as Area2D)
	return spawned


func _free_all(nodes: Array[Area2D]) -> void:
	for node: Area2D in nodes:
		if is_instance_valid(node):
			node.free()


# ---------------------------------------------------------------------------
# 1. Blaster damage scaling
# ---------------------------------------------------------------------------

func _assert_blaster_damage_scaling() -> bool:
	var ok: bool = true
	var player: Node2D = _make_player()
	await process_frame
	player.call(&"set_weapon", 0)

	var expected: Array[int] = [1, 1, 1, 1, 2, 2, 2, 2, 3, 3]
	var prev_volley: int = 0
	for lvl: int in range(1, 11):
		player.call(&"set_weapon_level", lvl)
		var shots: Array[Area2D] = _fire_and_collect(player)
		var volley_damage: int = 0
		for bullet: Area2D in shots:
			var dmg: int = int(bullet.get("damage"))
			ok = _check(dmg == expected[lvl - 1], "Blaster L%d projectile damage must be %d, got %d" % [lvl, expected[lvl - 1], dmg]) and ok
			volley_damage += dmg
		ok = _check(volley_damage > prev_volley, "Blaster volley damage must increase at L%d (%d <= %d)" % [lvl, volley_damage, prev_volley]) and ok
		prev_volley = volley_damage
		_free_all(shots)

	# Level 1 stays as in the original contract (SpreadBullet default damage = 1).
	var bullet_default: Area2D = (load("res://features/bullet/spread_bullet.tscn") as PackedScene).instantiate() as Area2D
	ok = _check(int(bullet_default.get("damage")) == 1, "SpreadBullet default damage must stay 1") and ok
	bullet_default.free()

	# Frontal deflector still attenuates scaled bullets: L9 bullet (3) x 0.35 = 1.05.
	player.call(&"set_weapon_level", 9)
	var armored: Area2D = _make_enemy(&"armored_fighter")
	var shots9: Array[Area2D] = _fire_and_collect(player)
	shots9[0].call(&"_on_area_entered", armored)
	var lost: float = 3.0 - float(armored.get("health"))
	ok = _check(absf(lost - 1.05) < 0.01, "L9 blaster vs deflector should deal 1.05, dealt %f" % lost) and ok
	_free_all(shots9)
	armored.free()
	player.free()
	return ok


# ---------------------------------------------------------------------------
# 2. Missile scaling and splash
# ---------------------------------------------------------------------------

func _assert_missile_scaling_and_splash() -> bool:
	var ok: bool = true
	var packed: PackedScene = load(MISSILE_PATH) as PackedScene

	var default_missile: Area2D = packed.instantiate() as Area2D
	ok = _check(int(default_missile.get("damage")) == 3, "Missile default damage must stay 3") and ok
	default_missile.free()

	var prev_damage: int = 0
	var prev_radius: float = 0.0
	for lvl: int in range(1, 11):
		var missile: Area2D = packed.instantiate() as Area2D
		ok = _check(missile.has_method(&"set_power_level"), "Missile must expose set_power_level()") and ok
		missile.call(&"set_power_level", lvl)
		var dmg: int = int(missile.get("damage"))
		var radius: float = float(missile.get("explosion_radius"))
		ok = _check(dmg == 3 + lvl / 2, "Missile L%d damage must be %d, got %d" % [lvl, 3 + lvl / 2, dmg]) and ok
		ok = _check(dmg >= prev_damage, "Missile damage must not decrease at L%d" % lvl) and ok
		ok = _check(radius > prev_radius, "Missile explosion radius must grow at L%d" % lvl) and ok
		ok = _check(radius >= 30.0 and radius <= 100.0, "Missile radius must stay small (30-100 px), got %f" % radius) and ok
		prev_damage = dmg
		prev_radius = radius
		missile.free()

	# Player-fired missiles carry the current level.
	var player: Node2D = _make_player()
	await process_frame
	player.call(&"set_weapon", 1)
	player.call(&"set_weapon_level", 6)
	var shots: Array[Area2D] = _fire_and_collect(player)
	ok = _check(shots.size() == 4, "Missile L6 fires 4 missiles, got %d" % shots.size()) and ok
	for m: Area2D in shots:
		ok = _check(int(m.get("damage")) == 6, "Player missile L6 damage must be 6, got %d" % int(m.get("damage"))) and ok
	_free_all(shots)
	player.free()

	# Splash: direct target takes full damage, neighbours inside the radius take 50 %.
	var origin: Vector2 = Vector2(300.0, 300.0)
	var direct: Area2D = _make_enemy(&"assault_frigate", origin)
	var near: Area2D = _make_enemy(&"assault_frigate", origin + Vector2(20.0, 0.0))
	var far: Area2D = _make_enemy(&"assault_frigate", origin + Vector2(300.0, 0.0))
	var missile1: Area2D = packed.instantiate() as Area2D
	root.add_child(missile1)
	missile1.global_position = origin
	missile1.call(&"set_power_level", 1)
	missile1.call(&"_on_area_entered", direct)
	ok = _check(absf(float(direct.get("health")) - 5.0) < 0.01, "Direct missile hit must deal 3 (hp 8 -> 5), hp=%f" % float(direct.get("health"))) and ok
	ok = _check(absf(float(near.get("health")) - 6.5) < 0.01, "Splash must deal 1.5 to a neighbour, hp=%f" % float(near.get("health"))) and ok
	ok = _check(is_equal_approx(float(far.get("health")), 8.0), "Enemies outside the radius must not take splash") and ok

	# A level 10 missile reaches an enemy that a level 1 missile cannot.
	var mid: Area2D = _make_enemy(&"assault_frigate", origin + Vector2(70.0, 0.0))
	var direct2: Area2D = _make_enemy(&"assault_frigate", origin + Vector2(0.0, 5.0))
	var missile10: Area2D = packed.instantiate() as Area2D
	root.add_child(missile10)
	missile10.global_position = origin
	missile10.call(&"set_power_level", 10)
	missile10.call(&"_on_area_entered", direct2)
	ok = _check(float(mid.get("health")) < 8.0, "Level 10 splash must reach enemies 70 px away") and ok
	ok = _check(is_equal_approx(float(far.get("health")), 8.0), "Level 10 splash must not reach 300 px away") and ok
	ok = _check(not is_instance_valid(missile1) or missile1.is_queued_for_deletion(), "Missile must be consumed on impact") and ok

	for enemy: Area2D in [direct, near, far, mid, direct2]:
		if is_instance_valid(enemy):
			enemy.free()
	if is_instance_valid(missile1):
		missile1.free()
	if is_instance_valid(missile10):
		missile10.free()
	return ok


# ---------------------------------------------------------------------------
# 3. Laser scaling and deflector bypass
# ---------------------------------------------------------------------------

func _assert_laser_scaling_and_deflector_bypass() -> bool:
	var ok: bool = true
	var laser: Area2D = (load(LASER_PATH) as PackedScene).instantiate() as Area2D
	root.add_child(laser)
	await process_frame

	laser.call(&"set_power_level", 1)
	ok = _check(is_equal_approx(float(laser.get("damage_per_second")), 2.5), "Laser L1 DPS must stay 2.5") and ok
	var prev: float = 0.0
	for lvl: int in range(1, 11):
		laser.call(&"set_power_level", lvl)
		var dps: float = float(laser.get("damage_per_second"))
		ok = _check(dps > prev, "Laser DPS must grow at L%d" % lvl) and ok
		prev = dps
	ok = _check(prev >= 20.0, "Laser L10 DPS must be >= 20 to threaten frigates, got %f" % prev) and ok

	# Deflector bypass: one tick deals the full tick amount to an armored fighter.
	laser.call(&"set_power_level", 5)
	laser.global_position = Vector2(500.0, 600.0)
	var armored: Area2D = _make_enemy(&"armored_fighter")
	laser.call(&"set_firing", true)
	var tick: float = float(laser.get("damage_per_second")) * float(laser.get("damage_tick_rate"))
	laser.call(&"_process", float(laser.get("damage_tick_rate")) + 0.001)
	var lost: float = 3.0 - float(armored.get("health"))
	ok = _check(absf(lost - tick) < 0.01, "Laser must bypass the deflector (tick %f, dealt %f)" % [tick, lost]) and ok
	laser.free()
	armored.free()
	return ok


# ---------------------------------------------------------------------------
# 4. Time-to-kill windows
# ---------------------------------------------------------------------------

## Seconds to kill one variant with the blaster, counting only shots aligned with the enemy lane.
func _blaster_ttk(player: Node2D, variant: StringName, level: int) -> float:
	player.call(&"set_weapon", 0)
	player.call(&"set_weapon_level", level)
	var enemy: Area2D = _make_enemy(variant)
	var volleys: int = 0
	while not bool(enemy.get("_destroyed")) and volleys < 100:
		var shots: Array[Area2D] = _fire_and_collect(player)
		for bullet: Area2D in shots:
			var dir: Vector2 = bullet.get("direction") as Vector2
			var in_lane: bool = absf(bullet.global_position.x - PLAYER_X) <= LANE_HALF_WIDTH and absf(dir.x) < 0.01
			if in_lane and not bool(enemy.get("_destroyed")):
				bullet.call(&"_on_area_entered", enemy)
		_free_all(shots)
		volleys += 1
	if is_instance_valid(enemy):
		enemy.free()
	return float(volleys) * BLASTER_COOLDOWN


## Seconds to kill one variant with a missile volley (all missiles home on the target).
func _missile_ttk(player: Node2D, variant: StringName, level: int) -> float:
	player.call(&"set_weapon", 1)
	player.call(&"set_weapon_level", level)
	var enemy: Area2D = _make_enemy(variant)
	var cooldown: float = lerpf(0.55, 0.35, float(level - 1) / 9.0)
	var volleys: int = 0
	while not bool(enemy.get("_destroyed")) and volleys < 100:
		var shots: Array[Area2D] = _fire_and_collect(player)
		for missile: Area2D in shots:
			if not bool(enemy.get("_destroyed")):
				missile.call(&"_on_area_entered", enemy)
		_free_all(shots)
		volleys += 1
	if is_instance_valid(enemy):
		enemy.free()
	return float(volleys) * cooldown


func _laser_ttk(variant: StringName, level: int) -> float:
	var laser: Area2D = (load(LASER_PATH) as PackedScene).instantiate() as Area2D
	laser.call(&"set_power_level", level)
	var enemy: Area2D = _make_enemy(variant)
	var tick_rate: float = float(laser.get("damage_tick_rate"))
	var amount: float = float(laser.get("damage_per_second")) * tick_rate
	var ticks: int = 0
	while not bool(enemy.get("_destroyed")) and ticks < 1000:
		enemy.call(&"take_damage", amount)
		ticks += 1
	if is_instance_valid(enemy):
		enemy.free()
	laser.free()
	return float(ticks) * tick_rate


func _assert_time_to_kill_windows() -> bool:
	var ok: bool = true
	var player: Node2D = _make_player()
	await process_frame
	var tough: Array[StringName] = [&"armored_fighter", &"assault_frigate"]
	var light: Array[StringName] = [&"standard", &"scout_drone", &"suicide_interceptor"]

	for variant: StringName in tough:
		# Blaster: from level 5 the tough variants die within two volleys (0.5 s).
		for lvl: int in [5, 7, 9, 10]:
			var t: float = _blaster_ttk(player, variant, lvl)
			ok = _check(t <= 0.5 + 0.001, "Blaster L%d vs %s TTK must be <= 0.5 s, got %f" % [lvl, variant, t]) and ok
		var t1: float = _blaster_ttk(player, variant, 1)
		var t5: float = _blaster_ttk(player, variant, 5)
		ok = _check(t5 < t1, "Blaster L5 must kill %s faster than L1 (%f vs %f)" % [variant, t5, t1]) and ok

		# Missile: tough variants die to a single volley from level 4.
		for lvl: int in [4, 5, 8, 10]:
			var tm: float = _missile_ttk(player, variant, lvl)
			var cd: float = lerpf(0.55, 0.35, float(lvl - 1) / 9.0)
			ok = _check(tm <= cd + 0.001, "Missile L%d vs %s must need a single volley, got %f" % [lvl, variant, tm]) and ok

		# Laser: bypasses the deflector, so even level 1 is bounded and level 5+ is quick.
		var tl1: float = _laser_ttk(variant, 1)
		var tl5: float = _laser_ttk(variant, 5)
		var tl10: float = _laser_ttk(variant, 10)
		ok = _check(tl1 <= 3.5, "Laser L1 vs %s TTK must be <= 3.5 s, got %f" % [variant, tl1]) and ok
		ok = _check(tl5 <= 1.0, "Laser L5 vs %s TTK must be <= 1.0 s, got %f" % [variant, tl5]) and ok
		ok = _check(tl10 <= 0.5 + 0.001, "Laser L10 vs %s TTK must be <= 0.5 s, got %f" % [variant, tl10]) and ok

	for variant: StringName in light:
		for lvl: int in [1, 5, 10]:
			var tb: float = _blaster_ttk(player, variant, lvl)
			ok = _check(tb <= 0.5 + 0.001, "Blaster L%d vs %s must kill in <= 2 volleys, got %f" % [lvl, variant, tb]) and ok
	player.free()
	return ok


# ---------------------------------------------------------------------------
# 5. Loot progression pacing
# ---------------------------------------------------------------------------

func _assert_loot_progression_pacing() -> bool:
	var ok: bool = true
	var main_script: GDScript = load(MAIN_SCRIPT_PATH) as GDScript
	var main_node: Node = main_script.new() as Node
	var chance: float = float(main_node.get("enemy_loot_drop_chance"))
	var basic: float = (
		float(main_node.get("score_loot_weight")) + float(main_node.get("double_shot_loot_weight"))
		+ float(main_node.get("shield_loot_weight")) + float(main_node.get("extra_life_loot_weight"))
		+ float(main_node.get("bomb_loot_weight"))
	)
	var weapon: float = (
		float(main_node.get("medallion_blaster_weight")) + float(main_node.get("medallion_missile_weight"))
		+ float(main_node.get("medallion_laser_weight")) + float(main_node.get("power_atom_weight"))
	)
	main_node.free()
	var weapon_share: float = weapon / (basic + weapon)
	# 55 % of weapon drops are level-ups (active medallion or atom); the rest switch weapons.
	# Only ~75 % of drops are collected in practice, and each death costs one level.
	var upgrade_per_kill: float = chance * weapon_share * 0.55 * COLLECTION_EFFICIENCY

	var spawner: Node = (load(SPAWNER_PATH) as PackedScene).instantiate()
	root.add_child(spawner)
	await process_frame
	var kills: float = 0.0
	var level_after_wave: Array[float] = []
	for wave: int in range(int(spawner.call(&"get_total_waves"))):
		var cfg: Dictionary = spawner.call(&"get_wave_config", wave)
		kills += float(int(cfg["rows"]) * int(cfg["columns"]))
		level_after_wave.append(1.0 + upgrade_per_kill * kills)
	spawner.free()

	ok = _check(level_after_wave[4] >= 3.5, "Expected level after wave 5 must be >= 3.5, got %f" % level_after_wave[4]) and ok
	ok = _check(level_after_wave[5] >= 4.5, "Expected level after wave 6 must be >= 4.5 (about L5), got %f" % level_after_wave[5]) and ok
	ok = _check(level_after_wave[8] < 10.0, "Weapon level must not saturate before wave 10, got %f after wave 9" % level_after_wave[8]) and ok
	return ok
