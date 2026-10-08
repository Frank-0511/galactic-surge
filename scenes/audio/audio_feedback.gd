# audio_feedback.gd
# Owns combat and boss music and SFX players for weapons, damage, explosions,
# and system warnings. Exposes presentation intents for Main to trigger.

extends Node

@onready var _combat_music: AudioStreamPlayer = $CombatMusic
@onready var _boss_music: AudioStreamPlayer = $BossMusic
@onready var _player_shot: AudioStreamPlayer = $PlayerShot
@onready var _player_double_shot: AudioStreamPlayer = $PlayerDoubleShot
@onready var _enemy_explosion: AudioStreamPlayer = $EnemyExplosion
@onready var _player_damage: AudioStreamPlayer = $PlayerDamage
@onready var _pickup_double_shot: AudioStreamPlayer = $PickupDoubleShot
@onready var _pickup_shield: AudioStreamPlayer = $PickupShield
@onready var _overheat_warning: AudioStreamPlayer = get_node_or_null("OverheatWarning") as AudioStreamPlayer

# PowerUp.Type values mirrored here until Task 5 creates the PowerUp class:
const _POWER_UP_DOUBLE_SHOT: int = 0
const _POWER_UP_SHIELD: int = 1


func _ready() -> void:
	if _combat_music != null and _combat_music.stream is AudioStreamMP3:
		(_combat_music.stream as AudioStreamMP3).loop = true
	if _boss_music != null and _boss_music.stream is AudioStreamMP3:
		(_boss_music.stream as AudioStreamMP3).loop = true


func start_combat_music() -> void:
	if _combat_music != null and not _combat_music.playing:
		_combat_music.play()


func stop_combat_music() -> void:
	if _combat_music != null:
		_combat_music.stop()
		_combat_music.stream_paused = false


func start_boss_music() -> void:
	if _boss_music != null and not _boss_music.playing:
		_boss_music.play()


func stop_boss_music() -> void:
	if _boss_music != null:
		_boss_music.stop()
		_boss_music.stream_paused = false


func set_session_paused(paused: bool) -> void:
	if _combat_music != null:
		_combat_music.stream_paused = paused
	if _boss_music != null:
		_boss_music.stream_paused = paused


func play_player_shot(is_double_shot: bool) -> void:
	if is_double_shot:
		if _player_double_shot != null:
			_player_double_shot.pitch_scale = 1.0
			_player_double_shot.play()
	else:
		if _player_shot != null:
			_player_shot.pitch_scale = 1.0
			_player_shot.play()


## Plays distinct audio for the specified weapon type (0: Blaster, 1: Missile, 2: Laser).
func play_weapon_shot(weapon_type: int) -> void:
	match weapon_type:
		0: # BLASTER
			if _player_shot != null:
				_player_shot.pitch_scale = 1.0
				_player_shot.play()
		1: # MISSILE
			if _player_shot != null:
				_player_shot.pitch_scale = 0.55
				_player_shot.play()
		2: # LASER
			if _player_shot != null:
				_player_shot.pitch_scale = 1.85
				_player_shot.play()
		_:
			if _player_shot != null:
				_player_shot.pitch_scale = 1.0
				_player_shot.play()


## Plays acoustic alert when thermal overload lock engages.
func play_overheat_warning() -> void:
	if _overheat_warning != null:
		_overheat_warning.play()
	elif _player_damage != null:
		_player_damage.pitch_scale = 1.8
		_player_damage.play()


## Plays acoustic alert when enemy formation enrages.
func play_enrage_warning() -> void:
	if _overheat_warning != null:
		_overheat_warning.pitch_scale = 1.35
		_overheat_warning.play()
	elif _player_damage != null:
		_player_damage.pitch_scale = 1.6
		_player_damage.play()


func play_enemy_explosion() -> void:
	if _enemy_explosion != null:
		_enemy_explosion.play()


func play_player_damage() -> void:
	if _player_damage != null:
		_player_damage.pitch_scale = 1.0
		_player_damage.play()


func play_power_up_collected(power_up_type: int) -> void:
	match power_up_type:
		_POWER_UP_DOUBLE_SHOT:
			if _pickup_double_shot != null:
				_pickup_double_shot.play()
		_POWER_UP_SHIELD:
			if _pickup_shield != null:
				_pickup_shield.play()
		_:
			push_warning("AudioFeedback: unknown power-up type %d" % power_up_type)


func play_medallion_collected(weapon_type: int = 0) -> void:
	if _pickup_double_shot != null:
		var pitches: Array[float] = [1.1, 0.85, 1.5]
		var idx: int = clampi(weapon_type, 0, 2)
		_pickup_double_shot.pitch_scale = pitches[idx]
		_pickup_double_shot.play()
	elif _pickup_shield != null:
		_pickup_shield.play()


func play_weapon_switched(weapon_type: int = 0) -> void:
	if _pickup_double_shot != null:
		var pitches: Array[float] = [1.25, 0.75, 1.7]
		var idx: int = clampi(weapon_type, 0, 2)
		_pickup_double_shot.pitch_scale = pitches[idx]
		_pickup_double_shot.play()
	elif _pickup_shield != null:
		_pickup_shield.play()


func play_power_atom_collected() -> void:
	if _pickup_shield != null:
		_pickup_shield.pitch_scale = 1.45
		_pickup_shield.play()
	elif _pickup_double_shot != null:
		_pickup_double_shot.pitch_scale = 1.4
		_pickup_double_shot.play()


func play_extra_life() -> void:
	if _pickup_shield != null:
		_pickup_shield.pitch_scale = 1.85
		_pickup_shield.play()
	elif _pickup_double_shot != null:
		_pickup_double_shot.pitch_scale = 1.75
		_pickup_double_shot.play()

