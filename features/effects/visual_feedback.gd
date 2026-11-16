# visual_feedback.gd
# Creates pausable geometric combat feedback without modifying gameplay state.

extends Node2D

const EXPLOSION_BURST_SCRIPT: Script = preload("res://features/effects/explosion_burst.gd")
const SCORE_POPUP_SCRIPT: Script = preload("res://features/effects/score_popup.gd")
const HULL_FRAGMENT_SCRIPT: Script = preload("res://features/effects/hull_fragment.gd")
const HULL_FRAGMENT_COLOR: Color = Color(0.4, 1.0, 0.8)

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


func play_hull_fragments(pos: Vector2, count: int = 6) -> void:
	for fragment_index: int in count:
		var fragment: Node2D = HULL_FRAGMENT_SCRIPT.new() as Node2D
		if fragment == null:
			continue
		var direction: Vector2 = Vector2.from_angle(randf() * TAU)
		var speed: float = randf_range(120.0, 260.0)
		var lifetime: float = randf_range(0.5, 0.8)
		fragment.name = "HullFragment"
		fragment.call("configure", direction * speed, lifetime, HULL_FRAGMENT_COLOR)
		_explosion_layer.add_child(fragment)
		fragment.global_position = pos


func play_score_popup(popup_position: Vector2, points: int, is_bonus: bool = false) -> void:
	var color: Color = Color(1.0, 0.85, 0.3) if is_bonus else Color(1.0, 1.0, 1.0)
	var popup: Node2D = SCORE_POPUP_SCRIPT.new("+%d" % points, color) as Node2D
	if popup == null:
		return
	popup.name = "ScorePopup"
	popup.global_position = popup_position
	_explosion_layer.add_child(popup)


func play_text_popup(popup_position: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var popup: Node2D = SCORE_POPUP_SCRIPT.new(text, color) as Node2D
	if popup == null:
		return
	popup.name = "TextPopup"
	popup.global_position = popup_position
	_explosion_layer.add_child(popup)


func play_level_up(position: Vector2, new_level: int) -> void:
	play_text_popup(position, "NIVEL %d!" % new_level, Color(0.2, 0.95, 1.0))


func play_weapon_switched(position: Vector2, weapon_name: String, color: Color) -> void:
	play_text_popup(position, "¡%s!" % weapon_name.to_upper(), color)


func play_extra_life_alert(position: Vector2) -> void:
	play_text_popup(position, "1UP!", Color(1.0, 0.2, 0.4))



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


func play_asteroid_warning() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	if _flash != null:
		_flash.color = Color(1.0, 0.6, 0.1)
		_flash.modulate.a = 0.55
		_flash_tween = create_tween()
		_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.45)
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
