extends SceneTree
# Contract test for the web mobile menu: the local coop button is hidden only when the build runs
# in a browser on a touch device. Verified through the public interface (apply_platform_availability).

const MAIN_MENU_SCENE_PATH := "res://features/ui/main_menu.tscn"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var scene: PackedScene = load(MAIN_MENU_SCENE_PATH) as PackedScene
	_expect(scene != null, "Contrato W21.0: existe la escena del menu principal")
	if scene != null:
		var menu: Node = scene.instantiate()
		get_root().add_child(menu)
		var coop: Button = menu.get_node("Control/Menu/CoopButton") as Button
		_expect(menu.has_method("apply_platform_availability"), "Contrato W21.1-0: el menu expone apply_platform_availability")
		if menu.has_method("apply_platform_availability"):
			menu.call("apply_platform_availability", true, true)
			_expect(not coop.visible, "Contrato W21.1: web en movil oculta el boton Coop local")
			menu.call("apply_platform_availability", true, false)
			_expect(coop.visible, "Contrato W21.2: web en escritorio conserva el boton Coop local")
			menu.call("apply_platform_availability", false, true)
			_expect(coop.visible, "Contrato W21.3: app nativa conserva el boton Coop local")
			menu.call("apply_platform_availability", false, false)
			_expect(coop.visible, "Contrato W21.4: escritorio nativo conserva el boton Coop local")
		get_root().remove_child(menu)
		menu.free()

	if _failures == 0:
		print("ETAPA 21 WEB MOBILE MENU CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 WEB MOBILE MENU CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
