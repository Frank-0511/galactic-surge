# audio_feedback.gd
# Owns the combat music, boss music and SFX players and exposes presentation intents
# for Main to trigger. Does not modify lives, waves, score or power-ups.

extends Node

@onready var _combat_music: AudioStreamPlayer = $CombatMusic
@onready var _boss_music: AudioStreamPlayer = $BossMusic
@onready var _player_shot: AudioStreamPlayer = $PlayerShot
@onready var _player_double_shot: AudioStreamPlayer = $PlayerDoubleShot
@onready var _enemy_explosion: AudioStreamPlayer = $EnemyExplosion
@onready var _player_damage: AudioStreamPlayer = $PlayerDamage
@onready var _pickup_double_shot: AudioStreamPlayer = $PickupDoubleShot
@onready var _pickup_shield: AudioStreamPlayer = $PickupShield

# PowerUp.Type values mirrored here until Task 5 creates the PowerUp class:
# DOUBLE_SHOT = 0, SHIELD = 1. The int parameter accepts PowerUp.Type enums
# (which are ints) unchanged once Task 5 lands.
const _POWER_UP_DOUBLE_SHOT: int = 0
const _POWER_UP_SHIELD: int = 1


func _ready() -> void:
	# Combat and boss music must loop for the whole session. The imported AudioStreamMP3
	# defaults to loop = false, so enable it on the assigned stream.
	if _combat_music.stream is AudioStreamMP3:
		(_combat_music.stream as AudioStreamMP3).loop = true
	if _boss_music.stream is AudioStreamMP3:
		(_boss_music.stream as AudioStreamMP3).loop = true


func start_combat_music() -> void:
	if not _combat_music.playing:
		_combat_music.play()


func stop_combat_music() -> void:
	_combat_music.stop()
	_combat_music.stream_paused = false


func start_boss_music() -> void:
	if not _boss_music.playing:
		_boss_music.play()


func stop_boss_music() -> void:
	_boss_music.stop()
	_boss_music.stream_paused = false


func set_session_paused(paused: bool) -> void:
	_combat_music.stream_paused = paused
	_boss_music.stream_paused = paused


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
	# Exhaustive match over the two PowerUp.Type values.
	match power_up_type:
		_POWER_UP_DOUBLE_SHOT:
			_pickup_double_shot.play()
		_POWER_UP_SHIELD:
			_pickup_shield.play()
		_:
			push_warning("AudioFeedback: unknown power-up type %d" % power_up_type)
