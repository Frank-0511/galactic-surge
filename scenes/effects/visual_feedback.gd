# visual_feedback.gd
# Creates pausable geometric combat feedback without modifying gameplay state.

extends Node2D

const EXPLOSION_BURST_SCRIPT: Script = preload("res://scenes/effects/explosion_burst.gd")
const SCORE_POPUP_SCRIPT: Script = preload("res://scenes/effects/score_popup.gd")

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


func play_score_popup(popup_position: Vector2, points: int, is_bonus: bool = false) -> void:
	var color: Color = Color(1.0, 0.85, 0.3) if is_bonus else Color(1.0, 1.0, 1.0)
	var popup: Node2D = SCORE_POPUP_SCRIPT.new("+%d" % points, color) as Node2D
	if popup == null:
		return
	popup.name = "ScorePopup"
	popup.global_position = popup_position
	_explosion_layer.add_child(popup)


func play_damage_flash() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash.modulate.a = 0.45
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.18)


func play_enrage_alert() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	if _flash != null:
		_flash.color = Color(1.0, 0.2, 0.1)
		_flash.modulate.a = 0.5
		_flash_tween = create_tween()
		_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.35)
		_flash_tween.tween_callback(func() -> void:
			if _flash != null:
				_flash.color = Color.WHITE
		)


func clear_effects() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash.modulate.a = 0.0
	for effect: Node in _explosion_layer.get_children():
		effect.queue_free()
