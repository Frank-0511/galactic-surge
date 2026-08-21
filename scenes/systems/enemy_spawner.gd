# enemy_spawner.gd
# Creates and moves the enemy formation as one synchronized group.

extends Node2D

## Emitted when an enemy directly collides with the player.
signal enemy_contacted_player(player: Node2D)

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

var _direction: float = 1.0
var _is_running: bool = true


func _ready() -> void:
	spawn_formation()


func _process(delta: float) -> void:
	if not _is_running:
		return
	var enemies: Array[Area2D] = _get_valid_enemies()
	if enemies.is_empty():
		return
	var viewport_rect: Rect2 = get_viewport_rect()
	var horizontal_delta: float = _direction * formation_speed * delta
	var left_edge: float = enemies[0].global_position.x
	var right_edge: float = left_edge
	for enemy: Area2D in enemies:
		left_edge = minf(left_edge, enemy.global_position.x)
		right_edge = maxf(right_edge, enemy.global_position.x)
	if left_edge + horizontal_delta < viewport_rect.position.x or right_edge + horizontal_delta > viewport_rect.end.x:
		_direction *= -1.0
		for enemy: Area2D in enemies:
			enemy.position.y += descent_distance
		return
	for enemy: Area2D in enemies:
		enemy.position.x += horizontal_delta


func spawn_formation() -> void:
	for enemy: Area2D in _get_valid_enemies():
		remove_child(enemy)
		enemy.queue_free()
	if enemy_scene == null:
		return
	for row: int in rows:
		for column: int in columns:
			var enemy: Area2D = enemy_scene.instantiate() as Area2D
			if enemy == null:
				continue
			enemy.position = Vector2(
				(column - (columns - 1) / 2.0) * horizontal_spacing,
				row * vertical_spacing + 120.0,
			)
			enemy.player_contacted.connect(_on_enemy_player_contacted)
			add_child(enemy)
	_direction = 1.0
	_is_running = true
	set_process(true)


func stop() -> void:
	_is_running = false
	set_process(false)
	for enemy: Area2D in _get_valid_enemies():
		var shoot_cooldown: Timer = enemy.get_node_or_null("ShootCooldown") as Timer
		if shoot_cooldown != null:
			shoot_cooldown.stop()


func _get_valid_enemies() -> Array[Area2D]:
	var enemies: Array[Area2D] = []
	for child: Node in get_children():
		if is_instance_valid(child) and child is Area2D and child.is_in_group("enemies"):
			enemies.append(child as Area2D)
	return enemies


func _on_enemy_player_contacted(player: Node2D) -> void:
	enemy_contacted_player.emit(player)
