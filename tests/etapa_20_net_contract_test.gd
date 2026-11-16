extends SceneTree
# Contract test for Etapa 20 (slice 2): lobby and connection over ENet.
# Verifies the network module that the Host/Join lobby will use (S1, S2, S3).
# Calls go through dynamic dispatch so a missing module reports a failed contract, not a parse error.

const NET_SCRIPT_PATH := "res://scripts/net/lobby_net.gd"
const MAIN_MENU_SCENE_PATH := "res://scenes/ui/main_menu.tscn"
const MAIN_SCRIPT_PATH := "res://scenes/main/main.gd"
const TEST_PORT: int = 7788

var _failures: int = 0


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var net_script: Script = load(NET_SCRIPT_PATH) as Script
	_expect(net_script != null, "Contrato N1: existe el modulo de red %s" % NET_SCRIPT_PATH)
	if net_script != null:
		var net: Object = net_script.new()
		_check_port_validation(net)
		_check_ip_validation(net)
		_check_host_and_join(net)
		_check_host_is_authority(net)
	_check_lobby_menu_fields()
	_check_lobby_menu_rejects_invalid_join()
	_check_lobby_menu_rejects_invalid_host()
	_check_main_connects_server_disconnected()
	_check_menu_shows_network_message()
	_check_menu_close_network_clears_peer()

	if _failures == 0:
		print("ETAPA 20 NET CONTRACT TESTS: ALL PASSED")
		quit(0)
	else:
		push_error("ETAPA 20 NET CONTRACT TESTS: %d FAILED" % _failures)
		quit(1)


# N2: ports must be a usable user port (1024-65535); anything else is rejected before ENet is touched.
func _check_port_validation(net: Object) -> void:
	_expect(net.call("validate_port", 7777) == true, "Contrato N2a: el puerto 7777 es valido")
	_expect(net.call("validate_port", 1023) == false, "Contrato N2b: un puerto reservado (1023) se rechaza")
	_expect(net.call("validate_port", 0) == false, "Contrato N2c: el puerto 0 se rechaza")
	_expect(net.call("validate_port", 70000) == false, "Contrato N2d: un puerto fuera de rango se rechaza")


# N3: an IP must be a dotted IPv4 address or a host name; empty or garbage text is rejected.
func _check_ip_validation(net: Object) -> void:
	_expect(net.call("validate_ip", "127.0.0.1") == true, "Contrato N3a: 127.0.0.1 es una IP valida")
	_expect(net.call("validate_ip", "192.168.1.20") == true, "Contrato N3b: una IP de LAN es valida")
	_expect(net.call("validate_ip", "") == false, "Contrato N3c: una IP vacia se rechaza")
	_expect(net.call("validate_ip", "no es ip") == false, "Contrato N3d: texto que no es IP se rechaza")


# N4: hosting opens a server on a valid port; joining a valid address returns OK without crashing.
func _check_host_and_join(net: Object) -> void:
	var host_err: int = net.call("host", TEST_PORT) as int
	_expect(host_err == OK, "Contrato N4a: host() en un puerto valido abre el servidor (OK)")
	net.call("close")
	var bad_host: int = net.call("host", 0) as int
	_expect(bad_host != OK, "Contrato N4b: host() con puerto invalido no abre servidor")
	var join_err: int = net.call("join", "127.0.0.1", TEST_PORT) as int
	_expect(join_err == OK, "Contrato N4c: join() a una IP valida devuelve OK")
	net.call("close")
	var bad_join: int = net.call("join", "no es ip", TEST_PORT) as int
	_expect(bad_join != OK, "Contrato N4d: join() con IP invalida se rechaza sin crash")
	net.call("close")


# N5.1/N5.2: the main menu has a Red section with IP and port fields (defaults 127.0.0.1 and 7777) and Host and Join buttons.
func _check_lobby_menu_fields() -> void:
	var menu: CanvasLayer = _instantiate_menu()
	var ip_field: LineEdit = menu.get_node_or_null("Control/NetPanel/AddressRow/IpField") as LineEdit
	_expect(ip_field != null and ip_field.text == "127.0.0.1", "Contrato N5.1a: el menu tiene campo IP con valor 127.0.0.1")
	var port_field: LineEdit = menu.get_node_or_null("Control/NetPanel/AddressRow/PortField") as LineEdit
	_expect(port_field != null and port_field.text == "7777", "Contrato N5.1b: el menu tiene campo puerto con valor 7777")
	var host_button: Button = menu.get_node_or_null("Control/NetPanel/ButtonRow/HostButton") as Button
	_expect(host_button != null and host_button.text == "Host", "Contrato N5.2a: el menu tiene boton Host")
	var join_button: Button = menu.get_node_or_null("Control/NetPanel/ButtonRow/JoinButton") as Button
	_expect(join_button != null and join_button.text == "Join", "Contrato N5.2b: el menu tiene boton Join")
	_free_menu(menu)


# N5.3: Join with an invalid IP shows an error message on the menu and does not assign a peer.
func _check_lobby_menu_rejects_invalid_join() -> void:
	var menu: CanvasLayer = _instantiate_menu()
	var ip_field: LineEdit = menu.get_node_or_null("Control/NetPanel/AddressRow/IpField") as LineEdit
	var port_field: LineEdit = menu.get_node_or_null("Control/NetPanel/AddressRow/PortField") as LineEdit
	var join_button: Button = menu.get_node_or_null("Control/NetPanel/ButtonRow/JoinButton") as Button
	var error_label: Label = menu.get_node_or_null("Control/NetPanel/NetErrorLabel") as Label
	if ip_field != null and port_field != null and join_button != null and error_label != null:
		ip_field.text = "no es ip"
		port_field.text = "7777"
		join_button.pressed.emit()
		_expect(error_label.text != "", "Contrato N5.3a: Join con IP invalida muestra un mensaje de error en el menu")
		_expect(not (root.multiplayer.multiplayer_peer is ENetMultiplayerPeer), "Contrato N5.3b: Join con IP invalida no asigna peer")
	else:
		_expect(false, "Contrato N5.3a: Join con IP invalida muestra un mensaje de error en el menu (faltan nodos)")
	_free_menu(menu)


# N5.4: Host with an invalid port shows an error message on the menu and does not assign a peer.
func _check_lobby_menu_rejects_invalid_host() -> void:
	var menu: CanvasLayer = _instantiate_menu()
	var port_field: LineEdit = menu.get_node_or_null("Control/NetPanel/AddressRow/PortField") as LineEdit
	var host_button: Button = menu.get_node_or_null("Control/NetPanel/ButtonRow/HostButton") as Button
	var error_label: Label = menu.get_node_or_null("Control/NetPanel/NetErrorLabel") as Label
	if port_field != null and host_button != null and error_label != null:
		port_field.text = "80"
		host_button.pressed.emit()
		_expect(error_label.text != "", "Contrato N5.4a: Host con puerto invalido muestra un mensaje de error en el menu")
		_expect(not (root.multiplayer.multiplayer_peer is ENetMultiplayerPeer), "Contrato N5.4b: Host con puerto invalido no asigna peer")
	else:
		_expect(false, "Contrato N5.4a: Host con puerto invalido muestra un mensaje de error en el menu (faltan nodos)")
	_free_menu(menu)


# N6.1: Main listens for a lost host (server_disconnected) and routes it to _on_network_lost.
func _check_main_connects_server_disconnected() -> void:
	var main_source: String = FileAccess.get_file_as_string(MAIN_SCRIPT_PATH)
	_expect(main_source.contains("multiplayer.server_disconnected.connect(_on_network_lost)"), "Contrato N6.1: main.gd conecta multiplayer.server_disconnected a _on_network_lost")


# N6.2: the main menu exposes the public methods Main uses to show a notice and to clean up the network.
func _check_menu_shows_network_message() -> void:
	var menu: CanvasLayer = _instantiate_menu()
	_expect(menu.has_method("show_network_message"), "Contrato N6.2a: el menu expone show_network_message")
	_expect(menu.has_method("close_network"), "Contrato N6.2b: el menu expone close_network")
	var error_label: Label = menu.get_node_or_null("Control/NetPanel/NetErrorLabel") as Label
	menu.call("show_network_message", "Se perdio la conexion con el host.")
	_expect(error_label != null and error_label.text == "Se perdio la conexion con el host.", "Contrato N6.2c: show_network_message escribe el texto en NetErrorLabel")
	_free_menu(menu)


# N6.3: close_network closes the lobby and leaves multiplayer.multiplayer_peer null after a Host.
func _check_menu_close_network_clears_peer() -> void:
	var menu: CanvasLayer = _instantiate_menu()
	var port_field: LineEdit = menu.get_node_or_null("Control/NetPanel/AddressRow/PortField") as LineEdit
	var host_button: Button = menu.get_node_or_null("Control/NetPanel/ButtonRow/HostButton") as Button
	if port_field != null and host_button != null:
		port_field.text = str(TEST_PORT)
		host_button.pressed.emit()
		_expect(root.multiplayer.multiplayer_peer is ENetMultiplayerPeer, "Contrato N6.3a: Host deja un peer ENet activo antes de cerrar")
		menu.call("close_network")
		_expect(root.multiplayer.multiplayer_peer == null, "Contrato N6.3b: close_network deja multiplayer.multiplayer_peer en null")
	else:
		_expect(false, "Contrato N6.3a: Host deja un peer ENet activo antes de cerrar (faltan nodos)")
	_free_menu(menu)


func _instantiate_menu() -> CanvasLayer:
	var menu: CanvasLayer = (load(MAIN_MENU_SCENE_PATH) as PackedScene).instantiate() as CanvasLayer
	root.add_child(menu)
	return menu


func _free_menu(menu: CanvasLayer) -> void:
	root.remove_child(menu)
	menu.free()


# N7: the host is the authority (server, peer id 1); a client is not. Only the host simulates the match.
func _check_host_is_authority(net: Object) -> void:
	net.call("host", TEST_PORT)
	_expect(net.call("is_host") == true, "Contrato N7a: tras host() el lobby es el host autoritativo")
	_expect(net.call("get_peer").get_unique_id() == 1, "Contrato N7b: el host es el servidor (id de peer 1)")
	net.call("close")
	net.call("join", "127.0.0.1", TEST_PORT)
	_expect(net.call("is_host") == false, "Contrato N7c: tras join() el lobby es cliente, no host")
	net.call("close")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("✓ %s" % message)
	else:
		_failures += 1
		push_error("✗ %s" % message)
