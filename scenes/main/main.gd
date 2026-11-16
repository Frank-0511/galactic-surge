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
const HighScore: Script = preload("res://core/session/high_score.gd")
const Settings: Script = preload("res://core/settings/settings.gd")
const SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
const SESSION_STATS := preload("res://core/session/session_stats.gd")
const MainLoot: Script = preload("res://scenes/main/main_loot.gd")
const MainBoss: Script = preload("res://scenes/main/main_boss.gd")
const MainShips: Script = preload("res://scenes/main/main_ships.gd")
const MainScoring: Script = preload("res://scenes/main/main_scoring.gd")
const MainWaves: Script = preload("res://scenes/main/main_waves.gd")
const MainSession: Script = preload("res://scenes/main/main_session.gd")
const MainHudLayout: Script = preload("res://scenes/main/main_hud_layout.gd")
const MainWiring: Script = preload("res://scenes/main/main_wiring.gd")
const SHIELD_DURATION: float = 10.0
const NEARBY_SHAKE_RADIUS: float = 220.0
const EXTRA_LIFE_SCORE_THRESHOLD: int = 1_000_000
const DS := preload("res://core/settings/difficulty_settings.gd")

const _RADAR_PHRASES: Array[String] = [
	"SEÑAL HOSTIL DETECTADA", "FORMACIÓN ENTRANTE",
	"CONTACTO EN EL RADAR", "ENEMIGOS APROXIMÁNDOSE",
	"DISTORSIÓN HIPERESPACIAL", "VANGUARDIA ALIENÍGENA",
	"ENJAMBRE EN APROXIMACIÓN", "FIRMA DE ENERGÍA CRÍTICA",
	"PATRÓN DE ASALTO CIBERNÉTICO", "INCURSIÓN ESTELAR INMINENTE",
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

## Score of J2 in coop local (Etapa 20); `score` is J1's.
var score_p2: int = 0

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
var _loot: RefCounted = MainLoot.new(self)
var _boss: RefCounted = MainBoss.new(self)
var _ships: RefCounted = MainShips.new(self)
var _scoring: RefCounted = MainScoring.new(self)
var _waves: RefCounted = MainWaves.new(self)
var _session: RefCounted = MainSession.new(self)
var _hud_layout: RefCounted = MainHudLayout.new(self)
var _wiring: RefCounted = MainWiring.new(self)

var _game_layout: GameLayout = GameLayout.new()


func _ready() -> void:
	_wiring.setup()
	if not multiplayer.server_disconnected.is_connected(_on_network_lost):
		multiplayer.server_disconnected.connect(_on_network_lost)
	_enter_main_menu()


func _on_network_lost() -> void:
	_wiring.on_network_lost()


func _unhandled_input(event: InputEvent) -> void:
	_wiring.unhandled_input(event)


func start_session() -> void:
	_session.start_session()


func pause_session() -> void:
	_session.pause_session()


func resume_session() -> void:
	_session.resume_session()


func return_to_main_menu() -> void:
	_enter_main_menu()


func _enter_main_menu() -> void:
	_enemy_spawner.difficulty_level = 1
	_session.enter_main_menu()


## Coop local (Etapa 20): creates the second ship with its own lives. Singleplayer never calls it.
func enable_coop_local() -> void:
	_ships.enable_coop_local()


## Shows or hides J2 for a session; activating gives J2 fresh lives and a respawn.
func _set_player_two_active(active: bool) -> void:
	_ships.set_player_two_active(active)


func _request_player_damage(player: Node2D) -> void:
	_ships.request_player_damage(player)


## ship: the ship that requested damage; null means J1 (keeps the singleplayer path).
func _on_player_damage_requested(ship: Node2D = null) -> void:
	_ships.on_player_damage_requested(ship)


func _add_score(points: int, ship: Node2D = null) -> void:
	_scoring.add_score(points, ship)

func _ship_for(attacker: Node) -> Node:
	return _scoring.ship_for(attacker)

func _check_score_milestones() -> void:
	_scoring.check_score_milestones()


func _on_enemy_destroyed(enemy: Area2D) -> void:
	_scoring.on_enemy_destroyed(enemy)


func _on_asteroid_destroyed(asteroid: Area2D, size_idx: int, pos: Vector2, _vel: Vector2) -> void:
	_scoring.on_asteroid_destroyed(asteroid, size_idx, pos, _vel)


func _pick_loot_type() -> int:
	return _loot.pick_type()


func _try_spawn_enemy_loot(spawn_position: Vector2) -> void:
	_loot.try_spawn_enemy_loot(spawn_position)


func _spawn_loot(loot_type: int, spawn_position: Vector2) -> void:
	_loot.spawn_loot(loot_type, spawn_position)


## collector: the ship that picked the drop up (Etapa 20); null means J1 (singleplayer).
func _on_loot_collected(loot_type: int, collector: Node2D = null) -> void:
	_loot.on_loot_collected(loot_type, collector)


func _on_wave_cleared(_wave_index: int) -> void:
	_waves.on_wave_cleared(_wave_index)


func _on_wave_announcement_finished() -> void:
	_waves.on_wave_announcement_finished()


func is_bonus_wave_active() -> bool:
	return _waves.is_bonus_wave_active()


func get_bonus_drops_spawned() -> int:
	return _waves.get_bonus_drops_spawned()


func get_hyperspace_jump_count() -> int:
	return _waves.get_hyperspace_jump_count()


func get_chapter() -> int:
	return _waves.get_chapter()


func get_total_chapters() -> int:
	return _waves.get_total_chapters()


func is_mission_complete() -> bool:
	return _session.is_mission_complete()


func is_session_active() -> bool:
	return _session.is_session_active()


func reset_session() -> void:
	# Restart the spawner difficulty (etapa_20 Contract 38 reads this body); the session sets it again before the first wave.
	_enemy_spawner.difficulty_level = 1
	_session.reset_session()


func _clear_enemy_bullets() -> void:
	_session.clear_enemy_bullets()


func get_asteroid_spawner() -> Node2D:
	return _waves.get_asteroid_spawner()


func is_asteroid_wave_active() -> bool:
	return _waves.is_asteroid_wave_active()


func start_asteroid_wave_direct(count: int = 4) -> void:
	_waves.start_asteroid_wave_direct(count)
