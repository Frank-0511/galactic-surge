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
# Etapa 15 T5: wave 5 of every chapter is guarded by a sector guardian.
const GUARDIAN_WAVE_NUMBER: int = 5
const GUARDIAN_MAX_HEALTH: int = 80
const GUARDIAN_POINTS: int = 500
const CLEAN_WAVE_BONUS: int = 500
# Etapa 15 T6: wave-cleared feedback (banner, camera zoom, invulnerability grace).
const WAVE_CLEARED_BANNER_TEXT: String = "¡OLEADA SUPERADA!"
const WAVE_CLEARED_GRACE_MIN: float = 1.5
const WAVE_CLEARED_GRACE_MAX: float = 2.0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = await _assert_chapter_structure_contract() and passed
	passed = await _assert_bonus_wave_contract() and passed
	passed = await _assert_guardian_contract() and passed
	passed = await _assert_blindado_core_contract() and passed
	passed = await _assert_wave_cleared_feedback_contract() and passed
	quit(0 if passed else 1)


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


# Sector guardian (T5): wave 5 of each chapter spawns a guardian with 80 HP and no
# multi-phase. The wave is not cleared while the guardian lives; defeating it
# advances the wave, pays 500 points and drops a medallion.
func _assert_guardian_contract() -> bool:
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

	for wave_index: int in GUARDIAN_WAVE_NUMBER - 1:
		await _clear_current_wave(main)
		await _finish_wave_transition(main)
	if main.wave != GUARDIAN_WAVE_NUMBER:
		push_error("Expected wave %d before its guardian, got %d" % [GUARDIAN_WAVE_NUMBER, main.wave])
		root.remove_child(main)
		main.free()
		return false

	var guardian: Area2D = _find_boss(main)
	if guardian == null:
		push_error("Wave %d must spawn a sector guardian" % GUARDIAN_WAVE_NUMBER)
		root.remove_child(main)
		main.free()
		return false
	if int(guardian.get("max_health")) != GUARDIAN_MAX_HEALTH:
		push_error("Sector guardian must have max_health %d, got %d" % [GUARDIAN_MAX_HEALTH, int(guardian.get("max_health"))])
		passed = false
	if bool(guardian.get("multi_phase_enabled")):
		push_error("Sector guardian must not enable multi-phase")
		passed = false

	# The wave must stay alive while the guardian lives.
	for _frame: int in range(60):
		await process_frame
	if main.wave != GUARDIAN_WAVE_NUMBER or not is_instance_valid(guardian):
		push_error("Wave %d must not clear while its guardian is alive" % GUARDIAN_WAVE_NUMBER)
		passed = false

	# Defeating the guardian clears the wave and advances to the next one.
	var score_before: int = main.score
	guardian.call("take_damage", GUARDIAN_MAX_HEALTH)
	await process_frame
	await process_frame
	await _finish_wave_transition(main)
	if main.wave != GUARDIAN_WAVE_NUMBER + 1:
		push_error("Defeating the guardian must advance to wave %d, got %d" % [GUARDIAN_WAVE_NUMBER + 1, main.wave])
		passed = false
	# No damage was taken, so the clean wave bonus applies on top of the guardian points.
	if main.score - score_before != GUARDIAN_POINTS + CLEAN_WAVE_BONUS:
		push_error("Guardian defeat must award %d points, got %d" % [GUARDIAN_POINTS + CLEAN_WAVE_BONUS, main.score - score_before])
		passed = false
	var has_medallion: bool = false
	for child: Node in main.get_children():
		if child.has_method("get_type") and int(child.call("get_type")) == LootDrop.Type.MEDALLION_BLASTER:
			has_medallion = true
	if not has_medallion:
		push_error("Defeating the sector guardian must drop a medallion")
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
	# Sector guardians (wave 5) must also fall to clear the wave.
	var guardian: Area2D = _find_boss(main)
	if guardian != null and int(guardian.get("max_health")) == GUARDIAN_MAX_HEALTH:
		guardian.call("take_damage", GUARDIAN_MAX_HEALTH)
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
