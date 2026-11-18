extends SceneTree
# Contract test for the chapter boss health table (Etapa 21 balance pass): chapter 1 keeps 150 PV,
# chapter 2 goes to 450 PV and chapter 3 to 600 PV. Verified through the main script constants.

const MAIN_SCRIPT_PATH := "res://features/main/main.gd"
const EXPECTED_HEALTH := [150, 450, 600]

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var script: Script = load(MAIN_SCRIPT_PATH) as Script
	_expect(script != null, "Contrato H21.0: existe el script principal %s" % MAIN_SCRIPT_PATH)
	if script != null:
		var constants: Dictionary = script.get_script_constant_map()
		_expect(constants.has("BOSS_HEALTH_BY_CHAPTER"), "Contrato H21.1: main.gd define BOSS_HEALTH_BY_CHAPTER")
		if constants.has("BOSS_HEALTH_BY_CHAPTER"):
			var table: Array = constants["BOSS_HEALTH_BY_CHAPTER"]
			_expect(table == EXPECTED_HEALTH, "Contrato H21.2: la vida por capítulo es 150, 450 y 600 (valor observado %s)" % str(table))
			_expect(table.size() == 3, "Contrato H21.3: hay exactamente una vida por capítulo (3)")

	if _failures == 0:
		print("ETAPA 21 BOSS HEALTH CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 BOSS HEALTH CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
