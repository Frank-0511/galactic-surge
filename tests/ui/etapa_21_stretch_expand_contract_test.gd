extends SceneTree
# Contract test for the Etapa 21 vertical layout: the window stretch aspect fills the screen height
# (expand) instead of letterboxing, and the base logical size stays 1080x960.

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var aspect: String = str(ProjectSettings.get_setting("display/window/stretch/aspect", ""))
	var mode: String = str(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	_expect(mode == "canvas_items", "Contrato E21.1: el estiramiento sigue en canvas_items")
	_expect(aspect == "expand", "Contrato E21.2: el aspecto de estiramiento es expand (llena el alto en m\u00f3vil), no keep")
	_expect(width == 1080 and height == 960, "Contrato E21.3: el tama\u00f1o l\u00f3gico base sigue en 1080x960")

	if _failures == 0:
		print("ETAPA 21 STRETCH EXPAND CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 STRETCH EXPAND CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
