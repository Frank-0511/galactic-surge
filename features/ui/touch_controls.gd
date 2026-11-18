extends CanvasLayer
# Touch controls (Etapa 21): on-screen joystick and fire button that drive the same input actions as the keyboard.
# The joystick only presses move_left / move_right; the fire button only presses shoot.
# The joystick floats: its base anchors where the first free touch lands, so the thumb never has to reach a fixed spot.
# One finger owns the joystick and one owns the fire button at a time (the first touch that claims each, until released).
# A pressed touch inside the fire zone claims the fire button and never the joystick.
# A tap on the pause button emits one pause action event (not a held state, like the keyboard).
# Drawn on a child Control; visible only after the first touch input (S6). A short hint names both zones, then fades.

const DEADZONE: float = 0.1
const RADIUS: float = 80.0
const FIRE_RADIUS: float = 80.0
const PAUSE_RADIUS: float = 55.0
const HINT_SECONDS: float = 5.0
const NO_TOUCH: int = -1
const BASE_COLOR: Color = Color(1.0, 1.0, 1.0, 0.18)
const KNOB_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)
const HINT_COLOR: Color = Color(1.0, 1.0, 1.0, 0.55)
const HINT_FONT_SIZE: int = 18

var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_anchor: Vector2 = Vector2.ZERO
var _has_anchor: bool = false
var _fire_center: Vector2 = Vector2.ZERO
var _pause_center: Vector2 = Vector2.ZERO
var _touch_index: int = NO_TOUCH
var _fire_index: int = NO_TOUCH
var _touch_seen: bool = false
var _hint_remaining: float = 0.0
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
	set_fire_button_center(Vector2(size.x * 0.8, size.y * 0.8))
	set_pause_button_center(Vector2(size.x * 0.9, size.y * 0.08))


func _process(delta: float) -> void:
	tick_hints(delta)


# Raw touch events reach the controls here: a CanvasLayer does not receive them through its children.
func _input(event: InputEvent) -> void:
	handle_input_event(event)


# Controls appear only once the device has produced touch input (S6).
func is_visible_for_touch() -> bool:
	return _touch_seen


# The hint is visible from the first touch until HINT_SECONDS have passed.
func is_hint_visible() -> bool:
	return _hint_remaining > 0.0


func tick_hints(delta: float) -> void:
	if _hint_remaining > 0.0:
		_hint_remaining = maxf(0.0, _hint_remaining - delta)
		_request_redraw()


func set_joystick_center(center: Vector2) -> void:
	_joystick_center = center
	_request_redraw()


func set_fire_button_center(center: Vector2) -> void:
	_fire_center = center
	_request_redraw()


func set_pause_button_center(center: Vector2) -> void:
	_pause_center = center
	_request_redraw()


# Routes a screen touch or drag event to the controls. Other events are ignored.
func handle_input_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not _touch_seen:
			_hint_remaining = HINT_SECONDS
		_touch_seen = true
	if event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)
	elif event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	_request_redraw()


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if touch.position.distance_to(_pause_center) <= PAUSE_RADIUS:
			_emit_pause()
			return
		# Fire zone is checked first so its touches are never claimed by the joystick.
		if _is_in_fire_zone(touch.position):
			if _fire_index == NO_TOUCH:
				_fire_index = touch.index
				Input.action_press("shoot")
			return
		if _touch_index == NO_TOUCH:
			_touch_index = touch.index
			_joystick_anchor = touch.position
			_has_anchor = true
	elif touch.index == _fire_index:
		_fire_index = NO_TOUCH
		Input.action_release("shoot")
	elif touch.index == _touch_index:
		_touch_index = NO_TOUCH
		_has_anchor = false
		apply_joystick_axis(0.0)


func _handle_drag(drag: InputEventScreenDrag) -> void:
	# A finger that owns the fire button never drives the joystick.
	if drag.index == _fire_index:
		return
	if _touch_index == NO_TOUCH:
		_touch_index = drag.index
	if drag.index == _touch_index:
		var origin: Vector2 = _joystick_anchor if _has_anchor else _joystick_center
		apply_joystick_axis((drag.position.x - origin.x) / RADIUS)


func _is_in_fire_zone(position: Vector2) -> bool:
	return position.distance_to(_fire_center) <= FIRE_RADIUS


func _emit_pause() -> void:
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	Input.parse_input_event(event)


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
	var base: Vector2 = _joystick_anchor if _has_anchor else _joystick_center
	_pad.draw_circle(base, RADIUS, BASE_COLOR)
	_pad.draw_circle(base + Vector2(_axis * RADIUS, 0.0), RADIUS * 0.4, KNOB_COLOR)
	_pad.draw_circle(_fire_center, FIRE_RADIUS, BASE_COLOR)
	_pad.draw_circle(_pause_center, PAUSE_RADIUS, BASE_COLOR)
	if is_hint_visible():
		var font: Font = ThemeDB.fallback_font
		_pad.draw_string(font, _joystick_center + Vector2(-RADIUS, -RADIUS - 12.0), "Mover", HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2.0, HINT_FONT_SIZE, HINT_COLOR)
		_pad.draw_string(font, _fire_center + Vector2(-FIRE_RADIUS, -FIRE_RADIUS - 12.0), "Disparar", HORIZONTAL_ALIGNMENT_CENTER, FIRE_RADIUS * 2.0, HINT_FONT_SIZE, HINT_COLOR)
