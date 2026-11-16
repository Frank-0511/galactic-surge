# hud_weapons.gd
# Weapon readouts of the HUD (spec S7, Etapa 20): the active weapon line, the
# weapon-level labels with their medallion icons for J1 and J2, and the glyph per
# weapon type. Owned by HUD through _hud; the labels and icons stay on HUD because
# the tests read them there.

extends RefCounted

const HudIcons: Script = preload("res://features/ui/hud_icons.gd")

var _hud: CanvasLayer
var current_type: int = 0
var _level: int = 1
var _type_p2: int = 0


func _init(hud: CanvasLayer) -> void:
	_hud = hud


## Updates active weapon text and neon color theme in the HUD.
func set_active(weapon_index: int) -> void:
	current_type = weapon_index
	if _hud._active_weapon_label != null:
		var weapon_names: Array[String] = ["BLASTER", "MISIL", "LÁSER"]
		var weapon_colors: Array[Color] = [
			Color(0.2, 0.6, 1.0),
			Color(1.0, 0.55, 0.1),
			Color(1.0, 0.2, 0.25)
		]
		var idx: int = clampi(weapon_index, 0, 2)
		_hud._active_weapon_label.text = "ARMA: %s" % weapon_names[idx]
		_hud._active_weapon_label.modulate = weapon_colors[idx]
		# The weapon icon in the bottom corner already shows the weapon (Etapa 20).
		_hud._active_weapon_label.visible = false


## Sets the weapon level of J1 and, when given, its weapon type.
func set_level(level: int, weapon_type: int = -1) -> void:
	if weapon_type >= 0:
		current_type = weapon_type
	_level = clampi(level, 1, 15)
	update_level_label()


## Creates J1's level label and medallion on first use, then refreshes both.
func update_level_label() -> void:
	if _hud._weapon_level_label == null:
		_hud._weapon_level_label = Label.new()
		_hud._weapon_level_label.name = "WeaponLevelLabel"
		_hud._weapon_level_label.custom_minimum_size = Vector2(0.0, 28.0)
		_hud._weapon_level_label.add_theme_font_size_override("font_size", 20)
		_hud._weapon_level_label.add_theme_color_override("font_color", Color(0.35, 0.92, 1.0, 1.0))
		var panel: Node = _hud.get_node_or_null("P1BottomPanel")
		if panel != null:
			_hud._weapon_icon = HudIcons.WeaponIcon.new()
			var row_p1: HBoxContainer = HBoxContainer.new()
			row_p1.name = "WeaponRowP1"
			panel.add_child(row_p1)
			row_p1.add_child(_hud._weapon_icon)
			row_p1.add_child(_hud._weapon_level_label)
		else:
			return
	_hud._weapon_icon.set("weapon_type", current_type)
	_hud._weapon_level_label.text = str(_level)


## Sets the weapon level of J2 (bottom-right corner) and, when given, its weapon type.
func set_level_p2(level: int, weapon_type: int = -1) -> void:
	if weapon_type >= 0:
		_type_p2 = weapon_type
	if _hud._weapon_level_p2_label == null:
		_hud._weapon_level_p2_label = Label.new()
		_hud._weapon_level_p2_label.name = "WeaponLevelP2Label"
		_hud._weapon_level_p2_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_hud._weapon_level_p2_label.custom_minimum_size = Vector2(0.0, 28.0)
		_hud._weapon_level_p2_label.add_theme_font_size_override("font_size", 20)
		_hud._weapon_level_p2_label.add_theme_color_override("font_color", Color(0.35, 0.92, 1.0, 1.0))
		_hud._weapon_icon_p2 = HudIcons.WeaponIcon.new()
		var row_p2: HBoxContainer = HBoxContainer.new()
		row_p2.name = "WeaponRowP2"
		row_p2.alignment = BoxContainer.ALIGNMENT_END
		_hud._layout.ensure_p2_bottom_panel().add_child(row_p2)
		row_p2.add_child(_hud._weapon_icon_p2)
		row_p2.add_child(_hud._weapon_level_p2_label)
	_hud._weapon_icon_p2.set("weapon_type", _type_p2)
	_hud._weapon_level_p2_label.text = str(clampi(level, 1, 15))


## Icon per weapon type (0 blaster, 1 misil, 2 laser); the icon follows the weapon (Etapa 20).
func glyph(weapon_type: int) -> String:
	match weapon_type:
		1:
			return "◆"
		2:
			return "●"
		_:
			return "▲"
