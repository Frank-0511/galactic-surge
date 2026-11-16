# enemy_tactics.gd
# Tactical variant and AI of one Enemy: applies the variant catalog definition, drives the
# EnemyAI component each frame, resolves the player target and forwards AI state changes.
# Owned by Enemy through _enemy.

extends RefCounted

const PlayerShip: Script = preload("res://scenes/entities/player/player.gd")
const EnemyAI: Script = preload("res://scripts/components/enemy_ai.gd")
const EnemyVariants: Script = preload("res://scripts/systems/enemy_variants.gd")

var _enemy: Area2D


func _init(enemy: Area2D) -> void:
	_enemy = enemy


## First-frame setup: applies the configured variant, or keeps the base catalog entry.
func init_variant() -> void:
	if _enemy._variant_applied:
		return
	if _enemy.variant_id != EnemyVariants.STANDARD:
		apply_variant(_enemy.variant_id)
	else:
		# Base enemy keeps any manually configured max_health.
		_enemy._variant_def = EnemyVariants.get_definition(EnemyVariants.STANDARD)


## Configures this enemy from the variant catalog. Safe before or after _ready().
func apply_variant(id: StringName) -> void:
	if not EnemyVariants.has_variant(id):
		id = EnemyVariants.STANDARD
	_enemy._variant_applied = true
	_enemy.variant_id = id
	_enemy._variant_def = EnemyVariants.get_definition(id)
	_enemy.max_health = float(_enemy._variant_def.get("max_health", 1.0))
	_enemy.health = _enemy.max_health
	var visual_scale: float = float(_enemy._variant_def.get("visual_scale", 1.0))
	_enemy.scale = Vector2(visual_scale, visual_scale)
	_enemy.set_fire_rate_scale(float(_enemy._variant_def.get("fire_rate_scale", 1.0)))
	_enemy._ai = null
	var ai_config: Dictionary = _enemy._variant_def.get("ai", {})
	if not ai_config.is_empty():
		_enemy._ai = EnemyAI.new()
		_enemy._ai.configure(ai_config)
		_enemy._ai.state_changed.connect(on_ai_state_changed)
	_enemy._charge_cooldown = randf_range(3.0, 6.0)


## Drives the AI each frame and, while formation-locked, starts suicide charges or steers.
func process_ai(delta: float) -> void:
	if _enemy._variant_def.is_empty():
		return
	if _enemy._ai != null:
		var ratio: float = clampf(_enemy.health / maxf(_enemy.max_health, 0.001), 0.0, 1.0)
		_enemy._ai.update(delta, _enemy.global_position, get_target_position(), ratio)

	if _enemy._state != _enemy.State.FORMATION:
		_enemy._ai_offset = Vector2.ZERO
		return

	_enemy._charge_cooldown = maxf(0.0, _enemy._charge_cooldown - delta)
	if bool(_enemy._variant_def.get("suicide", false)) and _enemy._ai != null and _enemy._ai.is_attacking() and _enemy._charge_cooldown <= 0.0:
		var target: Variant = get_target_position()
		if target is Vector2:
			_enemy._steering.start_charge(target as Vector2)
			return

	_enemy._steering.update_steering(delta)


## Player position for AI and steering: the test override, else the first alive ship.
func get_target_position() -> Variant:
	if _enemy._target_override is Vector2:
		return _enemy._target_override
	if not _enemy.is_inside_tree():
		return null
	var player: Node2D = PlayerShip.first_alive_ship(_enemy.get_tree())
	if player != null and is_instance_valid(player):
		return player.global_position
	return null


func on_ai_state_changed(previous_state: int, new_state: int) -> void:
	_enemy.ai_state_changed.emit(previous_state, new_state)
