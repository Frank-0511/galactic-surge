# player_input.gd
# Input for one Player slot: action names (J2 uses the p2_ actions, Etapa 20), the one-time
# registration of J2 bindings, J1 arrow-key suppression in coop, and horizontal movement
# clamped to the layout limits or the viewport. Owned by Player through _player.

extends RefCounted

const MARGIN: float = 16.0

var _player: CharacterBody2D


func _init(player: CharacterBody2D) -> void:
	_player = player


## Input action name for a player slot: J1 keeps the base name, J2 uses the p2_ prefix.
static func input_action_name(base: String, player_index: int) -> String:
	return base if player_index == 1 else "p2_" + base


## Registers J2's input actions (Etapa 20): arrows + Shift, or gamepad. Idempotent.
static func ensure_p2_input_actions() -> void:
	var bindings: Dictionary = {
		"p2_move_left": [KEY_LEFT],
		"p2_move_right": [KEY_RIGHT],
		"p2_shoot": [KEY_SHIFT],
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode: Key in bindings[action]:
			var key_event := InputEventKey.new()
			key_event.keycode = keycode
			_add_event_once(action, key_event)
	var motion_left := InputEventJoypadMotion.new()
	motion_left.axis = JOY_AXIS_LEFT_X
	motion_left.axis_value = -1.0
	_add_event_once("p2_move_left", motion_left)
	var motion_right := InputEventJoypadMotion.new()
	motion_right.axis = JOY_AXIS_LEFT_X
	motion_right.axis_value = 1.0
	_add_event_once("p2_move_right", motion_right)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	_add_event_once("p2_shoot", button)


static func _add_event_once(action: String, event: InputEvent) -> void:
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing.is_match(event, true) or existing.get_class() == event.get_class() and existing.as_text() == event.as_text():
			return
	InputMap.action_add_event(action, event)


## In coop local, J1 moves with A/D only so its arrows do not drive J2 (Etapa 20).
static func ignores_arrow_keys(player_index: int, coop_active: bool) -> bool:
	return player_index == 1 and coop_active


## Moves the ship horizontally from its slot's input, then clamps it to the horizontal limits.
func move_and_clamp() -> void:
	var direction: float = 0.0
	if ignores_arrow_keys(_player.player_index, _player.coop_active):
		direction = (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	else:
		direction = Input.get_axis(input_action_name("move_left", _player.player_index), input_action_name("move_right", _player.player_index))
	_player.velocity = Vector2(direction * _player.speed, 0.0)
	_player.move_and_slide()

	# Clamp to horizontal limits from GameLayout when provided, else viewport bounds.
	var limits: Vector2 = _player._horizontal_limits
	if limits != Vector2.ZERO:
		_player.position.x = clampf(_player.position.x, limits.x + MARGIN, limits.y - MARGIN)
	else:
		var viewport_rect: Rect2 = _player.get_viewport_rect()
		_player.position.x = clampf(_player.position.x, viewport_rect.position.x + MARGIN, viewport_rect.end.x - MARGIN)
