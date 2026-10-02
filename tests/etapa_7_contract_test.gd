# Contract harness for Etapa 7: Weapons Arsenal, Overheat System, and Combo System.
# Verifies Input Actions, SpreadBullet, Missile, LaserBeam, Player arsenal & thermal mechanics,
# Boss variable damage support, ComboSystem progression, HUD arsenal/heat/combo display,
# Main combo scoring integration, and AudioFeedback weapon sounds.
extends SceneTree

const SPREAD_BULLET_PATH := "res://scenes/entities/bullet/spread_bullet.tscn"
const MISSILE_PATH := "res://scenes/entities/bullet/missile.tscn"
const LASER_BEAM_PATH := "res://scenes/entities/bullet/laser_beam.tscn"
const PLAYER_PATH := "res://scenes/entities/player/player.tscn"
const BOSS_PATH := "res://scenes/entities/boss/boss.tscn"
const ENEMY_PATH := "res://scenes/entities/enemy/enemy.tscn"
const COMBO_SYSTEM_PATH := "res://scripts/systems/combo_system.gd"
const HUD_PATH := "res://scenes/ui/hud.tscn"
const MAIN_PATH := "res://scenes/main/main.tscn"
const AUDIO_FEEDBACK_PATH := "res://scenes/audio/audio_feedback.tscn"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var input_passed: bool = _assert_input_actions_contract()
	var spread_passed: bool = await _assert_spread_bullet_contract()
	var missile_passed: bool = await _assert_missile_contract()
	var laser_passed: bool = await _assert_laser_beam_contract()
	var player_passed: bool = await _assert_player_arsenal_and_overheat_contract()
	var boss_passed: bool = await _assert_boss_damage_contract()
	var combo_passed: bool = await _assert_combo_system_contract()
	var hud_passed: bool = await _assert_hud_contract()
	var main_combo_passed: bool = await _assert_main_combo_contract()
	var audio_passed: bool = _assert_audio_feedback_contract()

	var all_passed: bool = (
		input_passed
		and spread_passed
		and missile_passed
		and laser_passed
		and player_passed
		and boss_passed
		and combo_passed
		and hud_passed
		and main_combo_passed
		and audio_passed
	)
	if all_passed:
		print("ETAPA 7 CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 7 CONTRACT TESTS: FAILURES DETECTED")
	quit(0 if all_passed else 1)


# ---------------------------------------------------------------------------
# 1. Input Actions Contract
# ---------------------------------------------------------------------------

func _assert_input_actions_contract() -> bool:
	var passed: bool = true
	var required_actions: Array[StringName] = [
		&"weapon_1",
		&"weapon_2",
		&"weapon_3",
		&"weapon_4",
		&"weapon_prev",
		&"weapon_next",
	]

	for action: StringName in required_actions:
		if not InputMap.has_action(action):
			push_error("Missing input action in InputMap: %s" % action)
			passed = false

	return passed


# ---------------------------------------------------------------------------
# 2. Spread Bullet Contract
# ---------------------------------------------------------------------------

func _assert_spread_bullet_contract() -> bool:
	if not ResourceLoader.exists(SPREAD_BULLET_PATH):
		push_error("Missing scene: %s" % SPREAD_BULLET_PATH)
		return false

	var packed: PackedScene = load(SPREAD_BULLET_PATH) as PackedScene
	var bullet: Area2D = packed.instantiate() as Area2D
	if bullet == null:
		push_error("SpreadBullet root must be Area2D")
		return false
	root.add_child(bullet)
	var passed: bool = true

	if not bullet.is_in_group(&"combat_transients"):
		push_error("SpreadBullet must belong to group 'combat_transients'")
		passed = false

	if bullet.collision_layer != 2 or bullet.collision_mask != 4:
		push_error("SpreadBullet collision layer/mask must be 2 / 4, got %d / %d" % [bullet.collision_layer, bullet.collision_mask])
		passed = false

	if not bullet.has_signal(&"enemy_hit"):
		push_error("SpreadBullet missing signal: enemy_hit")
		passed = false

	if absf(float(bullet.get("speed")) - 550.0) > 0.1:
		push_error("SpreadBullet speed must default to 550.0")
		passed = false

	if int(bullet.get("damage")) != 1:
		push_error("SpreadBullet damage must default to 1")
		passed = false

	# Test collision with Enemy scene
	var enemy_packed: PackedScene = load(ENEMY_PATH) as PackedScene
	var enemy: Area2D = enemy_packed.instantiate() as Area2D
	root.add_child(enemy)

	var hit_emitted: Array[bool] = [false]
	bullet.connect(&"enemy_hit", func(_e: Area2D) -> void: hit_emitted[0] = true)
	bullet.call("_on_area_entered", enemy)
	await process_frame

	if not hit_emitted[0]:
		push_error("SpreadBullet must emit enemy_hit on enemy contact")
		passed = false

	# Test right screen edge persistence (1080 viewport bounds)
	var right_bullet: Area2D = packed.instantiate() as Area2D
	right_bullet.global_position = Vector2(1000.0, 500.0)
	root.add_child(right_bullet)
	right_bullet.call("_process", 0.016)
	if not is_instance_valid(right_bullet) or right_bullet.is_queued_for_deletion():
		push_error("SpreadBullet at x=1000.0 must not be destroyed off-screen on 1080px playfield")
		passed = false
	if is_instance_valid(right_bullet):
		right_bullet.queue_free()

	return passed



# ---------------------------------------------------------------------------
# 3. Missile Contract
# ---------------------------------------------------------------------------

func _assert_missile_contract() -> bool:
	if not ResourceLoader.exists(MISSILE_PATH):
		push_error("Missing scene: %s" % MISSILE_PATH)
		return false

	var packed: PackedScene = load(MISSILE_PATH) as PackedScene
	var missile: Area2D = packed.instantiate() as Area2D
	if missile == null:
		push_error("Missile root must be Area2D")
		return false
	root.add_child(missile)
	var passed: bool = true

	if not missile.is_in_group(&"combat_transients"):
		push_error("Missile must belong to group 'combat_transients'")
		passed = false

	if missile.collision_layer != 2 or missile.collision_mask != 4:
		push_error("Missile collision layer/mask must be 2 / 4")
		passed = false

	if not missile.has_signal(&"enemy_hit"):
		push_error("Missile missing signal: enemy_hit")
		passed = false

	if absf(float(missile.get("speed")) - 280.0) > 0.1:
		push_error("Missile initial speed must default to 280.0")
		passed = false

	if absf(float(missile.get("turn_rate")) - 3.5) > 0.1:
		push_error("Missile turn_rate must default to 3.5")
		passed = false

	if int(missile.get("damage")) != 3:
		push_error("Missile damage must default to 3")
		passed = false

	# Test homing target detection
	var dummy_enemy: Area2D = Area2D.new()
	dummy_enemy.add_to_group(&"enemies")
	dummy_enemy.position = Vector2(200.0, 200.0)
	root.add_child(dummy_enemy)
	missile.position = Vector2(0.0, 0.0)

	var target_found: Node2D = missile.call("_find_nearest_target") as Node2D
	if target_found != dummy_enemy:
		push_error("Missile _find_nearest_target failed to find enemy")
		passed = false

	dummy_enemy.queue_free()
	if is_instance_valid(missile):
		missile.queue_free()

	# Test right screen edge persistence (1080 viewport bounds)
	var right_missile: Area2D = packed.instantiate() as Area2D
	right_missile.global_position = Vector2(1000.0, 500.0)
	root.add_child(right_missile)
	right_missile.call("_process", 0.016)
	if not is_instance_valid(right_missile) or right_missile.is_queued_for_deletion():
		push_error("Missile at x=1000.0 must not be destroyed off-screen on 1080px playfield")
		passed = false
	if is_instance_valid(right_missile):
		right_missile.queue_free()

	return passed



# ---------------------------------------------------------------------------
# 4. Laser Beam Contract
# ---------------------------------------------------------------------------

func _assert_laser_beam_contract() -> bool:
	if not ResourceLoader.exists(LASER_BEAM_PATH):
		push_error("Missing scene: %s" % LASER_BEAM_PATH)
		return false

	var packed: PackedScene = load(LASER_BEAM_PATH) as PackedScene
	var laser: Area2D = packed.instantiate() as Area2D
	if laser == null:
		push_error("LaserBeam root must be Area2D")
		return false
	root.add_child(laser)
	var passed: bool = true

	if not laser.is_in_group(&"player_bullets"):
		push_error("LaserBeam must belong to group 'player_bullets'")
		passed = false

	if laser.collision_layer != 2 or laser.collision_mask != 4:
		push_error("LaserBeam collision layer/mask must be 2 / 4")
		passed = false

	if not laser.has_signal(&"enemy_hit"):
		push_error("LaserBeam missing signal: enemy_hit")
		passed = false

	if absf(float(laser.get("beam_length")) - 420.0) > 0.1:
		push_error("LaserBeam beam_length must default to 420.0")
		passed = false

	if int(laser.get("damage_per_tick")) != 1:
		push_error("LaserBeam damage_per_tick must default to 1")
		passed = false

	if not laser.has_method(&"set_firing"):
		push_error("LaserBeam missing method: set_firing")
		passed = false

	if not laser.has_method(&"is_beam"):
		push_error("LaserBeam missing method: is_beam")
		passed = false

	# Test set_firing toggles monitoring and visibility
	laser.call("set_firing", true)
	if not laser.visible or not laser.monitoring:
		push_error("set_firing(true) must make laser visible and monitoring")
		passed = false

	laser.call("set_firing", false)
	if laser.visible or laser.monitoring:
		push_error("set_firing(false) must make laser invisible and not monitoring")
		passed = false

	if is_instance_valid(laser):
		laser.queue_free()

	return passed


# ---------------------------------------------------------------------------
# 5. Player Arsenal and Overheat Contract
# ---------------------------------------------------------------------------

func _assert_player_arsenal_and_overheat_contract() -> bool:
	if not ResourceLoader.exists(PLAYER_PATH):
		push_error("Missing scene: %s" % PLAYER_PATH)
		return false

	var packed: PackedScene = load(PLAYER_PATH) as PackedScene
	var player: CharacterBody2D = packed.instantiate() as CharacterBody2D
	if player == null:
		push_error("Player root must be CharacterBody2D")
		return false
	root.add_child(player)
	await process_frame
	var passed: bool = true

	# Check exports
	for prop: StringName in [&"spread_bullet_scene", &"missile_scene", &"laser_beam_scene"]:
		if prop not in player:
			push_error("Player missing exported property: %s" % prop)
			passed = false

	# Check signals
	for sig: StringName in [&"weapon_changed", &"heat_changed", &"overheat_state_changed"]:
		if not player.has_signal(sig):
			push_error("Player missing signal: %s" % sig)
			passed = false

	# Check arsenal methods
	for meth: StringName in [&"set_weapon", &"get_weapon", &"cycle_weapon"]:
		if not player.has_method(meth):
			push_error("Player missing method: %s" % meth)
			passed = false

	# Weapon selection and cycling
	var changed_weapons: Array[int] = []
	player.connect(&"weapon_changed", func(w: int) -> void: changed_weapons.append(w))

	player.call("set_weapon", 1) # SPREAD
	if int(player.call("get_weapon")) != 1:
		push_error("set_weapon(1) failed to update current_weapon")
		passed = false

	player.call("cycle_weapon", true) # MISSILE (2)
	if int(player.call("get_weapon")) != 2:
		push_error("cycle_weapon(true) failed to cycle to 2")
		passed = false

	player.call("cycle_weapon", true) # LASER (3)
	if int(player.call("get_weapon")) != 3:
		push_error("cycle_weapon(true) failed to cycle to 3")
		passed = false

	player.call("cycle_weapon", true) # Wrap around to BLASTER (0)
	if int(player.call("get_weapon")) != 0:
		push_error("cycle_weapon(true) failed to wrap to 0")
		passed = false

	player.call("cycle_weapon", false) # Wrap back to LASER (3)
	if int(player.call("get_weapon")) != 3:
		push_error("cycle_weapon(false) failed to wrap to 3")
		passed = false

	player.call("set_weapon", 0) # Back to BLASTER

	# Overheat and heat mechanics
	if not ("heat" in player and "max_heat" in player and "is_overheated" in player):
		push_error("Player missing overheat variables")
		passed = false

	var heat_events: Array[float] = []
	player.connect(&"heat_changed", func(cur: float, _max: float) -> void: heat_events.append(cur))

	var overheat_events: Array[bool] = []
	player.connect(&"overheat_state_changed", func(is_oh: bool) -> void: overheat_events.append(is_oh))

	player.call("add_heat", 25.0)
	if absf(float(player.get("heat")) - 25.0) > 0.1:
		push_error("add_heat(25.0) failed, heat is %f" % float(player.get("heat")))
		passed = false

	# Simulate reaching 100 heat -> overheat triggers
	player.call("add_heat", 80.0)
	if not bool(player.get("is_overheated")):
		push_error("heat >= max_heat must engage is_overheated")
		passed = false
	if overheat_events.is_empty() or overheat_events[-1] != true:
		push_error("Overheat state change not emitted with true")
		passed = false

	# Reset heat clears overheat
	player.call("reset_heat")
	if bool(player.get("is_overheated")) or float(player.get("heat")) != 0.0:
		push_error("reset_heat() must reset heat to 0 and clear is_overheated")
		passed = false

	if is_instance_valid(player):
		player.queue_free()

	return passed


# ---------------------------------------------------------------------------
# 6. Boss Variable Damage Contract
# ---------------------------------------------------------------------------

func _assert_boss_damage_contract() -> bool:
	if not ResourceLoader.exists(BOSS_PATH):
		push_error("Missing scene: %s" % BOSS_PATH)
		return false

	var packed: PackedScene = load(BOSS_PATH) as PackedScene
	var boss: Area2D = packed.instantiate() as Area2D
	if boss == null:
		push_error("Boss root must be Area2D")
		return false
	root.add_child(boss)
	var passed: bool = true

	var initial_hp: int = int(boss.get("health"))

	# Create a missile with damage = 3
	var missile_packed: PackedScene = load(MISSILE_PATH) as PackedScene
	var missile: Area2D = missile_packed.instantiate() as Area2D
	root.add_child(missile)

	boss.call("_on_area_entered", missile)
	await process_frame

	var hp_after: int = int(boss.get("health"))
	if hp_after != initial_hp - 3:
		push_error("Boss must take 3 damage from missile with damage=3, expected %d got %d" % [initial_hp - 3, hp_after])
		passed = false

	if is_instance_valid(missile):
		missile.queue_free()
	if is_instance_valid(boss):
		boss.queue_free()

	return passed


# ---------------------------------------------------------------------------
# 7. Combo System Contract
# ---------------------------------------------------------------------------

func _assert_combo_system_contract() -> bool:
	if not ResourceLoader.exists(COMBO_SYSTEM_PATH):
		push_error("Missing script: %s" % COMBO_SYSTEM_PATH)
		return false

	var combo_script: Script = load(COMBO_SYSTEM_PATH) as Script
	var combo: Node = combo_script.new() as Node
	if combo == null:
		push_error("ComboSystem must instantiate as Node")
		return false
	root.add_child(combo)
	var passed: bool = true

	# Check constants
	if absf(float(combo.get("DECAY_DURATION")) - 3.0) > 0.01:
		push_error("ComboSystem DECAY_DURATION must be 3.0")
		passed = false

	if "MULTIPLIER_THRESHOLDS" not in combo:
		push_error("ComboSystem missing MULTIPLIER_THRESHOLDS")
		passed = false

	# Check signals
	for sig: StringName in [&"combo_updated", &"combo_reset"]:
		if not combo.has_signal(sig):
			push_error("ComboSystem missing signal: %s" % sig)
			passed = false

	# Check initial state
	if combo.call("get_multiplier") != 1 or combo.call("get_kills") != 0:
		push_error("ComboSystem must start with multiplier=1 and kills=0")
		passed = false

	var updated_signals: Array[Dictionary] = []
	combo.connect(&"combo_updated", func(m: int, k: int, r: float) -> void:
		updated_signals.append({"multiplier": m, "kills": k, "ratio": r})
	)

	# 1x threshold (0-2 kills)
	var m1: int = combo.call("register_kill")
	if m1 != 1 or combo.call("get_kills") != 1:
		push_error("Kill 1 must yield multiplier=1, kills=1")
		passed = false

	var m2: int = combo.call("register_kill")
	if m2 != 1 or combo.call("get_kills") != 2:
		push_error("Kill 2 must yield multiplier=1, kills=2")
		passed = false

	# 2x threshold (3-5 kills)
	var m3: int = combo.call("register_kill")
	if m3 != 2 or combo.call("get_kills") != 3:
		push_error("Kill 3 must yield multiplier=2, kills=3")
		passed = false

	combo.call("register_kill") # 4 kills -> 2x
	var m5: int = combo.call("register_kill") # 5 kills -> 2x
	if m5 != 2 or combo.call("get_kills") != 5:
		push_error("Kill 5 must yield multiplier=2, kills=5")
		passed = false

	# 3x threshold (6-9 kills)
	var m6: int = combo.call("register_kill")
	if m6 != 3 or combo.call("get_kills") != 6:
		push_error("Kill 6 must yield multiplier=3, kills=6")
		passed = false

	combo.call("register_kill") # 7 kills
	combo.call("register_kill") # 8 kills
	var m9: int = combo.call("register_kill") # 9 kills
	if m9 != 3 or combo.call("get_kills") != 9:
		push_error("Kill 9 must yield multiplier=3, kills=9")
		passed = false

	# 4x threshold (10+ kills)
	var m10: int = combo.call("register_kill")
	if m10 != 4 or combo.call("get_kills") != 10:
		push_error("Kill 10 must yield multiplier=4, kills=10")
		passed = false

	var m11: int = combo.call("register_kill")
	if m11 != 4 or combo.call("get_kills") != 11:
		push_error("Kill 11 must yield multiplier=4, kills=11")
		passed = false

	# Check time remaining decay
	if absf(float(combo.get("time_remaining")) - 3.0) > 0.05:
		push_error("After register_kill, time_remaining must be 3.0")
		passed = false

	combo.call("_process", 1.5)
	if absf(float(combo.get("time_remaining")) - 1.5) > 0.05:
		push_error("After 1.5s delta, time_remaining must be ~1.5")
		passed = false

	var ratio: float = float(combo.call("get_time_ratio"))
	if absf(ratio - 0.5) > 0.05:
		push_error("At 1.5s remaining, get_time_ratio() must be ~0.5")
		passed = false

	# Advancing time past remaining duration must automatically trigger decay/reset
	combo.call("_process", 1.6)
	if combo.call("get_multiplier") != 1 or combo.call("get_kills") != 0 or float(combo.get("time_remaining")) != 0.0:
		push_error("Combo must automatically reset when time_remaining reaches 0")
		passed = false

	# Test explicit reset_combo()
	combo.call("register_kill")
	combo.call("register_kill")
	combo.call("register_kill") # Multiplier 2
	var reset_emitted: Array[bool] = [false]
	combo.connect(&"combo_reset", func() -> void: reset_emitted[0] = true)
	combo.call("reset_combo")

	if not reset_emitted[0] or combo.call("get_multiplier") != 1 or combo.call("get_kills") != 0:
		push_error("reset_combo() must emit combo_reset and reset multiplier to 1")
		passed = false

	if is_instance_valid(combo):
		root.remove_child(combo)
		combo.free()

	return passed


# ---------------------------------------------------------------------------
# 8. HUD Arsenal, Heat, and Combo Contract
# ---------------------------------------------------------------------------

func _assert_hud_contract() -> bool:
	if not ResourceLoader.exists(HUD_PATH):
		push_error("Missing HUD scene: %s" % HUD_PATH)
		return false

	var packed: PackedScene = load(HUD_PATH) as PackedScene
	var hud: CanvasLayer = packed.instantiate() as CanvasLayer
	if hud == null:
		push_error("HUD root must be CanvasLayer")
		return false
	root.add_child(hud)
	await process_frame
	var passed: bool = true

	# Check required methods
	for meth: StringName in [&"set_active_weapon", &"set_heat", &"set_combo"]:
		if not hud.has_method(meth):
			push_error("HUD missing method: %s" % meth)
			passed = false

	# Check signal
	if not hud.has_signal(&"weapon_selected_by_user"):
		push_error("HUD missing signal: weapon_selected_by_user")
		passed = false

	# Check required node hierarchy (Heat and Combo must be present; WeaponSelectorContainer is deprecated)
	var heat_container: Control = hud.get_node_or_null("HeatContainer") as Control
	if heat_container == null:
		push_error("HUD missing HeatContainer")
		passed = false
	else:
		if heat_container.get_node_or_null("HeatLabel") == null:
			push_error("HeatContainer missing HeatLabel")
			passed = false
		if heat_container.get_node_or_null("HeatProgressBar") == null:
			push_error("HeatContainer missing HeatProgressBar")
			passed = false
		if heat_container.get_node_or_null("OverheatWarningLabel") == null:
			push_error("HeatContainer missing OverheatWarningLabel")
			passed = false

	var combo_container: Control = hud.get_node_or_null("ComboContainer") as Control
	if combo_container == null:
		push_error("HUD missing ComboContainer")
		passed = false
	else:
		if combo_container.get_node_or_null("ComboLabel") == null:
			push_error("ComboContainer missing ComboLabel")
			passed = false
		if combo_container.get_node_or_null("ComboProgressBar") == null:
			push_error("ComboContainer missing ComboProgressBar")
			passed = false

	# Test set_active_weapon (backward compatibility)
	hud.call("set_active_weapon", 1)

	# Test set_heat
	hud.call("set_heat", 35.0, 100.0, false)
	var heat_bar: ProgressBar = hud.get_node_or_null("HeatContainer/HeatProgressBar") as ProgressBar
	var heat_lbl: Label = hud.get_node_or_null("HeatContainer/HeatLabel") as Label
	var oh_lbl: Label = hud.get_node_or_null("HeatContainer/OverheatWarningLabel") as Label
	if heat_bar != null and absf(heat_bar.value - 35.0) > 0.1:
		push_error("set_heat(35, 100, false) did not set HeatProgressBar value to 35")
		passed = false
	if heat_lbl != null and not heat_lbl.text.contains("35%"):
		push_error("HeatLabel text must show '35%', got '%s'" % heat_lbl.text)
		passed = false
	if oh_lbl != null and oh_lbl.visible:
		push_error("OverheatWarningLabel must not be visible when is_overheated=false")
		passed = false

	hud.call("set_heat", 100.0, 100.0, true)
	if oh_lbl != null and not oh_lbl.visible:
		push_error("OverheatWarningLabel must be visible when is_overheated=true")
		passed = false

	# Test set_combo
	hud.call("set_combo", 1, 0, 0.0)
	if combo_container != null and combo_container.visible:
		push_error("ComboContainer must be hidden when multiplier is 1")
		passed = false

	hud.call("set_combo", 2, 3, 0.75)
	if combo_container != null and not combo_container.visible:
		push_error("ComboContainer must be visible when multiplier >= 2")
		passed = false
	var combo_bar: ProgressBar = hud.get_node_or_null("ComboContainer/ComboProgressBar") as ProgressBar
	var combo_lbl: Label = hud.get_node_or_null("ComboContainer/ComboLabel") as Label
	if combo_bar != null and absf(combo_bar.value - 0.75) > 0.05:
		push_error("ComboProgressBar value must match time_ratio 0.75")
		passed = false
	if combo_lbl != null and not combo_lbl.text.contains("x2"):
		push_error("ComboLabel must display 'x2'")
		passed = false

	hud.call("set_combo", 4, 10, 1.0)
	if combo_lbl != null and not combo_lbl.text.contains("x4"):
		push_error("ComboLabel must display 'x4'")
		passed = false

	if is_instance_valid(hud):
		root.remove_child(hud)
		hud.queue_free()
		await process_frame

	return passed


# ---------------------------------------------------------------------------
# 9. Main Combo Scoring and Reset Contract
# ---------------------------------------------------------------------------

func _assert_main_combo_contract() -> bool:
	if not ResourceLoader.exists(MAIN_PATH):
		push_error("Missing Main scene: %s" % MAIN_PATH)
		return false

	var packed: PackedScene = load(MAIN_PATH) as PackedScene
	var main: Node2D = packed.instantiate() as Node2D
	if main == null:
		push_error("Main root must be Node2D")
		return false
	root.add_child(main)
	await process_frame
	var passed: bool = true

	var combo_sys: Node = main.get_node_or_null("ComboSystem")
	if combo_sys == null:
		push_error("Main scene must contain ComboSystem node")
		passed = false

	main.call("start_session")
	var dummy_enemy: Area2D = Area2D.new()
	dummy_enemy.global_position = Vector2(300.0, 300.0)
	root.add_child(dummy_enemy)

	# Verify scoring progression:
	# Kill 1 (1x) -> +100
	main.call("_on_enemy_destroyed", dummy_enemy)
	if int(main.get("score")) != 100:
		push_error("Kill 1 score expected 100, got %d" % int(main.get("score")))
		passed = false

	# Kill 2 (1x) -> +100 (total 200)
	main.call("_on_enemy_destroyed", dummy_enemy)
	if int(main.get("score")) != 200:
		push_error("Kill 2 score expected 200, got %d" % int(main.get("score")))
		passed = false

	# Kill 3 (2x) -> +200 (total 400)
	main.call("_on_enemy_destroyed", dummy_enemy)
	if int(main.get("score")) != 400:
		push_error("Kill 3 score expected 400 (with 2x combo), got %d" % int(main.get("score")))
		passed = false

	# Kill 4 (2x) -> +200 (total 600)
	main.call("_on_enemy_destroyed", dummy_enemy)
	if int(main.get("score")) != 600:
		push_error("Kill 4 score expected 600 (with 2x combo), got %d" % int(main.get("score")))
		passed = false

	# Kill 5 (2x) -> +200 (total 800)
	main.call("_on_enemy_destroyed", dummy_enemy)
	if int(main.get("score")) != 800:
		push_error("Kill 5 score expected 800 (with 2x combo), got %d" % int(main.get("score")))
		passed = false

	# Kill 6 (3x) -> +300 (total 1100)
	main.call("_on_enemy_destroyed", dummy_enemy)
	if int(main.get("score")) != 1100:
		push_error("Kill 6 score expected 1100 (with 3x combo), got %d" % int(main.get("score")))
		passed = false

	# Taking damage must reset combo back to 1x
	main.call("_on_player_damage_requested")
	if combo_sys != null and (combo_sys.call("get_multiplier") != 1 or combo_sys.call("get_kills") != 0):
		push_error("Player damage must reset combo system to 1x and 0 kills")
		passed = false

	# Kill 7 after reset (1x) -> +100 (total 1200)
	main.call("_on_enemy_destroyed", dummy_enemy)
	if int(main.get("score")) != 1200:
		push_error("Kill after damage reset expected 1200 (1x combo), got %d" % int(main.get("score")))
		passed = false

	if is_instance_valid(dummy_enemy):
		dummy_enemy.queue_free()
	if is_instance_valid(main):
		root.remove_child(main)
		main.queue_free()
		await process_frame

	return passed


# ---------------------------------------------------------------------------
# 10. Audio Feedback Arsenal and Warning Contract
# ---------------------------------------------------------------------------

func _assert_audio_feedback_contract() -> bool:
	if not ResourceLoader.exists(AUDIO_FEEDBACK_PATH):
		push_error("Missing AudioFeedback scene: %s" % AUDIO_FEEDBACK_PATH)
		return false

	var packed: PackedScene = load(AUDIO_FEEDBACK_PATH) as PackedScene
	var audio: Node = packed.instantiate() as Node
	if audio == null:
		push_error("AudioFeedback root must be Node")
		return false
	root.add_child(audio)
	var passed: bool = true

	if not audio.has_method(&"play_weapon_shot"):
		push_error("AudioFeedback missing method: play_weapon_shot")
		passed = false

	if not audio.has_method(&"play_overheat_warning"):
		push_error("AudioFeedback missing method: play_overheat_warning")
		passed = false

	# Test calling methods without runtime errors
	for w: int in range(4):
		audio.call("play_weapon_shot", w)
	audio.call("play_overheat_warning")

	if is_instance_valid(audio):
		root.remove_child(audio)
		audio.queue_free()

	return passed

