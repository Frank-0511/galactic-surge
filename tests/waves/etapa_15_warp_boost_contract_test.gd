extends SceneTree
# Contract test for the hyperspace jump effect (Etapa 15): the starfield warp surges to the requested
# multiplier and eases back to normal speed. Verified through the public interface (trigger_warp_boost,
# speed_multiplier) with real time, so the Tween runs as it does in the game.

const STARFIELD_SCRIPT_PATH := "res://features/background/starfield.gd"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var script: Script = load(STARFIELD_SCRIPT_PATH) as Script
	_expect(script != null, "Contrato W15.0: existe el campo de estrellas %s" % STARFIELD_SCRIPT_PATH)
	if script != null:
		var starfield: Node = script.new() as Node
		get_root().add_child(starfield)
		_expect(starfield.get("speed_multiplier") == 1.0, "Contrato W15.1: antes del salto la velocidad es normal (1.0)")
		starfield.call("trigger_warp_boost", 2.5, 18.0)
		await create_timer(0.9).timeout
		var peak: float = float(starfield.get("speed_multiplier"))
		_expect(peak > 15.0, "Contrato W15.2: el salto lleva la velocidad cerca de 18x (valor observado %.2f)" % peak)
		await create_timer(2.5).timeout
		var settled: float = float(starfield.get("speed_multiplier"))
		_expect(absf(settled - 1.0) < 0.01, "Contrato W15.3: tras el salto la velocidad vuelve a 1.0 (valor observado %.3f)" % settled)
		get_root().remove_child(starfield)
		starfield.free()

	if _failures == 0:
		print("ETAPA 15 WARP BOOST CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 15 WARP BOOST CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
