extends SceneTree
# Contract test for Etapa 21 (touch controls). Verifies behavior through the public
# interface: the touch joystick drives the same input actions as the keyboard.
# Calls go through dynamic dispatch so a missing module reports a failed contract, not a parse error.

const TOUCH_SCRIPT_PATH := "res://scenes/ui/touch_controls.gd"

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


func _release_move_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
