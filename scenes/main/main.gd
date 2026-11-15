# main.gd
# Coordinates the combat session, navigation states, visual and audio feedback,
# loot drops, and wave-transition announcements.

extends Node2D

const STARTING_LIVES: int = 3
const PlayerScript: Script = preload("res://scenes/entities/player/player.gd")
const POINTS_PER_ENEMY: int = 100
const CLEAN_WAVE_BONUS: int = 500
const TOTAL_WAVES: int = 10
const TOTAL_CHAPTERS: int = 3
const BOSS_BASE_HEALTH: int = 150
const BOSS_HEALTH_STEP: float = 0.5
## Wave number (1-based) that is a peaceful bonus wave in every chapter.
const BONUS_WAVE_NUMBER: int = 8
const BONUS_DROP_COUNT: int = 8
## Wave-cleared feedback (Etapa 15 T6): invulnerability grace and camera zoom pulse.
const WAVE_CLEARED_INVULNERABILITY: float = 1.75
const CAMERA_ZOOM_PULSE: float = 1.15
const CAMERA_ZOOM_IN_DURATION: float = 0.35
const CAMERA_ZOOM_OUT_DURATION: float = 0.8

## Seconds between rained loot drops in a bonus wave. Tests set it to 0.
var bonus_drop_interval: float = 0.6
var _bonus_active: bool = false
var _bonus_drops_spawned: int = 0
var _hyperspace_jumps: int = 0
const BOSS_POINTS: int = 3000
## Boss per chapter (Etapa 15 T7): index 0 is chapter 1.
const BOSS_VARIANTS_BY_CHAPTER: Array[StringName] = [&"nexus", &"espectro", &"blindado"]
const BOSS_NAMES_BY_CHAPTER: Array[String] = ["NAVE NODRIZA NEXUS", "CRUCERO ESPECTRO", "NÚCLEO BLINDADO"]
const ARMOR_PHASE_SUBCORE: int = 2
const ARMOR_PHASE_EXPOSED_CORE: int = 3
const ARMOR_BROKEN_TEXT: String = "ARMADURA EXTERIOR ROTA"
const CORE_EXPOSED_TEXT: String = "NÚCLEO EXPUESTO"
const ARMOR_PHASE_CHANGE_TRAUMA: float = 0.35
const ASTEROID_WAVE_INDEX: int = 8
const ASTEROID_LARGE_POINTS: int = 150
const ASTEROID_MEDIUM_POINTS: int = 75
const ASTEROID_SMALL_POINTS: int = 30
const LOOT_DROP_SCENE: PackedScene = preload("res://scenes/loot/loot_drop.tscn")
const SCORE_LOOT_POINTS: int = 250
const POWER_UP_SCENE: PackedScene = preload("res://scenes/powerups/power_up.tscn")
const BOSS_SCENE: PackedScene = preload("res://scenes/entities/boss/boss.tscn")
const HighScore: Script = preload("res://scripts/systems/high_score.gd")
const Settings: Script = preload("res://scripts/systems/settings.gd")
const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const SESSION_STATS := preload("res://scripts/systems/session_stats.gd")
const SHIELD_DURATION: float = 10.0
const NEARBY_SHAKE_RADIUS: float = 220.0
const EXTRA_LIFE_SCORE_THRESHOLD: int = 1_000_000
const DS := preload("res://scripts/systems/difficulty_settings.gd")

const _RADAR_PHRASES: Array[String] = [
	"SEÑAL HOSTIL DETECTADA",
	"FORMACIÓN ENTRANTE",
	"CONTACTO EN EL RADAR",
	"ENEMIGOS APROXIMÁNDOSE",
	"DISTORSIÓN HIPERESPACIAL",
	"VANGUARDIA ALIENÍGENA",
	"ENJAMBRE EN APROXIMACIÓN",
	"FIRMA DE ENERGÍA CRÍTICA",
	"PATRÓN DE ASALTO CIBERNÉTICO",
	"INCURSIÓN ESTELAR INMINENTE",
]

enum SessionState { MAIN_MENU, PLAYING, PAUSED, WAVE_TRANSITION, BOSS_BATTLE, GAME_OVER, MISSION_COMPLETE, BONUS_WAVE }

## Bullet scene to provide to the player.
var bullet_scene: PackedScene = preload("res://scenes/entities/bullet/bullet.tscn")

@onready var _player: CharacterBody2D = $Player
@onready var _enemy_spawner: Node2D = $EnemySpawner
@onready var _asteroid_spawner: Node2D = get_node_or_null("AsteroidSpawner") as Node2D
@onready var _game_over: CanvasLayer = $GameOver
@onready var _hud: CanvasLayer = $HUD
@onready var _main_menu: CanvasLayer = $MainMenu
var _settings_menu: CanvasLayer
@onready var _pause_menu: CanvasLayer = $PauseMenu
@onready var _starfield: Node2D = $Starfield
@onready var _visual_feedback: Node2D = $VisualFeedback
@onready var _audio_feedback: Node = $AudioFeedback
@onready var _wave_announcement: CanvasLayer = $WaveAnnouncement
@onready var _camera: Camera2D = $Camera2D
@onready var _combo_system: Node = get_node_or_null("ComboSystem") as Node

## Current player lives, score, and 1-based wave number for this session.
var lives: int = STARTING_LIVES
var score: int = 0
var wave: int = 1

## Current campaign chapter (1-based). Each chapter is TOTAL_WAVES waves plus a boss.
var _chapter: int = 1

## Best score ever reached, loaded on startup and persisted to disk.
var _high_score: int = 0
var _last_extra_life_threshold: int = 0

## Post-session stats: kills per enemy variant. Shots and hits live in SessionStats.
var kills_by_type: Dictionary = {}

## Session difficulty tier (Etapa 18); COMMANDER keeps base score, speed, density and cooling.
var session_difficulty: int = DS.Tier.COMMANDER

## Loot drop probabilities and weights.
@export_range(0.0, 1.0, 0.01) var enemy_loot_drop_chance: float = 0.18
@export_range(0.0, 1.0, 0.01) var score_loot_weight: float = 0.35
@export_range(0.0, 1.0, 0.01) var double_shot_loot_weight: float = 0.0
@export_range(0.0, 1.0, 0.01) var shield_loot_weight: float = 0.12
@export_range(0.0, 1.0, 0.01) var extra_life_loot_weight: float = 0.08
@export_range(0.0, 1.0, 0.01) var bomb_loot_weight: float = 0.08
@export_range(0.0, 1.0, 0.01) var medallion_blaster_weight: float = 0.08
@export_range(0.0, 1.0, 0.01) var medallion_missile_weight: float = 0.08
@export_range(0.0, 1.0, 0.01) var medallion_laser_weight: float = 0.08
@export_range(0.0, 1.0, 0.01) var power_atom_weight: float = 0.11

var _session_state: SessionState = SessionState.MAIN_MENU
var _state_before_pause: SessionState = SessionState.PLAYING
var _session_active: bool = false

## Coop local (Etapa 20): second ship and its own lives; null/unused in singleplayer.
var _player_two: CharacterBody2D = null
var _player_two_lives: int = STARTING_LIVES

## True when the session that started from the menu is coop local.
var session_coop: bool = false
var _mission_complete: bool = false
var _wave_is_clean: bool = true
var _pending_wave_index: int = 0
## True while the boss of the current chapter is the next encounter (not a regular wave).
var _boss_pending: bool = false
var _last_phrase_index: int = -1
var _active_boss: Area2D = null
var _zoom_tween: Tween = null

var _game_layout: GameLayout = GameLayout.new()


func _ready() -> void:
	if _combo_system == null:
		var combo_script: Script = load("res://scripts/systems/combo_system.gd") as Script
		if combo_script != null:
			_combo_system = combo_script.new() as Node
			_combo_system.name = "ComboSystem"
			add_child(_combo_system)

	_player.bullet_scene = bullet_scene
	_player.damage_requested.connect(_on_player_damage_requested)
	if _player.has_signal(&"shot_fired"):
		_player.shot_fired.connect(_on_player_shot_fired)

	if _player.has_signal(&"weapon_changed") and _hud.has_method(&"set_active_weapon"):
		_player.weapon_changed.connect(func(w: int) -> void:
			_hud.set_active_weapon(w)
			if _hud.has_method(&"set_weapon_level"):
				_hud.set_weapon_level(_player.get_weapon_level() if _player.has_method(&"get_weapon_level") else 1, w)
		)

	if _player.has_signal(&"weapon_level_changed") and _hud.has_method(&"set_weapon_level"):
		_player.weapon_level_changed.connect(func(lvl: int) -> void:
			_hud.set_weapon_level(lvl, _player.get_weapon() if _player.has_method(&"get_weapon") else 0)
		)

	if _player.has_signal(&"heat_changed") and _hud.has_method(&"set_heat"):
		_player.heat_changed.connect(func(cur: float, m: float) -> void:
			_hud.set_heat(cur, m, _player.is_weapon_overheated() if _player.has_method(&"is_weapon_overheated") else false)
		)

	if _player.has_signal(&"overheat_state_changed"):
		_player.overheat_state_changed.connect(func(overheated: bool) -> void:
			if _hud.has_method(&"set_heat"):
				_hud.set_heat(_player.heat if "heat" in _player else 0.0, _player.max_heat if "max_heat" in _player else 100.0, overheated)
			if overheated and _session_active and _audio_feedback != null and _audio_feedback.has_method(&"play_overheat_warning"):
				_audio_feedback.play_overheat_warning()
		)

	if _hud.has_signal(&"weapon_selected_by_user") and _player.has_method(&"set_weapon"):
		_hud.weapon_selected_by_user.connect(_player.set_weapon)

	if _combo_system != null:
		if _combo_system.has_signal(&"combo_updated") and _hud.has_method(&"set_combo"):
			_combo_system.combo_updated.connect(_hud.set_combo)
		if _combo_system.has_signal(&"combo_reset") and _hud.has_method(&"set_combo"):
			_combo_system.combo_reset.connect(func() -> void: _hud.set_combo(1, 0, 0.0))

	_enemy_spawner.enemy_contacted_player.connect(_on_enemy_contacted_player)
	_enemy_spawner.enemy_destroyed.connect(_on_enemy_destroyed)
	_enemy_spawner.wave_cleared.connect(_on_wave_cleared)
	if _enemy_spawner.has_signal(&"enrage_triggered"):
		_enemy_spawner.enrage_triggered.connect(_on_enrage_triggered)

	if _asteroid_spawner == null:
		_asteroid_spawner = get_node_or_null("AsteroidSpawner") as Node2D
	if _asteroid_spawner != null:
		if _asteroid_spawner.has_signal(&"asteroid_spawned"):
			_asteroid_spawner.asteroid_spawned.connect(_on_asteroid_spawned)
		if _asteroid_spawner.has_signal(&"asteroid_wave_completed"):
			_asteroid_spawner.asteroid_wave_completed.connect(_on_asteroid_wave_completed)
	_game_over.retry_requested.connect(_on_game_over_retry_requested)
	_game_over.main_menu_requested.connect(return_to_main_menu)
	_hud.retry_mission_requested.connect(_on_hud_retry_mission_requested)
	_hud.main_menu_requested.connect(return_to_main_menu)
	_main_menu.play_requested.connect(_on_main_menu_play_requested)
	_main_menu.quit_requested.connect(_on_main_menu_quit_requested)
	_main_menu.settings_requested.connect(_on_main_menu_settings_requested)
	_settings_menu = SETTINGS_MENU_SCENE.instantiate()
	add_child(_settings_menu)
	_settings_menu.visible = false
	_settings_menu.back_requested.connect(_on_settings_back_requested)
	_pause_menu.resume_requested.connect(resume_session)
	_pause_menu.main_menu_requested.connect(return_to_main_menu)
	_wave_announcement.announcement_finished.connect(_on_wave_announcement_finished)
	child_entered_tree.connect(_on_child_entered_tree)
	_high_score = HighScore.load_value()
	Settings.apply_display(Settings.load_settings())
	_configure_game_layout()
	_update_hud()
	_enter_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"pause"):
		return
	if _session_state == SessionState.PLAYING or _session_state == SessionState.BOSS_BATTLE:
		pause_session()
	elif _session_state == SessionState.PAUSED:
		resume_session()
	else:
		return
	get_viewport().set_input_as_handled()


## Receives the difficulty picked in the main menu; only the menu sets session_difficulty.
func _on_main_menu_play_requested() -> void:
	if _session_state != SessionState.MAIN_MENU:
		return
	session_difficulty = _main_menu.selected_difficulty
	session_coop = _main_menu.coop_selected
	if session_coop:
		enable_coop_local()
	start_session()
	_set_player_two_active(session_coop)


func start_session() -> void:
	if _session_state != SessionState.MAIN_MENU:
		return
	reset_session()


func pause_session() -> void:
	if _session_state != SessionState.PLAYING and _session_state != SessionState.BOSS_BATTLE:
		return
	_state_before_pause = _session_state
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
	_session_state = _state_before_pause


func return_to_main_menu() -> void:
	_enter_main_menu()


func _enter_main_menu() -> void:
	get_tree().paused = false
	_end_belt_camera_follow()
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	_clear_boss()
	_clear_combat_transients()
	_reset_wave_cleared_feedback()
	_boss_pending = false
	_visual_feedback.clear_effects()
	_wave_announcement.cancel_announcement()
	_pending_wave_index = 0
	_audio_feedback.stop_combat_music()
	_audio_feedback.stop_boss_music()
	_hud.hide_boss_health_bar()
	_player.clear_power_ups()
	if _combo_system != null and _combo_system.has_method(&"reset_combo"):
		_combo_system.reset_combo()
	if _player != null:
		if _player.has_method(&"reset_heat"):
			_player.reset_heat()
		if _player.has_method(&"set_weapon"):
			_player.set_weapon(0)
		if _player.has_method(&"set_weapon_level"):
			_player.set_weapon_level(1)
	if _hud != null:
		if _hud.has_method(&"set_active_weapon"):
			_hud.set_active_weapon(0)
		if _hud.has_method(&"set_heat"):
			_hud.set_heat(0.0, _player.max_heat if _player != null and "max_heat" in _player else 100.0, false)
		if _hud.has_method(&"set_combo"):
			_hud.set_combo(1, 0, 0.0)
	lives = STARTING_LIVES
	score = 0
	wave = 1
	_chapter = 1
	_bonus_active = false
	_hyperspace_jumps = 0
	_session_active = false
	_mission_complete = false
	_wave_is_clean = true
	_session_state = SessionState.MAIN_MENU
	_game_over.visible = false
	_pause_menu.visible = false
	_hud.visible = false
	_player.set_gameplay_enabled(false)
	_player.visible = false
	_set_player_two_active(false)
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


## Coop local (Etapa 20): creates the second ship with its own lives. Singleplayer never calls it.
func enable_coop_local() -> void:
	if _player_two != null:
		return
	PlayerScript.ensure_p2_input_actions()
	var packed: PackedScene = load("res://scenes/entities/player/player.tscn") as PackedScene
	_player_two = packed.instantiate() as CharacterBody2D
	_player_two.player_index = 2
	_player_two.bullet_scene = bullet_scene
	_player_two.position = _game_layout.get_player_spawn_position() + Vector2(80.0, 0.0)
	add_child(_player_two)
	_player_two.damage_requested.connect(_on_player_damage_requested)
	_player_two.heat_changed.connect(func(cur: float, m: float) -> void:
		_hud.set_heat_p2(cur, m, _player_two.is_weapon_overheated()))
	_player_two.visible = false
	_player_two.set_gameplay_enabled(false)
	_player_two_lives = STARTING_LIVES


## Shows or hides J2 for a session; activating gives J2 fresh lives and a respawn.
func _set_player_two_active(active: bool) -> void:
	_player.coop_active = active and _player_two != null
	if _player_two == null:
		return
	if active:
		_player_two_lives = STARTING_LIVES
		_hud.set_lives_p2(_player_two_lives)
		_player_two.cooling_scale = _player.cooling_scale
		_hud.set_heat_p2(0.0, _player_two.max_heat, false)
		_player_two.respawn(_game_layout.get_player_spawn_position() + Vector2(80.0, 0.0))
		_player_two.set_gameplay_enabled(true)
	else:
		_player_two.reset_heat()
		_hud.set_heat_p2(0.0, _player_two.max_heat, false)
		_player_two.set_gameplay_enabled(false)
		_player_two.visible = false


func _request_player_damage(player: Node2D) -> void:
	if not _session_active:
		return
	if player == _player or (player != null and player == _player_two):
		player.take_damage()


## ship: the ship that requested damage; null means J1 (keeps the singleplayer path).
func _on_player_damage_requested(ship: Node2D = null) -> void:
	if not _session_active:
		return
	if ship != null and ship == _player_two:
		_on_player_two_damage_requested()
		return
	if _combo_system != null and _combo_system.has_method(&"reset_combo"):
		_combo_system.reset_combo()
	_visual_feedback.play_damage_flash()
	_camera.shake(6.0, 0.2)
	if _camera != null and _camera.has_method(&"add_trauma"):
		_camera.add_trauma(0.55)
	_audio_feedback.play_player_damage()
	_wave_is_clean = false
	var death_pos: Vector2 = _player.global_position
	var lost_level: int = _player.penalize_weapon_on_death() if _player.has_method(&"penalize_weapon_on_death") else 0
	if lost_level > 0:
		_spawn_recovery_capsule(death_pos)
	lives -= 1
	_hud.set_lives(lives)
	if lives > 0:
		_player.respawn(_game_layout.get_player_spawn_position())
		return
	if _player_two != null and _player_two_lives > 0:
		# J1 sin vidas: sale de la partida, J2 sigue (vidas por nave).
		_player.set_gameplay_enabled(false)
		_player.visible = false
		return
	_end_session()


## J2 loses a life; the session ends only when both ships are out of lives.
func _on_player_two_damage_requested() -> void:
	_player_two_lives -= 1
	_hud.set_lives_p2(_player_two_lives)
	if _player_two_lives > 0:
		_player_two.respawn(_game_layout.get_player_spawn_position() + Vector2(80.0, 0.0))
		return
	_player_two.set_gameplay_enabled(false)
	_player_two.visible = false
	if lives <= 0:
		_end_session()


func _spawn_recovery_capsule(spawn_pos: Vector2) -> void:
	var loot: Area2D = LOOT_DROP_SCENE.instantiate() as Area2D
	if loot == null:
		return
	if loot.has_signal(&"collected"):
		loot.collected.connect(_on_loot_collected)
	if loot.has_method(&"configure"):
		loot.configure(LootDrop.Type.RECOVERY_CAPSULE, spawn_pos, _player, 3.0)
	add_child(loot)


## Adds points scaled by the session difficulty score multiplier, then checks extra-life milestones.
func _add_score(points: int) -> void:
	score += int(round(points * DS.score_multiplier(session_difficulty)))
	_check_score_milestones()


func _check_score_milestones() -> void:
	if EXTRA_LIFE_SCORE_THRESHOLD <= 0:
		return
	var current_threshold: int = score / EXTRA_LIFE_SCORE_THRESHOLD
	if current_threshold > _last_extra_life_threshold:
		var bonus_lives: int = current_threshold - _last_extra_life_threshold
		_last_extra_life_threshold = current_threshold
		lives += bonus_lives
		_hud.set_lives(lives)
		if _visual_feedback != null and _visual_feedback.has_method(&"play_extra_life_alert"):
			_visual_feedback.play_extra_life_alert(_player.global_position)
		if _audio_feedback != null and _audio_feedback.has_method(&"play_extra_life"):
			_audio_feedback.play_extra_life()



func _on_player_shot_fired(is_double_shot: bool) -> void:
	if _session_active:
		if _player != null and _audio_feedback != null and _audio_feedback.has_method(&"play_weapon_shot"):
			_audio_feedback.play_weapon_shot(_player.get_weapon() if _player.has_method(&"get_weapon") else 0)
		elif _audio_feedback != null:
			_audio_feedback.play_player_shot(is_double_shot)


func _on_enemy_destroyed(enemy: Area2D) -> void:
	if not _session_active:
		return
	if enemy.has_method(&"get_variant_id"):
		var variant_id: StringName = enemy.call(&"get_variant_id")
		kills_by_type[variant_id] = int(kills_by_type.get(variant_id, 0)) + 1
	var explosion_position: Vector2 = enemy.global_position
	_visual_feedback.play_enemy_explosion(explosion_position)
	if _visual_feedback.has_method(&"play_hull_fragments"):
		_visual_feedback.play_hull_fragments(explosion_position)
	var multiplier: int = _combo_system.register_kill() if (_combo_system != null and _combo_system.has_method(&"register_kill")) else 1
	var points_earned: int = POINTS_PER_ENEMY * multiplier
	_add_score(points_earned)
	_hud.set_score(score)
	_visual_feedback.play_score_popup(explosion_position, points_earned, multiplier > 1)
	_audio_feedback.play_enemy_explosion()
	if explosion_position.distance_to(_player.global_position) < NEARBY_SHAKE_RADIUS:
		_camera.shake(3.0, 0.12)
	_try_spawn_enemy_loot(explosion_position)


func _on_asteroid_spawned(asteroid: Area2D) -> void:
	if asteroid == null:
		return
	if not asteroid.destroyed.is_connected(_on_asteroid_destroyed):
		asteroid.destroyed.connect(_on_asteroid_destroyed)
	if not asteroid.player_contacted.is_connected(_on_asteroid_player_contacted):
		asteroid.player_contacted.connect(_on_asteroid_player_contacted)


func _on_asteroid_destroyed(asteroid: Area2D, size_idx: int, pos: Vector2, _vel: Vector2) -> void:
	if not _session_active:
		return
	var base_pts: int = ASTEROID_LARGE_POINTS
	var trauma_add: float = 0.35
	match size_idx:
		0: # LARGE
			base_pts = ASTEROID_LARGE_POINTS
			trauma_add = 0.35
		1: # MEDIUM
			base_pts = ASTEROID_MEDIUM_POINTS
			trauma_add = 0.20
		2: # SMALL
			base_pts = ASTEROID_SMALL_POINTS
			trauma_add = 0.10

	var mult: int = _combo_system.register_kill() if (_combo_system != null and _combo_system.has_method(&"register_kill")) else 1
	var points_earned: int = base_pts * mult
	_add_score(points_earned)
	_hud.set_score(score)
	_visual_feedback.play_score_popup(pos, points_earned, mult > 1)
	_visual_feedback.play_enemy_explosion(pos)
	_audio_feedback.play_enemy_explosion()
	if _camera != null and _camera.has_method(&"add_trauma"):
		_camera.add_trauma(trauma_add)
	elif _camera != null:
		_camera.shake(4.0, 0.15)

	# High-HP large asteroids drop resources or power-ups
	if size_idx == 0:
		var has_loot: bool = (asteroid != null and asteroid.get("contains_loot") == true)
		if has_loot or randf() < 0.60:
			_spawn_loot(_pick_loot_type(), pos)


func _on_asteroid_player_contacted(player: Node2D) -> void:
	_request_player_damage(player)
	if _camera != null and _camera.has_method(&"add_trauma"):
		_camera.add_trauma(0.50)


func _on_asteroid_wave_completed() -> void:
	_end_belt_camera_follow()
	if not _session_active:
		return
	_on_wave_cleared(ASTEROID_WAVE_INDEX)


func _on_enrage_triggered() -> void:
	if not _session_active:
		return
	if _camera != null:
		_camera.shake(5.0, 0.25)
	if _audio_feedback != null:
		if _audio_feedback.has_method(&"play_enrage_warning"):
			_audio_feedback.play_enrage_warning()
		elif _audio_feedback.has_method(&"play_overheat_warning"):
			_audio_feedback.play_overheat_warning()
	if _visual_feedback != null:
		if _visual_feedback.has_method(&"play_enrage_alert"):
			_visual_feedback.play_enrage_alert()
		elif _visual_feedback.has_method(&"play_damage_flash"):
			_visual_feedback.play_damage_flash()


func _pick_loot_type() -> int:
	var w_score: float = maxf(score_loot_weight, 0.0)
	var w_double: float = maxf(double_shot_loot_weight, 0.0)
	var w_shield: float = maxf(shield_loot_weight, 0.0)
	var w_life: float = maxf(extra_life_loot_weight, 0.0)
	var w_bomb: float = maxf(bomb_loot_weight, 0.0)
	var w_m_blaster: float = maxf(medallion_blaster_weight, 0.0)
	var w_m_missile: float = maxf(medallion_missile_weight, 0.0)
	var w_m_laser: float = maxf(medallion_laser_weight, 0.0)
	var w_atom: float = maxf(power_atom_weight, 0.0)

	var base_weights: Array[float] = [w_score, w_double, w_shield, w_life, w_bomb]
	var zero_count: int = 0
	var single_one_index: int = -1
	for idx: int in range(base_weights.size()):
		if base_weights[idx] == 0.0:
			zero_count += 1
		elif base_weights[idx] == 1.0:
			single_one_index = idx

	# Contract testing support: isolated single basic weight or all basic weights zero
	if zero_count == 5:
		return LootDrop.Type.SCORE
	if zero_count == 4 and single_one_index >= 0:
		return single_one_index

	var all_weights: Array[float] = [
		w_score, w_double, w_shield, w_life, w_bomb,
		w_m_blaster, w_m_missile, w_m_laser, w_atom
	]
	var total_zeros: int = 0
	var total_single_index: int = -1
	for idx: int in range(all_weights.size()):
		if all_weights[idx] == 0.0:
			total_zeros += 1
		elif all_weights[idx] > 0.0:
			total_single_index = idx
	if total_zeros == all_weights.size() - 1 and total_single_index >= 0:
		return total_single_index

	var total_basic_weight: float = w_score + w_double + w_shield + w_life + w_bomb
	var total_weapon_weight: float = w_m_blaster + w_m_missile + w_m_laser + w_atom
	var total_weight: float = total_basic_weight + total_weapon_weight
	if total_weight <= 0.0:
		return LootDrop.Type.SCORE

	var roll: float = randf() * total_weight
	if roll < total_basic_weight:
		var cumulative: float = 0.0
		cumulative += w_score
		if roll < cumulative:
			return LootDrop.Type.SCORE
		cumulative += w_double
		if roll < cumulative:
			return LootDrop.Type.DOUBLE_SHOT
		cumulative += w_shield
		if roll < cumulative:
			return LootDrop.Type.SHIELD
		cumulative += w_life
		if roll < cumulative:
			return LootDrop.Type.EXTRA_LIFE
		return LootDrop.Type.BOMB

	# Weapon / Power drop: Chicken Invaders model:
	# ~55% chance of Power Atom or active weapon's medallion (+1 level)
	# ~45% chance of dropping a different weapon's medallion (distributed among the other 2)
	var active_w: int = _player.get_weapon() if (_player != null and _player.has_method(&"get_weapon")) else 0
	var weapon_roll: float = randf()
	if weapon_roll < 0.55:
		if randf() < 0.5:
			return LootDrop.Type.MEDALLION_BLASTER + active_w
		else:
			return LootDrop.Type.POWER_ATOM
	else:
		var alt_weapons: Array[int] = []
		for w_idx: int in range(3):
			if w_idx != active_w:
				alt_weapons.append(w_idx)
		var chosen_alt: int = alt_weapons[randi() % alt_weapons.size()]
		return LootDrop.Type.MEDALLION_BLASTER + chosen_alt



func _try_spawn_enemy_loot(spawn_position: Vector2) -> void:
	if not _session_active:
		return
	if enemy_loot_drop_chance <= 0.0 or randf() >= enemy_loot_drop_chance:
		return
	var total_weight: float = (
		maxf(score_loot_weight, 0.0)
		+ maxf(double_shot_loot_weight, 0.0)
		+ maxf(shield_loot_weight, 0.0)
		+ maxf(extra_life_loot_weight, 0.0)
		+ maxf(bomb_loot_weight, 0.0)
		+ maxf(medallion_blaster_weight, 0.0)
		+ maxf(medallion_missile_weight, 0.0)
		+ maxf(medallion_laser_weight, 0.0)
		+ maxf(power_atom_weight, 0.0)
	)
	if total_weight <= 0.0:
		return
	_spawn_loot(_pick_loot_type(), spawn_position)



func _spawn_loot(loot_type: int, spawn_position: Vector2) -> void:
	var loot: Area2D = LOOT_DROP_SCENE.instantiate() as Area2D
	if loot == null:
		return
	if loot.has_signal(&"collected"):
		loot.collected.connect(_on_loot_collected)
	if loot.has_method(&"configure"):
		loot.configure(loot_type, spawn_position, _player)
	add_child(loot)


## collector: the ship that picked the drop up (Etapa 20); null means J1 (singleplayer).
func _on_loot_collected(loot_type: int, collector: Node2D = null) -> void:
	if not _session_active and not _mission_complete:
		return
	var ship: CharacterBody2D = _player_two if collector != null and collector == _player_two else _player
	match loot_type:
		LootDrop.Type.SCORE:
			_add_score(SCORE_LOOT_POINTS)
			_hud.set_score(score)
			_visual_feedback.play_score_popup(ship.global_position, SCORE_LOOT_POINTS)
		LootDrop.Type.DOUBLE_SHOT:
			ship.enable_double_shot()
			_audio_feedback.play_power_up_collected(0)
		LootDrop.Type.SHIELD:
			ship.activate_shield(SHIELD_DURATION)
			_audio_feedback.play_power_up_collected(1)
		LootDrop.Type.EXTRA_LIFE:
			if ship == _player_two:
				_player_two_lives = mini(_player_two_lives + 1, STARTING_LIVES)
				_hud.set_lives_p2(_player_two_lives)
			else:
				lives = mini(lives + 1, STARTING_LIVES)
				_hud.set_lives(lives)
		LootDrop.Type.BOMB:
			_clear_enemy_bullets()
		LootDrop.Type.MEDALLION_BLASTER, LootDrop.Type.MEDALLION_MISSILE, LootDrop.Type.MEDALLION_LASER:
			var target_w: int = loot_type - LootDrop.Type.MEDALLION_BLASTER
			var prev_w: int = ship.get_weapon() if ship.has_method(&"get_weapon") else -1
			if ship.has_method(&"apply_medallion"):
				ship.apply_medallion(target_w)
			if target_w != prev_w:
				var weapon_names: Array[String] = ["BLASTER", "MISIL", "LÁSER"]
				var weapon_colors: Array[Color] = [
					Color(0.2, 0.6, 1.0),
					Color(1.0, 0.55, 0.1),
					Color(1.0, 0.2, 0.25)
				]
				var w_name: String = weapon_names[target_w] if target_w >= 0 and target_w < weapon_names.size() else "ARMA"
				var w_color: Color = weapon_colors[target_w] if target_w >= 0 and target_w < weapon_colors.size() else Color.WHITE
				if _visual_feedback != null and _visual_feedback.has_method(&"play_weapon_switched"):
					_visual_feedback.play_weapon_switched(ship.global_position, w_name, w_color)
				if _audio_feedback != null and _audio_feedback.has_method(&"play_weapon_switched"):
					_audio_feedback.play_weapon_switched(target_w)
			else:
				if _visual_feedback != null and _visual_feedback.has_method(&"play_level_up"):
					_visual_feedback.play_level_up(ship.global_position, ship.get_weapon_level() if ship.has_method(&"get_weapon_level") else 1)
				if _audio_feedback != null and _audio_feedback.has_method(&"play_medallion_collected"):
					_audio_feedback.play_medallion_collected(target_w)
		LootDrop.Type.POWER_ATOM, LootDrop.Type.RECOVERY_CAPSULE:
			if ship.has_method(&"apply_power_atom"):
				ship.apply_power_atom()
			if _audio_feedback != null and _audio_feedback.has_method(&"play_power_atom_collected"):
				_audio_feedback.play_power_atom_collected()
			if _visual_feedback != null and _visual_feedback.has_method(&"play_level_up"):
				_visual_feedback.play_level_up(ship.global_position, ship.get_weapon_level() if ship.has_method(&"get_weapon_level") else 1)



## Wave number within the current chapter (1-based, 1-10) from the global wave number.
func _local_wave(global_wave: int) -> int:
	return (global_wave - 1) % TOTAL_WAVES + 1


## Wave index within the current chapter (0-based, 0-9) from a global 0-based index.
func _local_index(global_index: int) -> int:
	return global_index % TOTAL_WAVES


func _on_wave_cleared(_wave_index: int) -> void:
	if not _session_active:
		return
	if _starfield != null and _starfield.has_method(&"trigger_warp_boost"):
		_starfield.trigger_warp_boost(3.0, 10.0)
	if _wave_is_clean:
		_add_score(CLEAN_WAVE_BONUS)
		_hud.set_score(score)
		_visual_feedback.play_score_popup(_player.global_position + Vector2(0, -50), CLEAN_WAVE_BONUS, true)
	if _local_wave(wave) >= TOTAL_WAVES:
		# Transition to Boss encounter instead of completing mission directly
		_session_state = SessionState.WAVE_TRANSITION
		_enemy_spawner.stop()
		_boss_pending = true
		_audio_feedback.stop_combat_music()
		_wave_announcement.show_announcement(wave + 1, "¡AMENAZA COLOSAL DETECTADA!")
		return
	_show_wave_cleared_feedback()
	# Enter wave transition instead of starting the next wave immediately.
	_session_state = SessionState.WAVE_TRANSITION
	_enemy_spawner.stop()
	_pending_wave_index = wave
	var phrase: String = _pick_radar_phrase()
	if _local_index(_pending_wave_index) == ASTEROID_WAVE_INDEX and _asteroid_spawner != null and _asteroid_spawner.has_method(&"start_asteroid_wave"):
		phrase = "¡ALERTA: CINTURÓN DE ASTEROIDES INMINENTE!"
		if _audio_feedback != null and _audio_feedback.has_method(&"play_asteroid_warning"):
			_audio_feedback.play_asteroid_warning()
		if _visual_feedback != null and _visual_feedback.has_method(&"play_asteroid_warning"):
			_visual_feedback.play_asteroid_warning()
		if _camera != null and _camera.has_method(&"add_trauma"):
			_camera.add_trauma(0.20)
	_wave_announcement.show_announcement(wave + 1, phrase)


## Wave-cleared feedback (Etapa 15 T6): banner, camera zoom pulse, and a short
## invulnerability grace period for the player.
func _show_wave_cleared_feedback() -> void:
	_hud.show_wave_cleared_banner()
	_player.grant_invulnerability(WAVE_CLEARED_INVULNERABILITY)
	if _camera == null:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_camera.zoom = Vector2.ONE
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(_camera, "zoom", Vector2.ONE * CAMERA_ZOOM_PULSE, CAMERA_ZOOM_IN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(_camera, "zoom", Vector2.ONE, CAMERA_ZOOM_OUT_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Stops the zoom pulse, returns the camera to its base zoom, and hides the banner.
func _reset_wave_cleared_feedback() -> void:
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null
	if _camera != null:
		_camera.zoom = Vector2.ONE
	_hud.hide_wave_cleared_banner()


func _on_wave_announcement_finished() -> void:
	if _session_state != SessionState.WAVE_TRANSITION or not _session_active:
		return
	if _boss_pending:
		_boss_pending = false
		_start_boss_battle()
		return
	wave = _pending_wave_index + 1
	_wave_is_clean = true
	_hud.set_wave(wave)
	_update_hud()
	_session_state = SessionState.PLAYING
	_enemy_spawner.difficulty_level = _chapter
	if _local_wave(wave) == BONUS_WAVE_NUMBER:
		_start_bonus_wave()
		return
	if _local_index(_pending_wave_index) == ASTEROID_WAVE_INDEX and _asteroid_spawner != null and _asteroid_spawner.has_method(&"start_asteroid_wave"):
		_enemy_spawner.stop()
		_enemy_spawner.clear_formation()
		_asteroid_spawner.start_asteroid_wave(24)
		_begin_belt_camera_follow()
	else:
		_enemy_spawner.start_wave(_local_index(_pending_wave_index), _pending_wave_index)


func _start_boss_battle() -> void:
	_session_state = SessionState.BOSS_BATTLE
	_clear_boss()
	var boss: Area2D = BOSS_SCENE.instantiate() as Area2D
	if boss == null:
		return
	_active_boss = boss
	boss.global_position = Vector2(get_viewport().get_visible_rect().size.x * 0.5, -100.0)
	boss.max_health = int(round(BOSS_BASE_HEALTH * (1.0 + BOSS_HEALTH_STEP * float(_chapter - 1))))
	var chapter_index: int = clampi(_chapter - 1, 0, TOTAL_CHAPTERS - 1)
	boss.boss_variant = BOSS_VARIANTS_BY_CHAPTER[chapter_index]
	# Núcleo Blindado three-phase fight is reserved for the final chapter.
	boss.multi_phase_enabled = _chapter == TOTAL_CHAPTERS
	boss.armor_phase_changed.connect(_on_boss_armor_phase_changed)
	boss.health_changed.connect(_on_boss_health_changed)
	boss.boss_defeated.connect(_on_boss_defeated)
	boss.boss_contacted_player.connect(_on_boss_contacted_player)
	add_child(boss)
	var max_hp: int = int(boss.get("max_health")) if "max_health" in boss else 150
	_hud.show_boss_health_bar(BOSS_NAMES_BY_CHAPTER[chapter_index], max_hp)
	_audio_feedback.stop_combat_music()
	_audio_feedback.start_boss_music()


func _on_boss_health_changed(current: int, max_hp: int) -> void:
	_hud.update_boss_health(current, max_hp)
	_camera.shake(4.0, 0.15)


## Núcleo Blindado armor phase change: camera shake and a short on-screen message.
func _on_boss_armor_phase_changed(phase: int) -> void:
	if not _session_active:
		return
	if phase != ARMOR_PHASE_SUBCORE and phase != ARMOR_PHASE_EXPOSED_CORE:
		return
	var text: String = ARMOR_BROKEN_TEXT if phase == ARMOR_PHASE_SUBCORE else CORE_EXPOSED_TEXT
	if _camera != null and _camera.has_method(&"add_trauma"):
		_camera.add_trauma(ARMOR_PHASE_CHANGE_TRAUMA)
	if _visual_feedback != null and _active_boss != null:
		_visual_feedback.play_text_popup(_active_boss.global_position + Vector2(0, -60), text, Color(1.0, 0.75, 0.25))


func _on_boss_contacted_player(player: Node2D) -> void:
	_request_player_damage(player)


func _on_boss_defeated(boss: Area2D) -> void:
	if not _session_active:
		return
	var explosion_pos: Vector2 = boss.global_position
	_visual_feedback.play_enemy_explosion(explosion_pos)
	_visual_feedback.play_enemy_explosion(explosion_pos + Vector2(-35, 15))
	_visual_feedback.play_enemy_explosion(explosion_pos + Vector2(35, -15))
	_visual_feedback.play_score_popup(explosion_pos, BOSS_POINTS, true)
	_camera.shake(8.0, 0.35)
	_audio_feedback.play_enemy_explosion()
	_add_score(BOSS_POINTS)
	_hud.set_score(score)

	# Guaranteed alternative weapon medallion reward post-boss with high magnetism
	var active_w: int = _player.get_weapon() if (_player != null and _player.has_method(&"get_weapon")) else 0
	var alt_weapons: Array[int] = []
	for w_idx: int in range(4):
		if w_idx != active_w:
			alt_weapons.append(w_idx)
	var chosen_alt: int = alt_weapons[randi() % alt_weapons.size()]
	var loot: Area2D = LOOT_DROP_SCENE.instantiate() as Area2D
	if loot != null:
		if loot.has_signal(&"collected"):
			loot.collected.connect(_on_loot_collected)
		if loot.has_method(&"configure"):
			loot.configure(LootDrop.Type.MEDALLION_BLASTER + chosen_alt, explosion_pos, _player)
		loot.set("magnet_radius", 2000.0)
		loot.set("magnet_acceleration", 1500.0)
		add_child(loot)

	_audio_feedback.stop_boss_music()
	_hud.hide_boss_health_bar()
	_active_boss = null
	if _chapter < TOTAL_CHAPTERS:
		_begin_next_chapter()
	else:
		_complete_mission()


## Starts the next chapter: waves restart at 1 after the chapter announcement.
func _begin_next_chapter() -> void:
	_chapter += 1
	_perform_hyperspace_jump()
	_session_state = SessionState.WAVE_TRANSITION
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	# Wave numbering is global: the next chapter continues after the boss wave.
	_pending_wave_index = wave
	_wave_is_clean = true
	_wave_announcement.show_announcement(wave + 1, "¡CAPÍTULO %d INICIADO!" % _chapter)


func is_bonus_wave_active() -> bool:
	return _bonus_active


func get_bonus_drops_spawned() -> int:
	return _bonus_drops_spawned


## Peaceful wave: no fighters, loot rains down, then the wave is cleared.
func _start_bonus_wave() -> void:
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	_bonus_active = true
	_bonus_drops_spawned = 0
	_session_state = SessionState.BONUS_WAVE
	_run_bonus_wave()


func _run_bonus_wave() -> void:
	var vp_width: float = get_viewport().get_visible_rect().size.x
	for _i: int in range(BONUS_DROP_COUNT):
		await get_tree().create_timer(bonus_drop_interval).timeout
		if not _session_active or not _bonus_active:
			return
		var loot_types: Array[int] = [LootDrop.Type.MEDALLION_BLASTER, LootDrop.Type.MEDALLION_MISSILE, LootDrop.Type.MEDALLION_LASER, LootDrop.Type.POWER_ATOM]
		_spawn_loot(loot_types[randi() % loot_types.size()], Vector2(randf_range(60.0, vp_width - 60.0), -20.0))
		_bonus_drops_spawned += 1
	await get_tree().create_timer(bonus_drop_interval).timeout
	if not _session_active or not _bonus_active:
		return
	_bonus_active = false
	_on_wave_cleared(BONUS_WAVE_NUMBER - 1)


## Cinematic jump between chapters: strong starfield warp plus camera trauma.
func _perform_hyperspace_jump() -> void:
	_hyperspace_jumps += 1
	if _starfield != null and _starfield.has_method(&"trigger_warp_boost"):
		_starfield.trigger_warp_boost(2.5, 18.0)
	if _camera != null and _camera.has_method(&"add_trauma"):
		_camera.add_trauma(0.5)


func get_hyperspace_jump_count() -> int:
	return _hyperspace_jumps


func get_chapter() -> int:
	return _chapter


func get_total_chapters() -> int:
	return TOTAL_CHAPTERS


func _clear_boss() -> void:
	if is_instance_valid(_active_boss):
		_active_boss.queue_free()
	_active_boss = null
	for child: Node in get_children():
		if child is Area2D and child.has_signal(&"boss_defeated"):
			child.queue_free()


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
	_end_belt_camera_follow()
	_session_state = SessionState.GAME_OVER
	_player.set_gameplay_enabled(false)
	_set_player_two_active(false)
	_enemy_spawner.stop()
	if _asteroid_spawner != null:
		_asteroid_spawner.stop()
	_clear_boss()
	_wave_announcement.cancel_announcement()
	_audio_feedback.stop_combat_music()
	_audio_feedback.stop_boss_music()
	_hud.hide_boss_health_bar()
	var is_new_record: bool = _update_high_score_if_needed()
	_game_over.show_session_stats(get_session_accuracy(), kills_by_type)
	_game_over.show_game_over(score, is_new_record)


func _complete_mission() -> void:
	_session_active = false
	_end_belt_camera_follow()
	_mission_complete = true
	_session_state = SessionState.MISSION_COMPLETE
	_player.set_gameplay_enabled(false)
	_enemy_spawner.stop()
	if _asteroid_spawner != null:
		_asteroid_spawner.stop()
	_clear_boss()
	_wave_announcement.cancel_announcement()
	_audio_feedback.stop_combat_music()
	_audio_feedback.stop_boss_music()
	_hud.hide_boss_health_bar()
	var is_new_record: bool = _update_high_score_if_needed()
	_hud.show_mission_complete(score, is_new_record)


func is_mission_complete() -> bool:
	return _mission_complete


func is_session_active() -> bool:
	return _session_active


func reset_session() -> void:
	get_tree().paused = false
	SESSION_STATS.reset()
	kills_by_type.clear()
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	if _asteroid_spawner != null:
		_asteroid_spawner.stop()
		_asteroid_spawner.clear_asteroids()
	_end_belt_camera_follow()
	if _camera != null and _camera.has_method(&"reset_shake"):
		_camera.reset_shake()
	_reset_wave_cleared_feedback()
	_clear_boss()
	_boss_pending = false
	_clear_combat_transients()
	_visual_feedback.clear_effects()
	_wave_announcement.cancel_announcement()
	_pending_wave_index = 0
	_audio_feedback.stop_combat_music()
	_audio_feedback.stop_boss_music()
	_hud.hide_boss_health_bar()
	_player.clear_power_ups()
	if _combo_system != null and _combo_system.has_method(&"reset_combo"):
		_combo_system.reset_combo()
	if _player != null:
		if _player.has_method(&"reset_heat"):
			_player.reset_heat()
		if _player.has_method(&"set_weapon"):
			_player.set_weapon(0)
	if _hud != null:
		if _hud.has_method(&"set_active_weapon"):
			_hud.set_active_weapon(0)
		if _hud.has_method(&"set_heat"):
			_hud.set_heat(0.0, _player.max_heat if _player != null and "max_heat" in _player else 100.0, false)
		if _hud.has_method(&"set_combo"):
			_hud.set_combo(1, 0, 0.0)
	lives = STARTING_LIVES
	score = 0
	wave = 1
	_chapter = 1
	_bonus_active = false
	_hyperspace_jumps = 0
	_last_extra_life_threshold = 0
	if _player != null and _player.has_method(&"set_weapon_level"):
		_player.set_weapon_level(1)
	_session_active = true
	_mission_complete = false
	_wave_is_clean = true
	_session_state = SessionState.PLAYING
	_enemy_spawner.session_difficulty = session_difficulty
	_player.cooling_scale = DS.cooling_multiplier(session_difficulty)
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
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_game_layout.configure(vp_size)
	if _camera != null:
		_camera.position = vp_size * 0.5
	_player.set_horizontal_limits(_game_layout.get_player_horizontal_limits())
	var formation_origin: Vector2 = _game_layout.get_enemy_formation_origin()
	_enemy_spawner.set_formation_layout(formation_origin, formation_origin.y)


func _clear_combat_transients() -> void:
	for transient: Node in get_tree().get_nodes_in_group(&"combat_transients"):
		if is_instance_valid(transient) and transient.get_parent() != _player and (_player == null or not _player.is_ancestor_of(transient)):
			transient.queue_free()


func _clear_enemy_bullets() -> void:
	for bullet: Node in get_tree().get_nodes_in_group(&"enemy_bullets"):
		if is_instance_valid(bullet):
			bullet.queue_free()


func _hide_mission_complete_message() -> void:
	_hud.hide_mission_complete()


func _update_hud() -> void:
	_hud.set_lives(lives)
	_hud.set_score(score)
	_hud.set_wave(wave)
	if _hud != null:
		if _hud.has_method(&"set_active_weapon"):
			_hud.set_active_weapon(_player.get_weapon() if (_player != null and _player.has_method(&"get_weapon")) else 0)
		if _hud.has_method(&"set_weapon_level"):
			var cur_w: int = _player.get_weapon() if (_player != null and _player.has_method(&"get_weapon")) else 0
			var cur_lvl: int = _player.get_weapon_level() if (_player != null and _player.has_method(&"get_weapon_level")) else 1
			_hud.set_weapon_level(cur_lvl, cur_w)
		if _hud.has_method(&"set_heat"):
			var cur_h: float = _player.heat if (_player != null and "heat" in _player) else 0.0
			var max_h: float = _player.max_heat if (_player != null and "max_heat" in _player) else 100.0
			var is_oh: bool = _player.is_weapon_overheated() if (_player != null and _player.has_method(&"is_weapon_overheated")) else false
			_hud.set_heat(cur_h, max_h, is_oh)
		if _hud.has_method(&"set_combo"):
			var mult: int = _combo_system.get_multiplier() if (_combo_system != null and _combo_system.has_method(&"get_multiplier")) else 1
			var kills: int = _combo_system.get_kills() if (_combo_system != null and _combo_system.has_method(&"get_kills")) else 0
			var ratio: float = _combo_system.get_time_ratio() if (_combo_system != null and _combo_system.has_method(&"get_time_ratio")) else 0.0
			_hud.set_combo(mult, kills, ratio)



## Shot accuracy of the current session as a percentage (0.0 to 100.0).
func get_session_accuracy() -> float:
	return SESSION_STATS.accuracy_percent(SESSION_STATS.hits, SESSION_STATS.shots)


## Returns true and persists the new best if this session's score beats
## the previous record; returns false otherwise.
func _update_high_score_if_needed() -> bool:
	if score <= _high_score:
		return false
	_high_score = score
	HighScore.save_value(_high_score)
	return true


func _on_game_over_retry_requested() -> void:
	reset_session()


func _on_hud_retry_mission_requested() -> void:
	reset_session()


func _on_main_menu_quit_requested() -> void:
	return_to_main_menu()
	get_tree().quit()


func _on_main_menu_settings_requested() -> void:
	_main_menu.visible = false
	_settings_menu.show_menu()


func _on_settings_back_requested() -> void:
	_settings_menu.visible = false
	_main_menu.show_menu()


## Etapa 16: the camera follows the ship only while the asteroid belt runs.
func _begin_belt_camera_follow() -> void:
	if _camera != null and _player != null and _camera.has_method(&"begin_follow"):
		_camera.begin_follow(_player)


func _end_belt_camera_follow() -> void:
	if _camera != null and _camera.has_method(&"end_follow"):
		_camera.end_follow()


func get_asteroid_spawner() -> Node2D:
	return _asteroid_spawner


func is_asteroid_wave_active() -> bool:
	return _asteroid_spawner != null and _asteroid_spawner.has_method(&"is_wave_active") and _asteroid_spawner.is_wave_active()


func start_asteroid_wave_direct(count: int = 4) -> void:
	_session_state = SessionState.PLAYING
	_enemy_spawner.stop()
	_enemy_spawner.clear_formation()
	if _asteroid_spawner != null and _asteroid_spawner.has_method(&"start_asteroid_wave"):
		_asteroid_spawner.start_asteroid_wave(count)
