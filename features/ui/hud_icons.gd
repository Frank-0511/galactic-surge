# hud_icons.gd
# Icons drawn in code for the HUD (Etapa 20): a heart for the lives counter and a
# weapon medallion that matches the loot drop of the same weapon.
# Used by hud.gd and the hud_*.gd modules as HudIcons.HeartIcon and HudIcons.WeaponIcon.

extends RefCounted


## Heart drawn in code (two circles and a triangle) for the lives counter (Etapa 20).
class HeartIcon extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(18.0, 18.0)

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var red: Color = Color(1.0, 0.22, 0.3)
		draw_circle(c + Vector2(-3.5, -2.5), 4.5, red)
		draw_circle(c + Vector2(3.5, -2.5), 4.5, red)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-7.9, -1.2), c + Vector2(7.9, -1.2), c + Vector2(0.0, 8.5)
		]), red)
		draw_circle(c + Vector2(-4.5, -4.0), 1.4, Color(1.0, 0.85, 0.9, 0.9))


## Draws the falling medallion of a weapon, so the HUD icon matches the drop (Etapa 20).
class WeaponIcon extends Control:
	var weapon_type: int = 0:
		set(value):
			weapon_type = value
			queue_redraw()

	func _ready() -> void:
		custom_minimum_size = Vector2(20.0, 20.0)

	func _draw() -> void:
		draw_set_transform(size * 0.5, 0.0, Vector2(1.0, 1.0))
		LootDrop.paint_medallion(self, weapon_type)
