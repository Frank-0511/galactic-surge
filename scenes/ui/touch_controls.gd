extends CanvasLayer
# Touch controls (Etapa 21): on-screen joystick that drives the same input actions as the keyboard.
# The joystick only presses move_left / move_right; movement logic is unchanged.
# One finger owns the joystick at a time (the first touch that claims it, until it is released).
# Drawn on a child Control; visible only after the first touch input (S6).

const DEADZONE: float = 0.2
const RADIUS: float = 80.0
const NO_TOUCH: int = -1
const BASE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.18)
const KNOB_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)

var _joystick_center: Vector2 = Vector2.ZERO
var _touch_index: int = NO_TOUCH
var _touch_seen: bool = false
var _axis: float = 0.0
var _pad: Control = null


func _ready() -> void:
	_pad = Control.new()
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.draw.connect(_draw_pad)
	add_child(_pad)
	var size: Vector2 = get_viewport().get_visible_rect().size
	set_joystick_center(Vector2(size.x * 0.2, size.y * 0.8))


# Raw touch events reach the joystick here: a CanvasLayer does not receive them through its children.
func _input(event: InputEvent) -> void:
	handle_input_event(event)


# Controls appear only once the device has produced touch input (S6).
func is_visible_for_touch() -> bool:
	return _touch_seen


func set_joystick_center(center: Vector2) -> void:
	_joystick_center = center
	_request_redraw()


# Routes a screen touch or drag event to the joystick. Other events are ignored.
func handle_input_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_touch_seen = true
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
	_request_redraw()


# axis in [-1, 1]: negative = left, positive = right, inside the deadzone = released.
func apply_joystick_axis(axis: float) -> void:
	var clamped: float = clampf(axis, -1.0, 1.0)
	_axis = clamped
	if clamped < -DEADZONE:
		Input.action_release("move_right")
		Input.action_press("move_left", -clamped)
	elif clamped > DEADZONE:
		Input.action_release("move_left")
		Input.action_press("move_right", clamped)
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")
	_request_redraw()


func _request_redraw() -> void:
	if _pad != null:
		_pad.queue_redraw()


func _draw_pad() -> void:
	if not is_visible_for_touch():
		return
	_pad.draw_circle(_joystick_center, RADIUS, BASE_COLOR)
	_pad.draw_circle(_joystick_center + Vector2(_axis * RADIUS, 0.0), RADIUS * 0.4, KNOB_COLOR)
