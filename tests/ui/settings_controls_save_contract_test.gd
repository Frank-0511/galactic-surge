# settings_controls_save_contract_test.gd
# Contract test for Ajustes > Controles: the "GUARDAR Y CERRAR" button must exist,
# be visible inside the viewport, and when pressed save and return to Ajustes.
extends SceneTree

const LABEL := "GUARDAR Y CERRAR"
var _menu: Node = null
var _frame := 0
var _errors: Array[String] = []


func _initialize() -> void:
	_menu = load("res://features/ui/settings_menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_menu.call("_on_controls_pressed")
	elif _frame == 6:
		var button := _find_button(root, LABEL)
		if button == null:
			_errors.append("no existe el boton %s en Controles" % LABEL)
		else:
			var viewport := root.get_visible_rect()
			if not button.is_visible_in_tree():
				_errors.append("el boton %s no es visible" % LABEL)
			if not viewport.encloses(button.get_global_rect()):
				_errors.append("el boton %s queda fuera del viewport: %s" % [LABEL, button.get_global_rect()])
			button.pressed.emit()
	elif _frame == 9:
		if _menu.get("_remap_panel") != null:
			_errors.append("GUARDAR Y CERRAR no cerro el panel de Controles")
		var content: Control = _menu.get_node("Control/Center/Content")
		if not content.visible:
			_errors.append("al cerrar Controles no volvio el contenido de Ajustes")
	elif _frame == 10:
		var passed := _errors.is_empty()
		for error in _errors:
			push_error(error)
		print("settings_controls_save_contract: %s" % ("PASS" if passed else "FAIL"))
		quit(0 if passed else 1)
	return false


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null
