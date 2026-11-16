# Contract harness for the Etapa 4A UI, visual feedback, and session navigation.
extends SceneTree

const MAIN_SCENE_PATH := "res://features/main/main.tscn"
const MAIN_MENU_SCENE_PATH := "res://features/ui/main_menu.tscn"
const PAUSE_MENU_SCENE_PATH := "res://features/ui/pause_menu.tscn"
const STARFIELD_SCENE_PATH := "res://features/background/starfield.tscn"
const VISUAL_FEEDBACK_SCENE_PATH := "res://features/effects/visual_feedback.tscn"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = _assert_input_contract() and passed
	passed = _assert_main_menu_contract() and passed
	passed = _assert_pause_menu_contract() and passed
	passed = _assert_game_over_menu_contract() and passed
	passed = _assert_starfield_contract() and passed
	var visual_feedback_passed: bool = await _assert_visual_feedback_contract()
	passed = visual_feedback_passed and passed
	passed = await _assert_background_full_rect_contract() and passed
	passed = await _assert_main_navigation_contract() and passed
	quit(0 if passed else 1)


func _assert_input_contract() -> bool:
	if not InputMap.has_action(&"pause"):
		push_error("Missing input action: pause")
		return false
	for input_event: InputEvent in InputMap.action_get_events(&"pause"):
		if input_event is InputEventKey and input_event.keycode == KEY_ESCAPE:
			return true
	push_error("pause must be mapped to Escape")
	return false


func _assert_main_menu_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_MENU_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_MENU_SCENE_PATH)
		return false
	var main_menu: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if main_menu == null:
		push_error("MainMenu scene root must be CanvasLayer")
		return false
	root.add_child(main_menu)
	var passed: bool = true
	passed = _assert_menu_button_contract(
		main_menu, "Control/Menu/PlayButton", &"play_requested", &"_on_play_button_pressed", "MainMenu"
	) and passed
	passed = _assert_menu_button_contract(
		main_menu, "Control/Menu/QuitButton", &"quit_requested", &"_on_quit_button_pressed", "MainMenu"
	) and passed
	if main_menu.has_method("show_menu"):
		main_menu.call("show_menu")
		if not main_menu.visible:
			push_error("MainMenu show_menu() must make the menu visible")
			passed = false
		var play_button: Control = main_menu.get_node_or_null("Control/Menu/PlayButton") as Control
		if play_button != null and not play_button.has_focus():
			push_error("MainMenu show_menu() must focus PlayButton")
			passed = false
		if play_button is Button and play_button.text != "Jugar":
			push_error("MainMenu PlayButton must display Jugar")
			passed = false
		var quit_button: Button = main_menu.get_node_or_null("Control/Menu/QuitButton") as Button
		if quit_button != null and quit_button.text != "Salir":
			push_error("MainMenu QuitButton must display Salir")
			passed = false
	else:
		push_error("MainMenu missing public method: show_menu")
		passed = false
	root.remove_child(main_menu)
	main_menu.free()
	return passed


func _assert_pause_menu_contract() -> bool:
	var packed_scene: PackedScene = load(PAUSE_MENU_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % PAUSE_MENU_SCENE_PATH)
		return false
	var pause_menu: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if pause_menu == null:
		push_error("PauseMenu scene root must be CanvasLayer")
		return false
	root.add_child(pause_menu)
	var passed: bool = true
	passed = _assert_menu_button_contract(
		pause_menu, "Control/ResumeButton", &"resume_requested", &"_on_resume_button_pressed", "PauseMenu"
	) and passed
	passed = _assert_menu_button_contract(
		pause_menu,
		"Control/MainMenuButton",
		&"main_menu_requested",
		&"_on_main_menu_button_pressed",
		"PauseMenu"
	) and passed
	if pause_menu.has_method("show_menu"):
		pause_menu.call("show_menu")
		if not pause_menu.visible:
			push_error("PauseMenu show_menu() must make the menu visible")
			passed = false
		var resume_button: Control = pause_menu.get_node_or_null("Control/ResumeButton") as Control
		if resume_button != null and not resume_button.has_focus():
			push_error("PauseMenu show_menu() must focus ResumeButton")
			passed = false
		if resume_button is Button and resume_button.text != "Reanudar":
			push_error("PauseMenu ResumeButton must display Reanudar")
			passed = false
		var main_menu_button: Button = pause_menu.get_node_or_null("Control/MainMenuButton") as Button
		if main_menu_button != null and main_menu_button.text != "Menú principal":
			push_error("PauseMenu MainMenuButton must display Menú principal")
			passed = false
	else:
		push_error("PauseMenu missing public method: show_menu")
		passed = false
	root.remove_child(pause_menu)
	pause_menu.free()
	return passed


func _assert_game_over_menu_contract() -> bool:
	var packed_scene: PackedScene = load("res://features/ui/game_over.tscn") as PackedScene
	if packed_scene == null:
		push_error("Missing scene: res://features/ui/game_over.tscn")
		return false
	var game_over: CanvasLayer = packed_scene.instantiate() as CanvasLayer
	if game_over == null:
		push_error("GameOver scene root must be CanvasLayer")
		return false
	root.add_child(game_over)
	var passed: bool = true
	if game_over.get_node_or_null("Control/Content/RetryButton") == null:
		push_error("GameOver missing Control/Content/RetryButton")
		passed = false
	if game_over.get_node_or_null("Control/Content/FinalScoreLabel") == null:
		push_error("GameOver missing Control/Content/FinalScoreLabel")
		passed = false
	passed = _assert_menu_button_contract(
		game_over,
		"Control/Content/MainMenuButton",
		&"main_menu_requested",
		&"_on_main_menu_button_pressed",
		"GameOver"
	) and passed
	var main_menu_button: Button = game_over.get_node_or_null("Control/Content/MainMenuButton") as Button
	if main_menu_button != null and main_menu_button.text != "Menú principal":
		push_error("GameOver MainMenuButton must display Menú principal")
		passed = false
	root.remove_child(game_over)
	game_over.free()
	return passed


func _assert_menu_button_contract(
	menu: CanvasLayer, button_path: NodePath, signal_name: StringName, handler_name: StringName, menu_name: String
) -> bool:
	var passed: bool = true
	if menu.get_node_or_null(button_path) == null:
		push_error("%s missing %s" % [menu_name, button_path])
		passed = false
	if not menu.has_signal(signal_name):
		push_error("%s missing signal: %s" % [menu_name, signal_name])
		return false
	if not menu.has_method(handler_name):
		push_error("%s missing button handler: %s" % [menu_name, handler_name])
		return false
	var emission_count: Dictionary = {"value": 0}
	menu.connect(signal_name, func() -> void: emission_count["value"] = int(emission_count["value"]) + 1)
	menu.call(handler_name)
	if int(emission_count["value"]) != 1:
		push_error("%s must emit %s exactly once when %s is called" % [menu_name, signal_name, handler_name])
		passed = false
	return passed


func _assert_starfield_contract() -> bool:
	var packed_scene: PackedScene = load(STARFIELD_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % STARFIELD_SCENE_PATH)
		return false
	var starfield: Node2D = packed_scene.instantiate() as Node2D
	if starfield == null:
		push_error("Starfield scene root must be Node2D")
		return false
	root.add_child(starfield)
	var passed: bool = true
	for method_name: StringName in [&"reset_scroll", &"get_layer_count", &"get_star_positions_for_test"]:
		if not starfield.has_method(method_name):
			push_error("Starfield missing public method: %s" % method_name)
			passed = false
	if starfield.has_method("get_layer_count"):
		if int(starfield.call("get_layer_count")) != 2:
			push_error("Starfield must expose exactly two layers")
			passed = false
	if starfield.has_method("reset_scroll"):
		starfield.call("reset_scroll")
		if starfield.has_method("get_layer_count") and int(starfield.call("get_layer_count")) != 2:
			push_error("Starfield reset_scroll() must preserve two layers")
			passed = false
	if starfield.has_method("get_star_positions_for_test"):
		var initial_positions: Dictionary = starfield.call("get_star_positions_for_test") as Dictionary
		var initial_far: PackedVector2Array = initial_positions.get("far", PackedVector2Array()) as PackedVector2Array
		var initial_near: PackedVector2Array = initial_positions.get("near", PackedVector2Array()) as PackedVector2Array
		if initial_far.is_empty() or initial_near.is_empty():
			push_error("Starfield must generate stars in both layers")
			passed = false
		else:
			starfield._process(0.25)
			var moved_positions: Dictionary = starfield.call("get_star_positions_for_test") as Dictionary
			var moved_far: PackedVector2Array = moved_positions.get("far", PackedVector2Array()) as PackedVector2Array
			var moved_near: PackedVector2Array = moved_positions.get("near", PackedVector2Array()) as PackedVector2Array
			if moved_far.is_empty() or moved_near.is_empty():
				push_error("Starfield movement must preserve both layers")
				passed = false
			elif absf(moved_near[0].y - initial_near[0].y) <= absf(moved_far[0].y - initial_far[0].y):
				push_error("Starfield near layer must scroll faster than far layer")
				passed = false
			starfield.call("reset_scroll")
			var first_reset: Dictionary = starfield.call("get_star_positions_for_test") as Dictionary
			starfield.call("reset_scroll")
			var second_reset: Dictionary = starfield.call("get_star_positions_for_test") as Dictionary
			if first_reset.get("far") != second_reset.get("far") or first_reset.get("near") != second_reset.get("near"):
				push_error("Starfield reset_scroll() must restore deterministic positions")
				passed = false
	var source: String = FileAccess.get_file_as_string("res://features/background/starfield.gd")
	for forbidden_api: String in ["load(", "preload(", "Texture2D", "Sprite2D"]:
		if source.contains(forbidden_api):
			push_error("Starfield must not use %s" % forbidden_api)
			passed = false
	root.remove_child(starfield)
	starfield.free()
	return passed


func _assert_visual_feedback_contract() -> bool:
	var packed_scene: PackedScene = load(VISUAL_FEEDBACK_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % VISUAL_FEEDBACK_SCENE_PATH)
		return false
	var visual_feedback: Node2D = packed_scene.instantiate() as Node2D
	if visual_feedback == null:
		push_error("VisualFeedback scene root must be Node2D")
		return false
	root.add_child(visual_feedback)
	var passed: bool = true
	for method_name: StringName in [&"play_enemy_explosion", &"play_damage_flash", &"clear_effects"]:
		if not visual_feedback.has_method(method_name):
			push_error("VisualFeedback missing public method: %s" % method_name)
			passed = false
	var flash: ColorRect = visual_feedback.get_node_or_null("DamageFlashLayer/Flash") as ColorRect
	if flash == null:
		push_error("VisualFeedback missing ColorRect DamageFlashLayer/Flash")
		passed = false
	var explosion_layer: Node2D = visual_feedback.get_node_or_null("ExplosionLayer") as Node2D
	if explosion_layer == null:
		push_error("VisualFeedback missing Node2D ExplosionLayer")
		passed = false
	var gameplay_state: Dictionary = {"lives": 3, "score": 0, "wave": 1}
	var expected_state: Dictionary = gameplay_state.duplicate(true)
	if visual_feedback.has_method("play_enemy_explosion"):
		var explosion_position := Vector2(220, 160)
		visual_feedback.play_enemy_explosion(explosion_position)
		if explosion_layer != null:
			if explosion_layer.get_child_count() != 1:
				push_error("VisualFeedback must add one ExplosionBurst per explosion")
				passed = false
			else:
				var burst: Node2D = explosion_layer.get_child(0) as Node2D
				if burst == null or burst.name != "ExplosionBurst":
					push_error("VisualFeedback must create an ExplosionBurst node")
					passed = false
				elif burst.global_position != explosion_position:
					push_error("ExplosionBurst must use the requested global position")
					passed = false
	if visual_feedback.has_method("play_damage_flash"):
		visual_feedback.play_damage_flash()
		if flash != null and flash.modulate.a <= 0.0:
			push_error("VisualFeedback damage flash must become visible")
			passed = false
		visual_feedback.play_damage_flash()
		if flash != null and flash.modulate.a <= 0.0:
			push_error("VisualFeedback damage flash must restart when requested again")
			passed = false
	if visual_feedback.has_method("clear_effects"):
		visual_feedback.clear_effects()
		await process_frame
		if explosion_layer != null and explosion_layer.get_child_count() != 0:
			push_error("VisualFeedback clear_effects() must remove all explosions")
			passed = false
		if flash != null and not is_zero_approx(flash.modulate.a):
			push_error("VisualFeedback clear_effects() must hide the damage flash")
			passed = false
	if gameplay_state != expected_state:
		push_error("VisualFeedback must not alter gameplay state")
		passed = false
	root.remove_child(visual_feedback)
	visual_feedback.free()
	return passed


func _assert_background_full_rect_contract() -> bool:
	# Task 3 red contract: the Main background must fill the whole viewport
	# using full anchors with all four offsets at zero, so it no longer
	# depends on the historical 600x800 rect.
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	if main == null:
		push_error("Main scene root must be Node2D")
		return false
	root.add_child(main)
	await process_frame
	var passed: bool = true
	var background: Control = main.get_node_or_null("Background") as Control
	if background == null:
		push_error("Main missing Background node")
		passed = false
	else:
		passed = _assert_full_rect(background, "Main Background") and passed
	root.remove_child(main)
	main.free()
	return passed


func _assert_full_rect(control: Control, label: String) -> bool:
	var passed: bool = true
	if control.anchor_right != 1.0 or control.anchor_bottom != 1.0:
		push_error("%s must fill the viewport with full anchors" % label)
		passed = false
	if control.offset_left != 0.0 or control.offset_top != 0.0 \
			or control.offset_right != 0.0 or control.offset_bottom != 0.0:
		push_error("%s must not retain 600x800 offsets" % label)
		passed = false
	return passed


func _assert_main_navigation_contract() -> bool:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % MAIN_SCENE_PATH)
		return false
	var main: Node2D = packed_scene.instantiate() as Node2D
	if main == null:
		push_error("Main scene root must be Node2D")
		return false
	root.add_child(main)
	await process_frame
	var passed: bool = true
	var main_menu: CanvasLayer = main.get_node_or_null("MainMenu") as CanvasLayer
	var pause_menu: CanvasLayer = main.get_node_or_null("PauseMenu") as CanvasLayer
	var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
	var spawner: Node = main.get_node_or_null("EnemySpawner")
	if main_menu == null:
		push_error("Main missing MainMenu child")
		passed = false
	elif not main_menu.visible:
		push_error("MainMenu must be visible before a session starts")
		passed = false
	if hud == null:
		push_error("Main missing HUD child")
		passed = false
	elif hud.visible:
		push_error("HUD must start hidden in the main menu")
		passed = false
	passed = _assert_main_state(main, false, 3, 0, 1, "before a session starts") and passed
	if spawner == null:
		push_error("Main missing EnemySpawner child")
		passed = false
	elif _count_enemies(spawner) != 0:
		push_error("Main menu must start without enemies")
		passed = false
	for method_name: StringName in [&"start_session", &"pause_session", &"resume_session", &"return_to_main_menu"]:
		if not main.has_method(method_name):
			push_error("Main missing public method: %s" % method_name)
			passed = false
	if main.has_method("start_session") and main.has_method("pause_session") and main.has_method("resume_session") and main.has_method("return_to_main_menu"):
		main.call("start_session")
		passed = _assert_main_state(main, true, 3, 0, 1, "after start_session()") and passed
		if spawner != null and _count_enemies(spawner) != 18:
			push_error("start_session() must create exactly 18 enemies")
			passed = false
		var enemy_before_pause: Area2D = null
		if spawner != null:
			enemy_before_pause = spawner.get_child(0) as Area2D
		var position_before_pause: Vector2 = Vector2.ZERO
		if enemy_before_pause != null:
			position_before_pause = enemy_before_pause.global_position
		main.call("pause_session")
		if not paused:
			push_error("pause_session() must pause the SceneTree")
			passed = false
		if pause_menu == null or not pause_menu.visible:
			push_error("pause_session() must show PauseMenu")
			passed = false
		await process_frame
		if enemy_before_pause != null and enemy_before_pause.global_position != position_before_pause:
			push_error("Enemies must stop moving while the session is paused")
			passed = false
		main.call("resume_session")
		if paused:
			push_error("resume_session() must unpause the SceneTree")
			passed = false
		passed = _assert_main_state(main, true, 3, 0, 1, "after resume_session()") and passed
		main.call("return_to_main_menu")
		if paused:
			push_error("return_to_main_menu() must unpause the SceneTree")
			passed = false
		passed = _assert_main_state(main, false, 3, 0, 1, "after return_to_main_menu()") and passed
		if spawner != null and _count_enemies(spawner) != 0:
			push_error("return_to_main_menu() must clear all enemies")
			passed = false
		main.call("start_session")
		passed = _assert_main_state(main, true, 3, 0, 1, "after starting a clean second session") and passed
		if spawner != null and _count_enemies(spawner) != 18:
			push_error("A new session must create exactly 18 enemies")
			passed = false
	if paused:
		paused = false
	root.remove_child(main)
	main.free()
	return passed


func _assert_main_state(main: Node2D, expected_active: bool, expected_lives: int, expected_score: int, expected_wave: int, context: String) -> bool:
	var passed: bool = true
	if not main.has_method("is_session_active"):
		push_error("Main missing public method: is_session_active")
		return false
	if bool(main.call("is_session_active")) != expected_active:
		push_error("Main session activity is incorrect %s" % context)
		passed = false
	if int(main.get("lives")) != expected_lives:
		push_error("Main lives must be %d %s" % [expected_lives, context])
		passed = false
	if int(main.get("score")) != expected_score:
		push_error("Main score must be %d %s" % [expected_score, context])
		passed = false
	if int(main.get("wave")) != expected_wave:
		push_error("Main wave must be %d %s" % [expected_wave, context])
		passed = false
	return passed


func _count_enemies(spawner: Node) -> int:
	var enemy_count: int = 0
	for child: Node in spawner.get_children():
		if child.is_in_group("enemies"):
			enemy_count += 1
	return enemy_count
