extends Node
# Touch controls (Etapa 21): on-screen joystick that drives the same input actions as the keyboard.
# The joystick only presses move_left / move_right; movement logic is unchanged.

const DEADZONE: float = 0.2


# axis in [-1, 1]: negative = left, positive = right, inside the deadzone = released.
func apply_joystick_axis(axis: float) -> void:
	var clamped: float = clampf(axis, -1.0, 1.0)
	if clamped < -DEADZONE:
		Input.action_release("move_right")
		Input.action_press("move_left", -clamped)
	elif clamped > DEADZONE:
		Input.action_release("move_left")
		Input.action_press("move_right", clamped)
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")
