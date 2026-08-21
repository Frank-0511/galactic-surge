# visual_feedback.gd
# Creates pausable geometric combat feedback without modifying gameplay state.

extends Node2D

const EXPLOSION_BURST_SCRIPT: Script = preload("res://scenes/effects/explosion_burst.gd")

@onready var _explosion_layer: Node2D = $ExplosionLayer
@onready var _flash: ColorRect = $DamageFlashLayer/Flash

var _flash_tween: Tween


func play_enemy_explosion(position: Vector2) -> void:
	var burst: Node2D = EXPLOSION_BURST_SCRIPT.new() as Node2D
	if burst == null:
		return
	burst.name = "ExplosionBurst"
	burst.global_position = position
	_explosion_layer.add_child(burst)


func play_damage_flash() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash.modulate.a = 0.45
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.18)


func clear_effects() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash.modulate.a = 0.0
	for effect: Node in _explosion_layer.get_children():
		effect.queue_free()
