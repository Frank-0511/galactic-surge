# main.gd
# Coordinates the combat session, navigation states, and visual feedback.

extends Node2D

const STARTING_LIVES: int = 3
const POINTS_PER_ENEMY: int = 100
const CLEAN_WAVE_BONUS: int = 500
const TOTAL_WAVES: int = 5
const PLAYER_RESPAWN_POSITION := Vector2(300, 700)

enum SessionState { MAIN_MENU, PLAYING, PAUSED, GAME_OVER, MISSION_COMPLETE }

## Bullet scene to provide to the player.
var bullet_scene: PackedScene = preload("res://scenes/entities/bullet/bullet.tscn")

@onready var _player: CharacterBody2D = $Player
@onready var _enemy_spawner: Node2D = $EnemySpawner
@onready var _game_over: CanvasLayer = $GameOver
@onready var _hud: CanvasLayer = $HUD
@onready var _main_menu: CanvasLayer = $MainMenu
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _starfield: Node2D = $Starfield
@onready var _visual_feedback: Node2D = $VisualFeedback

## Current player lives, score, and 1-based wave number for this session.
var lives: int = STARTING_LIVES
var score: int = 0
var wave: int = 1

var _session_state: SessionState = SessionState.MAIN_MENU
var _session_active: bool = false
var _mission_complete: bool = false
var _wave_is_clean: bool = true


func _ready() -> void:
	_player.bullet_scene = bullet_scene
	_player.damage_requested.connect(_on_player_damage_requested)
	_enemy_spawner.enemy_contacted_player.connect(_on_enemy_contacted_player)
	_enemy_spawner.enemy_destroyed.connect(_on_enemy_destroyed)
	_enemy_spawner.wave_cleared.connect(_on_wave_cleared)
	_game_over.retry_requested.connect(_on_game_over_retry_requested)
	_game_over.main_menu_requested.connect(return_to_main_menu)
	_main_menu.play_requested.connect(start_session)
	_main_menu.quit_requested.connect(_on_main_menu_quit_requested)
	_pause_menu.resume_requested.connect(resume_session)
	_pause_menu.main_menu_requested.connect(return_to_main_menu)
	child_entered_tree.connect(_on_child_entered_tree)
	_update_hud()
	_enter_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"pause"):
		return
	if _session_state == SessionState.PLAYING:
		pause_session()
	elif _session_state == SessionState.PAUSED:
		resume_session()
	else:
		return
	get_viewport().set_input_as_handled()


func start_session() -> void:
	if _session_state != SessionState.MAIN_MENU:
		return
	reset_session()


func pause_session() -> void:
	if _session_state != SessionState.PLAYING:
		return
	_session_state = SessionState.PAUSED
	_pause_menu.show_menu()
	get_tree().paused = true


func resume_session() -> void:
	if _session_state != SessionState.PAUSED:
		return
	get_tree().paused = false
	_pause_menu.visible = false
	_session_state = SessionState.PLAYING


func return_to_main_menu() -> void:
	_enter_main_menu()


func _enter_main_menu() -> void:
	get_tree().paused = false
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	_clear_combat_transients()
	_visual_feedback.clear_effects()
	lives = STARTING_LIVES
	score = 0
	wave = 1
	_session_active = false
	_mission_complete = false
	_wave_is_clean = true
	_session_state = SessionState.MAIN_MENU
	_game_over.visible = false
	_pause_menu.visible = false
	_hud.visible = false
	_player.set_gameplay_enabled(false)
	_player.visible = false
	_hide_mission_complete_message()
	_update_hud()
	_main_menu.show_menu()


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
	_visual_feedback.play_damage_flash()
	_wave_is_clean = false
	lives -= 1
	_hud.set_lives(lives)
	if lives > 0:
		_player.respawn(PLAYER_RESPAWN_POSITION)
		return
	_end_session()


func _on_enemy_destroyed(enemy: Area2D) -> void:
	if not _session_active:
		return
	var explosion_position: Vector2 = enemy.global_position
	_visual_feedback.play_enemy_explosion(explosion_position)
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
	_session_state = SessionState.GAME_OVER
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	_game_over.show_game_over(score)


func _complete_mission() -> void:
	_session_active = false
	_mission_complete = true
	_session_state = SessionState.MISSION_COMPLETE
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	_hud.show_mission_complete()


func is_mission_complete() -> bool:
	return _mission_complete


func is_session_active() -> bool:
	return _session_active


func reset_session() -> void:
	get_tree().paused = false
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	_clear_combat_transients()
	_visual_feedback.clear_effects()
	lives = STARTING_LIVES
	score = 0
	wave = 1
	_session_active = true
	_mission_complete = false
	_wave_is_clean = true
	_session_state = SessionState.PLAYING
	_main_menu.visible = false
	_game_over.visible = false
	_pause_menu.visible = false
	_hud.visible = true
	_player.set_gameplay_enabled(true)
	_player.respawn(PLAYER_RESPAWN_POSITION)
	_hide_mission_complete_message()
	_starfield.reset_scroll()
	_update_hud()
	_enemy_spawner.start_wave(0)


func _clear_combat_transients() -> void:
	for transient: Node in get_tree().get_nodes_in_group(&"combat_transients"):
		transient.queue_free()


func _hide_mission_complete_message() -> void:
	var mission_label: CanvasItem = _hud.get_node_or_null("MissionCompleteLabel") as CanvasItem
	if mission_label != null:
		mission_label.visible = false


func _update_hud() -> void:
	_hud.set_lives(lives)
	_hud.set_score(score)
	_hud.set_wave(wave)


func _on_game_over_retry_requested() -> void:
	reset_session()


func _on_main_menu_quit_requested() -> void:
	return_to_main_menu()
	get_tree().quit()
