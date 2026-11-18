extends SceneTree
# Contract test for the Etapa 21 mobile fix (odd/tasks/movil-banda-controles.md): the playfield is a fixed
# 1080x960 area anchored to the top of the screen; the extra height on tall phones is a bottom band that
# holds the touch controls. Spawn, formation, boss and dive anchors use the playfield bottom (y=960), not
# the viewport bottom. Verified through the static helpers, passing the viewport rect explicitly.

const LAYOUT_PATH := "res://core/layout/game_layout.gd"
const TOUCH_PATH := "res://features/ui/touch_controls.gd"
const ENEMY_SPAWNER_PATH := "res://features/spawning/enemy_spawner.gd"
const ENEMY_PRESSURE_PATH := "res://features/spawning/enemy_spawner_pressure.gd"
const BOSS_MOVEMENT_PATH := "res://features/boss/boss_movement.gd"

const BASE_VIEWPORT := Rect2(0.0, 0.0, 1080.0, 960.0)
const TALL_VIEWPORT := Rect2(0.0, 0.0, 1080.0, 2300.0)
const PLAYFIELD_BOTTOM: float = 960.0

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var layout_script: Script = load(LAYOUT_PATH) as Script
	var touch_script: Script = load(TOUCH_PATH) as Script
	var spawner_script: Script = load(ENEMY_SPAWNER_PATH) as Script
	var pressure_script: Script = load(ENEMY_PRESSURE_PATH) as Script
	var boss_script: Script = load(BOSS_MOVEMENT_PATH) as Script
	_expect(layout_script != null, "Contrato B21.0a: existe game_layout.gd")
	_expect(touch_script != null, "Contrato B21.0b: existe touch_controls.gd")

	if layout_script != null:
		_expect(layout_script.has_method("playfield_of"), "Contrato B21.1-0: GameLayout expone playfield_of")
		_expect(layout_script.has_method("control_band_of"), "Contrato B21.2-0: GameLayout expone control_band_of")
		if layout_script.has_method("playfield_of"):
			# El area de juego es 1080x960 anclada arriba, aunque el telefono sea mas alto.
			_expect(layout_script.call("playfield_of", TALL_VIEWPORT) == BASE_VIEWPORT, "Contrato B21.1a: en 1080x2300 el area de juego sigue siendo 1080x960 arriba")
			_expect(layout_script.call("playfield_of", BASE_VIEWPORT) == BASE_VIEWPORT, "Contrato B21.1b: en 1080x960 el area de juego es el viewport")
		if layout_script.has_method("control_band_of"):
			# La banda empieza donde termina el juego y ocupa el resto del alto.
			_expect(layout_script.call("control_band_of", TALL_VIEWPORT) == Rect2(0.0, PLAYFIELD_BOTTOM, 1080.0, 1340.0), "Contrato B21.2a: en 1080x2300 la banda va de y=960 a y=2300")
			var band_base: Rect2 = layout_script.call("control_band_of", BASE_VIEWPORT) as Rect2
			_expect(band_base.size.y == 0.0, "Contrato B21.2b: en 1080x960 no hay banda (alto 0)")

		# La nave nace dentro del area de juego, a 96 px de su fondo (y=864), no al fondo del telefono.
		var layout: RefCounted = layout_script.new()
		layout.call("configure", Vector2(1080.0, 2300.0))
		var spawn: Vector2 = layout.call("get_player_spawn_position")
		_expect(spawn == Vector2(540.0, 864.0), "Contrato B21.3a: en 1080x2300 la nave nace en (540, 864)")
		var playfield: Rect2 = layout.get("playfield_rect") as Rect2
		_expect(absf(playfield.size.y - 744.0) < 0.001, "Contrato B21.3b: el playfield_rect mide 744 de alto (960 - 120 - 96)")

	if touch_script != null:
		_expect(touch_script.has_method("default_centers"), "Contrato B21.4-0: touch_controls expone default_centers")
		if touch_script.has_method("default_centers"):
			var tall: Dictionary = touch_script.call("default_centers", TALL_VIEWPORT) as Dictionary
			var joystick: Vector2 = tall.get("joystick", Vector2.ZERO) as Vector2
			var fire: Vector2 = tall.get("fire", Vector2.ZERO) as Vector2
			var pause: Vector2 = tall.get("pause", Vector2.ZERO) as Vector2
			_expect(joystick.y > PLAYFIELD_BOTTOM, "Contrato B21.4a: el joystick cae dentro de la banda inferior (y > 960)")
			_expect(fire.y > PLAYFIELD_BOTTOM, "Contrato B21.4b: el boton de disparo cae dentro de la banda inferior (y > 960)")
			_expect(pause.y < PLAYFIELD_BOTTOM, "Contrato B21.4c: el boton de pausa queda arriba, dentro del area de juego")

	# Anchors take the playfield rect (1080x960 at the top), never the tall viewport.
	if spawner_script != null:
		_expect(spawner_script.has_method("descent_limit_y") and _near(spawner_script.call("descent_limit_y", BASE_VIEWPORT), 380.0), "Contrato B21.5a: el limite de descenso se ancla al area de juego (380)")
		_expect(spawner_script.has_method("bottom_limit_y") and _near(spawner_script.call("bottom_limit_y", BASE_VIEWPORT), 480.0), "Contrato B21.5b: el limite inferior de formacion se ancla al area de juego (480)")

	if pressure_script != null:
		_expect(pressure_script.has_method("fallback_dive_point") and pressure_script.call("fallback_dive_point", BASE_VIEWPORT) == Vector2(540.0, 850.0), "Contrato B21.6a: el punto de picada de respaldo se ancla al area de juego (540, 850)")

	if boss_script != null:
		_expect(boss_script.has_method("dive_target_y") and _near(boss_script.call("dive_target_y", BASE_VIEWPORT), 760.0), "Contrato B21.7a: el objetivo de picada del jefe se ancla al area de juego (760)")
		_expect(boss_script.has_method("dive_cap_y") and _near(boss_script.call("dive_cap_y", BASE_VIEWPORT), 740.0), "Contrato B21.7b: el tope de picada del jefe se ancla al area de juego (740)")

	if _failures == 0:
		print("ETAPA 21 BANDA CONTROLES CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 BANDA CONTROLES CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _near(value: Variant, expected: float) -> bool:
	return value != null and absf(float(value) - expected) < 0.001


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
