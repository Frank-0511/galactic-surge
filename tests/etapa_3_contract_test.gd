# Contract harness for the Etapa 3 waves, scoring, and HUD systems.
extends SceneTree

const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"
const SPAWNER_SCENE_PATH := "res://scenes/systems/enemy_spawner.tscn"
const GAME_OVER_SCENE_PATH := "res://scenes/ui/game_over.tscn"

const POINTS_PER_ENEMY: int = 100
const CLEAN_WAVE_BONUS: int = 500
const STARTING_LIVES: int = 3
const TOTAL_WAVES: int = 10


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = _assert_hud_contract() and passed
	passed = _assert_spawner_wave_contract() and passed
	passed = _assert_main_owns_state_contract() and passed
	passed = await _assert_score_contract() and passed
	passed = await _assert_clean_wave_bonus_contract() and passed
	passed = _assert_wave_progression_contract() and passed
	passed = _assert_game_over_score_contract() and passed
	passed = await _assert_mission_complete_contract() and passed
	passed = _assert_retry_reset_contract() and passed
	quit(0 if passed else 1)


func _assert_hud_contract() -> bool:
	var packed_scene: PackedScene = load(HUD_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % HUD_SCENE_PATH)
		return false
	var hud: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if hud == null:
		push_error("HUD scene root must be CanvasLayer")
		return false
	root.add_child(hud)
	var passed: bool = true
	if not hud.has_signal("lives_changed"):
		push_error("HUD missing signal: lives_changed")
		passed = false
	if not hud.has_signal("score_changed"):
		push_error("HUD missing signal: score_changed")
		passed = false
	if not hud.has_signal("wave_changed"):
		push_error("HUD missing signal: wave_changed")
		passed = false
	for method_name: String in ["set_lives", "set_score", "set_wave", "show_mission_complete", "hide_mission_complete"]:
		if not hud.has_method(method_name):
			push_error("HUD missing public method: %s" % method_name)
			passed = false
	for signal_name: String in ["lives_changed", "score_changed", "wave_changed", "retry_mission_requested", "main_menu_requested"]:
		if not hud.has_signal(signal_name):
			push_error("HUD missing signal: %s" % signal_name)
			passed = false
	for node_path: String in ["Margin/LivesLabel", "Margin/ScoreLabel", "Margin/WaveLabel", "VictoryLabel", "VictoryScoreLabel", "RetryButton", "MainMenuButton"]:
		if hud.get_node_or_null(node_path) == null:
			push_error("HUD missing node: %s" % node_path)
			passed = false
	# Victory labels must start hidden.
	var victory_label: Label = hud.get_node("VictoryLabel") as Label
	var victory_score_label: Label = hud.get_node("VictoryScoreLabel") as Label
	if victory_label != null and victory_label.visible:
		push_error("HUD VictoryLabel must start hidden")
		passed = false
	if victory_score_label != null and victory_score_label.visible:
		push_error("HUD VictoryScoreLabel must start hidden")
		passed = false
	# Final buttons must start hidden during normal play.
	var retry_button: CanvasItem = hud.get_node_or_null("RetryButton") as CanvasItem
	if retry_button != null and retry_button.visible:
		push_error("HUD RetryButton must start hidden")
		passed = false
	var main_menu_button: CanvasItem = hud.get_node_or_null("MainMenuButton") as CanvasItem
	if main_menu_button != null and main_menu_button.visible:
		push_error("HUD MainMenuButton must start hidden")
		passed = false
	# show_mission_complete() must reveal the victory copy and buttons, and focus RetryButton.
	hud.show_mission_complete(12345)
	if victory_label == null or victory_label.text != "¡Victoria!":
		push_error("HUD VictoryLabel must show '¡Victoria!' after show_mission_complete()")
		passed = false
	if victory_score_label == null or not victory_score_label.text.contains("12345"):
		push_error("HUD VictoryScoreLabel must contain the final score after show_mission_complete()")
		passed = false
	if victory_label != null and not victory_label.visible:
		push_error("HUD VictoryLabel must be visible after show_mission_complete()")
		passed = false
	if victory_score_label != null and not victory_score_label.visible:
		push_error("HUD VictoryScoreLabel must be visible after show_mission_complete()")
		passed = false
	if retry_button != null and not retry_button.visible:
		push_error("HUD RetryButton must be visible after show_mission_complete()")
		passed = false
	if main_menu_button != null and not main_menu_button.visible:
		push_error("HUD MainMenuButton must be visible after show_mission_complete()")
		passed = false
	if retry_button is Control and not retry_button.has_focus():
		push_error("HUD RetryButton must grab focus after show_mission_complete()")
		passed = false
	# hide_mission_complete() must hide everything again.
	hud.hide_mission_complete()
	if victory_label != null and victory_label.visible:
		push_error("HUD VictoryLabel must be hidden after hide_mission_complete()")
		passed = false
	if victory_score_label != null and victory_score_label.visible:
		push_error("HUD VictoryScoreLabel must be hidden after hide_mission_complete()")
		passed = false
	if retry_button != null and retry_button.visible:
		push_error("HUD RetryButton must be hidden after hide_mission_complete()")
		passed = false
	if main_menu_button != null and main_menu_button.visible:
		push_error("HUD MainMenuButton must be hidden after hide_mission_complete()")
		passed = false
	# HUD must not have a VictoryScreen child.
	if hud.get_node_or_null("VictoryScreen") != null:
		push_error("HUD must not have a VictoryScreen node")
		passed = false
	hud.free()
	return passed


func _assert_spawner_wave_contract() -> bool:
	var packed_scene: PackedScene = load(SPAWNER_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % SPAWNER_SCENE_PATH)
		return false
	var spawner: Node2D = packed_scene.instantiate() as Node2D
	if spawner == null:
		push_error("EnemySpawner scene root must be Node2D")
		return false
	var passed: bool = true
	# Wave configuration export.
	if not spawner.has_method("get_total_waves") or spawner.get_total_waves() != TOTAL_WAVES:
		push_error("EnemySpawner must report %d total waves" % TOTAL_WAVES)
		passed = false
	if not spawner.has_method("get_current_wave"):
		push_error("EnemySpawner missing method: get_current_wave")
		passed = false
	if not spawner.has_signal("wave_cleared"):
		push_error("EnemySpawner missing signal: wave_cleared")
		passed = false
	if not spawner.has_signal("all_waves_cleared"):
		push_error("EnemySpawner missing signal: all_waves_cleared")
		passed = false
	# Wave 1 must remain 3x6 at 80 px/s.
	if spawner.rows != 3 or spawner.columns != 6:
		push_error("Wave 1 formation must be 3x6")
		passed = false
	if spawner.formation_speed != 80.0:
		push_error("Wave 1 formation_speed must be 80.0")
		passed = false
	spawner.free()
	return passed


func _assert_main_owns_state_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	if main == null:
		push_error("Main scene root must be Node2D")
		return false
	root.add_child(main)
	var passed: bool = true
	# Main must own lives, score, and wave as single source of truth.
	for property_name: String in ["lives", "score", "wave"]:
		if not property_name in main:
			push_error("Main must own state property: %s" % property_name)
			passed = false
	if main.get("lives") != STARTING_LIVES:
		push_error("Main lives must start at %d" % STARTING_LIVES)
		passed = false
	if main.get("score") != 0:
		push_error("Main score must start at 0")
		passed = false
	if main.get("wave") != 1:
		push_error("Main wave must start at 1")
		passed = false
	# HUD must be a separate CanvasLayer child.
	if main.get_node_or_null("HUD") == null:
		push_error("Main missing HUD child")
		passed = false
	var hud: Node = main.get_node_or_null("HUD")
	if hud != null and not (hud is CanvasLayer):
		push_error("HUD must be a CanvasLayer")
		passed = false
	# Player must spawn at the GameLayout position after start_session.
	main.call("start_session")
	var layout: GameLayout = GameLayout.new()
	layout.configure(main.get_viewport().get_visible_rect().size)
	var expected_spawn: Vector2 = layout.get_player_spawn_position()
	var player: Node2D = main.get_node_or_null("Player") as Node2D
	if player != null and player.global_position != expected_spawn:
		push_error("Player must spawn at the GameLayout position %s, got %s" % [expected_spawn, player.global_position])
		passed = false
	root.remove_child(main)
	main.free()
	return passed


func _assert_score_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	var passed: bool = true
	# Destroying one enemy must add 100 points.
	var initial_score: int = main.score
	_destroy_one_enemy(main)
	if main.score - initial_score != POINTS_PER_ENEMY:
		push_error("Destroying one enemy must add %d points, got %d" % [POINTS_PER_ENEMY, main.score - initial_score])
		passed = false
	root.remove_child(main)
	main.free()
	return passed


func _assert_clean_wave_bonus_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	var passed: bool = true
	# Clear wave 1 without taking damage: 18 enemies * 100 + 500 bonus.
	_set_zero_display_duration(main)
	var initial_score: int = main.score
	_clear_current_wave(main)
	await _finish_wave_transition(main)
	var expected: int = (5600 + CLEAN_WAVE_BONUS) if main.get_node_or_null("ComboSystem") != null else (POINTS_PER_ENEMY * 18 + CLEAN_WAVE_BONUS)
	if main.score - initial_score != expected:
		push_error("Clean wave 1 must add %d points, got %d" % [expected, main.score - initial_score])
		passed = false
	# Wave must advance after clearing.
	if main.wave != 2:
		push_error("Wave must advance to 2 after clearing wave 1, got %d" % main.wave)
		passed = false
	root.remove_child(main)
	main.free()
	return passed


func _assert_wave_progression_contract() -> bool:
	var packed_scene: PackedScene = load(SPAWNER_SCENE_PATH) as PackedScene
	if packed_scene == null:
		return false
	var spawner: Node2D = packed_scene.instantiate() as Node2D
	root.add_child(spawner)
	var passed: bool = true
	# Waves 2-5 must have increasing difficulty (speed or count).
	var wave_configs: Array = []
	for wave_index: int in TOTAL_WAVES:
		var config: Dictionary = spawner.get_wave_config(wave_index)
		wave_configs.append(config)
	# Wave 1 baseline.
	var wave1_speed: float = float(wave_configs[0].get("formation_speed", 80.0))
	if absf(wave1_speed - 80.0) > 0.01:
		push_error("Wave 1 speed must be 80.0, got %f" % wave1_speed)
		passed = false
	# At least one later wave must be faster than wave 1.
	var has_increase: bool = false
	for wave_index: int in range(1, TOTAL_WAVES):
		var wave_speed: float = float(wave_configs[wave_index].get("formation_speed", 80.0))
		if wave_speed > wave1_speed:
			has_increase = true
	if not has_increase:
		push_error("At least one wave after wave 1 must have higher speed")
		passed = false
	spawner.free()
	return passed


func _assert_game_over_score_contract() -> bool:
	var packed_scene: PackedScene = load(GAME_OVER_SCENE_PATH) as PackedScene
	if packed_scene == null:
		return false
	var game_over: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if game_over == null:
		return false
	root.add_child(game_over)
	var passed: bool = true
	# Game Over must accept and show the final score.
	if not game_over.has_method("show_game_over"):
		push_error("GameOver missing method: show_game_over")
		passed = false
	# show_game_over must accept a final_score argument without error.
	if game_over.has_method("show_game_over"):
		game_over.show_game_over(12345)
		if not game_over.visible:
			push_error("GameOver must become visible after show_game_over")
			passed = false
		var score_label: Node = game_over.get_node_or_null("Control/FinalScoreLabel")
		if score_label == null:
			push_error("GameOver missing Control/FinalScoreLabel")
			passed = false
		elif score_label is Label and not score_label.text.contains("12345"):
			push_error("GameOver FinalScoreLabel must contain the final score")
			passed = false
	game_over.free()
	return passed


func _assert_mission_complete_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	var passed: bool = true
	# Completing all 5 waves must trigger mission complete on the HUD, not a separate victory screen.
	var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		push_error("Main missing HUD for mission complete")
		passed = false
	else:
		var victory_label: Label = hud.get_node_or_null("VictoryLabel") as Label
		var victory_score_label: Label = hud.get_node_or_null("VictoryScoreLabel") as Label
		if victory_label == null:
			push_error("HUD missing VictoryLabel")
			passed = false
		if victory_score_label == null:
			push_error("HUD missing VictoryScoreLabel")
			passed = false
		var retry_button: CanvasItem = hud.get_node_or_null("RetryButton") as CanvasItem
		var main_menu_button: CanvasItem = hud.get_node_or_null("MainMenuButton") as CanvasItem
		if retry_button == null:
			push_error("HUD missing RetryButton")
			passed = false
		if main_menu_button == null:
			push_error("HUD missing MainMenuButton")
			passed = false
		if victory_label != null and victory_score_label != null:
			# Fast-forward: clear all 5 waves without damage.
			_set_zero_display_duration(main)
			for wave_index: int in TOTAL_WAVES:
				await _clear_current_wave(main)
				await _finish_wave_transition(main)
			# In Etapa 5+, defeat the boss if present to reach mission complete.
			for child: Node in main.get_children():
				if child is Area2D and child.has_method("take_damage"):
					var boss_hp: int = int(child.get("health")) if "health" in child else 150
					child.call("take_damage", boss_hp)
					await process_frame
					await process_frame
					break
			# After 5 waves and boss battle, mission must be complete.
			if not main.has_method("is_mission_complete") or not main.is_mission_complete():
				push_error("Main must report mission complete after clearing all waves")
				passed = false
			# Victory copy and both buttons must be visible.
			if not victory_label.visible or victory_label.text != "¡Victoria!":
				push_error("HUD VictoryLabel must be visible with victory copy after mission complete")
				passed = false
			if not victory_score_label.visible or not victory_score_label.text.contains(str(main.score)):
				push_error("HUD VictoryScoreLabel must be visible with the final score after mission complete")
				passed = false
			if retry_button != null and not retry_button.visible:
				push_error("HUD RetryButton must be visible after mission complete")
				passed = false
			if main_menu_button != null and not main_menu_button.visible:
				push_error("HUD MainMenuButton must be visible after mission complete")
				passed = false
			# RetryButton must have keyboard focus for accessibility.
			if retry_button is Control and not retry_button.has_focus():
				push_error("HUD RetryButton must grab focus after mission complete")
				passed = false
			# Session must be stopped.
			if main.has_method("is_session_active") and main.is_session_active():
				push_error("Main session must be stopped after mission complete")
				passed = false
			# No separate victory screen node should exist on Main or HUD.
			if main.get_node_or_null("VictoryScreen") != null:
				push_error("Main must not have a separate VictoryScreen node")
				passed = false
			if hud.get_node_or_null("VictoryScreen") != null:
				push_error("HUD must not have a separate VictoryScreen node")
				passed = false
			# "Jugar de nuevo" signal must trigger a clean reset.
			hud.retry_mission_requested.emit()
			await process_frame
			if main.score != 0:
				push_error("Retry mission must reset score to 0, got %d" % main.score)
				passed = false
			if main.wave != 1:
				push_error("Retry mission must reset wave to 1, got %d" % main.wave)
				passed = false
			if main.lives != STARTING_LIVES:
				push_error("Retry mission must reset lives to %d" % STARTING_LIVES)
				passed = false
			if main.has_method("is_mission_complete") and main.is_mission_complete():
				push_error("Retry mission must clear mission complete state")
				passed = false
			if main.has_method("is_session_active") and not main.is_session_active():
				push_error("Retry mission must restart the session")
				passed = false
			if victory_label.visible or victory_score_label.visible:
				push_error("Retry mission must hide the victory labels")
				passed = false
			if retry_button != null and retry_button.visible:
				push_error("Retry mission must hide RetryButton")
				passed = false
			if main_menu_button != null and main_menu_button.visible:
				push_error("Retry mission must hide MainMenuButton")
				passed = false
			# "Menú principal" signal must return to the menu state.
			hud.main_menu_requested.emit()
			await process_frame
			if main.has_method("is_session_active") and main.is_session_active():
				push_error("Main menu signal must stop the session")
				passed = false
			if main.has_method("is_mission_complete") and main.is_mission_complete():
				push_error("Main menu signal must clear mission complete state")
				passed = false
			var main_menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
			if main_menu != null and not main_menu.visible:
				push_error("Main menu signal must show the main menu")
				passed = false
			if hud.visible:
				push_error("Main menu signal must hide the HUD")
				passed = false
			if victory_label.visible or victory_score_label.visible:
				push_error("Main menu signal must hide the victory labels")
				passed = false
			if retry_button != null and retry_button.visible:
				push_error("Main menu signal must hide RetryButton")
				passed = false
			if main_menu_button != null and main_menu_button.visible:
				push_error("Main menu signal must hide MainMenuButton")
				passed = false
	root.remove_child(main)
	main.free()
	return passed


func _assert_retry_reset_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	root.add_child(main)
	main.start_session()
	var passed: bool = true
	# Modify state.
	main.set("score", 9999)
	main.set("wave", 4)
	main.set("lives", 1)
	# Retry must reset everything (simulated by checking reset method exists and resets in-place).
	if not main.has_method("reset_session"):
		push_error("Main missing method: reset_session")
		passed = false
	else:
		main.reset_session()
		if main.score != 0:
			push_error("Retry must reset score to 0")
			passed = false
		if main.wave != 1:
			push_error("Retry must reset wave to 1")
			passed = false
		if main.lives != STARTING_LIVES:
			push_error("Retry must reset lives to %d" % STARTING_LIVES)
			passed = false
	root.remove_child(main)
	main.free()
	return passed


# --- Helpers ---

func _destroy_one_enemy(main: Node2D) -> void:
	var spawner: Node2D = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return
	var enemies: Array[Area2D] = _get_formation_enemies(spawner)
	if enemies.is_empty():
		return
	var first_enemy: Area2D = enemies[0]
	if is_instance_valid(first_enemy) and first_enemy.has_method("destroy"):
		first_enemy.destroy()


func _clear_current_wave(main: Node2D) -> void:
	# Wave 9 is the ADR 011 asteroid belt, which has no fighters to destroy.
	if main.has_method("is_asteroid_wave_active") and main.call("is_asteroid_wave_active"):
		await _clear_asteroid_wave(main)
		return
	var spawner: Node2D = main.get_node_or_null("EnemySpawner")
	if spawner == null:
		return
	var enemies: Array[Area2D] = _get_formation_enemies(spawner)
	for enemy: Area2D in enemies:
		if is_instance_valid(enemy) and enemy.has_method("destroy"):
			enemy.destroy()
	# Allow deferred signals to flush.
	await create_timer(0.0).timeout


# Destroys every asteroid and fragment of the belt wave until the spawner reports
# completion. Spawn timing uses wall-clock delta, so the timer is forced to 0 on
# each frame to spawn pending asteroids without waiting.
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


func _get_formation_enemies(spawner: Node2D) -> Array[Area2D]:
	var enemies: Array[Area2D] = []
	for child: Node in spawner.get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			enemies.append(child as Area2D)
	return enemies


func _set_zero_display_duration(main: Node2D) -> void:
	var announcement: CanvasLayer = main.get_node_or_null("WaveAnnouncement") as CanvasLayer
	if announcement != null and "display_duration" in announcement:
		announcement.set("display_duration", 0.0)
	# Disable drops so power-ups don't interfere with score assertions.
	if "enemy_drop_chance" in main:
		main.set("enemy_drop_chance", 0.0)
	if "clear_wave_drop_chance" in main:
		main.set("clear_wave_drop_chance", 0.0)
	if "enemy_loot_drop_chance" in main:
		main.set("enemy_loot_drop_chance", 0.0)


func _finish_wave_transition(main: Node2D) -> void:
	# Wait for the announcement timer to fire and Main to start the next wave.
	await process_frame
	await process_frame
	await process_frame
