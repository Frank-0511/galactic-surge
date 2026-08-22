# enemy_spawner.gd
# Creates and moves the enemy formation as one synchronized group.
# Owns the progressive wave system: five waves with increasing speed and density.

extends Node2D

## Emitted when an enemy directly collides with the player.
signal enemy_contacted_player(player: Node2D)

## Emitted once for every enemy destruction signal received.
signal enemy_destroyed(enemy: Area2D)

## Emitted exactly once when the last enemy of a wave is destroyed.
## wave_index is 0-based.
signal wave_cleared(wave_index: int)

## Emitted after the final wave (index 4) is cleared.
signal all_waves_cleared

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

## Half of the 36 px Enemy collision shape width.
const ENEMY_HALF_WIDTH: float = 18.0

## Progressive wave configurations (rows, columns, formation_speed).
## Indices are 0-based: wave 0 is the first wave, wave 4 is the last.
const _WAVE_CONFIGS: Array = [
	{"rows": 3, "columns": 6, "formation_speed": 80.0},
	{"rows": 3, "columns": 6, "formation_speed": 95.0},
	{"rows": 3, "columns": 7, "formation_speed": 110.0},
	{"rows": 4, "columns": 7, "formation_speed": 125.0},
	{"rows": 4, "columns": 8, "formation_speed": 140.0},
]

var _direction: float = 1.0
var _is_running: bool = false
var _current_wave: int = 0
var _alive_count: int = 0
var _wave_cleared_emitted: bool = false
var _formation_origin: Vector2 = Vector2.ZERO
var _first_row_y: float = 120.0


## Sets the formation origin (center_x, first_row_y) from GameLayout.
func set_formation_layout(origin: Vector2, first_row_y: float) -> void:
	_formation_origin = origin
	_first_row_y = first_row_y


func _process(delta: float) -> void:
	if not _is_running:
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
	for row: int in rows:
		for column: int in columns:
			var enemy: Area2D = enemy_scene.instantiate() as Area2D
			if enemy == null:
				continue
			add_child(enemy)
			enemy.global_position = Vector2(
				_formation_origin.x + (column - (columns - 1) / 2.0) * horizontal_spacing,
				_first_row_y + row * vertical_spacing,
			)
			enemy.player_contacted.connect(_on_enemy_player_contacted)
			enemy.destroyed.connect(_on_enemy_destroyed)
			_alive_count += 1
	_direction = 1.0
	_is_running = true
	set_process(true)


func clear_formation() -> void:
	for enemy: Area2D in _get_valid_enemies():
		remove_child(enemy)
		enemy.queue_free()
	_alive_count = 0
	_wave_cleared_emitted = false


func stop() -> void:
	_is_running = false
	set_process(false)
	for enemy: Area2D in _get_valid_enemies():
		var shoot_cooldown: Timer = enemy.get_node_or_null("ShootCooldown") as Timer
		if shoot_cooldown != null:
			shoot_cooldown.stop()


func get_total_waves() -> int:
	return _WAVE_CONFIGS.size()


func get_current_wave() -> int:
	return _current_wave


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
	spawn_formation()


func _get_valid_enemies() -> Array[Area2D]:
	var enemies: Array[Area2D] = []
	for child: Node in get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			enemies.append(child as Area2D)
	return enemies


func _on_enemy_player_contacted(player: Node2D) -> void:
	enemy_contacted_player.emit(player)


func _on_enemy_destroyed(enemy: Area2D) -> void:
	enemy_destroyed.emit(enemy)
	_alive_count -= 1
	if _alive_count <= 0 and not _wave_cleared_emitted:
		_wave_cleared_emitted = true
		wave_cleared.emit(_current_wave)
		if _current_wave == _WAVE_CONFIGS.size() - 1:
			all_waves_cleared.emit()
