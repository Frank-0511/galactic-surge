extends SceneTree
# Contract test for Etapa 21 (touch controls). Verifies behavior through the public
# interface: the touch joystick drives the same input actions as the keyboard.
# Calls go through dynamic dispatch so a missing module reports a failed contract, not a parse error.

const TOUCH_SCRIPT_PATH := "res://scenes/ui/touch_controls.gd"
const TOUCH_SCENE_PATH := "res://scenes/ui/touch_controls.tscn"

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


func _release_move_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
