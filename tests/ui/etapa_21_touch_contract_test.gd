extends SceneTree
# Contract test for Etapa 21 (touch controls). Verifies behavior through the public
# interface: the touch joystick drives the same input actions as the keyboard.
# Calls go through dynamic dispatch so a missing module reports a failed contract, not a parse error.

const TOUCH_SCRIPT_PATH := "res://features/ui/touch_controls.gd"
const TOUCH_SCENE_PATH := "res://features/ui/touch_controls.tscn"
const MAIN_MENU_SCENE_PATH := "res://features/ui/main_menu.tscn"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var touch_script: Script = load(TOUCH_SCRIPT_PATH) as Script
	_expect(touch_script != null, "Contrato T21.1: existe el modulo de controles tactiles %s" % TOUCH_SCRIPT_PATH)
	if touch_script != null:
		var controls: Node = touch_script.new() as Node
		_check_joystick_left_presses_move_left(controls)
		_check_joystick_right_presses_move_right(controls)
		_check_joystick_release_clears_both(controls)
		var has_touch_api: bool = controls.has_method("set_joystick_center") and controls.has_method("handle_input_event")
		_expect(has_touch_api, "Contrato T21.5-0: el modulo expone set_joystick_center y handle_input_event")
		if has_touch_api:
			_check_touch_drag_left_presses_move_left(controls)
			_check_touch_release_clears_move(controls)
		_check_hidden_without_touch(touch_script)
		_check_visible_after_touch(touch_script)
		_check_scene_root_has_script()
		_check_touch_reaches_joystick_in_tree()
		var has_fire_api: bool = controls.has_method("set_fire_button_center")
		_expect(has_fire_api, "Contrato T21.11-0: el modulo expone set_fire_button_center")
		if has_fire_api:
			_check_fire_button_presses_shoot(controls)
		var has_pause_api: bool = controls.has_method("set_pause_button_center")
		_expect(has_pause_api, "Contrato T21.12-0: el modulo expone set_pause_button_center")
		if has_pause_api:
			await _check_pause_button_emits_pause(controls)
		await _check_web_hides_network_and_quit()
		controls.free()

	if _failures == 0:
		print("ETAPA 21 TOUCH CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 TOUCH CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# T21.2 (S2): arrastrar el joystick a la izquierda activa move_left y no move_right.
func _check_joystick_left_presses_move_left(controls: Node) -> void:
	_release_move_actions()
	controls.call("apply_joystick_axis", -0.8)
	_expect(Input.is_action_pressed("move_left"), "Contrato T21.2a: joystick a la izquierda presiona move_left")
	_expect(not Input.is_action_pressed("move_right"), "Contrato T21.2b: joystick a la izquierda no presiona move_right")


# T21.3 (S2): arrastrar el joystick a la derecha activa move_right y no move_left.
func _check_joystick_right_presses_move_right(controls: Node) -> void:
	_release_move_actions()
	controls.call("apply_joystick_axis", 0.8)
	_expect(Input.is_action_pressed("move_right"), "Contrato T21.3a: joystick a la derecha presiona move_right")
	_expect(not Input.is_action_pressed("move_left"), "Contrato T21.3b: joystick a la derecha no presiona move_left")


# T21.4 (S2): soltar el joystick libera ambas acciones.
func _check_joystick_release_clears_both(controls: Node) -> void:
	controls.call("apply_joystick_axis", -0.8)
	controls.call("apply_joystick_axis", 0.0)
	_expect(not Input.is_action_pressed("move_left"), "Contrato T21.4a: soltar el joystick libera move_left")
	_expect(not Input.is_action_pressed("move_right"), "Contrato T21.4b: soltar el joystick libera move_right")


# T21.5 (S2): un arrastre tactil a la izquierda del centro del joystick presiona move_left.
func _check_touch_drag_left_presses_move_left(controls: Node) -> void:
	_release_move_actions()
	controls.call("set_joystick_center", Vector2(200.0, 700.0))
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(140.0, 700.0)
	controls.call("handle_input_event", drag)
	_expect(Input.is_action_pressed("move_left"), "Contrato T21.5a: arrastre tactil a la izquierda presiona move_left")
	_expect(not Input.is_action_pressed("move_right"), "Contrato T21.5b: arrastre tactil a la izquierda no presiona move_right")


# T21.6 (S2): al levantar el dedo del joystick se liberan las acciones de movimiento.
func _check_touch_release_clears_move(controls: Node) -> void:
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = Vector2(140.0, 700.0)
	controls.call("handle_input_event", release)
	_expect(not Input.is_action_pressed("move_left"), "Contrato T21.6a: levantar el dedo libera move_left")
	_expect(not Input.is_action_pressed("move_right"), "Contrato T21.6b: levantar el dedo libera move_right")


# T21.7 (S6): sin entrada tactil los controles estan ocultos (escritorio sin cambios).
func _check_hidden_without_touch(touch_script: Script) -> void:
	var controls: Node = touch_script.new() as Node
	_expect(controls.has_method("is_visible_for_touch") and not controls.call("is_visible_for_touch"), "Contrato T21.7: sin toque los controles estan ocultos")
	controls.free()


# T21.8 (S6): al recibir un toque los controles pasan a visibles.
func _check_visible_after_touch(touch_script: Script) -> void:
	var controls: Node = touch_script.new() as Node
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = Vector2(140.0, 700.0)
	controls.call("handle_input_event", press)
	_expect(controls.has_method("is_visible_for_touch") and controls.call("is_visible_for_touch"), "Contrato T21.8: tras un toque los controles son visibles")
	controls.free()


# T21.9 (S2): la escena de controles existe y su raiz usa el script de controles.
func _check_scene_root_has_script() -> void:
	var scene: PackedScene = load(TOUCH_SCENE_PATH) as PackedScene
	_expect(scene != null, "Contrato T21.9a: existe la escena de controles tactiles %s" % TOUCH_SCENE_PATH)
	if scene == null:
		return
	var root: Node = scene.instantiate()
	_expect(root.get_script() != null and root.get_script().resource_path == TOUCH_SCRIPT_PATH, "Contrato T21.9b: la raiz de la escena usa touch_controls.gd")
	root.free()


# T21.10 (S2): un toque real en el viewport, con la escena montada en el arbol, mueve el joystick.
func _check_touch_reaches_joystick_in_tree() -> void:
	_release_move_actions()
	var scene: PackedScene = load(TOUCH_SCENE_PATH) as PackedScene
	if scene == null:
		_expect(false, "Contrato T21.10: la escena de controles carga para montarla en el arbol")
		return
	var controls: Node = scene.instantiate()
	get_root().add_child(controls)
	var size: Vector2 = get_root().get_visible_rect().size
	var center: Vector2 = Vector2(size.x * 0.2, size.y * 0.8)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	# Touch positions arrive in window space: the viewport applies its final transform to them.
	drag.position = get_root().get_final_transform() * (center + Vector2(-60.0, 0.0))
	get_root().push_input(drag)
	_expect(Input.is_action_pressed("move_left"), "Contrato T21.10a: toque real a la izquierda del joystick presiona move_left")
	get_root().remove_child(controls)
	controls.free()
	_release_move_actions()


# T21.11 (S3): un toque en la zona del boton de disparo presiona shoot; levantarlo lo libera.
# Un toque fuera de esa zona no dispara.
func _check_fire_button_presses_shoot(controls: Node) -> void:
	Input.action_release("shoot")
	controls.call("set_fire_button_center", Vector2(900.0, 700.0))
	var outside := InputEventScreenTouch.new()
	outside.index = 1
	outside.pressed = true
	outside.position = Vector2(200.0, 700.0)
	controls.call("handle_input_event", outside)
	_expect(not Input.is_action_pressed("shoot"), "Contrato T21.11a: un toque fuera de la zona de disparo no dispara")
	var press := InputEventScreenTouch.new()
	press.index = 2
	press.pressed = true
	press.position = Vector2(900.0, 700.0)
	controls.call("handle_input_event", press)
	_expect(Input.is_action_pressed("shoot"), "Contrato T21.11b: un toque en la zona de disparo presiona shoot")
	var release := InputEventScreenTouch.new()
	release.index = 2
	release.pressed = false
	release.position = Vector2(900.0, 700.0)
	controls.call("handle_input_event", release)
	_expect(not Input.is_action_pressed("shoot"), "Contrato T21.11c: levantar el dedo del disparo libera shoot")
	Input.action_release("shoot")


# T21.12 (S3): un toque en el boton de pausa emite una vez el evento de accion pause (no un estado).
# Un toque fuera de esa zona no emite pause.
func _check_pause_button_emits_pause(controls: Node) -> void:
	controls.call("set_pause_button_center", Vector2(900.0, 80.0))
	var source := GDScript.new()
	source.source_code = "extends Node\nvar pauses: int = 0\nfunc _unhandled_input(event: InputEvent) -> void:\n\tif event.is_action_pressed(&\"pause\"):\n\t\tpauses += 1\n"
	source.reload()
	var probe: Node = Node.new()
	probe.set_script(source)
	get_root().add_child(probe)
	var outside := InputEventScreenTouch.new()
	outside.index = 4
	outside.pressed = true
	outside.position = Vector2(200.0, 700.0)
	controls.call("handle_input_event", outside)
	await process_frame
	_expect(probe.get("pauses") == 0, "Contrato T21.12a: un toque fuera del boton de pausa no emite pause")
	var press := InputEventScreenTouch.new()
	press.index = 5
	press.pressed = true
	press.position = Vector2(900.0, 80.0)
	controls.call("handle_input_event", press)
	await process_frame
	_expect(probe.get("pauses") == 1, "Contrato T21.12b: un toque en el boton de pausa emite pause una vez")
	get_root().remove_child(probe)
	probe.free()


# T21.13 (S7): en web el panel de red y el boton Salir quedan ocultos (no hay red ni cierre del
# proceso en el navegador); fuera de web vuelven a estar visibles.
func _check_web_hides_network_and_quit() -> void:
	var scene: PackedScene = load(MAIN_MENU_SCENE_PATH) as PackedScene
	_expect(scene != null, "Contrato T21.13-0: existe la escena del menu principal")
	if scene == null:
		return
	var menu: Node = scene.instantiate()
	get_root().add_child(menu)
	var host: Button = menu.get_node("Control/NetPanel/ButtonRow/HostButton") as Button
	var join: Button = menu.get_node("Control/NetPanel/ButtonRow/JoinButton") as Button
	var net_coop: Button = menu.get_node("Control/NetPanel/ButtonRow/NetCoopButton") as Button
	var net_panel: Control = menu.get_node("Control/NetPanel") as Control
	var quit_button: Button = menu.get_node("Control/Menu/QuitButton") as Button
	var has_api: bool = menu.has_method("apply_network_availability")
	_expect(has_api, "Contrato T21.13-1: el menu expone apply_network_availability")
	if not has_api:
		menu.free()
		return
	menu.call("apply_network_availability", true)
	_expect(not host.is_visible_in_tree() and not join.is_visible_in_tree() and not net_coop.is_visible_in_tree(), "Contrato T21.13a: en web el panel de red y sus botones quedan ocultos")
	_expect(not quit_button.is_visible_in_tree(), "Contrato T21.13b: en web el boton Salir queda oculto")
	menu.call("apply_network_availability", false)
	_expect(net_panel.is_visible_in_tree() and host.is_visible_in_tree() and join.is_visible_in_tree() and net_coop.is_visible_in_tree(), "Contrato T21.13c: fuera de web el panel de red queda visible")
	_expect(quit_button.is_visible_in_tree(), "Contrato T21.13d: fuera de web el boton Salir queda visible")
	get_root().remove_child(menu)
	menu.free()


func _release_move_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
