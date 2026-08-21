# main.gd
# Main scene — owns the combat session, player lives, and game-over retry flow.

extends Node2D

const STARTING_LIVES: int = 3
const PLAYER_RESPAWN_POSITION := Vector2(300, 700)

## Bullet scene to provide to the player.
var bullet_scene: PackedScene = preload("res://scenes/entities/bullet/bullet.tscn")

@onready var _player: CharacterBody2D = $Player
@onready var _enemy_spawner: Node2D = $EnemySpawner
@onready var _game_over: CanvasLayer = $GameOver

var _lives: int = STARTING_LIVES
var _session_active: bool = true


func _ready() -> void:
	_player.bullet_scene = bullet_scene
	_player.damage_requested.connect(_on_player_damage_requested)
	_enemy_spawner.enemy_contacted_player.connect(_on_enemy_contacted_player)
	_game_over.retry_requested.connect(_on_game_over_retry_requested)
	child_entered_tree.connect(_on_child_entered_tree)


func _on_child_entered_tree(child: Node) -> void:
	if child is Area2D and child.has_signal(&"player_hit"):
		child.connect(&"player_hit", _on_enemy_bullet_player_hit)


func _on_enemy_contacted_player(player: Node2D) -> void:
	_request_player_damage(player)


func _on_enemy_bullet_player_hit(player: Node2D) -> void:
	_request_player_damage(player)


func _request_player_damage(player: Node2D) -> void:
	if not _session_active or player != _player:
		return
	_player.take_damage()


func _on_player_damage_requested() -> void:
	if not _session_active:
		return
	_lives -= 1
	if _lives > 0:
		_player.respawn(PLAYER_RESPAWN_POSITION)
		return
	_end_session()


func _end_session() -> void:
	if not _session_active:
		return
	_session_active = false
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	_game_over.show_game_over()


func _on_game_over_retry_requested() -> void:
	get_tree().reload_current_scene()
