extends Node
# Touch controls (Etapa 21): on-screen joystick that drives the same input actions as the keyboard.
# The joystick only presses move_left / move_right; movement logic is unchanged.
# One finger owns the joystick at a time (the first touch that claims it, until it is released).

const DEADZONE: float = 0.2
const RADIUS: float = 80.0
const NO_TOUCH: int = -1

var _joystick_center: Vector2 = Vector2.ZERO
var _touch_index: int = NO_TOUCH


func set_joystick_center(center: Vector2) -> void:
	_joystick_center = center


# Routes a screen touch or drag event to the joystick. Other events are ignored.
func handle_input_event(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_index == NO_TOUCH:
			_touch_index = drag.index
		if drag.index == _touch_index:
			apply_joystick_axis((drag.position.x - _joystick_center.x) / RADIUS)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == NO_TOUCH:
			_touch_index = touch.index
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = NO_TOUCH
			apply_joystick_axis(0.0)


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
