extends SceneTree
# Contract test for the Etapa 21 vertical layout pass: the dive side and the asteroid cull limits
# come from the live viewport, not from fixed 1080x960 numbers. Verified through the static helpers.

const ENEMY_MOTION_PATH := "res://features/enemy/enemy_motion.gd"
const ASTEROID_MOTION_PATH := "res://features/asteroid/asteroid_motion.gd"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var enemy_script: Script = load(ENEMY_MOTION_PATH) as Script
	var asteroid_script: Script = load(ASTEROID_MOTION_PATH) as Script
	_expect(enemy_script != null, "Contrato L21.0a: existe enemy_motion.gd")
	_expect(asteroid_script != null, "Contrato L21.0b: existe asteroid_motion.gd")

	if enemy_script != null:
		_expect(enemy_script.has_method("dive_side"), "Contrato L21.1-0: enemy_motion expone dive_side")
		if enemy_script.has_method("dive_side"):
			# Mismo resultado que el 540 fijo cuando el viewport mide 1080 de ancho.
			_expect(enemy_script.call("dive_side", 800.0, 800.0, 540.0) == -1.0, "Contrato L21.1a: en 1080 de ancho, un enemigo a la derecha del centro cae con lado -1")
			_expect(enemy_script.call("dive_side", 200.0, 200.0, 540.0) == 1.0, "Contrato L21.1b: en 1080 de ancho, un enemigo a la izquierda del centro cae con lado 1")
			# Viewport ancho: el centro se mueve con el viewport, no queda en 540.
			_expect(enemy_script.call("dive_side", 800.0, 800.0, 1000.0) == 1.0, "Contrato L21.1c: con viewport de 2000 de ancho el enemigo en x=800 cae con lado 1")

	if asteroid_script != null:
		_expect(asteroid_script.has_method("is_outside_cull"), "Contrato L21.2-0: asteroid_motion expone is_outside_cull")
		if asteroid_script.has_method("is_outside_cull"):
			var small := Rect2(0.0, 0.0, 1080.0, 960.0)
			_expect(not asteroid_script.call("is_outside_cull", Vector2(1300.0, 100.0), small), "Contrato L21.2a: en 1080 de ancho, x=1300 sigue dentro del corte")
			_expect(asteroid_script.call("is_outside_cull", Vector2(1500.0, 100.0), small), "Contrato L21.2b: en 1080 de ancho, x=1500 queda fuera del corte")
			var tall := Rect2(0.0, 0.0, 1600.0, 2300.0)
			_expect(not asteroid_script.call("is_outside_cull", Vector2(1500.0, 100.0), tall), "Contrato L21.2c: con viewport de 1600 de ancho, x=1500 sigue dentro del corte")
			_expect(asteroid_script.call("is_outside_cull", Vector2(2000.0, 100.0), tall), "Contrato L21.2d: con viewport de 1600 de ancho, x=2000 queda fuera del corte")

	if _failures == 0:
		print("ETAPA 21 LAYOUT RELATIVE CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 LAYOUT RELATIVE CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
