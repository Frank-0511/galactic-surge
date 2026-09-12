# enemy_spawner.gd
# Creates and moves the enemy formation as one synchronized group.
# Owns the progressive wave system: five waves with increasing speed, patterns, and Bézier fly-in.

extends Node2D

const FormationPatterns: Script = preload("res://scripts/systems/formation_patterns.gd")

## Emitted when an enemy directly collides with the player.
signal enemy_contacted_player(player: Node2D)

## Emitted once for every enemy destruction signal received.
signal enemy_destroyed(enemy: Area2D)

## Emitted exactly once when the last enemy of a wave is destroyed.
## wave_index is 0-based.
signal wave_cleared(wave_index: int)

## Emitted after the final wave (index 4) is cleared.
signal all_waves_cleared

## Emitted when all flying-in enemies of the current wave have settled into formation.
signal fly_in_completed_all

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

## Whether enemies enter using Bézier curve fly-in.
@export var fly_in_enabled: bool = true

## Duration in seconds of each enemy's Bézier fly-in entrance.
@export var fly_in_duration: float = 1.2

## Half of the 36 px Enemy collision shape width.
const ENEMY_HALF_WIDTH: float = 18.0

## Progressive wave configurations.
## Indices are 0-based: wave 0 is the first wave, wave 4 is the last.
const _WAVE_CONFIGS: Array = [
	{"rows": 3, "columns": 6, "formation_speed": 80.0, "formation_type": "grid", "fly_in_trajectory": "swoop_left"},
	{"rows": 3, "columns": 6, "formation_speed": 95.0, "formation_type": "v_shape", "fly_in_trajectory": "pincer"},
	{"rows": 3, "columns": 7, "formation_speed": 110.0, "formation_type": "arc", "fly_in_trajectory": "swoop_right"},
	{"rows": 4, "columns": 7, "formation_speed": 125.0, "formation_type": "diagonal", "fly_in_trajectory": "cross_dive"},
	{"rows": 4, "columns": 8, "formation_speed": 140.0, "formation_type": "grid", "fly_in_trajectory": "center_loop"},
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


## Sets the formation origin (center_x, first_row_y) from GameLayout.
func set_formation_layout(origin: Vector2, first_row_y: float) -> void:
	_formation_origin = origin
	_first_row_y = first_row_y


func _process(delta: float) -> void:
	if not _is_running or _is_flying_in:
		return
	var enemies: Array[Area2D] = _get_valid_enemies()
	if enemies.is_empty():
		return
	var viewport_rect: Rect2 = get_viewport_rect()
	var horizontal_delta: float = _direction * formation_speed * delta
	var left_edge: float = enemies[0].global_position.x - ENEMY_HALF_WIDTH
	var right_edge: float = enemies[0].global_position.x + ENEMY_HALF_WIDTH
	for enemy: Area2D in enemies:
		left_edge = minf(left_edge, enemy.global_position.x - ENEMY_HALF_WIDTH)
		right_edge = maxf(right_edge, enemy.global_position.x + ENEMY_HALF_WIDTH)
	if left_edge + horizontal_delta < viewport_rect.position.x or right_edge + horizontal_delta > viewport_rect.end.x:
		_direction *= -1.0
		for enemy: Area2D in enemies:
			enemy.position.y += descent_distance
		return
	for enemy: Area2D in enemies:
		enemy.position.x += horizontal_delta


func spawn_formation() -> void:
	clear_formation()
	if enemy_scene == null:
		return

	var pattern: int = FormationPatterns.pattern_from_string(_current_pattern_type)
	var slots: Array[Vector2] = FormationPatterns.calculate_slots(
		pattern, rows, columns, horizontal_spacing, vertical_spacing,
		Vector2(_formation_origin.x, _first_row_y)
	)

	var vp_rect: Rect2 = get_viewport_rect() if is_inside_tree() else Rect2(0, 0, 1080, 960)
	if vp_rect.size == Vector2.ZERO:
		vp_rect = Rect2(0, 0, 1080, 960)

	var should_fly_in: bool = fly_in_enabled and fly_in_duration > 0.0
	_is_flying_in = should_fly_in
	_flying_in_count = 0

	for i: int in range(slots.size()):
		var slot_pos: Vector2 = slots[i]
		var enemy: Area2D = enemy_scene.instantiate() as Area2D
		if enemy == null:
			continue
		add_child(enemy)
		enemy.player_contacted.connect(_on_enemy_player_contacted)
		enemy.destroyed.connect(_on_enemy_destroyed)
		_alive_count += 1

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
