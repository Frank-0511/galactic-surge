# audio_feedback.gd
# Isolated audio playback for combat music and SFX; owns its AudioStreamPlayers.
# Does not modify session state, lives, score, waves or power-ups.

extends Node

const COMBAT_MUSIC_STREAM: AudioStream = preload("res://assets/audio/music/combat_8bit_space_shooter.mp3")
const PLAYER_SHOT_STREAM: AudioStreamWAV = preload("res://assets/audio/sfx/player_shoot.wav")
const PLAYER_DOUBLE_SHOT_STREAM: AudioStreamWAV = preload("res://assets/audio/sfx/player_double_shoot.wav")
const ENEMY_EXPLOSION_STREAM: AudioStreamWAV = preload("res://assets/audio/sfx/enemy_explosion.wav")
const PLAYER_DAMAGE_STREAM: AudioStreamWAV = preload("res://assets/audio/sfx/player_damage.wav")
const PICKUP_DOUBLE_SHOT_STREAM: AudioStreamWAV = preload("res://assets/audio/sfx/pickup_double_shot.wav")
const PICKUP_SHIELD_STREAM: AudioStreamWAV = preload("res://assets/audio/sfx/pickup_shield.wav")

@onready var _combat_music: AudioStreamPlayer = $CombatMusic
@onready var _player_shot: AudioStreamPlayer = $PlayerShot
@onready var _player_double_shot: AudioStreamPlayer = $PlayerDoubleShot
@onready var _enemy_explosion: AudioStreamPlayer = $EnemyExplosion
@onready var _player_damage: AudioStreamPlayer = $PlayerDamage
@onready var _pickup_double_shot: AudioStreamPlayer = $PickupDoubleShot
@onready var _pickup_shield: AudioStreamPlayer = $PickupShield


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var music_stream: AudioStream = _combat_music.stream
	if music_stream is AudioStreamMP3:
		(music_stream as AudioStreamMP3).loop = true
	elif music_stream is AudioStreamOggVorbis:
		(music_stream as AudioStreamOggVorbis).loop = true


func start_combat_music() -> void:
	if not _combat_music.playing:
		_combat_music.play()


func stop_combat_music() -> void:
	_combat_music.stop()
	_combat_music.stream_paused = false


func set_session_paused(paused: bool) -> void:
	_combat_music.stream_paused = paused


func play_player_shot(is_double_shot: bool) -> void:
	if is_double_shot:
		_player_double_shot.play()
	else:
		_player_shot.play()


func play_enemy_explosion() -> void:
	_enemy_explosion.play()


func play_player_damage() -> void:
	_player_damage.play()


func play_power_up_collected(power_up_type: int) -> void:
	# Match on PowerUp.Type values (0 = DOUBLE_SHOT, 1 = SHIELD).
	match power_up_type:
		0:
			_pickup_double_shot.play()
		1:
			_pickup_shield.play()
		_:
			push_warning("AudioFeedback: unknown power-up type %d" % power_up_type)
