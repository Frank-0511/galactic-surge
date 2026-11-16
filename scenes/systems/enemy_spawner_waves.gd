# enemy_spawner_waves.gd
# Wave table and difficulty of the enemy formation: the ten base wave configurations, the
# scaling of global waves past chapter 1, and start_wave, which applies chapter, session
# difficulty and layout to the spawner before it spawns the formation.
# Owned by EnemySpawner through _spawner; it reads and writes the spawner's state there.

extends RefCounted

const DS := preload("res://core/settings/difficulty_settings.gd")

## Progressive wave configurations.
## The optional "variants" dictionary maps a tactical variant id (enemy_variants.gd)
## to the number of formation slots that use it; remaining slots are standard enemies.
## Indices are 0-based: wave 0 is the first wave, wave 9 is the last.
const WAVE_CONFIGS: Array = [
	{
		"rows": 3, "columns": 6, "formation_speed": 80.0,  "formation_type": "grid",     "fly_in_trajectory": "swoop_left",
		"bullet_mix": [1.00, 0.00, 0.00], "enraged_bullet_mix": [0.80, 0.20, 0.00], "fire_rate_scale": 1.60,
		"variants": {}
	},
	{
		"rows": 3, "columns": 6, "formation_speed": 90.0,  "formation_type": "v_shape",  "fly_in_trajectory": "pincer",
		"bullet_mix": [0.90, 0.10, 0.00], "enraged_bullet_mix": [0.70, 0.30, 0.00], "fire_rate_scale": 1.50,
		"variants": {"scout_drone": 2}
	},
	{
		"rows": 3, "columns": 7, "formation_speed": 100.0, "formation_type": "arc",      "fly_in_trajectory": "swoop_right",
		"bullet_mix": [0.80, 0.20, 0.00], "enraged_bullet_mix": [0.60, 0.40, 0.00], "fire_rate_scale": 1.40,
		"variants": {"scout_drone": 3}
	},
	{
		"rows": 4, "columns": 7, "formation_speed": 110.0, "formation_type": "diagonal", "fly_in_trajectory": "cross_dive",
		"bullet_mix": [0.75, 0.25, 0.00], "enraged_bullet_mix": [0.50, 0.45, 0.05], "fire_rate_scale": 1.30,
		"variants": {"armored_fighter": 1, "suicide_interceptor": 1, "scout_drone": 2}
	},
	{
		"rows": 4, "columns": 7, "formation_speed": 120.0, "formation_type": "grid",     "fly_in_trajectory": "center_loop",
		"bullet_mix": [0.70, 0.25, 0.05], "enraged_bullet_mix": [0.45, 0.45, 0.10], "fire_rate_scale": 1.20,
		"variants": {"assault_frigate": 1, "armored_fighter": 1, "scout_drone": 3}
	},
	{
		"rows": 4, "columns": 8, "formation_speed": 128.0, "formation_type": "v_shape",  "fly_in_trajectory": "swoop_left",
		"bullet_mix": [0.65, 0.27, 0.08], "enraged_bullet_mix": [0.40, 0.45, 0.15], "fire_rate_scale": 1.15,
		"variants": {"assault_frigate": 1, "armored_fighter": 2, "suicide_interceptor": 1}
	},
	{
		"rows": 4, "columns": 8, "formation_speed": 136.0, "formation_type": "arc",      "fly_in_trajectory": "pincer",
		"bullet_mix": [0.60, 0.30, 0.10], "enraged_bullet_mix": [0.35, 0.45, 0.20], "fire_rate_scale": 1.10,
		"variants": {"assault_frigate": 1, "armored_fighter": 2, "suicide_interceptor": 1, "scout_drone": 3}
	},
	{
		"rows": 5, "columns": 7, "formation_speed": 144.0, "formation_type": "diagonal", "fly_in_trajectory": "swoop_right",
		"bullet_mix": [0.55, 0.32, 0.13], "enraged_bullet_mix": [0.30, 0.45, 0.25], "fire_rate_scale": 1.05,
		"variants": {"assault_frigate": 1, "armored_fighter": 2, "suicide_interceptor": 2, "scout_drone": 3}
	},
	{
		"rows": 5, "columns": 8, "formation_speed": 152.0, "formation_type": "grid",     "fly_in_trajectory": "cross_dive",
		"bullet_mix": [0.52, 0.33, 0.15], "enraged_bullet_mix": [0.25, 0.45, 0.30], "fire_rate_scale": 1.00,
		"variants": {"assault_frigate": 2, "armored_fighter": 3, "suicide_interceptor": 2, "scout_drone": 3}
	},
	{
		"rows": 5, "columns": 8, "formation_speed": 160.0, "formation_type": "arc",      "fly_in_trajectory": "center_loop",
		"bullet_mix": [0.50, 0.35, 0.15], "enraged_bullet_mix": [0.20, 0.45, 0.35], "fire_rate_scale": 1.00,
		"variants": {"assault_frigate": 2, "armored_fighter": 3, "suicide_interceptor": 2, "scout_drone": 4}
	},
]

var _spawner: Node2D


func _init(spawner: Node2D) -> void:
	_spawner = spawner


func get_total_waves() -> int:
	return WAVE_CONFIGS.size()


func get_wave_config(wave_index: int) -> Dictionary:
	if wave_index < 0 or wave_index >= WAVE_CONFIGS.size():
		return {}
	var config: Dictionary = WAVE_CONFIGS[wave_index]
	return config.duplicate()


## Returns the wave config for a local index (0-9) at a global wave index (0-29).
## Chapter 1 returns the base config; later waves are harder than the previous one.
func get_scaled_wave_config(local_index: int, global_index: int) -> Dictionary:
	var config: Dictionary = get_wave_config(local_index)
	if global_index < WAVE_CONFIGS.size() or config.is_empty():
		return config
	var scaled: Dictionary = get_wave_config(WAVE_CONFIGS.size() - 1)
	var step: int = global_index - WAVE_CONFIGS.size() + 1
	# Keep the local wave's visual variety (formation and fly-in), harden the rest.
	scaled["formation_type"] = config.get("formation_type", "grid")
	scaled["fly_in_trajectory"] = config.get("fly_in_trajectory", "swoop_left")
	scaled["formation_speed"] = float(scaled["formation_speed"]) * (1.0 + _spawner.GLOBAL_STEP_SPEED * step)
	scaled["fire_rate_scale"] = maxf(float(scaled["fire_rate_scale"]) - _spawner.GLOBAL_STEP_FIRE * step, _spawner.MIN_FIRE_RATE_SCALE)
	scaled["columns"] = mini(int(scaled["columns"]), _spawner.MAX_FORMATION_COLUMNS)
	return scaled


## wave_index is the local index (0-9); global_index (0-29, -1 = same as local) drives the
## difficulty ramp across chapters.
func start_wave(wave_index: int, global_index: int = -1) -> void:
	if _spawner.replica:
		return # Client replica (Etapa 20 T3): the host starts the waves.
	var effective_global: int = global_index if global_index >= 0 else wave_index
	var config: Dictionary = get_scaled_wave_config(wave_index, effective_global)
	if config.is_empty():
		return
	_spawner._current_wave = wave_index
	_spawner._current_config = config
	var level_offset: int = maxi(_spawner.difficulty_level - 1, 0)
	_spawner.rows = int(config["rows"])
	_spawner.columns = mini(int(config["columns"]) + level_offset, _spawner.MAX_FORMATION_COLUMNS)
	_spawner.formation_speed = float(config["formation_speed"]) * (1.0 + _spawner.DIFFICULTY_SPEED_STEP * level_offset)
	_spawner.formation_speed *= DS.speed_multiplier(_spawner.session_difficulty)
	_spawner.columns = clampi(_spawner.columns + DS.density_offset(_spawner.session_difficulty), 1, _spawner.MAX_FORMATION_COLUMNS)
	_spawner._current_pattern_type = String(config.get("formation_type", "grid"))
	_spawner._current_trajectory = String(config.get("fly_in_trajectory", "swoop_left"))
	_spawner.spawn_formation()
