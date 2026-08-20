extends Node
## Hosts or joins a coop session and keeps the roster of who is in it.
##
## Deliberately the only script in the project that touches ENet or
## `multiplayer.multiplayer_peer`. Everything else asks this node questions
## ("am I the host?", "who is playing?") rather than reaching into the
## MultiplayerAPI, so swapping the transport later - Steam P2P is the likely
## next one - is a change to this file and nothing else.
##
## Single player is not a special case anywhere in the codebase: with no peer
## assigned, Godot reports unique_id 1 and every node answers true to
## is_multiplayer_authority(). A solo run is simply a session of one that never
## opened a socket, which is why the gameplay scripts can gate on authority
## without ever asking whether networking is on.

signal player_joined(peer_id: int, info: Dictionary)
signal player_left(peer_id: int)
## The roster changed for any reason - lobby UI redraws off this one signal.
signal roster_changed()
## Join attempt failed before the session started (bad address, host is full,
## nobody listening). Carries a message already fit to show a player.
signal join_failed(reason: String)
## The host went away mid-run. Clients get kicked back to the menu on this.
signal host_disconnected()

const DEFAULT_PORT: int = 27015
## Four is the design target for coop; the arena and wave pacing are tuned
## around it. create_server() takes the client count, so it reserves one slot
## for the host itself.
const MAX_PLAYERS: int = 4
const SERVER_ID: int = 1

## peer_id -> {name: String}. Always contains the local player once a session
## exists, including the host's own entry.
var players: Dictionary = {}

var _peer: ENetMultiplayerPeer = null
## Kept so a client can name itself to the host on connect.
var _local_name: String = ""


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# Public API

## Opens a session others can join. The host plays too - it is a listen server,
## not a dedicated one.
func host_session(player_name: String, port: int = DEFAULT_PORT) -> Error:
	_local_name = _sanitize_name(player_name)
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		push_error("NetworkManager: could not listen on port %d (%d)" % [port, error])
		return error
	_peer = peer
	multiplayer.multiplayer_peer = peer
	players = {SERVER_ID: {"name": _local_name}}
	player_joined.emit(SERVER_ID, players[SERVER_ID])
	roster_changed.emit()
	return OK


func join_session(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	_local_name = _sanitize_name(player_name)
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(address, port)
	if error != OK:
		push_error("NetworkManager: could not reach %s:%d (%d)" % [address, port, error])
		join_failed.emit("No se pudo conectar a %s" % address)
		return error
	_peer = peer
	multiplayer.multiplayer_peer = peer
	return OK


## Tears the session down and returns to the solo-equivalent state, so a player
## who leaves a coop game can start a normal run without restarting the app.
func leave_session() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	roster_changed.emit()


## Tracked through our own peer handle rather than `multiplayer.multiplayer_peer`,
## which is never null: Godot installs an OfflineMultiplayerPeer by default and
## it reports itself as connected. Asking the MultiplayerAPI "are we networked?"
## therefore always answers yes, and an earlier version of this check silently
## made single player look like an empty session - the arena loaded with nobody
## in it. This node creates every peer that exists, so it can just remember.
func is_online() -> bool:
	return _peer != null \
		and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


## True when this instance owns the simulation: enemies, waves and damage
## resolution. Also true in single player, which is what lets the match scripts
## run one code path in both modes.
func is_host() -> bool:
	return not is_online() or multiplayer.is_server()


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else SERVER_ID


## Peers to spawn a body for. Single player answers [1], so the spawn path does
## not branch on the session type either.
func get_peer_ids() -> Array[int]:
	if not is_online():
		return [SERVER_ID]
	var ids: Array[int] = []
	for id: int in players:
		ids.append(id)
	ids.sort()
	return ids


func get_player_name(peer_id: int) -> String:
	var info: Dictionary = players.get(peer_id, {})
	return String(info.get("name", "Jugador %d" % peer_id))


func is_full() -> bool:
	return players.size() >= MAX_PLAYERS


# Private - roster replication
#
# The host owns the roster. Clients never add entries on their own; they get the
# whole table pushed to them, so everyone renders the same lobby and nobody can
# desync by guessing who else connected.

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if is_full():
		# Refusing here rather than at create_server() lets the host answer with
		# something the player can read instead of a silent timeout.
		_reject_peer.rpc_id(peer_id, "La partida esta llena (%d/%d)" % [
			players.size(), MAX_PLAYERS])
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	# The name arrives from the client in _register_self; seat them first so the
	# slot is reserved against a second peer connecting in the same frame.
	players[peer_id] = {"name": "Jugador %d" % peer_id}
	_receive_roster.rpc_id(peer_id, players)
	player_joined.emit(peer_id, players[peer_id])
	roster_changed.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	if not players.has(peer_id):
		return
	players.erase(peer_id)
	if multiplayer.is_server():
		_receive_roster.rpc(players)
	player_left.emit(peer_id)
	roster_changed.emit()


func _on_connected_to_server() -> void:
	_register_self.rpc_id(SERVER_ID, _local_name)


func _on_connection_failed() -> void:
	leave_session()
	join_failed.emit("El host no respondio")


func _on_server_disconnected() -> void:
	leave_session()
	host_disconnected.emit()


## Client -> host: claim a display name. Validated host-side; a client cannot
## name itself into another slot or overwrite anyone else's entry.
@rpc("any_peer", "call_remote", "reliable")
func _register_self(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	players[sender] = {"name": _sanitize_name(player_name)}
	_receive_roster.rpc(players)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_roster(roster: Dictionary) -> void:
	players = roster.duplicate(true)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _reject_peer(reason: String) -> void:
	leave_session()
	join_failed.emit(reason)


## Names go straight into other players' HUDs, so they are length-capped and
## stripped here rather than trusted from the wire.
func _sanitize_name(raw: String) -> String:
	var clean: String = raw.strip_edges().substr(0, 16)
	return clean if not clean.is_empty() else "Jugador"
