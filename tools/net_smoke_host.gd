extends SceneTree
## Manual harness: opens a session and reports who showed up.
##
## The unit tests can assert what a session of one looks like, but nothing in
## GUT opens a socket - two processes have to actually find each other. This is
## how that gets checked:
##
##   godot --headless --path . -s res://tools/net_smoke_host.gd &
##   sleep 2
##   godot --headless --path . -s res://tools/net_smoke_client.gd
##
## Both sides print their roster. The host should list two seats with the names
## each side chose; the client should report is_host=false and a peer id that is
## not 1. Mind the windows - each script quits on its own timer, and whichever
## outlives the other will correctly report the roster after the disconnect.
##
## Autoloads are fetched by path, not by their global identifier: a script
## passed to -s is compiled before the autoloads are registered, so the name
## NetworkManager does not resolve at compile time here.

var _elapsed: float = 0.0
var _started: bool = false


func _process(delta: float) -> bool:
	var net: Node = root.get_node_or_null("/root/NetworkManager")
	if net == null:
		print("HOST: NetworkManager autoload missing")
		return true

	if not _started:
		_started = true
		print("HOST: host_session -> ", net.host_session("ElHost"))

	_elapsed += delta
	if _elapsed < 8.0:
		return false

	print("HOST: online=", net.is_online(), " is_host=", net.is_host())
	print("HOST: local_id=", net.local_id())
	print("HOST: peers=", net.get_peer_ids())
	for peer_id: int in net.get_peer_ids():
		print("HOST:   seat ", peer_id, " -> ", net.get_player_name(peer_id))
	return true
