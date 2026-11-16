# hud_layout.gd
# Layout and anchoring of the HUD panels (Etapa 20, specs S7-S8): J1 top-left and
# bottom-left panels, the J2 right-side panels, the mouse-passive wrappers and the
# visibility of the J2 panels. Owned by HUD through _hud; the J2 panel handles
# live on HUD (_p2_panel) because the tests read them there.

extends RefCounted

const HudIcons: Script = preload("res://scenes/ui/hud_icons.gd")

var _hud: CanvasLayer
var _p2_bottom_panel: VBoxContainer = null


func _init(hud: CanvasLayer) -> void:
	_hud = hud


## HUD is passive (skill scenario-godot-ui, regla 7): wrappers must not capture the mouse.
func make_passive() -> void:
	for path: String in ["BossContainer", "Margin", "HeatContainer", "ComboContainer"]:
		var node: Control = _hud.get_node_or_null(path) as Control
		if node != null:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Right-side panel for J2 (Etapa 20): stacks its labels so they never overlap J1's.
func ensure_p2_panel() -> VBoxContainer:
	if _hud._p2_panel == null:
		_hud._p2_panel = VBoxContainer.new()
		_hud._p2_panel.name = "P2Panel"
		_hud._p2_panel.anchor_left = 1.0
		_hud._p2_panel.anchor_right = 1.0
		_hud._p2_panel.offset_left = -260.0
		_hud._p2_panel.offset_right = -16.0
		_hud._p2_panel.offset_top = 16.0
		_hud._p2_panel.grow_horizontal = 0
		_hud._p2_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(_hud._p2_panel)
	return _hud._p2_panel


## Bottom-right panel for J2 lives and weapon level (spec S7, Etapa 20).
func ensure_p2_bottom_panel() -> VBoxContainer:
	if _p2_bottom_panel == null:
		_p2_bottom_panel = VBoxContainer.new()
		_p2_bottom_panel.name = "P2BottomPanel"
		_p2_bottom_panel.anchor_left = 1.0
		_p2_bottom_panel.anchor_top = 1.0
		_p2_bottom_panel.anchor_right = 1.0
		_p2_bottom_panel.anchor_bottom = 1.0
		_p2_bottom_panel.offset_left = -260.0
		_p2_bottom_panel.offset_top = -80.0
		_p2_bottom_panel.offset_right = -16.0
		_p2_bottom_panel.offset_bottom = -16.0
		_p2_bottom_panel.grow_horizontal = 0
		_p2_bottom_panel.grow_vertical = 0
		_p2_bottom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(_p2_bottom_panel)
	return _p2_bottom_panel


## Shows or hides both J2 panels; outside coop local they must not appear (Etapa 20).
func set_p2_visible(on: bool) -> void:
	if _hud._p2_panel != null:
		_hud._p2_panel.visible = on
	if _p2_bottom_panel != null:
		_p2_bottom_panel.visible = on


## Top-left panel for J1 (spec S8, Etapa 20): score and heat bar, then wave and weapon name.
func move_p1_top_left() -> void:
	if _hud._score_label == null or _hud._heat_container == null:
		return
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "P1TopPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 320.0
	panel.grow_horizontal = 1
	panel.grow_vertical = 1
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	_hud._score_label.reparent(panel)
	_hud._heat_container.custom_minimum_size = Vector2(304.0, 38.0)
	_hud._heat_container.reparent(panel)
	if _hud._wave_label != null:
		_hud._wave_label.reparent(panel)
	if _hud._active_weapon_label != null:
		_hud._active_weapon_label.reparent(panel)


## Bottom-left panel for J1 lives (spec S7, Etapa 20): J1 lives move out of the top stack.
func move_p1_lives_bottom_left() -> void:
	if _hud._lives_label == null:
		return
	var panel: VBoxContainer = VBoxContainer.new()
	panel.name = "P1BottomPanel"
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = -80.0
	panel.offset_right = 260.0
	panel.offset_bottom = -16.0
	panel.grow_horizontal = 1
	panel.grow_vertical = 0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "LivesRowP1"
	panel.add_child(row)
	row.add_child(HudIcons.HeartIcon.new())
	_hud._lives_label.reparent(row)
