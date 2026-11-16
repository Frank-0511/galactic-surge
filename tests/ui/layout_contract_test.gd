# Contract harness for the GameLayout geometry (layout responsivo, Task 1).
#
# Verifies the viewport-derived geometry for the portrait preset (720x960) and
# the landscape preset prepared for future 16:9 (1280x720), without scaling any
# entity size, collision or physical speed. All coordinates are derived from the
# real viewport size through GameLayout.
extends SceneTree


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = true
	passed = _assert_portrait_geometry() and passed
	passed = _assert_landscape_geometry() and passed
	quit(0 if passed else 1)


func _assert_portrait_geometry() -> bool:
	var layout: GameLayout = GameLayout.new()
	layout.configure(Vector2(720, 960))
	var passed: bool = true
	if layout.get_player_spawn_position() != Vector2(360, 864):
		push_error("Portrait player spawn must be (360, 864), got %s" % layout.get_player_spawn_position())
		passed = false
	if layout.get_player_horizontal_limits() != Vector2(0, 720):
		push_error("Portrait player horizontal limits must be (0, 720), got %s" % layout.get_player_horizontal_limits())
		passed = false
	if layout.get_enemy_formation_origin() != Vector2(360, 120):
		push_error("Portrait enemy formation origin must be (360, 120), got %s" % layout.get_enemy_formation_origin())
		passed = false
	if layout.get_enemy_row_position(2, 64.0) != Vector2(360, 248):
		push_error("Portrait enemy row 2 at 64 px spacing must be (360, 248), got %s" % layout.get_enemy_row_position(2, 64.0))
		passed = false
	if layout.get_power_up_fallback_position() != Vector2(360, 160):
		push_error("Portrait power-up fallback must be (360, 160), got %s" % layout.get_power_up_fallback_position())
		passed = false
	if layout.get_full_viewport_rect() != Rect2(Vector2.ZERO, Vector2(720, 960)):
		push_error("Portrait full viewport rect must be Rect2(0, 0, 720, 960), got %s" % layout.get_full_viewport_rect())
		passed = false
	return passed


func _assert_landscape_geometry() -> bool:
	var layout: GameLayout = GameLayout.new()
	layout.relayout(Vector2(1280, 720))
	var passed: bool = true
	if layout.get_player_spawn_position() != Vector2(640, 624):
		push_error("Landscape player spawn must be (640, 624), got %s" % layout.get_player_spawn_position())
		passed = false
	if layout.get_player_horizontal_limits() != Vector2(0, 1280):
		push_error("Landscape player horizontal limits must be (0, 1280), got %s" % layout.get_player_horizontal_limits())
		passed = false
	if layout.get_enemy_formation_origin() != Vector2(640, 120):
		push_error("Landscape enemy formation origin must be (640, 120), got %s" % layout.get_enemy_formation_origin())
		passed = false
	if layout.get_power_up_fallback_position() != Vector2(640, 160):
		push_error("Landscape power-up fallback must be (640, 160), got %s" % layout.get_power_up_fallback_position())
		passed = false
	return passed
