# asteroid_spawner.gd
# Manages dedicated asteroid belt waves without enemy fighters.
# Spawns initial large asteroids, tracks fragments created through hierarchical
# destruction, broadcasts sensor warning alerts, and emits completion signals
# when the hazard zone is cleared.

class_name AsteroidSpawner
extends Node2D

const AsteroidScript: Script = preload("res://scenes/entities/asteroid/asteroid.gd")

## Emitted when any asteroid (initial or fragment) is spawned into the scene.
signal asteroid_spawned(asteroid: Area2D)

## Emitted when all asteroids and child fragments of the wave have been cleared.
signal asteroid_wave_completed

## Emitted when no active asteroids remain on screen.
signal all_asteroids_cleared

## Emitted to request sensory (visual banner/audio siren) warning of incoming impact.
signal warning_requested(duration: float, message: String)

@export var asteroid_scene: PackedScene = preload("res://scenes/entities/asteroid/asteroid.tscn")
@export var wave_asteroid_count: int = 8
@export var spawn_interval: float = 1.5
@export var min_speed: float = 60.0
@export var max_speed: float = 120.0
@export var loot_chance: float = 0.50

var _active_asteroids: Array[Area2D] = []
var _pending_to_spawn: int = 0
var _spawn_timer: float = 0.0
var _is_active: bool = false


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if not _is_active:
		return

	# Periodic cleanup of invalid / queued references
	_cleanup_active_list()

	if _pending_to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = spawn_interval
			_pending_to_spawn -= 1
			_spawn_random_large_asteroid()

	# Check wave completion condition
	if _pending_to_spawn <= 0 and _active_asteroids.is_empty():
		_is_active = false
		all_asteroids_cleared.emit()
		asteroid_wave_completed.emit()


func _cleanup_active_list() -> void:
	var valid: Array[Area2D] = []
	for ast: Area2D in _active_asteroids:
		if is_instance_valid(ast) and not ast.is_queued_for_deletion():
			valid.append(ast)
	_active_asteroids = valid


## Starts a new asteroid belt wave with the specified count of large asteroids.
func start_asteroid_wave(count: int = -1) -> void:
	clear_asteroids()
	_pending_to_spawn = count if count > 0 else wave_asteroid_count
	_spawn_timer = 0.3
	_is_active = true
	warning_requested.emit(2.8, "¡ALERTA: CINTURÓN DE ASTEROIDES INMINENTE!")


## Spawns a configured asteroid at position with velocity.
func spawn_asteroid(size: int = 0, pos: Vector2 = Vector2.ZERO, vel: Vector2 = Vector2.ZERO) -> Area2D:
	if asteroid_scene == null:
		return null

	var asteroid: Area2D = asteroid_scene.instantiate() as Area2D
	if asteroid == null:
		return null

	if asteroid.has_method(&"set_size"):
		asteroid.call(&"set_size", size)
	if vel != Vector2.ZERO:
		asteroid.linear_velocity = vel

	_register_asteroid(asteroid)
	add_child(asteroid)
	# Set after add_child: global_position outside the tree is treated as local,
	# which would offset the asteroid by the spawner's own position.
	if pos != Vector2.ZERO:
		asteroid.global_position = pos
	asteroid_spawned.emit(asteroid)
	return asteroid


func _spawn_random_large_asteroid() -> void:
	var vp_width: float = 1080.0
	if is_inside_tree():
		var vp_rect: Rect2 = get_viewport_rect()
		if vp_rect.size.x > 0.0:
			vp_width = vp_rect.size.x

	var spawn_x: float = randf_range(80.0, vp_width - 80.0)
	var spawn_pos: Vector2 = Vector2(spawn_x, -70.0)
	var speed: float = randf_range(min_speed, max_speed)
	var drift: float = randf_range(-10.0, 10.0)
	var vel: Vector2 = Vector2(drift, speed)

	var ast: Area2D = spawn_asteroid(0, spawn_pos, vel) # 0 = Size.LARGE
	if ast != null:
		ast.angular_velocity = randf_range(-2.0, 2.0)
		ast.set("contains_loot", (randf() < loot_chance))


## Registers tracking signals on an asteroid (or fragment).
func _register_asteroid(asteroid: Area2D) -> void:
	if not _active_asteroids.has(asteroid):
		_active_asteroids.append(asteroid)

	if asteroid.has_signal(&"fragment_spawned") and not asteroid.fragment_spawned.is_connected(_on_fragment_spawned):
		asteroid.fragment_spawned.connect(_on_fragment_spawned)
	if not asteroid.tree_exited.is_connected(_on_asteroid_tree_exited.bind(asteroid)):
		asteroid.tree_exited.connect(_on_asteroid_tree_exited.bind(asteroid))


func _on_fragment_spawned(fragment: Area2D) -> void:
	_register_asteroid(fragment)
	asteroid_spawned.emit(fragment)


func _on_asteroid_tree_exited(asteroid: Area2D) -> void:
	_active_asteroids.erase(asteroid)
	if _is_active and _pending_to_spawn <= 0 and _active_asteroids.is_empty():
		_is_active = false
		all_asteroids_cleared.emit()
		asteroid_wave_completed.emit()


## Halts spawning and clears wave state.
func stop() -> void:
	_is_active = false
	_pending_to_spawn = 0


## Frees all tracked asteroids immediately.
func clear_asteroids() -> void:
	stop()
	for ast: Area2D in _active_asteroids:
		if is_instance_valid(ast) and not ast.is_queued_for_deletion():
			ast.queue_free()
	_active_asteroids.clear()


func get_active_asteroid_count() -> int:
	_cleanup_active_list()
	return _active_asteroids.size()


func is_wave_active() -> bool:
	return _is_active
