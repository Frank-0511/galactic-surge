# enemy_spawner.gd
# Creates and moves the enemy formation as one synchronized group.
# Owns the progressive wave system: ten waves with increasing speed, patterns, and Bézier fly-in.
# Manages dynamic offensive dives (1-on-1 and pairs) and the wave enrage countdown timer.

extends Node2D

const FormationPatterns: Script = preload("res://scripts/systems/formation_patterns.gd")

## Emitted when an enemy directly collides with the player.
signal enemy_contacted_player(player: Node2D)

## Emitted once for every enemy destruction signal received.
signal enemy_destroyed(enemy: Area2D)

## Emitted exactly once when the last enemy of a wave is destroyed.
## wave_index is 0-based.
signal wave_cleared(wave_index: int)

## Emitted after the final wave (index 9) is cleared.
signal all_waves_cleared

## Emitted when all flying-in enemies of the current wave have settled into formation.
signal fly_in_completed_all

## Emitted when the formation enrage threshold is reached.
signal enrage_triggered

## Emitted when an enemy begins an offensive dive toward the player.
signal enemy_dived(enemy: Area2D)

## Emitted when an enemy returns from a dive and re-enters formation.
signal formation_rejoined(enemy: Area2D)

## Scene used for every member of the formation.
@export var enemy_scene: PackedScene = preload("res://scenes/entities/enemy/enemy.tscn")

## Number of horizontal formation rows.
@export var rows: int = 3

## Number of enemies per row.
@export var columns: int = 6

## Horizontal distance between enemy centers.
@export var horizontal_spacing: float = 72.0

## Vertical distance between enemy centers.
@export var vertical_spacing: float = 64.0

## Shared horizontal speed in pixels per second.
@export var formation_speed: float = 80.0

## Vertical step applied after reaching a viewport edge.
@export var descent_distance: float = 32.0

## Maximum vertical descent accumulated for the formation.
@export var max_formation_descent_y: float = 380.0

## Maximum Y position allowed for the lowest enemy in formation.
@export var max_formation_bottom_y: float = 480.0

## Whether enemies enter using Bézier curve fly-in.
@export var fly_in_enabled: bool = true

## Duration in seconds of each enemy's Bézier fly-in entrance.
@export var fly_in_duration: float = 1.2

## Wave elapsed seconds before enemies enter enrage state.
@export var enrage_time: float = 35.0

## Base interval in seconds between offensive dives.
@export var base_dive_interval: float = 4.2

## Half of the 36 px Enemy collision shape width.
const ENEMY_HALF_WIDTH: float = 18.0

## Progressive wave configurations.
## Indices are 0-based: wave 0 is the first wave, wave 9 is the last.
const _WAVE_CONFIGS: Array = [
	{"rows": 3, "columns": 6, "formation_speed": 80.0,  "formation_type": "grid",     "fly_in_trajectory": "swoop_left"},
	{"rows": 3, "columns": 6, "formation_speed": 90.0,  "formation_type": "v_shape",  "fly_in_trajectory": "pincer"},
	{"rows": 3, "columns": 7, "formation_speed": 100.0, "formation_type": "arc",      "fly_in_trajectory": "swoop_right"},
	{"rows": 4, "columns": 7, "formation_speed": 110.0, "formation_type": "diagonal", "fly_in_trajectory": "cross_dive"},
	{"rows": 4, "columns": 7, "formation_speed": 120.0, "formation_type": "grid",     "fly_in_trajectory": "center_loop"},
	{"rows": 4, "columns": 8, "formation_speed": 128.0, "formation_type": "v_shape",  "fly_in_trajectory": "swoop_left"},
	{"rows": 4, "columns": 8, "formation_speed": 136.0, "formation_type": "arc",      "fly_in_trajectory": "pincer"},
	{"rows": 5, "columns": 7, "formation_speed": 144.0, "formation_type": "diagonal", "fly_in_trajectory": "swoop_right"},
	{"rows": 5, "columns": 8, "formation_speed": 152.0, "formation_type": "grid",     "fly_in_trajectory": "cross_dive"},
	{"rows": 5, "columns": 8, "formation_speed": 160.0, "formation_type": "arc",      "fly_in_trajectory": "center_loop"},
]

var _direction: float = 1.0
var _is_running: bool = false
var _is_flying_in: bool = false
var _flying_in_count: int = 0
var _current_wave: int = 0
var _alive_count: int = 0
var _wave_cleared_emitted: bool = false
var _formation_origin: Vector2 = Vector2.ZERO
var _first_row_y: float = 120.0
var _current_pattern_type: String = "grid"
var _current_trajectory: String = "swoop_left"

## Stage 9 temporal escalation and slot tracking
var _wave_timer: float = 0.0
var _is_enraged: bool = false
var _dive_cooldown_timer: float = 3.5
var _enemy_base_slots: Dictionary = {} # Area2D -> Vector2
var _formation_shift: Vector2 = Vector2.ZERO


## Sets the formation origin (center_x, first_row_y) from GameLayout.
func set_formation_layout(origin: Vector2, first_row_y: float) -> void:
	_formation_origin = origin
	_first_row_y = first_row_y


func _process(delta: float) -> void:
	if not _is_running or _is_flying_in:
		return

	# Temporal escalation (enrage countdown)
	if not _is_enraged:
		_wave_timer += delta
		if _wave_timer >= enrage_time:
			_trigger_enrage()

	var all_enemies: Array[Area2D] = _get_valid_enemies()
	if all_enemies.is_empty():
		return

	# Formation movement: only considers and displaces enemies actively IN FORMATION
	var formation_enemies: Array[Area2D] = []
	for enemy: Area2D in all_enemies:
		if enemy.has_method(&"is_in_formation") and not enemy.is_in_formation():
			continue
		formation_enemies.append(enemy)

	# Dive attack countdown: only tick down when at least one candidate is in formation
	if not formation_enemies.is_empty():
		_dive_cooldown_timer -= delta
		if _dive_cooldown_timer <= 0.0:
			var dive_count: int = 1
			if _current_wave >= 2 or _is_enraged:
				dive_count = 2 if randf() < 0.65 else 1
			trigger_dive(dive_count)
			_dive_cooldown_timer = randf_range(1.6, 2.5) if _is_enraged else randf_range(3.2, 5.0)

	# If no enemies are currently in formation, freeze formation shift to prevent off-screen drift
	if formation_enemies.is_empty():
		return

	var horizontal_delta: float = _direction * formation_speed * delta
	var viewport_rect: Rect2 = get_viewport_rect()
	var left_edge: float = formation_enemies[0].global_position.x - ENEMY_HALF_WIDTH
	var right_edge: float = formation_enemies[0].global_position.x + ENEMY_HALF_WIDTH
	for enemy: Area2D in formation_enemies:
		left_edge = minf(left_edge, enemy.global_position.x - ENEMY_HALF_WIDTH)
		right_edge = maxf(right_edge, enemy.global_position.x + ENEMY_HALF_WIDTH)

	# Strict edge bounce: only reverse direction if moving toward that wall
	var hit_right: bool = (_direction > 0.0 and right_edge + horizontal_delta >= viewport_rect.end.x)
	var hit_left: bool = (_direction < 0.0 and left_edge + horizontal_delta <= viewport_rect.position.x)

	if hit_right or hit_left:
		_direction = -1.0 if hit_right else 1.0

		# Clamp positions to prevent formation from remaining outside viewport bounds
		var clamp_x: float = 0.0
		if hit_right and right_edge > viewport_rect.end.x:
			clamp_x = viewport_rect.end.x - right_edge
		elif hit_left and left_edge < viewport_rect.position.x:
			clamp_x = viewport_rect.position.x - left_edge

		if absf(clamp_x) > 0.001:
			_formation_shift.x += clamp_x
			for enemy: Area2D in formation_enemies:
				enemy.position.x += clamp_x

		# Check descent ceiling: only descend if formation bottom remains within safe limits
		var can_descend: bool = (_formation_shift.y + descent_distance <= max_formation_descent_y)
		if can_descend:
			var lowest_y: float = -INF
			for enemy: Area2D in formation_enemies:
				lowest_y = maxf(lowest_y, enemy.global_position.y)
			if lowest_y + descent_distance > max_formation_bottom_y:
				can_descend = false

		if can_descend:
			_formation_shift.y += descent_distance
			for enemy: Area2D in formation_enemies:
				enemy.position.y += descent_distance
		return

	_formation_shift.x += horizontal_delta
	for enemy: Area2D in formation_enemies:
		enemy.position.x += horizontal_delta


func spawn_formation() -> void:
	clear_formation()
	if enemy_scene == null:
		return

	var vp_rect: Rect2 = get_viewport_rect() if is_inside_tree() else Rect2(0, 0, 1080, 960)
	if vp_rect.size == Vector2.ZERO:
		vp_rect = Rect2(0, 0, 1080, 960)

	var origin: Vector2 = _formation_origin
	if origin == Vector2.ZERO:
		origin = Vector2(vp_rect.get_center().x, _first_row_y)

	var pattern: int = FormationPatterns.pattern_from_string(_current_pattern_type)
	var slots: Array[Vector2] = FormationPatterns.calculate_slots(
		pattern, rows, columns, horizontal_spacing, vertical_spacing,
		origin
	)

	var should_fly_in: bool = fly_in_enabled and fly_in_duration > 0.0
	_is_flying_in = should_fly_in
	_flying_in_count = 0
	_enemy_base_slots.clear()
	_formation_shift = Vector2.ZERO
	_wave_timer = 0.0
	_is_enraged = false
	_dive_cooldown_timer = 3.5

	for i: int in range(slots.size()):
		var slot_pos: Vector2 = slots[i]
		var enemy: Area2D = enemy_scene.instantiate() as Area2D
		if enemy == null:
			continue
		add_child(enemy)
		enemy.player_contacted.connect(_on_enemy_player_contacted)
		enemy.destroyed.connect(_on_enemy_destroyed)
		_alive_count += 1
		_enemy_base_slots[enemy] = slot_pos

		if should_fly_in:
			_flying_in_count += 1
			var points: Array[Vector2] = _generate_bezier_points(_current_trajectory, slot_pos, i, vp_rect)
			var delay: float = 0.06 * float(i)
			enemy.global_position = points[0]
			if enemy.has_signal(&"fly_in_completed"):
				enemy.fly_in_completed.connect(_on_enemy_fly_in_completed)
			if enemy.has_method(&"start_fly_in"):
				enemy.start_fly_in(points[0], points[1], points[2], points[3], fly_in_duration, delay)
		else:
			enemy.global_position = slot_pos

	_direction = 1.0
	_is_running = true
	set_process(true)


func clear_formation() -> void:
	for enemy: Area2D in _get_valid_enemies():
		remove_child(enemy)
		enemy.queue_free()
	_alive_count = 0
	_flying_in_count = 0
	_is_flying_in = false
	_wave_cleared_emitted = false
	_enemy_base_slots.clear()
	_formation_shift = Vector2.ZERO
	_wave_timer = 0.0
	_is_enraged = false
	_dive_cooldown_timer = 3.5


func stop() -> void:
	_is_running = false
	_is_flying_in = false
	set_process(false)
	for enemy: Area2D in _get_valid_enemies():
		if enemy.has_method(&"cancel_fly_in"):
			enemy.cancel_fly_in()
		var shoot_cooldown: Timer = enemy.get_node_or_null("ShootCooldown") as Timer
		if shoot_cooldown != null:
			shoot_cooldown.stop()


func get_total_waves() -> int:
	return _WAVE_CONFIGS.size()


func get_current_wave() -> int:
	return _current_wave


func is_flying_in() -> bool:
	return _is_flying_in


func is_enraged() -> bool:
	return _is_enraged


func get_wave_config(wave_index: int) -> Dictionary:
	if wave_index < 0 or wave_index >= _WAVE_CONFIGS.size():
		return {}
	var config: Dictionary = _WAVE_CONFIGS[wave_index]
	return config.duplicate()


func start_wave(wave_index: int) -> void:
	var config: Dictionary = get_wave_config(wave_index)
	if config.is_empty():
		return
	_current_wave = wave_index
	rows = int(config["rows"])
	columns = int(config["columns"])
	formation_speed = float(config["formation_speed"])
	_current_pattern_type = String(config.get("formation_type", "grid"))
	_current_trajectory = String(config.get("fly_in_trajectory", "swoop_left"))
	spawn_formation()


func get_enemy_slot_position(enemy: Area2D) -> Vector2:
	if _enemy_base_slots.has(enemy):
		return _enemy_base_slots[enemy] + _formation_shift
	return enemy.global_position


func trigger_dive(count: int = 1) -> Array[Area2D]:
	var candidates: Array[Area2D] = []
	for enemy: Area2D in _get_valid_enemies():
		if enemy.has_method(&"is_in_formation") and enemy.is_in_formation():
			candidates.append(enemy)

	if candidates.is_empty():
		return []

	# Prioritize lower rows (higher Y)
	candidates.sort_custom(func(a: Area2D, b: Area2D) -> bool:
		return a.global_position.y > b.global_position.y
	)

	var target_pos: Vector2 = Vector2(540.0, 850.0)
	if is_inside_tree():
		var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
		if not players.is_empty() and is_instance_valid(players[0]) and players[0] is Node2D:
			target_pos = (players[0] as Node2D).global_position

	var selected_count: int = mini(count, candidates.size())
	var attackers: Array[Area2D] = []

	for i: int in range(selected_count):
		var enemy: Area2D = candidates[i]
		var dive_dur: float = 1.6 if _is_enraged else 2.0
		var enemy_ref: Area2D = enemy
		var slot_getter: Callable = func() -> Vector2:
			return get_enemy_slot_position(enemy_ref)

		if enemy.has_method(&"start_dive"):
			enemy.start_dive(target_pos, dive_dur, "swoop", slot_getter)
		if enemy.has_method(&"set_slot_getter"):
			enemy.set_slot_getter(slot_getter)

		var bound_callback: Callable = _on_enemy_returned_to_formation.bind(enemy)
		if not enemy.returned_to_formation.is_connected(bound_callback):
			enemy.returned_to_formation.connect(bound_callback, CONNECT_ONE_SHOT)

		attackers.append(enemy)
		enemy_dived.emit(enemy)

	return attackers


func _on_enemy_returned_to_formation(enemy: Area2D) -> void:
	var bound: Callable = _on_enemy_returned_to_formation.bind(enemy)
	if is_instance_valid(enemy):
		if enemy.returned_to_formation.is_connected(bound):
			enemy.returned_to_formation.disconnect(bound)
		elif enemy.returned_to_formation.is_connected(_on_enemy_returned_to_formation):
			enemy.returned_to_formation.disconnect(_on_enemy_returned_to_formation)
	formation_rejoined.emit(enemy)
	# Grace period: ensure cooldown is at least 3.8s (or 2.2s if enraged) so player has ample time to shoot
	var min_grace: float = 2.2 if _is_enraged else 3.8
	_dive_cooldown_timer = maxf(_dive_cooldown_timer, min_grace)


func _trigger_enrage() -> void:
	if _is_enraged:
		return
	_is_enraged = true
	formation_speed *= 1.4
	enrage_triggered.emit()
	for enemy: Area2D in _get_valid_enemies():
		if enemy.has_method(&"set_enraged"):
			enemy.set_enraged(true)


func _generate_bezier_points(trajectory: String, slot_pos: Vector2, index: int, vp_rect: Rect2) -> Array[Vector2]:
	var p0: Vector2
	var p1: Vector2
	var p2: Vector2
	var p3: Vector2 = slot_pos

	var vp_w: float = vp_rect.size.x
	var vp_h: float = vp_rect.size.y
	var center_x: float = vp_rect.get_center().x

	match trajectory.to_lower():
		"swoop_left":
			p0 = Vector2(vp_rect.position.x - 100.0, vp_rect.position.y - 60.0)
			p1 = Vector2(vp_rect.position.x + vp_w * 0.25, vp_rect.position.y + vp_h * 0.45)
			p2 = Vector2(slot_pos.x - 80.0, slot_pos.y + 120.0)
		"swoop_right":
			p0 = Vector2(vp_rect.end.x + 100.0, vp_rect.position.y - 60.0)
			p1 = Vector2(vp_rect.end.x - vp_w * 0.25, vp_rect.position.y + vp_h * 0.45)
			p2 = Vector2(slot_pos.x + 80.0, slot_pos.y + 120.0)
		"pincer":
			if (index % 2) == 0:
				p0 = Vector2(vp_rect.position.x - 120.0, slot_pos.y + 40.0)
				p1 = Vector2(vp_rect.position.x + vp_w * 0.4, vp_rect.position.y + 80.0)
				p2 = Vector2(slot_pos.x - 60.0, slot_pos.y - 40.0)
			else:
				p0 = Vector2(vp_rect.end.x + 120.0, slot_pos.y + 40.0)
				p1 = Vector2(vp_rect.end.x - vp_w * 0.4, vp_rect.position.y + 80.0)
				p2 = Vector2(slot_pos.x + 60.0, slot_pos.y - 40.0)
		"cross_dive":
			if (index % 2) == 0:
				p0 = Vector2(vp_rect.position.x + vp_w * 0.1, vp_rect.position.y - 120.0)
				p1 = Vector2(vp_rect.end.x - 80.0, vp_rect.position.y + vp_h * 0.4)
				p2 = Vector2(slot_pos.x + 60.0, slot_pos.y + 90.0)
			else:
				p0 = Vector2(vp_rect.end.x - vp_w * 0.1, vp_rect.position.y - 120.0)
				p1 = Vector2(vp_rect.position.x + 80.0, vp_rect.position.y + vp_h * 0.4)
				p2 = Vector2(slot_pos.x - 60.0, slot_pos.y + 90.0)
		"center_loop":
			p0 = Vector2(center_x, vp_rect.position.y - 120.0)
			var side: float = -1.0 if slot_pos.x < center_x else 1.0
			p1 = Vector2(center_x + side * (vp_w * 0.2), vp_rect.position.y + vp_h * 0.45)
			p2 = Vector2(slot_pos.x + side * 40.0, slot_pos.y + 100.0)
		_:
			p0 = Vector2(slot_pos.x, vp_rect.position.y - 100.0)
			p1 = Vector2(slot_pos.x, vp_rect.position.y + 50.0)
			p2 = Vector2(slot_pos.x, slot_pos.y - 40.0)

	return [p0, p1, p2, p3]


func _get_valid_enemies() -> Array[Area2D]:
	var enemies: Array[Area2D] = []
	for child: Node in get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			enemies.append(child as Area2D)
	return enemies


func _on_enemy_player_contacted(player: Node2D) -> void:
	enemy_contacted_player.emit(player)


func _on_enemy_fly_in_completed() -> void:
	_flying_in_count -= 1
	if _flying_in_count <= 0 and _is_flying_in:
		_is_flying_in = false
		fly_in_completed_all.emit()


func _on_enemy_destroyed(enemy: Area2D) -> void:
	_enemy_base_slots.erase(enemy)
	if _is_flying_in:
		_flying_in_count -= 1
		if _flying_in_count <= 0:
			_is_flying_in = false
			fly_in_completed_all.emit()
	enemy_destroyed.emit(enemy)
	_alive_count -= 1
	if _alive_count <= 0 and not _wave_cleared_emitted:
		_wave_cleared_emitted = true
		wave_cleared.emit(_current_wave)
		if _current_wave == _WAVE_CONFIGS.size() - 1:
			all_waves_cleared.emit()
