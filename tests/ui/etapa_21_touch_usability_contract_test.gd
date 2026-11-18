extends SceneTree
# Contract test for the Etapa 21 touch usability pass: floating joystick anchored where the thumb lands,
# smaller deadzone, larger fire and pause hit areas, and a hint shown after the first touch.
# Verified through the public interface (handle_input_event, Input actions, is_hint_visible, tick_hints).

const TOUCH_SCRIPT_PATH := "res://features/ui/touch_controls.gd"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var touch_script: Script = load(TOUCH_SCRIPT_PATH) as Script
	_expect(touch_script != null, "Contrato U21.0: existe el modulo de controles tactiles %s" % TOUCH_SCRIPT_PATH)
	if touch_script != null:
		var controls: Node = touch_script.new() as Node
		_check_joystick_floats_to_press_point(controls)
		_check_small_drag_passes_deadzone(controls)
		_check_fire_hit_area_is_larger(controls)
		await _check_pause_hit_area_is_larger(controls)
		_check_hint_shows_after_touch_and_fades(touch_script)
		controls.free()

	if _failures == 0:
		print("ETAPA 21 TOUCH USABILITY CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		print("ETAPA 21 TOUCH USABILITY CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# U21.1: el joystick se ancla donde cae el pulgar. Un arrastre de 60 px a la izquierda desde ese
# punto presiona move_left, aunque el centro fijo del joystick este en otro lugar.
func _check_joystick_floats_to_press_point(controls: Node) -> void:
	_release_move_actions()
	controls.call("set_joystick_center", Vector2(200.0, 700.0))
	_send_touch(controls, 0, true, Vector2(500.0, 600.0))
	_send_drag(controls, 0, Vector2(440.0, 600.0))
	_expect(Input.is_action_pressed("move_left"), "Contrato U21.1a: joystick flotante, arrastre a la izquierda del punto de toque presiona move_left")
	_expect(not Input.is_action_pressed("move_right"), "Contrato U21.1b: joystick flotante, arrastre a la izquierda no presiona move_right")
	_send_touch(controls, 0, false, Vector2(440.0, 600.0))
	_release_move_actions()


# U21.2: una desviacion de 12 px (0.15 del radio) ya mueve la nave: la zona muerta baja a ~0.1.
func _check_small_drag_passes_deadzone(controls: Node) -> void:
	_release_move_actions()
	_send_touch(controls, 0, true, Vector2(500.0, 600.0))
	_send_drag(controls, 0, Vector2(488.0, 600.0))
	_expect(Input.is_action_pressed("move_left"), "Contrato U21.2: desviacion de 12 px a la izquierda ya presiona move_left")
	_send_touch(controls, 0, false, Vector2(488.0, 600.0))
	_release_move_actions()


# U21.3: el boton de disparo acepta toques hasta 80 px del centro (antes 60).
func _check_fire_hit_area_is_larger(controls: Node) -> void:
	Input.action_release("shoot")
	controls.call("set_fire_button_center", Vector2(900.0, 700.0))
	_send_touch(controls, 2, true, Vector2(975.0, 700.0))
	_expect(Input.is_action_pressed("shoot"), "Contrato U21.3: toque a 75 px del centro de disparo presiona shoot")
	_send_touch(controls, 2, false, Vector2(975.0, 700.0))
	Input.action_release("shoot")


# U21.4: el boton de pausa acepta toques hasta 55 px del centro (antes 40).
func _check_pause_hit_area_is_larger(controls: Node) -> void:
	controls.call("set_pause_button_center", Vector2(900.0, 80.0))
	var source := GDScript.new()
	source.source_code = "extends Node\nvar pauses: int = 0\nfunc _unhandled_input(event: InputEvent) -> void:\n\tif event.is_action_pressed(&\"pause\"):\n\t\tpauses += 1\n"
	source.reload()
	var probe: Node = Node.new()
	probe.set_script(source)
	get_root().add_child(probe)
	_send_touch(controls, 6, true, Vector2(960.0, 80.0))
	await process_frame
	await process_frame
	_expect(probe.get("pauses") == 0, "Contrato U21.4a: toque a 60 px del centro de pausa no emite pause")
	_send_touch(controls, 6, false, Vector2(960.0, 80.0))
	_send_touch(controls, 5, true, Vector2(955.0, 80.0))
	await process_frame
	await process_frame
	_expect(probe.get("pauses") == 1, "Contrato U21.4b: toque a 55 px del centro de pausa emite pause")
	_send_touch(controls, 5, false, Vector2(955.0, 80.0))
	get_root().remove_child(probe)
	probe.free()


# U21.5: la pista "Mover / Disparar" aparece con el primer toque y se oculta despues de unos segundos.
func _check_hint_shows_after_touch_and_fades(touch_script: Script) -> void:
	var controls: Node = touch_script.new() as Node
	_expect(controls.has_method("is_hint_visible") and not controls.call("is_hint_visible"), "Contrato U21.5a: sin toque la pista esta oculta")
	_send_touch(controls, 0, true, Vector2(300.0, 600.0))
	_expect(controls.has_method("is_hint_visible") and controls.call("is_hint_visible"), "Contrato U21.5b: tras el primer toque la pista es visible")
	if controls.has_method("tick_hints"):
		controls.call("tick_hints", 6.0)
	_expect(controls.has_method("is_hint_visible") and not controls.call("is_hint_visible"), "Contrato U21.5c: tras 6 segundos la pista se oculta")
	controls.free()


func _send_touch(controls: Node, index: int, pressed: bool, position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = position
	controls.call("handle_input_event", event)


func _send_drag(controls: Node, index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	controls.call("handle_input_event", event)


func _release_move_actions() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		print("✗ %s" % message)
		_failures += 1
