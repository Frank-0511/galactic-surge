# Contract harness for Task 3 — backgrounds and UI must use the full viewport.
#
# Verifies that Starfield covers the complete viewport (no 600×800 gap), and
# that the UI scenes use center anchors instead of absolute offsets derived
# from the historical 600×800 reference. Preserves the Etapa 4A contracts.
extends SceneTree

const STARFIELD_SCENE_PATH := "res://scenes/background/starfield.tscn"
const HUD_SCENE_PATH := "res://scenes/ui/hud.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const GAME_OVER_SCENE_PATH := "res://scenes/ui/game_over.tscn"
const PAUSE_MENU_SCENE_PATH := "res://scenes/ui/pause_menu.tscn"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = _assert_starfield_full_viewport() and passed
	passed = _assert_hud_uses_center_anchors() and passed
	passed = _assert_main_menu_uses_center_anchors() and passed
	passed = _assert_game_over_uses_center_anchors() and passed
	passed = _assert_pause_menu_uses_center_anchors() and passed
	quit(0 if passed else 1)


func _assert_starfield_full_viewport() -> bool:
	var source: String = FileAccess.get_file_as_string("res://scenes/background/starfield.gd")
	var passed: bool = true
	# The star generator must not subtract a fixed offset from the viewport end,
	# which would leave a gap derived from a historical speed constant.
	if source.contains("end.y - NEAR_SPEED"):
		push_error("Starfield _generate_stars must not subtract NEAR_SPEED from viewport end.y")
		passed = false
	if source.contains("end.y - FAR_SPEED"):
		push_error("Starfield _generate_stars must not subtract FAR_SPEED from viewport end.y")
		passed = false
	# Star positions must be generated across the full viewport range.
	var packed_scene: PackedScene = load(STARFIELD_SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("Missing scene: %s" % STARFIELD_SCENE_PATH)
		return false
	var starfield: Node2D = packed_scene.instantiate() as Node2D
	if starfield == null:
		push_error("Starfield scene root must be Node2D")
		return false
	root.add_child(starfield)
	if starfield.has_method("reset_scroll"):
		starfield.call("reset_scroll")
	if starfield.has_method("get_star_positions_for_test"):
		var positions: Dictionary = starfield.call("get_star_positions_for_test") as Dictionary
		var near: PackedVector2Array = positions.get("near", PackedVector2Array()) as PackedVector2Array
		if not near.is_empty():
			var viewport_rect: Rect2 = starfield.get_viewport_rect()
			for star: Vector2 in near:
				if star.y < viewport_rect.position.y or star.y > viewport_rect.end.y:
					push_error("Starfield near star at y=%f is outside viewport range [0, %f]" % [star.y, viewport_rect.end.y])
					passed = false
					break
	root.remove_child(starfield)
	starfield.free()
	return passed


func _assert_hud_uses_center_anchors() -> bool:
	var source: String = FileAccess.get_file_as_string(HUD_SCENE_PATH)
	var passed: bool = true
	# MissionCompleteLabel must use center anchors (anchor 0.5), not absolute offsets.
	if source.contains("offset_left = 120.0") or source.contains("offset_top = 360.0"):
		push_error("HUD MissionCompleteLabel must not use absolute offsets from 600×800")
		passed = false
	if not source.contains("anchor_left = 0.5") or not source.contains("anchor_top = 0.5"):
		push_error("HUD MissionCompleteLabel must use center anchors (0.5, 0.5)")
		passed = false
	return passed


func _assert_main_menu_uses_center_anchors() -> bool:
	var source: String = FileAccess.get_file_as_string(MAIN_MENU_SCENE_PATH)
	var passed: bool = true
	# Title, Play and Quit must use center anchors, not offsets like 100/240 or 200/365.
	if source.contains("offset_left = 100.0") or source.contains("offset_top = 240.0"):
		push_error("MainMenu TitleLabel must not use absolute offsets from 600×800")
		passed = false
	if source.contains("offset_left = 200.0") and source.contains("offset_top = 365.0"):
		push_error("MainMenu PlayButton must not use absolute offsets from 600×800")
		passed = false
	# Count center anchors — Title, Play, Quit should each have anchor_left = 0.5.
	var center_anchor_count: int = source.count("anchor_left = 0.5")
	if center_anchor_count < 3:
		push_error("MainMenu must use center anchors (anchor_left = 0.5) for Title, Play and Quit, got %d" % center_anchor_count)
		passed = false
	return passed


func _assert_game_over_uses_center_anchors() -> bool:
	var source: String = FileAccess.get_file_as_string(GAME_OVER_SCENE_PATH)
	var passed: bool = true
	# GameOverLabel, FinalScoreLabel, RetryButton, MainMenuButton must use center anchors.
	if source.contains("offset_left = 185.0") or source.contains("offset_top = 310.0"):
		push_error("GameOver must not use absolute offsets from 600×800")
		passed = false
	if source.contains("offset_left = 225.0") or source.contains("offset_top = 415.0"):
		push_error("GameOver RetryButton must not use absolute offsets from 600×800")
		passed = false
	var center_anchor_count: int = source.count("anchor_left = 0.5")
	if not source.contains("name=\"Content\" type=\"VBoxContainer\""):
		push_error("GameOver must center its content in a VBoxContainer named Content")
		passed = false
	if center_anchor_count < 1:
		push_error("GameOver must use a center anchor for its Content column, got %d" % center_anchor_count)
		passed = false
	return passed


func _assert_pause_menu_uses_center_anchors() -> bool:
	var source: String = FileAccess.get_file_as_string(PAUSE_MENU_SCENE_PATH)
	var passed: bool = true
	# Title, Resume, MainMenu must use center anchors, not offsets like 150/275 or 200/385.
	if source.contains("offset_left = 150.0") or source.contains("offset_top = 275.0"):
		push_error("PauseMenu TitleLabel must not use absolute offsets from 600×800")
		passed = false
	if source.contains("offset_left = 200.0") and source.contains("offset_top = 385.0"):
		push_error("PauseMenu ResumeButton must not use absolute offsets from 600×800")
		passed = false
	var center_anchor_count: int = source.count("anchor_left = 0.5")
	if center_anchor_count < 3:
		push_error("PauseMenu must use center anchors for 3 elements, got %d" % center_anchor_count)
		passed = false
	return passed
