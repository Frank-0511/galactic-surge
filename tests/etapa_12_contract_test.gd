# etapa_12_contract_test.gd
# Contract test harness for Etapa 12: Enemigos con IA y Variantes Tacticas.
# Verifies:
# 1. Variant catalog: HP ranges, deflector, burst, swarm and suicide parameters.
# 2. Enemy.apply_variant(): health, scale and AI component wiring (standard unchanged).
# 3. Frontal deflector: attenuates frontal hits, flanks and laser (take_damage) bypass it.
# 4. EnemyAI FSM: PATROL -> DETECT -> ATTACK -> FLEE -> PATROL with state_changed signal.
# 5. Slow projectile evasion (pure maths and enemy integration with a missile).
# 6. Swarm separation/cohesion steering.
# 7. Assault frigate burst fire and AI flee displacement.
# 8. Suicide interceptor charge and direct collision.
# 9. EnemySpawner integration: variants per wave, formation size preserved.

extends SceneTree

const ENEMY_PATH := "res://scenes/entities/enemy/enemy.tscn"
const MISSILE_PATH := "res://features/bullet/missile.tscn"
const SPAWNER_PATH := "res://scenes/systems/enemy_spawner.tscn"
const EnemyAIScript: Script = preload("res://scripts/components/enemy_ai.gd")
const EnemyVariantsScript: Script = preload("res://scripts/systems/enemy_variants.gd")

var _transitions: Array = []


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var results: Array[bool] = [
		_assert_variant_catalog(),
		await _assert_apply_variant(),
		await _assert_deflector(),
		_assert_fsm_transitions(),
		_assert_evasion_math(),
		await _assert_evasion_integration(),
		_assert_swarm_steering(),
		await _assert_frigate_burst_and_flee(),
		await _assert_suicide_interceptor(),
		await _assert_spawner_integration(),
	]
	var all_passed: bool = not results.has(false)
	if all_passed:
		print("ETAPA 12 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 12 CONTRACT TESTS: FAILURES DETECTED")
	quit(0 if all_passed else 1)


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
	return condition


func _spawn_enemy(variant: StringName) -> Area2D:
	var enemy: Area2D = (load(ENEMY_PATH) as PackedScene).instantiate() as Area2D
	enemy.call(&"apply_variant", variant)
	root.add_child(enemy)
	return enemy


# ---------------------------------------------------------------------------
# 1. Catalog
# ---------------------------------------------------------------------------

func _assert_variant_catalog() -> bool:
	var ok: bool = true
	for id: StringName in [&"standard", &"armored_fighter", &"assault_frigate", &"scout_drone", &"suicide_interceptor"]:
		ok = _check(EnemyVariantsScript.has_variant(id), "Missing variant: %s" % id) and ok
	var armored: Dictionary = EnemyVariantsScript.get_definition(&"armored_fighter")
	ok = _check(float(armored["max_health"]) >= 3.0 and float(armored["max_health"]) <= 5.0, "Armored fighter HP must be 3-5") and ok
	ok = _check(bool(armored["deflector"]), "Armored fighter must have a deflector") and ok
	var frigate: Dictionary = EnemyVariantsScript.get_definition(&"assault_frigate")
	ok = _check(float(frigate["max_health"]) >= 8.0 and float(frigate["max_health"]) <= 12.0, "Assault frigate HP must be 8-12") and ok
	ok = _check(int(frigate["burst_count"]) >= 3, "Assault frigate must fire bursts of 3+") and ok
	var drone: Dictionary = EnemyVariantsScript.get_definition(&"scout_drone")
	ok = _check(is_equal_approx(float(drone["max_health"]), 1.0), "Scout drone must have 1 HP") and ok
	ok = _check(bool(drone["swarm"]) and float(drone["evasion_speed"]) > 100.0, "Scout drone must swarm and be agile") and ok
	var interceptor: Dictionary = EnemyVariantsScript.get_definition(&"suicide_interceptor")
	ok = _check(bool(interceptor["suicide"]) and float(interceptor["charge_speed"]) >= 350.0, "Interceptor must be suicide and fast") and ok
	ok = _check(EnemyVariantsScript.get_definition(&"nope").is_empty(), "Unknown variant must return empty definition") and ok
	return ok


# ---------------------------------------------------------------------------
# 2. apply_variant
# ---------------------------------------------------------------------------

func _assert_apply_variant() -> bool:
	var ok: bool = true
	var standard: Area2D = (load(ENEMY_PATH) as PackedScene).instantiate() as Area2D
	root.add_child(standard)
	await process_frame
	ok = _check(is_equal_approx(standard.health, 1.0) and standard.get_ai() == null, "Standard enemy must stay 1 HP without AI") and ok
	ok = _check(not standard.has_deflector(), "Standard enemy must not have a deflector") and ok
	standard.queue_free()

	var frigate: Area2D = _spawn_enemy(&"assault_frigate")
	await process_frame
	ok = _check(is_equal_approx(frigate.health, frigate.max_health) and frigate.max_health >= 8.0, "Frigate health must match max_health") and ok
	ok = _check(frigate.get_ai() != null, "Frigate must own an AI component") and ok
	ok = _check(frigate.scale.x > 1.2, "Frigate must be visually larger") and ok
	ok = _check(frigate.get_variant_id() == &"assault_frigate", "Variant id must be exposed") and ok
	frigate.queue_free()
	return ok


# ---------------------------------------------------------------------------
# 3. Deflector
# ---------------------------------------------------------------------------

func _assert_deflector() -> bool:
	var ok: bool = true
	var enemy: Area2D = _spawn_enemy(&"armored_fighter")
	await process_frame
	var deflected: Array = [0.0]
	enemy.connect(&"deflected", func(amount: float) -> void: deflected[0] += amount)

	var start: float = enemy.health
	enemy.call(&"take_damage_from", 1.0, Vector2.UP) # frontal shot from below
	var frontal_loss: float = start - enemy.health
	ok = _check(frontal_loss > 0.0 and frontal_loss < 0.5, "Frontal hit must be attenuated (lost %f)" % frontal_loss) and ok
	ok = _check(deflected[0] > 0.5, "Deflected signal must report absorbed damage") and ok

	var before_flank: float = enemy.health
	enemy.call(&"take_damage_from", 1.0, Vector2.LEFT) # lateral shot from the right flank
	ok = _check(is_equal_approx(before_flank - enemy.health, 1.0), "Flank hit must deal full damage") and ok

	var before_laser: float = enemy.health
	enemy.call(&"take_damage", 0.5) # continuous laser path
	ok = _check(is_equal_approx(before_laser - enemy.health, 0.5), "Laser (take_damage) must bypass the deflector") and ok

	var plain: Area2D = _spawn_enemy(&"scout_drone")
	await process_frame
	ok = _check(is_equal_approx(plain.call(&"get_deflector_multiplier", Vector2.UP), 1.0), "Non-deflector variants take full damage") and ok
	plain.queue_free()
	enemy.queue_free()
	return ok


# ---------------------------------------------------------------------------
# 4. FSM
# ---------------------------------------------------------------------------

func _on_state_changed(previous_state: int, new_state: int) -> void:
	_transitions.append([previous_state, new_state])


func _assert_fsm_transitions() -> bool:
	var ok: bool = true
	var ai: RefCounted = EnemyAIScript.new()
	ai.configure({"detect_range": 400.0, "attack_range": 300.0, "detect_time": 0.5, "attack_duration": 2.0, "flee_health_ratio": 0.3, "flee_duration": 1.0})
	_transitions.clear()
	ai.state_changed.connect(_on_state_changed)
	var pos: Vector2 = Vector2(0, 0)

	ok = _check(ai.get_state() == EnemyAIScript.State.PATROL, "AI must start in PATROL") and ok
	ai.update(0.1, pos, Vector2(0, 900), 1.0)
	ok = _check(ai.get_state() == EnemyAIScript.State.PATROL, "Distant target must not trigger DETECT") and ok
	ai.update(0.1, pos, null, 1.0)
	ok = _check(ai.get_state() == EnemyAIScript.State.PATROL, "Missing target must keep PATROL") and ok

	ai.update(0.1, pos, Vector2(0, 250), 1.0)
	ok = _check(ai.get_state() == EnemyAIScript.State.DETECT, "Nearby target must trigger DETECT") and ok
	ai.update(0.2, pos, Vector2(0, 250), 1.0)
	ok = _check(ai.get_state() == EnemyAIScript.State.DETECT, "DETECT must last detect_time") and ok
	ai.update(0.4, pos, Vector2(0, 250), 1.0)
	ok = _check(ai.get_state() == EnemyAIScript.State.ATTACK, "DETECT must progress to ATTACK") and ok

	ai.update(0.1, pos, Vector2(0, 250), 0.2)
	ok = _check(ai.get_state() == EnemyAIScript.State.FLEE, "Low health must trigger FLEE") and ok
	ai.update(1.1, pos, Vector2(0, 250), 0.2)
	ok = _check(ai.get_state() == EnemyAIScript.State.PATROL, "FLEE must end back in PATROL") and ok
	ai.update(0.1, pos, Vector2(0, 250), 0.2)
	ok = _check(ai.get_state() == EnemyAIScript.State.DETECT, "Flee must trigger only once (no re-flee)") and ok

	var expected: Array = [[0, 1], [1, 2], [2, 3], [3, 0], [0, 1]]
	ok = _check(_transitions == expected, "state_changed sequence mismatch: %s" % str(_transitions)) and ok

	# Target lost during ATTACK and attack timeout both return to PATROL.
	var ai2: RefCounted = EnemyAIScript.new()
	ai2.configure({"detect_range": 400.0, "attack_range": 300.0, "detect_time": 0.1, "attack_duration": 1.0})
	ai2.update(0.1, pos, Vector2(0, 200), 1.0)
	ai2.update(0.2, pos, Vector2(0, 200), 1.0)
	ok = _check(ai2.get_state() == EnemyAIScript.State.ATTACK, "ai2 must reach ATTACK") and ok
	ai2.update(0.1, pos, Vector2(0, 900), 1.0)
	ok = _check(ai2.get_state() == EnemyAIScript.State.PATROL, "Losing the target must return to PATROL") and ok
	return ok


# ---------------------------------------------------------------------------
# 5. Evasion
# ---------------------------------------------------------------------------

func _assert_evasion_math() -> bool:
	var ok: bool = true
	var enemy_pos: Vector2 = Vector2(500, 300)
	var slow_missile: Dictionary = {"position": Vector2(505, 480), "velocity": Vector2(0, -300)}
	var dir: float = EnemyAIScript.compute_evasion_direction(enemy_pos, [slow_missile])
	ok = _check(dir != 0.0, "Slow missile on a collision course must trigger a dodge") and ok
	ok = _check(dir < 0.0, "Dodge must move away from the missile line (missile right of enemy -> go left)") and ok

	var offset_missile: Dictionary = {"position": Vector2(700, 480), "velocity": Vector2(0, -300)}
	ok = _check(EnemyAIScript.compute_evasion_direction(enemy_pos, [offset_missile]) == 0.0, "Laterally offset missile must be ignored") and ok
	var fast_bullet: Dictionary = {"position": Vector2(500, 480), "velocity": Vector2(0, -900)}
	ok = _check(EnemyAIScript.compute_evasion_direction(enemy_pos, [fast_bullet]) == 0.0, "Fast bullets are not dodgeable") and ok
	var receding: Dictionary = {"position": Vector2(500, 480), "velocity": Vector2(0, 300)}
	ok = _check(EnemyAIScript.compute_evasion_direction(enemy_pos, [receding]) == 0.0, "Receding projectiles must be ignored") and ok
	var far_missile: Dictionary = {"position": Vector2(500, 900), "velocity": Vector2(0, -300)}
	ok = _check(EnemyAIScript.compute_evasion_direction(enemy_pos, [far_missile]) == 0.0, "Distant missiles must be ignored") and ok
	return ok


func _assert_evasion_integration() -> bool:
	var ok: bool = true
	var drone: Area2D = _spawn_enemy(&"scout_drone")
	drone.global_position = Vector2(500, 300)
	await process_frame
	drone.global_position = Vector2(500, 300)

	var missile: Area2D = (load(MISSILE_PATH) as PackedScene).instantiate() as Area2D
	root.add_child(missile)
	missile.set_process(false)
	missile.global_position = Vector2(505, 480)
	await process_frame
	ok = _check(missile.is_in_group(&"player_bullets"), "Missile must be in player_bullets group") and ok
	ok = _check(missile.has_method(&"get_projectile_velocity"), "Missile must expose get_projectile_velocity") and ok
	ok = _check((missile.call(&"get_projectile_velocity") as Vector2).y < 0.0, "Missile velocity must point upward") and ok

	var start_x: float = drone.global_position.x
	for _i: int in range(10):
		drone.call(&"_update_steering", 0.1)
	ok = _check(drone.global_position.x < start_x - 5.0, "Drone must dodge laterally away from the missile") and ok
	ok = _check(absf((drone.call(&"get_ai_offset") as Vector2).x) <= 48.0, "AI offset must stay bounded") and ok

	missile.global_position = Vector2(900, 900)
	for _i: int in range(40):
		drone.call(&"_update_steering", 0.1)
	ok = _check(drone.call(&"get_ai_offset").length() < 0.5, "Offset must decay back to the formation slot") and ok
	missile.queue_free()
	drone.queue_free()
	return ok


# ---------------------------------------------------------------------------
# 6. Swarm
# ---------------------------------------------------------------------------

func _assert_swarm_steering() -> bool:
	var ok: bool = true
	var me: Vector2 = Vector2(100, 100)
	var sep: Vector2 = EnemyAIScript.compute_swarm_steering(me, [Vector2(120, 100)])
	ok = _check(sep.x < 0.0, "Close neighbor must push the drone away (separation)") and ok
	var coh: Vector2 = EnemyAIScript.compute_swarm_steering(me, [Vector2(250, 100), Vector2(250, 120)])
	ok = _check(coh.x > 0.0, "Distant neighbors must attract the drone (cohesion)") and ok
	ok = _check(EnemyAIScript.compute_swarm_steering(me, []) == Vector2.ZERO, "No neighbors -> no steering") and ok
	ok = _check(sep.length() <= 1.0001 and coh.length() <= 1.0001, "Steering must be bounded to unit length") and ok
	return ok


# ---------------------------------------------------------------------------
# 7. Frigate burst + flee
# ---------------------------------------------------------------------------

func _assert_frigate_burst_and_flee() -> bool:
	var ok: bool = true
	var holder: Node2D = Node2D.new()
	root.add_child(holder)
	current_scene = holder

	var frigate: Area2D = (load(ENEMY_PATH) as PackedScene).instantiate() as Area2D
	frigate.call(&"apply_variant", &"assault_frigate")
	holder.add_child(frigate)
	await process_frame
	frigate.global_position = Vector2(540, 200)

	frigate.call(&"_on_shoot_cooldown_timeout")
	for _i: int in range(60):
		await create_timer(0.05).timeout
		if get_nodes_in_group(&"enemy_bullets").size() >= 3:
			break
	var shots: int = get_nodes_in_group(&"enemy_bullets").size()
	ok = _check(shots == 3, "Frigate must fire a burst of 3 shots, got %d" % shots) and ok
	for bullet: Node in get_nodes_in_group(&"enemy_bullets"):
		bullet.queue_free()

	# Flee when badly damaged: displacement goes upward and stays bounded.
	frigate.set_target_override(Vector2(540, 800))
	frigate.call(&"take_damage", frigate.max_health - 1.0)
	frigate.call(&"_process_ai", 0.016)
	ok = _check(frigate.get_ai().is_fleeing(), "Damaged frigate must enter FLEE") and ok
	var start_y: float = frigate.global_position.y
	for _i: int in range(10):
		frigate.call(&"_update_steering", 0.1)
	ok = _check(frigate.global_position.y < start_y - 10.0, "Fleeing frigate must retreat upward") and ok
	ok = _check((frigate.call(&"get_ai_offset") as Vector2).length() <= 70.001, "Flee offset must stay bounded") and ok

	frigate.queue_free()
	holder.queue_free()
	await process_frame
	return ok


# ---------------------------------------------------------------------------
# 8. Suicide interceptor
# ---------------------------------------------------------------------------

func _assert_suicide_interceptor() -> bool:
	var ok: bool = true
	var enemy: Area2D = _spawn_enemy(&"suicide_interceptor")
	await process_frame
	enemy.global_position = Vector2(540, 100)
	enemy.set_target_override(Vector2(540, 500))
	enemy.get_ai().set_state(EnemyAIScript.State.ATTACK)
	enemy.set("_charge_cooldown", 0.0)

	var charged: Array = [false]
	enemy.connect(&"charge_started", func() -> void: charged[0] = true)
	enemy.call(&"_process_ai", 0.016)
	ok = _check(charged[0] and enemy.is_charging(), "Attacking interceptor must start a charge") and ok
	ok = _check(not enemy.is_in_formation(), "Charging enemy must leave the formation") and ok

	var start: Vector2 = enemy.global_position
	for _i: int in range(10):
		enemy.call(&"_process_charging", 0.1)
	var travelled: float = enemy.global_position.distance_to(start)
	ok = _check(travelled >= 350.0, "Interceptor must close at high speed (travelled %f in 1 s)" % travelled) and ok
	ok = _check(enemy.global_position.y > start.y, "Interceptor must head toward the target") and ok

	var contacted: Array = [false]
	var destroyed_flag: Array = [false]
	enemy.connect(&"player_contacted", func(_p: Node2D) -> void: contacted[0] = true)
	enemy.connect(&"destroyed", func(_e: Area2D) -> void: destroyed_flag[0] = true)
	var fake_player: Node2D = Node2D.new()
	fake_player.add_to_group(&"player")
	root.add_child(fake_player)
	enemy.call(&"_on_body_entered", fake_player)
	ok = _check(contacted[0] and destroyed_flag[0], "Collision must hit the player and destroy the interceptor") and ok
	fake_player.queue_free()
	await process_frame
	return ok


# ---------------------------------------------------------------------------
# 9. Spawner
# ---------------------------------------------------------------------------

func _assert_spawner_integration() -> bool:
	var ok: bool = true
	var spawner: Node2D = (load(SPAWNER_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(spawner)
	spawner.set("fly_in_enabled", false)
	await process_frame

	spawner.call(&"start_wave", 0)
	var wave0: Array = spawner.get_children().filter(func(n: Node) -> bool: return n.is_in_group(&"enemies"))
	ok = _check(wave0.size() == 18, "Wave 0 must keep its 18 standard enemies, got %d" % wave0.size()) and ok
	for enemy: Node in wave0:
		if enemy.call(&"get_variant_id") != &"standard":
			ok = _check(false, "Wave 0 must contain no tactical variants")
			break

	# The spawner gates variants behind ENEMY_AI_ENABLED; expectations follow the flag.
	var ai_enabled: bool = bool(spawner.get_script().get_script_constant_map().get("ENEMY_AI_ENABLED", true))
	for wave: int in range(1, 10):
		var cfg: Dictionary = spawner.call(&"get_wave_config", wave)
		var wanted: Dictionary = cfg.get("variants", {})
		if not ai_enabled:
			wanted = {}
		spawner.call(&"start_wave", wave)
		var members: Array = spawner.get_children().filter(func(n: Node) -> bool: return n.is_in_group(&"enemies"))
		ok = _check(members.size() == int(cfg["rows"]) * int(cfg["columns"]), "Wave %d formation size must be preserved" % wave) and ok
		var counts: Dictionary = {}
		for enemy: Node in members:
			var id: String = String(enemy.call(&"get_variant_id"))
			counts[id] = int(counts.get(id, 0)) + 1
		if not ai_enabled:
			ok = _check(counts.size() == 1 and counts.has("standard"), "Wave %d must spawn only standard enemies while ENEMY_AI_ENABLED is false, got %s" % [wave, str(counts)]) and ok
		for key: Variant in wanted.keys():
			ok = _check(int(counts.get(String(key), 0)) == int(wanted[key]), "Wave %d expected %d x %s, got %d" % [wave, int(wanted[key]), String(key), int(counts.get(String(key), 0))]) and ok
		ok = _check(counts.get("standard", 0) > 0, "Wave %d must still contain standard enemies" % wave) and ok

	var final_cfg: Dictionary = spawner.call(&"get_wave_config", 9)
	var heavy: int = int(final_cfg["variants"].get("assault_frigate", 0))
	ok = _check(heavy >= 1, "Final wave must include assault frigates") and ok
	ok = _check(spawner.call(&"get_wave_config", 1)["variants"].has("scout_drone"), "Wave 1 must introduce scout drones") and ok

	var layout_a: Dictionary = spawner.call(&"assign_variant_slots", {"assault_frigate": 2, "scout_drone": 4}, 20)
	var layout_b: Dictionary = spawner.call(&"assign_variant_slots", {"assault_frigate": 2, "scout_drone": 4}, 20)
	ok = _check(layout_a == layout_b and layout_a.size() == 6, "Variant slot assignment must be deterministic and collision free") and ok

	spawner.call(&"clear_formation")
	spawner.queue_free()
	await process_frame
	return ok
