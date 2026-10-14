# enemy_variants.gd
# Data-driven catalog of tactical enemy variants (Stage 12). Each entry is a plain
# Dictionary consumed by enemy.gd via apply_variant(), so new enemy types need no
# new scenes or scripts (composition over inheritance).

extends RefCounted

const STANDARD: StringName = &"standard"
const ARMORED_FIGHTER: StringName = &"armored_fighter"
const ASSAULT_FRIGATE: StringName = &"assault_frigate"
const SCOUT_DRONE: StringName = &"scout_drone"
const SUICIDE_INTERCEPTOR: StringName = &"suicide_interceptor"

## Variant definitions.
## - max_health: hit points.
## - visual_scale: uniform scale of the Area2D (also scales collision).
## - deflector: true when frontal hits are attenuated (flanks and laser bypass it).
## - deflector_cone_deg: total frontal cone angle protected by the deflector.
## - deflector_multiplier: damage multiplier applied to frontal hits.
## - burst_count / burst_interval: shots per volley and delay between them.
## - fire_rate_scale: multiplier on the shoot cooldown (<1.0 fires faster).
## - ai: enemy_ai.gd configuration (detect/attack ranges, flee threshold, ...).
## - evasion_speed: lateral dodge speed (px/s) against slow projectiles; 0 disables.
## - swarm: true enables separation/cohesion steering.
## - suicide: true makes the ATTACK state a direct high-speed charge.
## - charge_speed: charge speed in px/s (suicide variants).
const _DEFINITIONS: Dictionary = {
	&"standard": {
		"max_health": 1.0,
		"visual_scale": 1.0,
		"deflector": false,
		"burst_count": 1,
		"burst_interval": 0.0,
		"fire_rate_scale": 1.0,
		"ai": {},
		"evasion_speed": 0.0,
		"swarm": false,
		"suicide": false,
		"charge_speed": 0.0,
		"score_weight": 1.0,
	},
	&"armored_fighter": {
		"max_health": 4.0,
		"visual_scale": 1.15,
		"deflector": true,
		"deflector_cone_deg": 70.0,
		"deflector_multiplier": 0.25,
		"burst_count": 1,
		"burst_interval": 0.0,
		"fire_rate_scale": 1.0,
		"ai": {"detect_range": 520.0, "attack_range": 420.0, "detect_time": 0.6, "attack_duration": 3.0, "flee_health_ratio": 0.0},
		"evasion_speed": 0.0,
		"swarm": false,
		"suicide": false,
		"charge_speed": 0.0,
		"score_weight": 3.0,
	},
	&"assault_frigate": {
		"max_health": 10.0,
		"visual_scale": 1.4,
		"deflector": false,
		"burst_count": 3,
		"burst_interval": 0.14,
		"fire_rate_scale": 1.3,
		"ai": {"detect_range": 700.0, "attack_range": 600.0, "detect_time": 0.8, "attack_duration": 4.0, "flee_health_ratio": 0.2, "flee_duration": 2.5},
		"evasion_speed": 40.0,
		"swarm": false,
		"suicide": false,
		"charge_speed": 0.0,
		"score_weight": 6.0,
	},
	&"scout_drone": {
		"max_health": 1.0,
		"visual_scale": 0.75,
		"deflector": false,
		"burst_count": 1,
		"burst_interval": 0.0,
		"fire_rate_scale": 1.6,
		"ai": {"detect_range": 600.0, "attack_range": 500.0, "detect_time": 0.3, "attack_duration": 2.0, "flee_health_ratio": 0.0},
		"evasion_speed": 160.0,
		"swarm": true,
		"suicide": false,
		"charge_speed": 0.0,
		"score_weight": 1.0,
	},
	&"suicide_interceptor": {
		"max_health": 2.0,
		"visual_scale": 0.9,
		"deflector": false,
		"burst_count": 1,
		"burst_interval": 0.0,
		"fire_rate_scale": 3.0,
		"ai": {"detect_range": 520.0, "attack_range": 520.0, "detect_time": 0.9, "attack_duration": 6.0, "flee_health_ratio": 0.0},
		"evasion_speed": 90.0,
		"swarm": false,
		"suicide": true,
		"charge_speed": 520.0,
		"score_weight": 2.0,
	},
}


static func get_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for key: Variant in _DEFINITIONS.keys():
		ids.append(key as StringName)
	return ids


static func has_variant(id: StringName) -> bool:
	return _DEFINITIONS.has(id)


## Returns a copy of the definition ({} for unknown ids).
static func get_definition(id: StringName) -> Dictionary:
	if not _DEFINITIONS.has(id):
		return {}
	var def: Dictionary = _DEFINITIONS[id]
	return def.duplicate(true)
