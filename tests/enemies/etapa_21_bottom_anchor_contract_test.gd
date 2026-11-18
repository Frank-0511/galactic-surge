extends SceneTree
# Contract test for the Etapa 21 T4 pass (odd/tasks/movil-layout-vertical.md): the formation descent
# limits, the boss dive target and cap, and the dive fallback point are anchored to the BOTTOM of the
# viewport. At the base 1080x960 they equal the former fixed values; on a taller viewport they move
# down by the same offset. Verified through the static helpers, passing the viewport rect explicitly.

const ENEMY_SPAWNER_PATH := "res://features/spawning/enemy_spawner.gd"
const ENEMY_PRESSURE_PATH := "res://features/spawning/enemy_spawner_pressure.gd"
const BOSS_MOVEMENT_PATH := "res://features/boss/boss_movement.gd"

const BASE_VIEWPORT := Rect2(0.0, 0.0, 1080.0, 960.0)
const TALL_VIEWPORT := Rect2(0.0, 0.0, 1080.0, 2300.0)
const TALL_OFFSET: float = 1340.0 # 2300 - 960

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var spawner_script: Script = load(ENEMY_SPAWNER_PATH) as Script
	var pressure_script: Script = load(ENEMY_PRESSURE_PATH) as Script
	var boss_script: Script = load(BOSS_MOVEMENT_PATH) as Script
	_expect(spawner_script != null, "Contrato T4.0a: existe enemy_spawner.gd")
	_expect(pressure_script != null, "Contrato T4.0b: existe enemy_spawner_pressure.gd")
	_expect(boss_script != null, "Contrato T4.0c: existe boss_movement.gd")

	if spawner_script != null:
		_expect(spawner_script.has_method("descent_limit_y"), "Contrato T4.1-0: enemy_spawner expone descent_limit_y")
		if spawner_script.has_method("descent_limit_y"):
			# Antes: max_formation_descent_y = 380 fijo.
			_expect(_near(spawner_script.call("descent_limit_y", BASE_VIEWPORT), 380.0), "Contrato T4.1a: en 1080x960 el limite de descenso es 380")
			_expect(_near(spawner_script.call("descent_limit_y", TALL_VIEWPORT), 380.0 + TALL_OFFSET), "Contrato T4.1b: en 1080x2300 el limite de descenso baja 1340 hasta 1720")

		_expect(spawner_script.has_method("bottom_limit_y"), "Contrato T4.2-0: enemy_spawner expone bottom_limit_y")
		if spawner_script.has_method("bottom_limit_y"):
			# Antes: max_formation_bottom_y = 480 fijo.
			_expect(_near(spawner_script.call("bottom_limit_y", BASE_VIEWPORT), 480.0), "Contrato T4.2a: en 1080x960 el limite inferior de formacion es 480")
			_expect(_near(spawner_script.call("bottom_limit_y", TALL_VIEWPORT), 480.0 + TALL_OFFSET), "Contrato T4.2b: en 1080x2300 el limite inferior de formacion baja 1340 hasta 1820")

	if pressure_script != null:
		_expect(pressure_script.has_method("fallback_dive_point"), "Contrato T4.3-0: enemy_spawner_pressure expone fallback_dive_point")
		if pressure_script.has_method("fallback_dive_point"):
			# Antes: Vector2(540, 850) fijo.
			_expect(pressure_script.call("fallback_dive_point", BASE_VIEWPORT) == Vector2(540.0, 850.0), "Contrato T4.3a: en 1080x960 el punto de picada de respaldo es (540, 850)")
			_expect(pressure_script.call("fallback_dive_point", TALL_VIEWPORT) == Vector2(540.0, 850.0 + TALL_OFFSET), "Contrato T4.3b: en 1080x2300 el punto de respaldo baja 1340 hasta y=2190")
			var wide := Rect2(0.0, 0.0, 1200.0, 960.0)
			_expect(pressure_script.call("fallback_dive_point", wide) == Vector2(600.0, 850.0), "Contrato T4.3c: con viewport de 1200 de ancho el punto de respaldo se centra en x=600")

	if boss_script != null:
		_expect(boss_script.has_method("dive_target_y"), "Contrato T4.4-0: boss_movement expone dive_target_y")
		if boss_script.has_method("dive_target_y"):
			# Antes: dive target y = 760 fijo.
			_expect(_near(boss_script.call("dive_target_y", BASE_VIEWPORT), 760.0), "Contrato T4.4a: en 1080x960 el objetivo de picada del jefe es y=760")
			_expect(_near(boss_script.call("dive_target_y", TALL_VIEWPORT), 760.0 + TALL_OFFSET), "Contrato T4.4b: en 1080x2300 el objetivo de picada baja 1340 hasta y=2100")
		_expect(boss_script.has_method("dive_cap_y"), "Contrato T4.5-0: boss_movement expone dive_cap_y")
		if boss_script.has_method("dive_cap_y"):
			# Antes: tope de picada y >= 740 fijo, siempre por encima del objetivo (760).
			_expect(_near(boss_script.call("dive_cap_y", BASE_VIEWPORT), 740.0), "Contrato T4.5a: en 1080x960 el tope de picada del jefe es y=740")
			_expect(_near(boss_script.call("dive_cap_y", TALL_VIEWPORT), 740.0 + TALL_OFFSET), "Contrato T4.5b: en 1080x2300 el tope de picada baja 1340 hasta y=2080")
			_expect(float(boss_script.call("dive_cap_y", BASE_VIEWPORT)) < float(boss_script.call("dive_target_y", BASE_VIEWPORT)), "Contrato T4.5c: el tope de picada sigue por encima del objetivo (orden relativo intacto)")

	if _failures == 0:
		print("ETAPA 21 BOTTOM ANCHOR CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 BOTTOM ANCHOR CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _near(value: Variant, expected: float) -> bool:
	return value != null and absf(float(value) - expected) < 0.001


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
