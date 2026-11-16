# Contract harness for Etapa 5: Boss Battle.
# Verifies AudioFeedback BossMusic, BossBullet, Boss entity, HUD boss health bar,
# and Main orchestration of the Boss encounter upon clearing wave 5.
extends SceneTree

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const AUDIO_FEEDBACK_SCENE_PATH := "res://features/audio/audio_feedback.tscn"
const HUD_SCENE_PATH := "res://features/ui/hud.tscn"
const BOSS_SCENE_PATH := "res://features/boss/boss.tscn"
const BOSS_BULLET_SCENE_PATH := "res://features/boss/boss_bullet.tscn"
const BOSS_MUSIC_PATH := "res://assets/audio/music/boss_battle_8bit.mp3"

const BOSS_MAX_HEALTH: int = 150
const BOSS_DEFEAT_SCORE: int = 3000
const TOTAL_WAVES: int = 10


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = _assert_audio_feedback_boss_contract() and passed
	passed = await _assert_boss_bullet_contract() and passed
	passed = await _assert_boss_entity_contract() and passed
	passed = _assert_hud_boss_health_bar_contract() and passed
	passed = await _assert_main_boss_integration_contract() and passed
	quit(0 if passed else 1)


# ---------------------------------------------------------------------------
# 1. AudioFeedback BossMusic contract
# ---------------------------------------------------------------------------

func _assert_audio_feedback_boss_contract() -> bool:
	var packed_scene: PackedScene = load(AUDIO_FEEDBACK_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % AUDIO_FEEDBACK_SCENE_PATH)
		return false
	var audio_feedback: Node = packed_scene.instantiate()
	if audio_feedback == null:
		push_error("AudioFeedback scene root must be Node")
		return false
	root.add_child(audio_feedback)
	var passed: bool = true

	# Must have BossMusic AudioStreamPlayer child.
	var boss_music: AudioStreamPlayer = audio_feedback.get_node_or_null("BossMusic") as AudioStreamPlayer
	if boss_music == null:
		push_error("AudioFeedback missing AudioStreamPlayer child: BossMusic")
		passed = false
	else:
		if boss_music.stream == null or boss_music.stream.resource_path != BOSS_MUSIC_PATH:
			push_error("BossMusic must use asset %s" % BOSS_MUSIC_PATH)
			passed = false
		if boss_music.autoplay:
			push_error("BossMusic autoplay must be false")
			passed = false
		if absf(boss_music.volume_db - (-10.89)) > 0.05:
			push_error("BossMusic volume_db must be around -10.89 dB, got %f" % boss_music.volume_db)
			passed = false

	# Must declare boss music API methods.
	for method_name: StringName in [&"start_boss_music", &"stop_boss_music"]:
		if not audio_feedback.has_method(method_name):
			push_error("AudioFeedback missing method: %s" % method_name)
			passed = false

	# Behavioral test for boss music.
	if boss_music != null and audio_feedback.has_method(&"start_boss_music") and audio_feedback.has_method(&"stop_boss_music"):
		audio_feedback.call("start_boss_music")
		if not boss_music.playing:
			push_error("start_boss_music() must start BossMusic")
			passed = false
		audio_feedback.call("set_session_paused", true)
		if not boss_music.stream_paused:
			push_error("set_session_paused(true) must pause BossMusic stream")
			passed = false
		audio_feedback.call("set_session_paused", false)
		if boss_music.stream_paused:
			push_error("set_session_paused(false) must unpause BossMusic stream")
			passed = false
		audio_feedback.call("stop_boss_music")
		if boss_music.playing:
			push_error("stop_boss_music() must stop BossMusic")
			passed = false

	root.remove_child(audio_feedback)
	audio_feedback.free()
	return passed


# ---------------------------------------------------------------------------
# 2. BossBullet contract
# ---------------------------------------------------------------------------

func _assert_boss_bullet_contract() -> bool:
	if not ResourceLoader.exists(BOSS_BULLET_SCENE_PATH):
		push_error("Missing scene: %s" % BOSS_BULLET_SCENE_PATH)
		return false
	var packed_scene: PackedScene = load(BOSS_BULLET_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % BOSS_BULLET_SCENE_PATH)
		return false
	var bullet: Area2D = packed_scene.instantiate() as Area2D
	if bullet == null:
		push_error("BossBullet root must be Area2D")
		return false
	root.add_child(bullet)
	var passed: bool = true

	if not bullet.is_in_group(&"enemy_bullets"):
		push_error("BossBullet must be in group 'enemy_bullets'")
		passed = false
	if not bullet.is_in_group(&"combat_transients"):
		push_error("BossBullet must be in group 'combat_transients'")
		passed = false
	if not bullet.has_signal(&"player_hit"):
		push_error("BossBullet missing signal: player_hit")
		passed = false
	if not "direction" in bullet:
		push_error("BossBullet missing property: direction")
		passed = false
	if not "speed" in bullet:
		push_error("BossBullet missing property: speed")
		passed = false

	# Check bullet movement.
	if "direction" in bullet and "speed" in bullet:
		bullet.global_position = Vector2(300, 100)
		bullet.set("direction", Vector2(0, 1))
		bullet.set("speed", 400.0)
		var y_initial: float = bullet.global_position.y
		await create_timer(0.05).timeout
		if bullet.global_position.y <= y_initial:
			push_error("BossBullet must advance along direction vector over time")
			passed = false

	# Test player contact emission.
	var bullet2: Area2D = packed_scene.instantiate() as Area2D
	if bullet2 != null:
		root.add_child(bullet2)
		var hit_count: Array[int] = [0]
		if bullet2.has_signal(&"player_hit"):
			bullet2.connect(&"player_hit", func(_p: Node2D) -> void: hit_count[0] += 1)
		var fake_player: CharacterBody2D = CharacterBody2D.new()
		fake_player.add_to_group(&"player", true)
		root.add_child(fake_player)
		bullet2.call("_on_body_entered", fake_player)
		await process_frame
		fake_player.queue_free()
		if hit_count[0] != 1:
			push_error("BossBullet must emit player_hit when contacting player body")
			passed = false
		if is_instance_valid(bullet2):
			bullet2.queue_free()

	if is_instance_valid(bullet):
		root.remove_child(bullet)
		bullet.free()
	return passed


# ---------------------------------------------------------------------------
# 3. Boss entity contract
# ---------------------------------------------------------------------------

func _assert_boss_entity_contract() -> bool:
	if not ResourceLoader.exists(BOSS_SCENE_PATH):
		push_error("Missing scene: %s" % BOSS_SCENE_PATH)
		return false
	var packed_scene: PackedScene = load(BOSS_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Failed to load scene: %s" % BOSS_SCENE_PATH)
		return false
	var boss: Area2D = packed_scene.instantiate() as Area2D
	if boss == null:
		push_error("Boss root must be Area2D")
		return false
	root.add_child(boss)
	var passed: bool = true

	if not boss.is_in_group(&"enemies"):
		push_error("Boss must be in group 'enemies'")
		passed = false

	# Required signals.
	for sig: StringName in [&"health_changed", &"boss_defeated", &"boss_contacted_player"]:
		if not boss.has_signal(sig):
			push_error("Boss missing signal: %s" % sig)
			passed = false

	# Required method take_damage.
	if not boss.has_method(&"take_damage"):
		push_error("Boss missing method: take_damage")
		passed = false

	# Health properties.
	var max_hp: int = int(boss.get("max_health")) if "max_health" in boss else -1
	var current_hp: int = int(boss.get("health")) if "health" in boss else (int(boss.get("current_health")) if "current_health" in boss else -1)
	if max_hp != BOSS_MAX_HEALTH:
		push_error("Boss max_health must be %d, got %d" % [BOSS_MAX_HEALTH, max_hp])
		passed = false
	if current_hp != BOSS_MAX_HEALTH:
		push_error("Boss initial health must be %d, got %d" % [BOSS_MAX_HEALTH, current_hp])
		passed = false

	# Damage logic and health_changed signal.
	if boss.has_method(&"take_damage"):
		var hp_signals: Array[Dictionary] = []
		boss.connect(&"health_changed", func(cur: int, m_hp: int) -> void:
			hp_signals.append({"current": cur, "max": m_hp})
		)
		boss.call("take_damage", 20)
		if hp_signals.is_empty():
			push_error("Boss take_damage() must emit health_changed")
			passed = false
		elif hp_signals[-1]["current"] != 130 or hp_signals[-1]["max"] != 150:
			push_error("health_changed arguments incorrect: expected (130, 150), got %s" % str(hp_signals[-1]))
			passed = false

		# Phase 1 vs Phase 2 (enraged).
		# At 130 HP (> 75), is_enraged should be false.
		if "is_enraged" in boss and bool(boss.get("is_enraged")):
			push_error("Boss must not be enraged at 130 HP (> 75)")
			passed = false
		# Deal 55 more damage -> 75 HP (<= 75): enraged phase.
		boss.call("take_damage", 55)
		if "is_enraged" in boss and not bool(boss.get("is_enraged")):
			push_error("Boss must become enraged at 75 HP (<= 75)")
			passed = false

		# Defeat when HP reaches 0.
		var defeated_count: Array[int] = [0]
		boss.connect(&"boss_defeated", func(_b: Area2D) -> void: defeated_count[0] += 1)
		boss.call("take_damage", 75)
		if defeated_count[0] != 1:
			push_error("Boss take_damage reaching 0 HP must emit boss_defeated exactly once")
			passed = false

	# Player body contact emission.
	var boss2: Area2D = packed_scene.instantiate() as Area2D
	if boss2 != null:
		root.add_child(boss2)
		var contact_count: Array[int] = [0]
		if boss2.has_signal(&"boss_contacted_player"):
			boss2.connect(&"boss_contacted_player", func(_p: Node2D) -> void: contact_count[0] += 1)
		var fake_player: CharacterBody2D = CharacterBody2D.new()
		fake_player.add_to_group(&"player", true)
		root.add_child(fake_player)
		boss2.call("_on_body_entered", fake_player)
		await process_frame
		fake_player.queue_free()
		if contact_count[0] != 1:
			push_error("Boss must emit boss_contacted_player when player body collides")
			passed = false
		if is_instance_valid(boss2):
			boss2.queue_free()

	# Dynamic movement, banking tilt, and dive maneuver contract.
	var boss3: Area2D = packed_scene.instantiate() as Area2D
	if boss3 != null:
		root.add_child(boss3)
		boss3.global_position = Vector2(400, 140)
		boss3._process(0.02) # Triggers ENTERING -> CRUISE transition

		# Verify sinusoidal vertical oscillation in CRUISE
		var min_y: float = 99999.0
		var max_y: float = -99999.0
		var has_tilted: bool = false
		for i in 50:
			boss3._process(0.05)
			var cur_y: float = boss3.global_position.y
			min_y = minf(min_y, cur_y)
			max_y = maxf(max_y, cur_y)
			if absf(boss3.rotation) > 0.05:
				has_tilted = true

		if (max_y - min_y) < 30.0:
			push_error("Boss must vary dynamically in Y during combat, oscillation amplitude too small: min=%f, max=%f" % [min_y, max_y])
			passed = false

		if not has_tilted:
			push_error("Boss must exhibit dynamic banking tilt during horizontal/diagonal navigation")
			passed = false

		# Verify dive maneuver reaching lower altitude
		if boss3.has_method(&"trigger_dive"):
			boss3.call("trigger_dive")
			var max_dive_y: float = -99999.0
			for i in 80:
				boss3._process(0.05)
				max_dive_y = maxf(max_dive_y, boss3.global_position.y)

			if max_dive_y < 700.0:
				push_error("Boss must reach lower altitudes during dive maneuvers, reached only Y=%f" % max_dive_y)
				passed = false

		if is_instance_valid(boss3):
			boss3.queue_free()

	if is_instance_valid(boss):
		root.remove_child(boss)
		boss.free()
	return passed


# ---------------------------------------------------------------------------
# 4. HUD Boss health bar contract
# ---------------------------------------------------------------------------

func _assert_hud_boss_health_bar_contract() -> bool:
	var packed_scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % HUD_SCENE_PATH)
		return false
	var hud: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if hud == null:
		push_error("HUD root must be CanvasLayer")
		return false
	root.add_child(hud)
	var passed: bool = true

	for method_name: StringName in [&"show_boss_health_bar", &"update_boss_health", &"hide_boss_health_bar"]:
		if not hud.has_method(method_name):
			push_error("HUD missing method: %s" % method_name)
			passed = false

	# Check boss bar node existence and initial hidden state.
	var boss_bar_container: Control = hud.get_node_or_null("BossContainer") as Control
	if boss_bar_container == null:
		boss_bar_container = hud.get_node_or_null("BossHealthContainer") as Control
	if boss_bar_container == null:
		boss_bar_container = hud.get_node_or_null("BossBar") as Control
	if boss_bar_container != null and boss_bar_container.visible:
		push_error("HUD boss health bar container must start hidden")
		passed = false

	# Behavioral test.
	if hud.has_method(&"show_boss_health_bar"):
		hud.call("show_boss_health_bar", "NAVE NODRIZA NEXUS", 30)
		if boss_bar_container != null and not boss_bar_container.visible:
			push_error("HUD boss health bar container must be visible after show_boss_health_bar()")
			passed = false

		var name_label: Label = hud.find_child("BossNameLabel", true, false) as Label
		if name_label == null:
			push_error("HUD missing BossNameLabel child")
			passed = false
		elif not name_label.text.contains("NAVE NODRIZA NEXUS"):
			push_error("BossNameLabel text must contain boss name, got '%s'" % name_label.text)
			passed = false

		var progress_bar: Range = hud.find_child("BossProgressBar", true, false) as Range
		if progress_bar == null:
			push_error("HUD missing BossProgressBar child")
			passed = false
		else:
			if int(progress_bar.max_value) != 30 or int(progress_bar.value) != 30:
				push_error("BossProgressBar must initialize with max=30 and val=30, got max=%f, val=%f" % [progress_bar.max_value, progress_bar.value])
				passed = false

		if hud.has_method(&"update_boss_health") and progress_bar != null:
			hud.call("update_boss_health", 18, 30)
			if int(progress_bar.value) != 18:
				push_error("update_boss_health(18, 30) must set ProgressBar value to 18, got %f" % progress_bar.value)
				passed = false

		if hud.has_method(&"hide_boss_health_bar"):
			hud.call("hide_boss_health_bar")
			if boss_bar_container != null and boss_bar_container.visible:
				push_error("hide_boss_health_bar() must hide boss health bar container")
				passed = false

	root.remove_child(hud)
	hud.free()
	return passed


# ---------------------------------------------------------------------------
# 5. Main Boss Integration contract
# ---------------------------------------------------------------------------

func _assert_main_boss_integration_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	if main == null:
		push_error("Main root must be Node2D")
		return false
	root.add_child(main)
	main.start_session()
	await process_frame
	var passed: bool = true

	# Zero out announcement duration and drop chance for deterministic flow.
	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	if announcement != null and "display_duration" in announcement:
		announcement.set("display_duration", 0.0)
	if "enemy_drop_chance" in main:
		main.set("enemy_drop_chance", 0.0)
	if "clear_wave_drop_chance" in main:
		main.set("clear_wave_drop_chance", 0.0)
	main.set("bonus_drop_interval", 0.0)

	# Fast-forward clearing waves 1 to 5.
	for wave_index: int in TOTAL_WAVES:
		await _clear_current_wave(main)
		await _finish_wave_transition(main)

	# After wave 5, mission must NOT be complete immediately.
	if main.has_method("is_mission_complete") and main.is_mission_complete():
		push_error("Main must NOT complete mission immediately upon clearing wave 5; Boss must be defeated first")
		passed = false

	# Locate the Boss instance in Main.
	var boss: Area2D = null
	for child: Node in main.get_children():
		if child is Area2D and child.has_signal(&"boss_defeated"):
			boss = child as Area2D
			break

	if boss == null:
		push_error("Main must spawn Boss after clearing wave 5")
		passed = false
	else:
		# Check Boss music started and regular combat music stopped.
		var audio_feedback: Node = main.get_node_or_null("AudioFeedback")
		if audio_feedback != null:
			var boss_music: AudioStreamPlayer = audio_feedback.get_node_or_null("BossMusic") as AudioStreamPlayer
			var combat_music: AudioStreamPlayer = audio_feedback.get_node_or_null("CombatMusic") as AudioStreamPlayer
			if boss_music != null and not boss_music.playing:
				push_error("Boss music must be playing during boss battle")
				passed = false
			if combat_music != null and combat_music.playing:
				push_error("Combat music must be stopped during boss battle")
				passed = false

		# Check HUD boss health bar is visible.
		var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
		if hud != null:
			var boss_container: Control = hud.get_node_or_null("BossContainer") as Control
			if boss_container == null:
				boss_container = hud.get_node_or_null("BossHealthContainer") as Control
			if boss_container == null:
				boss_container = hud.get_node_or_null("BossBar") as Control
			if boss_container != null and not boss_container.visible:
				push_error("Boss health bar in HUD must be visible during boss battle")
				passed = false

		# Now defeat the boss and verify victory sequence.
		var score_before_defeat: int = main.score
		if boss.has_method(&"take_damage"):
			boss.call("take_damage", BOSS_MAX_HEALTH)
		await process_frame
		await process_frame

		# Etapa 15: defeating the chapter 1 Boss starts chapter 2; mission completes only after chapter 3.
		if main.is_mission_complete():
			push_error("Defeating the chapter 1 Boss must NOT complete the mission")
			passed = false
		for chapter_index: int in range(2):
			await _finish_wave_transition(main)
			for wave_index: int in TOTAL_WAVES:
				await _clear_current_wave(main)
				await _finish_wave_transition(main)
			var next_boss: Area2D = null
			for child: Node in main.get_children():
				if child is Area2D and child.has_signal(&"boss_defeated"):
					next_boss = child as Area2D
			if next_boss == null:
				push_error("Chapter %d must spawn its Boss" % (chapter_index + 2))
				passed = false
				break
			next_boss.call("take_damage", int(next_boss.get("max_health")))
			await process_frame
			await process_frame
		if not main.has_method("is_mission_complete") or not main.is_mission_complete():
			push_error("Defeating the last Boss must trigger mission complete")
			passed = false

		if main.score - score_before_defeat < BOSS_DEFEAT_SCORE:
			push_error("Defeating Boss must award %d points, got %d" % [BOSS_DEFEAT_SCORE, main.score - score_before_defeat])
			passed = false

		if audio_feedback != null:
			var boss_music: AudioStreamPlayer = audio_feedback.get_node_or_null("BossMusic") as AudioStreamPlayer
			if boss_music != null and boss_music.playing:
				push_error("Boss music must stop upon defeating the boss")
				passed = false

	root.remove_child(main)
	main.free()
	return passed


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _clear_current_wave(main: Node2D) -> void:
	# Wave 9 is the ADR 011 asteroid belt, which has no fighters to destroy.
	if main.has_method("is_asteroid_wave_active") and main.call("is_asteroid_wave_active"):
		await _clear_asteroid_wave(main)
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


# Destroys every asteroid and fragment of the belt wave until the spawner reports
# completion. Spawn timing uses wall-clock delta, so the timer is forced to 0 on
# each frame to spawn pending asteroids without waiting.
func _find_boss(main: Node2D) -> Area2D:
	for child: Node in main.get_children():
		if child is Area2D and child.has_signal(&"boss_defeated"):
			return child as Area2D
	return null


func _clear_asteroid_wave(main: Node2D) -> void:
	var asteroid_spawner: Node2D = main.call("get_asteroid_spawner") as Node2D
	if asteroid_spawner == null:
		return
	for _attempt: int in range(500):
		if not asteroid_spawner.call("is_wave_active"):
			return
		asteroid_spawner.set("_spawn_timer", 0.0)
		for child: Node in asteroid_spawner.get_children():
			if is_instance_valid(child) and child is Area2D and child.has_method("destroy"):
				child.call("destroy")
		await process_frame


func _finish_wave_transition(main: Node2D) -> void:
	await process_frame
	await process_frame
	await process_frame
	# Etapa 15: wave 8 is a peaceful bonus that runs on its own; wait for it to end.
	for _frame: int in range(400):
		if not main.has_method("is_bonus_wave_active") or not main.is_bonus_wave_active():
			return
		await process_frame
