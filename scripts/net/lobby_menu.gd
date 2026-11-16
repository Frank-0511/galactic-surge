# lobby_menu.gd
# Red section of the main menu (Etapa 20, S2/S4 and T1): Host, Join and Coop en red. Validates the
# input through lobby_net.gd, owns the scene multiplayer peer and shows notices in NetErrorLabel.
# main_menu.gd keeps the signal handlers as thin delegates to this module.

extends RefCounted

const LobbyNet: GDScript = preload("res://scripts/net/lobby_net.gd")
const NO_PEER_TEXT: String = "Primero abre Host o conecta con Join."

var _menu: CanvasLayer
var _lobby: RefCounted = LobbyNet.new()
var _ip_field: LineEdit
var _port_field: LineEdit
var _error_label: Label


func _init(menu: CanvasLayer) -> void:
	_menu = menu
	_ip_field = menu.get_node("Control/NetPanel/AddressRow/IpField") as LineEdit
	_port_field = menu.get_node("Control/NetPanel/AddressRow/PortField") as LineEdit
	_error_label = menu.get_node("Control/NetPanel/NetErrorLabel") as Label


func host_pressed() -> void:
	_error_label.text = ""
	var port: int = _port_field.text.strip_edges().to_int()
	var input_error: String = _lobby.host_input_error(port)
	if input_error != "":
		show_message(input_error)
		return
	var err: Error = _lobby.host(port)
	if err != OK:
		# The lobby closed its previous peer before failing; never leave the scene on that closed peer.
		_menu.multiplayer.multiplayer_peer = null
		show_message("No se pudo abrir el servidor: %s" % error_string(err))
		return
	_menu.multiplayer.multiplayer_peer = _lobby.get_peer()


func join_pressed() -> void:
	_error_label.text = ""
	var address: String = _ip_field.text.strip_edges()
	var port: int = _port_field.text.strip_edges().to_int()
	var input_error: String = _lobby.join_input_error(address, port)
	if input_error != "":
		show_message(input_error)
		return
	var err: Error = _lobby.join(address, port)
	if err != OK:
		_menu.multiplayer.multiplayer_peer = null
		show_message("No se pudo conectar a %s:%d: %s" % [address, port, error_string(err)])
		return
	_menu.multiplayer.multiplayer_peer = _lobby.get_peer()


## True when a Host or Join peer is open, so Coop en red may start. Otherwise shows a notice and returns false.
func can_start_network() -> bool:
	if _menu.multiplayer.has_multiplayer_peer():
		return true
	show_message(NO_PEER_TEXT)
	return false


## Shows a message in the Red section (errors, or a notice such as a lost host).
func show_message(text: String) -> void:
	_error_label.text = text


## Closes the lobby and clears the scene multiplayer peer. Safe when nothing is open.
func close() -> void:
	_lobby.close()
	_menu.multiplayer.multiplayer_peer = null
