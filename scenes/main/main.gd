# main.gd
# Main scene — owns the combat session, player lives, and game-over retry flow.

extends Node2D

const STARTING_LIVES: int = 3
const POINTS_PER_ENEMY: int = 100
const CLEAN_WAVE_BONUS: int = 500
const TOTAL_WAVES: int = 5
const PLAYER_RESPAWN_POSITION := Vector2(300, 700)

## Bullet scene to provide to the player.
var bullet_scene: PackedScene = preload("res://scenes/entities/bullet/bullet.tscn")

@onready var _player: CharacterBody2D = $Player
@onready var _enemy_spawner: Node2D = $EnemySpawner
@onready var _game_over: CanvasLayer = $GameOver
@onready var _hud: CanvasLayer = $HUD

## Current player lives, score, and 1-based wave number for this session.
var lives: int = STARTING_LIVES
var score: int = 0
var wave: int = 1

var _session_active: bool = true
var _mission_complete: bool = false
var _wave_is_clean: bool = true


func _ready() -> void:
	_player.bullet_scene = bullet_scene
	_player.damage_requested.connect(_on_player_damage_requested)
	_enemy_spawner.enemy_contacted_player.connect(_on_enemy_contacted_player)
	_enemy_spawner.enemy_destroyed.connect(_on_enemy_destroyed)
	_enemy_spawner.wave_cleared.connect(_on_wave_cleared)
	_game_over.retry_requested.connect(_on_game_over_retry_requested)
	child_entered_tree.connect(_on_child_entered_tree)
	_update_hud()
	_enemy_spawner.start_wave(0)


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
	_wave_is_clean = false
	lives -= 1
	_hud.set_lives(lives)
	if lives > 0:
		_player.respawn(PLAYER_RESPAWN_POSITION)
		return
	_end_session()


func _on_enemy_destroyed(_enemy: Area2D) -> void:
	if not _session_active:
		return
	score += POINTS_PER_ENEMY
	_hud.set_score(score)


func _on_wave_cleared(_wave_index: int) -> void:
	if not _session_active:
		return
	if _wave_is_clean:
		score += CLEAN_WAVE_BONUS
		_hud.set_score(score)
	if wave >= TOTAL_WAVES:
		_complete_mission()
		return
	wave += 1
	_wave_is_clean = true
	_hud.set_wave(wave)
	_enemy_spawner.start_wave(wave - 1)


func _end_session() -> void:
	if not _session_active:
		return
	_session_active = false
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	_game_over.show_game_over(score)


func _complete_mission() -> void:
	_session_active = false
	_mission_complete = true
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	_hud.show_mission_complete()


func is_mission_complete() -> bool:
	return _mission_complete


func is_session_active() -> bool:
	return _session_active


func reset_session() -> void:
	lives = STARTING_LIVES
	score = 0
	wave = 1
	_session_active = true
	_mission_complete = false
	_wave_is_clean = true
	_game_over.visible = false
	_player.set_gameplay_enabled(true)
	_player.respawn(PLAYER_RESPAWN_POSITION)
	var mission_label: CanvasItem = _hud.get_node_or_null("MissionCompleteLabel") as CanvasItem
	if mission_label != null:
		mission_label.visible = false
	_update_hud()
	_enemy_spawner.start_wave(0)


func _update_hud() -> void:
	_hud.set_lives(lives)
	_hud.set_score(score)
	_hud.set_wave(wave)


func _on_game_over_retry_requested() -> void:
	reset_session()
