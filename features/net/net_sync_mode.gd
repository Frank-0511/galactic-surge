# net_sync_mode.gd
# Session modes of a coop match (Etapa 20, S6). LOCAL_COOP: J2 is driven by keyboard or gamepad on
# this PC (the existing coop). NETWORK: J2 is the remote peer; the host simulates it from the client's input.
# The player picks the mode in the main menu before the session starts. Singleplayer has no J2 and no mode.

extends RefCounted

const LOCAL_COOP: int = 0
const NETWORK: int = 1
const DEFAULT_MODE: int = LOCAL_COOP


## True when the chosen mode takes J2 from the network.
static func is_network(mode: int) -> bool:
	return mode == NETWORK
