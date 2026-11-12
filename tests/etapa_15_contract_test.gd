# Contract harness for Etapa 15 (T1): campaign structure in 3 chapters.
# Chapter 1 is the current 10-wave campaign plus boss. Wave numbering is global
# (1-30): defeating the boss of chapters 1 and 2 starts the next chapter and the
# wave continues at 11 and 21; defeating the boss of chapter 3 completes the mission.
extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const BOSS_DEFEAT_CHAPTER_SCORE: int = 3000
const TOTAL_WAVES: int = 10
const TOTAL_CHAPTERS: int = 3
const BONUS_WAVE_NUMBER: int = 8
const BOSS_SCENE_PATH := "res://scenes/entities/boss/boss.tscn"
# Chapter 3 boss health (T1 scaling: 150 -> 225 -> 300).
const BLINDADO_MAX_HEALTH: int = 300
const ARMOR_PHASE_EXTERIOR: int = 1
const ARMOR_PHASE_SUBCORE: int = 2
const ARMOR_PHASE_EXPOSED_CORE: int = 3
const CLEAN_WAVE_BONUS: int = 500
# Etapa 15 T6: wave-cleared feedback (banner, camera zoom, invulnerability grace).
const WAVE_CLEARED_BANNER_TEXT: String = "¡OLEADA SUPERADA!"
const WAVE_CLEARED_GRACE_MIN: float = 1.5
const WAVE_CLEARED_GRACE_MAX: float = 2.0
# Etapa 15 T7: one boss per chapter (names as shown on the boss health bar).
const BOSS_NAME_NEXUS: String = "NAVE NODRIZA NEXUS"
const BOSS_NAME_ESPECTRO: String = "CRUCERO ESPECTRO"
const BOSS_NAME_BLINDADO: String = "NÚCLEO BLINDADO"
const ARMOR_BROKEN_TEXT: String = "ARMADURA EXTERIOR ROTA"
const CORE_EXPOSED_TEXT: String = "NÚCLEO EXPUESTO"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = await _assert_chapter_structure_contract() and passed
	passed = await _assert_bonus_wave_contract() and passed
	passed = await _assert_blindado_core_contract() and passed
	passed = await _assert_boss_variants_contract() and passed
	passed = await _assert_wave_cleared_feedback_contract() and passed
	passed = await _assert_global_difficulty_contract() and passed
	passed = await _assert_stacking_shield_contract() and passed
	quit(0 if passed else 1)


# Picking up a shield while one is active raises its level (1 -> 3): each level has
# its own ring color and lasts longer; once it expires the next pickup is level 1 again.
func _assert_stacking_shield_contract() -> bool:
	var player: CharacterBody2D = (load("res://scenes/entities/player/player.tscn") as PackedScene).instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	var passed: bool = true
	if not player.has_method(&"get_shield_level"):
		push_error("Player must expose get_shield_level()")
		root.remove_child(player)
		player.free()
		return false
	var ring: Node2D = player.get_node("ShieldRing") as Node2D
	var timer: Timer = player.get_node("ShieldTimer") as Timer
	var colors: Array[Color] = []
	var durations: Array[float] = []
	for expected_level: int in [1, 2, 3, 3]:
		player.call(&"activate_shield", 10.0)
		if int(player.call(&"get_shield_level")) != expected_level:
			push_error("Shield level must be %d, got %d" % [expected_level, int(player.call(&"get_shield_level"))])
			passed = false
		colors.append(ring.call(&"get_ring_color") as Color)
		durations.append(timer.wait_time)
	if colors[0] == colors[1] or colors[1] == colors[2] or colors[0] == colors[2]:
		push_error("Shield levels 1, 2 and 3 must each use a different ring color")
		passed = false
	if durations[0] != 10.0 or not (durations[1] > durations[0] and durations[2] > durations[1]):
		push_error("Level 1 lasts the given 10 s and each higher level must last longer, got %s" % [durations])
		passed = false
	player.call(&"_on_shield_timer_timeout")
	if player.call(&"has_shield") or int(player.call(&"get_shield_level")) != 0:
		push_error("An expired shield must be gone and report level 0")
		passed = false
	player.call(&"activate_shield", 10.0)
	if int(player.call(&"get_shield_level")) != 1:
		push_error("A shield picked up after expiry must start at level 1")
		passed = false
	root.remove_child(player)
	player.free()
	return passed


# Waves 11-30 keep getting harder: wave 11 is harder than wave 10 and wave 30 is
# harder than wave 11 (faster formation, faster fire, never beyond 8 columns).
func _assert_global_difficulty_contract() -> bool:
	var spawner: Node2D = (load("res://scenes/systems/enemy_spawner.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(spawner)
	await process_frame
	var passed: bool = true
	if not spawner.has_method(&"get_scaled_wave_config"):
		push_error("EnemySpawner must expose get_scaled_wave_config(local_index, global_index)")
		root.remove_child(spawner)
		spawner.free()
		return false
	# Chapter 1 is untouched: the scaled config equals the base config.
	for i: int in range(10):
		if spawner.call(&"get_scaled_wave_config", i, i) != spawner.call(&"get_wave_config", i):
			push_error("Wave %d (chapter 1) must keep its base configuration" % (i + 1))
			passed = false
	var wave10: Dictionary = spawner.call(&"get_scaled_wave_config", 9, 9)
	var wave11: Dictionary = spawner.call(&"get_scaled_wave_config", 0, 10)
	var wave30: Dictionary = spawner.call(&"get_scaled_wave_config", 9, 29)
	if float(wave11["formation_speed"]) <= float(wave10["formation_speed"]):
		push_error("Wave 11 must be faster than wave 10")
		passed = false
	if float(wave11["fire_rate_scale"]) >= float(wave10["fire_rate_scale"]):
		push_error("Wave 11 must fire faster than wave 10 (lower fire_rate_scale)")
		passed = false
	if float(wave30["formation_speed"]) <= float(wave11["formation_speed"]):
		push_error("Wave 30 must be faster than wave 11")
		passed = false
	for g: int in range(10, 30):
		var cfg: Dictionary = spawner.call(&"get_scaled_wave_config", g % 10, g)
		if int(cfg["columns"]) > 8:
			push_error("Wave %d must not exceed 8 columns" % (g + 1))
			passed = false
		if float(cfg["fire_rate_scale"]) < 0.5:
			push_error("Wave %d fire_rate_scale must stay >= 0.5" % (g + 1))
			passed = false
	root.remove_child(spawner)
	spawner.free()
	return passed


func _assert_chapter_structure_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	await process_frame
	var passed: bool = true

	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	if announcement != null and "display_duration" in announcement:
		announcement.set("display_duration", 0.0)
	if "enemy_drop_chance" in main:
		main.set("enemy_drop_chance", 0.0)
	if "clear_wave_drop_chance" in main:
		main.set("clear_wave_drop_chance", 0.0)
	main.set("bonus_drop_interval", 0.0)

	if not main.has_method("get_chapter") or not main.has_method("get_total_chapters"):
		push_error("Main must expose get_chapter() and get_total_chapters()")
		root.remove_child(main)
		main.free()
		return false

	if int(main.call("get_total_chapters")) != TOTAL_CHAPTERS:
		push_error("Main must report %d total chapters" % TOTAL_CHAPTERS)
		passed = false

	if int(main.call("get_chapter")) != 1:
		push_error("A new session must start at chapter 1")
		passed = false

	var chapter_speeds: Array[float] = []
	var chapter_boss_hp: Array[int] = []
	for chapter_index: int in range(1, TOTAL_CHAPTERS + 1):
		if int(main.call("get_chapter")) != chapter_index:
			push_error("Expected chapter %d before its boss, got %d" % [chapter_index, int(main.call("get_chapter"))])
			passed = false
			break
		var spawner: Node2D = main.get_node_or_null("EnemySpawner") as Node2D
		if spawner != null:
			chapter_speeds.append(float(spawner.get("formation_speed")))
		for wave_index: int in TOTAL_WAVES:
			# Waves 5, 15 and 25 are regular waves: no boss or guardian may appear.
			if wave_index == 4 and _find_boss(main) != null:
				push_error("Wave %d must be a normal wave without a boss or guardian" % main.wave)
				passed = false
			await _clear_current_wave(main)
			await _finish_wave_transition(main)
			await _wait_for_bonus(main)
		var boss: Area2D = _find_boss(main)
		if boss == null:
			push_error("Chapter %d must spawn its boss after wave %d" % [chapter_index, TOTAL_WAVES])
			passed = false
			break
		chapter_boss_hp.append(int(boss.get("max_health")))
		if (boss.get("multi_phase_enabled") == true) != (chapter_index == TOTAL_CHAPTERS):
			push_error("Only chapter %d boss may enable the Núcleo Blindado phases" % TOTAL_CHAPTERS)
			passed = false
		boss.call("take_damage", int(boss.get("max_health")))
		await process_frame
		await process_frame
		if chapter_index < TOTAL_CHAPTERS:
			if main.is_mission_complete():
				push_error("Defeating the boss of chapter %d must NOT complete the mission" % chapter_index)
				passed = false
				break
			await _finish_wave_transition(main)
			var expected_wave: int = chapter_index * TOTAL_WAVES + 1
			if int(main.get("wave")) != expected_wave:
				push_error("After chapter %d's boss the wave must continue at %d, got %d" % [chapter_index, expected_wave, int(main.get("wave"))])
				passed = false
		else:
			if not main.is_mission_complete():
				push_error("Defeating the boss of chapter %d must complete the mission" % chapter_index)
				passed = false

	if not main.has_method("get_hyperspace_jump_count") or int(main.call("get_hyperspace_jump_count")) != TOTAL_CHAPTERS - 1:
		push_error("Each chapter change must perform one hyperspace jump (%d expected)" % (TOTAL_CHAPTERS - 1))
		passed = false
	if chapter_speeds.size() == TOTAL_CHAPTERS:
		for i: int in range(1, TOTAL_CHAPTERS):
			if chapter_speeds[i] <= chapter_speeds[i - 1]:
				push_error("Chapter %d formation speed must be higher than chapter %d" % [i + 1, i])
				passed = false
	else:
		push_error("EnemySpawner must expose formation_speed for each chapter")
		passed = false
	if chapter_boss_hp.size() == TOTAL_CHAPTERS:
		for i: int in range(1, TOTAL_CHAPTERS):
			if chapter_boss_hp[i] <= chapter_boss_hp[i - 1]:
				push_error("Chapter %d boss must have more health than chapter %d" % [i + 1, i])
				passed = false
	root.remove_child(main)
	main.free()
	return passed


# Wave 8 of each chapter is a peaceful bonus: no fighters spawn, loot rains
# down, and the next wave (9, the asteroid belt) starts after it.
func _assert_bonus_wave_contract() -> bool:
	var main: Node2D = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	await process_frame
	var passed: bool = true
	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	if announcement != null and "display_duration" in announcement:
		announcement.set("display_duration", 0.0)
	if "enemy_drop_chance" in main:
		main.set("enemy_drop_chance", 0.0)
	if "clear_wave_drop_chance" in main:
		main.set("clear_wave_drop_chance", 0.0)
	main.set("bonus_drop_interval", 0.0)

	for wave_index: int in BONUS_WAVE_NUMBER - 1:
		await _clear_current_wave(main)
		await _finish_wave_transition(main)
	await _clear_current_wave(main)
	await _finish_wave_transition(main)

	if not main.has_method("is_bonus_wave_active") or not main.is_bonus_wave_active():
		push_error("Wave %d must be a bonus (peaceful) wave" % BONUS_WAVE_NUMBER)
		root.remove_child(main)
		main.free()
		return false

	var fighters_during_bonus: int = 0
	for _frame: int in range(400):
		if not main.is_bonus_wave_active():
			break
		for child: Node in main.get_children():
			if child is Area2D and child.is_in_group("enemies"):
				fighters_during_bonus += 1
		await process_frame
	if main.is_bonus_wave_active():
		push_error("Bonus wave must finish on its own")
		passed = false
	if fighters_during_bonus > 0:
		push_error("Bonus wave must spawn no fighters")
		passed = false
	if int(main.call("get_bonus_drops_spawned")) <= 0:
		push_error("Bonus wave must rain loot drops")
		passed = false
	if main.is_mission_complete() or main.wave != BONUS_WAVE_NUMBER + 1:
		await _finish_wave_transition(main)
	if main.wave != BONUS_WAVE_NUMBER + 1:
		push_error("After the bonus wave the next wave must be %d, got %d" % [BONUS_WAVE_NUMBER + 1, main.wave])
		passed = false

	root.remove_child(main)
	main.free()
	return passed


# Núcleo Blindado (T4): with multi_phase_enabled the boss moves through three
# armor phases by health threshold (exterior > 66%, subcore <= 66%, exposed core
# <= 33%), and the exposed core takes more damage per hit. Without the flag the
# boss keeps its chapter 1-2 behaviour: one phase and exact damage.
func _assert_blindado_core_contract() -> bool:
	var passed: bool = true
	var boss_scene: PackedScene = load(BOSS_SCENE_PATH) as PackedScene
	if boss_scene == null:
		push_error("Missing scene: %s" % BOSS_SCENE_PATH)
		return false

	var boss: Area2D = _spawn_test_boss(boss_scene, true)
	if boss == null or not boss.has_method("get_armor_phase"):
		push_error("Boss must expose get_armor_phase() for the Núcleo Blindado")
		if boss != null:
			boss.free()
		return false

	var transitions: Array[int] = []
	boss.connect(&"armor_phase_changed", func(phase: int) -> void: transitions.append(phase))

	if int(boss.call("get_armor_phase")) != ARMOR_PHASE_EXTERIOR:
		push_error("Núcleo Blindado must start in the exterior armor phase")
		passed = false

	# 300 -> 199 HP: still above 66%, exterior armor.
	boss.call("take_damage", 101)
	if int(boss.call("get_armor_phase")) != ARMOR_PHASE_EXTERIOR:
		push_error("Exterior armor must hold above 66%% health (199/300)")
		passed = false
	# 198 HP: exactly 66%, subcore starts.
	boss.call("take_damage", 1)
	if int(boss.call("get_armor_phase")) != ARMOR_PHASE_SUBCORE:
		push_error("Subcore phase must start at 66%% health (198/300)")
		passed = false
	# 100 HP: still above 33%, subcore.
	boss.call("take_damage", 98)
	if int(boss.call("get_armor_phase")) != ARMOR_PHASE_SUBCORE:
		push_error("Subcore phase must hold above 33%% health (100/300)")
		passed = false
	# 99 HP: exactly 33%, exposed core starts.
	boss.call("take_damage", 1)
	if int(boss.call("get_armor_phase")) != ARMOR_PHASE_EXPOSED_CORE:
		push_error("Exposed core phase must start at 33%% health (99/300)")
		passed = false
	if transitions != [ARMOR_PHASE_SUBCORE, ARMOR_PHASE_EXPOSED_CORE]:
		push_error("armor_phase_changed must emit subcore then exposed core, got %s" % str(transitions))
		passed = false

	# Exposed core: a 10-damage hit removes 15 HP (1.5x).
	boss.call("take_damage", 10)
	var core_health: int = int(boss.get("health"))
	if core_health != 84:
		push_error("Exposed core must take 1.5x damage (expected 84 HP, got %d)" % core_health)
		passed = false

	# Same 10-damage hit in the exterior phase removes exactly 10 HP.
	var exterior_boss: Area2D = _spawn_test_boss(boss_scene, true)
	exterior_boss.call("take_damage", 10)
	if int(exterior_boss.get("health")) != BLINDADO_MAX_HEALTH - 10:
		push_error("Exterior armor must take exact damage (expected 290 HP)")
		passed = false

	# Chapter 1-2 behaviour: flag off means one phase and exact damage even at low HP.
	var plain_boss: Area2D = _spawn_test_boss(boss_scene, false)
	plain_boss.call("take_damage", BLINDADO_MAX_HEALTH - 50)
	if int(plain_boss.call("get_armor_phase")) != ARMOR_PHASE_EXTERIOR:
		push_error("Boss without multi_phase_enabled must stay in one phase")
		passed = false
	if int(plain_boss.get("health")) != 50:
		push_error("Boss without multi_phase_enabled must take exact damage (expected 50 HP)")
		passed = false

	for node: Area2D in [boss, exterior_boss, plain_boss]:
		root.remove_child(node)
		node.free()
	return passed


# Boss per chapter (T7): chapter 1 Nexus (unchanged), chapter 2 Espectro (fan of 5
# alternating with a ring of 8), chapter 3 Núcleo Blindado (armor phase feedback).
# Each chapter boss shows its own name on the health bar.
func _assert_boss_variants_contract() -> bool:
	var main: Node2D = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	await process_frame
	var passed: bool = true
	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	if announcement != null and "display_duration" in announcement:
		announcement.set("display_duration", 0.0)
	if "enemy_drop_chance" in main:
		main.set("enemy_drop_chance", 0.0)
	main.set("bonus_drop_interval", 0.0)

	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var name_label: Label = hud.get_node("BossContainer/BossNameLabel") as Label
	var expected_variants: Array[StringName] = [&"nexus", &"espectro", &"blindado"]
	var expected_names: Array[String] = [BOSS_NAME_NEXUS, BOSS_NAME_ESPECTRO, BOSS_NAME_BLINDADO]
	var volleys: Array[Array] = []

	for chapter_index: int in range(1, TOTAL_CHAPTERS + 1):
		for wave_index: int in TOTAL_WAVES:
			await _clear_current_wave(main)
			await _finish_wave_transition(main)
			await _wait_for_bonus(main)
		var boss: Area2D = _find_boss(main)
		if boss == null:
			push_error("Chapter %d must spawn its boss" % chapter_index)
			passed = false
			break
		var variant: Variant = boss.get("boss_variant")
		if variant != expected_variants[chapter_index - 1]:
			push_error("Chapter %d boss_variant must be %s, got %s" % [chapter_index, expected_variants[chapter_index - 1], str(variant)])
			passed = false
		if name_label.text != "BOSS: %s" % expected_names[chapter_index - 1]:
			push_error("Chapter %d boss bar must read '%s', got '%s'" % [chapter_index, expected_names[chapter_index - 1], name_label.text])
			passed = false
		await _wait_until_boss_in_cruise(boss)
		var sizes: Array[int] = _sample_volley_sizes(boss, 2)
		volleys.append(sizes)
		if chapter_index == TOTAL_CHAPTERS:
			passed = await _assert_blindado_phase_feedback(main, boss) and passed
		boss.call("take_damage", int(boss.get("health")))
		await process_frame
		await process_frame
		if chapter_index < TOTAL_CHAPTERS:
			await _finish_wave_transition(main)

	if volleys.size() == TOTAL_CHAPTERS:
		if volleys[0] != [2, 1]:
			push_error("Nexus volleys must keep the chapter 1 pattern [2, 1], got %s" % str(volleys[0]))
			passed = false
		if volleys[1] != [5, 8]:
			push_error("Espectro must alternate a fan of 5 with a ring of 8, got %s" % str(volleys[1]))
			passed = false
	else:
		passed = false

	root.remove_child(main)
	main.free()
	return passed


# Núcleo Blindado feedback (T7): each armor phase change emits armor_phase_changed,
# shakes the camera and shows its short text on screen.
func _assert_blindado_phase_feedback(main: Node2D, boss: Area2D) -> bool:
	var passed: bool = true
	var camera: Camera2D = main.get_node("Camera2D") as Camera2D
	var popups: Node = main.get_node("VisualFeedback/ExplosionLayer")
	var phases: Array[int] = []
	boss.connect(&"armor_phase_changed", func(phase: int) -> void: phases.append(phase))

	camera.set("trauma", 0.0)
	boss.call("take_damage", 102)
	if phases != [2]:
		push_error("Losing the exterior armor must emit phase 2, got %s" % str(phases))
		passed = false
	if not _has_label_text(popups, ARMOR_BROKEN_TEXT):
		push_error("Breaking the exterior armor must show '%s'" % ARMOR_BROKEN_TEXT)
		passed = false
	if float(camera.get("trauma")) <= 0.0:
		push_error("Breaking the exterior armor must shake the camera")
		passed = false

	camera.set("trauma", 0.0)
	boss.call("take_damage", 99)
	if phases != [2, 3]:
		push_error("Exposing the core must emit phase 3 after phase 2, got %s" % str(phases))
		passed = false
	if not _has_label_text(popups, CORE_EXPOSED_TEXT):
		push_error("Exposing the core must show '%s'" % CORE_EXPOSED_TEXT)
		passed = false
	if float(camera.get("trauma")) <= 0.0:
		push_error("Exposing the core must shake the camera")
		passed = false
	return passed


# Fires two volleys by emitting the boss shoot timer and returns the bullets each one created.
func _sample_volley_sizes(boss: Area2D, volley_count: int) -> Array[int]:
	var sizes: Array[int] = []
	var shoot_timer: Timer = boss.get_node("ShootTimer") as Timer
	for _volley: int in volley_count:
		var before: Array = get_nodes_in_group(&"enemy_bullets")
		shoot_timer.timeout.emit()
		var created: int = 0
		for bullet: Node in get_nodes_in_group(&"enemy_bullets"):
			if not before.has(bullet):
				created += 1
				bullet.queue_free()
		sizes.append(created)
	return sizes


func _wait_until_boss_in_cruise(boss: Area2D) -> void:
	for _frame: int in range(600):
		if int(boss.call("get_movement_state")) != 0:
			return
		await process_frame


func _has_label_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child: Node in node.get_children():
		if _has_label_text(child, text):
			return true
	return false


# Wave-cleared feedback (T6): clearing a normal wave shows the "¡OLEADA SUPERADA!"
# banner, pulses the Camera2D zoom away from 1.0 and grants the player a 1.5-2 s
# invulnerability window in which enemy contact costs no life.
func _assert_wave_cleared_feedback_contract() -> bool:
	var main: Node2D = (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	await process_frame
	var passed: bool = true
	main.set("enemy_drop_chance", 0.0)
	main.set("bonus_drop_interval", 0.0)

	var player: CharacterBody2D = main.get_node("Player") as CharacterBody2D
	var camera: Camera2D = main.get_node("Camera2D") as Camera2D
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var spawner: Node2D = main.get_node("EnemySpawner") as Node2D

	# Let the spawn-time invulnerability expire so only the wave-cleared grace is measured.
	await create_timer(WAVE_CLEARED_GRACE_MAX).timeout
	await _clear_current_wave(main)
	await process_frame

	if not hud.has_method(&"get_wave_cleared_banner_text") or str(hud.call(&"get_wave_cleared_banner_text")) != WAVE_CLEARED_BANNER_TEXT:
		push_error("Clearing a normal wave must show the banner '%s'" % WAVE_CLEARED_BANNER_TEXT)
		passed = false
	if camera.zoom == Vector2.ONE:
		push_error("Clearing a normal wave must change the camera zoom away from 1.0")
		passed = false

	var lives_before: int = main.lives
	spawner.enemy_contacted_player.emit(player)
	if main.lives != lives_before:
		push_error("Player must be invulnerable right after clearing a wave (lives %d -> %d)" % [lives_before, main.lives])
		passed = false
	if not player.has_method(&"get_invulnerability_time_left"):
		push_error("Player must expose get_invulnerability_time_left()")
		passed = false
	else:
		var grace: float = float(player.call(&"get_invulnerability_time_left"))
		if grace < WAVE_CLEARED_GRACE_MIN or grace > WAVE_CLEARED_GRACE_MAX:
			push_error("Wave-cleared invulnerability must last 1.5-2 s, got %.2f s" % grace)
			passed = false

	# Effects end on their own: zoom back to 1.0 and banner hidden after its display time (2.5 s).
	await create_timer(2.75).timeout
	if camera.zoom != Vector2.ONE:
		push_error("Camera zoom must return to 1.0 after the wave-cleared effect")
		passed = false
	if hud.has_method(&"get_wave_cleared_banner_text") and str(hud.call(&"get_wave_cleared_banner_text")) != "":
		push_error("Wave-cleared banner must hide after its display time")
		passed = false

	root.remove_child(main)
	main.free()
	return passed


func _spawn_test_boss(boss_scene: PackedScene, multi_phase: bool) -> Area2D:
	var boss: Area2D = boss_scene.instantiate() as Area2D
	boss.max_health = BLINDADO_MAX_HEALTH
	boss.set("multi_phase_enabled", multi_phase)
	root.add_child(boss)
	return boss


func _wait_for_bonus(main: Node2D) -> void:
	for _frame: int in range(400):
		if not main.is_bonus_wave_active():
			return
		await process_frame


func _find_boss(main: Node2D) -> Area2D:
	for child: Node in main.get_children():
		if child is Area2D and child.has_signal(&"boss_defeated"):
			return child as Area2D
	return null


func _clear_current_wave(main: Node2D) -> void:
	if main.has_method("is_asteroid_wave_active") and main.call("is_asteroid_wave_active"):
		var asteroid_spawner: Node2D = main.call("get_asteroid_spawner") as Node2D
		for _attempt: int in range(500):
			if asteroid_spawner == null or not asteroid_spawner.call("is_wave_active"):
				break
			asteroid_spawner.set("_spawn_timer", 0.0)
			for child: Node in asteroid_spawner.get_children():
				if is_instance_valid(child) and child is Area2D and child.has_method("destroy"):
					child.call("destroy")
			await process_frame
		return
	var spawner: Node2D = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return
	for child: Node in spawner.get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			var enemy: Area2D = child as Area2D
			if enemy.has_method("destroy"):
				enemy.destroy()
	await create_timer(0.0).timeout


func _finish_wave_transition(main: Node2D) -> void:
	await process_frame
	await process_frame
	await process_frame
