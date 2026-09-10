# main.gd
# Coordinates the combat session, navigation states, visual and audio feedback,
# power-up drops, and wave-transition announcements.

extends Node2D

const STARTING_LIVES: int = 3
const POINTS_PER_ENEMY: int = 100
const CLEAN_WAVE_BONUS: int = 500
const TOTAL_WAVES: int = 5
const POWER_UP_SCENE: PackedScene = preload("res://scenes/powerups/power_up.tscn")
const HighScore: Script = preload("res://scripts/systems/high_score.gd")
const SHIELD_DURATION: float = 10.0
const NEARBY_SHAKE_RADIUS: float = 220.0

const _RADAR_PHRASES: Array[String] = [
	"SEÑAL HOSTIL DETECTADA",
	"FORMACIÓN ENTRANTE",
	"CONTACTO EN EL RADAR",
	"ENEMIGOS APROXIMÁNDOSE",
]

enum SessionState { MAIN_MENU, PLAYING, PAUSED, WAVE_TRANSITION, GAME_OVER, MISSION_COMPLETE }

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
@onready var _audio_feedback: Node = $AudioFeedback
@onready var _wave_announcement: CanvasLayer = $WaveAnnouncement
@onready var _camera: Camera2D = $Camera2D

## Current player lives, score, and 1-based wave number for this session.
var lives: int = STARTING_LIVES
var score: int = 0
var wave: int = 1

## Best score ever reached, loaded on startup and persisted to disk.
var _high_score: int = 0

## Probability of a power-up dropping when an enemy is destroyed.
@export_range(0.0, 1.0, 0.01) var enemy_drop_chance: float = 0.04

## Probability of a power-up dropping when a wave is cleared without any prior drop.
@export_range(0.0, 1.0, 0.01) var clear_wave_drop_chance: float = 0.50

var _session_state: SessionState = SessionState.MAIN_MENU
var _session_active: bool = false
var _mission_complete: bool = false
var _wave_is_clean: bool = true
var _power_up_dropped_this_wave: bool = false
var _pending_wave_index: int = 0
var _last_phrase_index: int = -1

var _game_layout: GameLayout = GameLayout.new()


func _ready() -> void:
	_player.bullet_scene = bullet_scene
	_player.damage_requested.connect(_on_player_damage_requested)
	if _player.has_signal(&"shot_fired"):
		_player.shot_fired.connect(_on_player_shot_fired)
	_enemy_spawner.enemy_contacted_player.connect(_on_enemy_contacted_player)
	_enemy_spawner.enemy_destroyed.connect(_on_enemy_destroyed)
	_enemy_spawner.wave_cleared.connect(_on_wave_cleared)
	_game_over.retry_requested.connect(_on_game_over_retry_requested)
	_game_over.main_menu_requested.connect(return_to_main_menu)
	_hud.retry_mission_requested.connect(_on_hud_retry_mission_requested)
	_hud.main_menu_requested.connect(return_to_main_menu)
	_main_menu.play_requested.connect(start_session)
	_main_menu.quit_requested.connect(_on_main_menu_quit_requested)
	_pause_menu.resume_requested.connect(resume_session)
	_pause_menu.main_menu_requested.connect(return_to_main_menu)
	_wave_announcement.announcement_finished.connect(_on_wave_announcement_finished)
	child_entered_tree.connect(_on_child_entered_tree)
	_high_score = HighScore.load_value()
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
	_audio_feedback.set_session_paused(true)
	get_tree().paused = true


func resume_session() -> void:
	if _session_state != SessionState.PAUSED:
		return
	get_tree().paused = false
	_pause_menu.visible = false
	_audio_feedback.set_session_paused(false)
	_session_state = SessionState.PLAYING


func return_to_main_menu() -> void:
	_enter_main_menu()


func _enter_main_menu() -> void:
	get_tree().paused = false
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	_clear_combat_transients()
	_visual_feedback.clear_effects()
	_wave_announcement.cancel_announcement()
	_pending_wave_index = 0
	_audio_feedback.stop_combat_music()
	_player.clear_power_ups()
	lives = STARTING_LIVES
	score = 0
	wave = 1
	_session_active = false
	_mission_complete = false
	_wave_is_clean = true
	_power_up_dropped_this_wave = false
	_session_state = SessionState.MAIN_MENU
	_game_over.visible = false
	_pause_menu.visible = false
	_hud.visible = false
	_player.set_gameplay_enabled(false)
	_player.visible = false
	_hide_mission_complete_message()
	_update_hud()
	_main_menu.set_high_score(_high_score)
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
	_camera.shake(6.0, 0.2)
	_audio_feedback.play_player_damage()
	_wave_is_clean = false
	lives -= 1
	_hud.set_lives(lives)
	if lives > 0:
		_player.respawn(_game_layout.get_player_spawn_position())
		return
	_end_session()


func _on_player_shot_fired(is_double_shot: bool) -> void:
	if _session_active:
		_audio_feedback.play_player_shot(is_double_shot)


func _on_enemy_destroyed(enemy: Area2D) -> void:
	if not _session_active:
		return
	var explosion_position: Vector2 = enemy.global_position
	_visual_feedback.play_enemy_explosion(explosion_position)
	_visual_feedback.play_score_popup(explosion_position, POINTS_PER_ENEMY)
	_audio_feedback.play_enemy_explosion()
	if explosion_position.distance_to(_player.global_position) < NEARBY_SHAKE_RADIUS:
		_camera.shake(3.0, 0.12)
	score += POINTS_PER_ENEMY
	_hud.set_score(score)
	_try_spawn_enemy_power_up(explosion_position)


func _try_spawn_enemy_power_up(spawn_position: Vector2) -> void:
	if _power_up_dropped_this_wave:
		return
	if randf() >= enemy_drop_chance:
		return
	_spawn_power_up(spawn_position)


func _spawn_power_up(spawn_position: Vector2) -> void:
	var power_up: Area2D = POWER_UP_SCENE.instantiate() as Area2D
	if power_up == null:
		return
	var power_up_type: int = randi() % 2
	power_up.configure(power_up_type, spawn_position)
	if power_up.has_signal(&"collected"):
		power_up.collected.connect(_on_power_up_collected)
	add_child(power_up)
	_power_up_dropped_this_wave = true


func _on_power_up_collected(power_up_type: int) -> void:
	if not _session_active:
		return
	match power_up_type:
		0: # PowerUp.Type.DOUBLE_SHOT
			_player.enable_double_shot()
		1: # PowerUp.Type.SHIELD
			_player.activate_shield(SHIELD_DURATION)
	_audio_feedback.play_power_up_collected(power_up_type)


func _on_wave_cleared(_wave_index: int) -> void:
	if not _session_active:
		return
	if _wave_is_clean:
		score += CLEAN_WAVE_BONUS
		_hud.set_score(score)
		_visual_feedback.play_score_popup(_player.global_position + Vector2(0, -50), CLEAN_WAVE_BONUS, true)
	if wave >= TOTAL_WAVES:
		_complete_mission()
		return
	# Clear-wave fallback drop: if no power-up dropped this wave, try once more.
	if not _power_up_dropped_this_wave and randf() < clear_wave_drop_chance:
		_spawn_power_up(_game_layout.get_power_up_fallback_position())
	# Enter wave transition instead of starting the next wave immediately.
	_session_state = SessionState.WAVE_TRANSITION
	_enemy_spawner.stop()
	_pending_wave_index = wave
	var phrase: String = _pick_radar_phrase()
	_wave_announcement.show_announcement(wave + 1, phrase)


func _on_wave_announcement_finished() -> void:
	if _session_state != SessionState.WAVE_TRANSITION or not _session_active:
		return
	wave = _pending_wave_index + 1
	_wave_is_clean = true
	_power_up_dropped_this_wave = false
	_hud.set_wave(wave)
	_update_hud()
	_enemy_spawner.start_wave(_pending_wave_index)
	_session_state = SessionState.PLAYING


func _pick_radar_phrase() -> String:
	var index: int = randi() % _RADAR_PHRASES.size()
	if index == _last_phrase_index and _RADAR_PHRASES.size() > 1:
		index = (index + 1) % _RADAR_PHRASES.size()
	_last_phrase_index = index
	return _RADAR_PHRASES[index]


func _end_session() -> void:
	if not _session_active:
		return
	_session_active = false
	_session_state = SessionState.GAME_OVER
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	_wave_announcement.cancel_announcement()
	_audio_feedback.stop_combat_music()
	_update_high_score_if_needed()
	_game_over.show_game_over(score)


func _complete_mission() -> void:
	_session_active = false
	_mission_complete = true
	_session_state = SessionState.MISSION_COMPLETE
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	_wave_announcement.cancel_announcement()
	_audio_feedback.stop_combat_music()
	_update_high_score_if_needed()
	_hud.show_mission_complete(score)


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
	_wave_announcement.cancel_announcement()
	_pending_wave_index = 0
	_audio_feedback.stop_combat_music()
	_player.clear_power_ups()
	lives = STARTING_LIVES
	score = 0
	wave = 1
	_session_active = true
	_mission_complete = false
	_wave_is_clean = true
	_power_up_dropped_this_wave = false
	_session_state = SessionState.PLAYING
	_main_menu.visible = false
	_game_over.visible = false
	_pause_menu.visible = false
	_hud.visible = true
	_configure_game_layout()
	_player.set_gameplay_enabled(true)
	_player.respawn(_game_layout.get_player_spawn_position())
	_hide_mission_complete_message()
	_starfield.reset_scroll()
	_update_hud()
	_audio_feedback.start_combat_music()
	_enemy_spawner.start_wave(0)


func _configure_game_layout() -> void:
	_game_layout.configure(get_viewport().get_visible_rect().size)
	_player.set_horizontal_limits(_game_layout.get_player_horizontal_limits())
	var formation_origin: Vector2 = _game_layout.get_enemy_formation_origin()
	_enemy_spawner.set_formation_layout(formation_origin, formation_origin.y)


func _clear_combat_transients() -> void:
	for transient: Node in get_tree().get_nodes_in_group(&"combat_transients"):
		transient.queue_free()


func _hide_mission_complete_message() -> void:
	_hud.hide_mission_complete()


func _update_hud() -> void:
	_hud.set_lives(lives)
	_hud.set_score(score)
	_hud.set_wave(wave)


func _update_high_score_if_needed() -> void:
	if score > _high_score:
		_high_score = score
		HighScore.save_value(_high_score)


func _on_game_over_retry_requested() -> void:
	reset_session()


func _on_hud_retry_mission_requested() -> void:
	reset_session()


func _on_main_menu_quit_requested() -> void:
	return_to_main_menu()
	get_tree().quit()
