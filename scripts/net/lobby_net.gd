# lobby_net.gd
# Network module for the Host/Join lobby (Etapa 20, slice 2). Wraps ENet so the lobby
# validates IP and port before touching the network, and so Host and Join share one peer.
# The host is authoritative: it is the server; the client never simulates the match.

extends RefCounted

const MIN_PORT: int = 1024
const MAX_PORT: int = 65535
const LOCALHOST_NAME: String = "localhost"

var _peer: ENetMultiplayerPeer = null
var _is_host: bool = false


## True for a usable user port (1024-65535). Reserved and out-of-range ports are rejected.
func validate_port(port: int) -> bool:
	return port >= MIN_PORT and port <= MAX_PORT


## True for a dotted IPv4 or IPv6 address, or the name "localhost". Empty or garbage text is rejected.
func validate_ip(address: String) -> bool:
	if address == LOCALHOST_NAME:
		return true
	return address.is_valid_ip_address()


## Opens a server on the port (the host). Returns OK, or an error without opening anything.
func host(port: int) -> Error:
	if not validate_port(port):
		return ERR_INVALID_PARAMETER
	close()
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_server(port)
	if err != OK:
		close()
		return err
	_is_host = true
	return err


## Connects to a host at address:port (the client). Returns OK, or an error without connecting.
func join(address: String, port: int) -> Error:
	if not validate_ip(address) or not validate_port(port):
		return ERR_INVALID_PARAMETER
	close()
	_peer = ENetMultiplayerPeer.new()
	var err: Error = _peer.create_client(address, port)
	if err != OK:
		close()
		return err
	_is_host = false
	return err


## The ENet peer in use, or null when no connection is open. The lobby hands it to the scene multiplayer.
func get_peer() -> ENetMultiplayerPeer:
	return _peer


## True when this lobby hosts the match (the authority). A client returns false.
func is_host() -> bool:
	return _is_host and _peer != null


## Closes the current peer, if any. Safe to call when nothing is open.
func close() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	_is_host = false
