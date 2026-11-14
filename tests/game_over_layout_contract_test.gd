# Contract harness — game over layout: the session stats card must sit above the
# action buttons, everything must fit the viewport, and the kills grid must be
# populated with one name/value label pair per enemy type.
extends SceneTree

const GAME_OVER_SCENE := preload("res://scenes/ui/game_over.tscn")


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var game_over: CanvasLayer = GAME_OVER_SCENE.instantiate() as CanvasLayer
	if game_over == null:
		push_error("game_over.tscn must instantiate as CanvasLayer")
		quit(1)
		return
	root.add_child(game_over)
	game_over.call("show_session_stats", 75.0, {&"standard": 2, &"assault_frigate": 1})
	game_over.call("show_game_over", 1200, true)
	await process_frame
	await process_frame
	await process_frame

	var card: Control = game_over.get_node_or_null("Control/Content/StatsCard") as Control
	var retry: Control = game_over.get_node_or_null("Control/Content/RetryButton") as Control
	var menu_button: Control = game_over.get_node_or_null("Control/Content/MainMenuButton") as Control
	var grid: GridContainer = game_over.get_node_or_null(
		"Control/Content/StatsCard/StatsMargin/StatsBox/KillsGrid") as GridContainer
	var accuracy_label: Label = game_over.get_node_or_null(
		"Control/Content/StatsCard/StatsMargin/StatsBox/AccuracyLabel") as Label

	var passed: bool = true
	if card == null or retry == null or menu_button == null or grid == null or accuracy_label == null:
		push_error("game_over.tscn must contain Content/StatsCard (with AccuracyLabel and KillsGrid), RetryButton and MainMenuButton")
		game_over.get_parent().remove_child(game_over)
		game_over.free()
		quit(1)
		return

	var viewport_rect: Rect2 = game_over.get_viewport().get_visible_rect()
	if card.get_global_rect().end.y > retry.get_global_rect().position.y:
		push_error("StatsCard must sit above RetryButton, card bottom %.1f > retry top %.1f" % [card.get_global_rect().end.y, retry.get_global_rect().position.y])
		passed = false
	if menu_button.get_global_rect().end.y > viewport_rect.size.y:
		push_error("MainMenuButton must fit inside the viewport, bottom %.1f > %.1f" % [menu_button.get_global_rect().end.y, viewport_rect.size.y])
		passed = false
	if card.get_global_rect().position.y < 0.0:
		push_error("StatsCard must not be clipped at the top of the viewport")
		passed = false
	if not accuracy_label.text.contains("75%"):
		push_error("AccuracyLabel must show 75%%, got '%s'" % accuracy_label.text)
		passed = false
	if grid.get_child_count() != 10:
		push_error("KillsGrid must hold 10 labels (5 names + 5 counts), got %d" % grid.get_child_count())
		passed = false
	elif grid.get_child(1).text != "2" or grid.get_child(9).text != "1":
		push_error("KillsGrid counts must be Caza=2 and Fragata=1, got '%s' and '%s'" % [grid.get_child(1).text, grid.get_child(9).text])
		passed = false

	root.remove_child(game_over)
	game_over.free()
	if passed:
		print("✓ Game over: tarjeta de estadísticas arriba de los botones, dentro de pantalla, grilla de bajas poblada")
	quit(0 if passed else 1)
