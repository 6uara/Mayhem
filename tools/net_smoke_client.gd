extends SceneTree
## Throwaway harness: joins the session opened by tools/net_smoke_host.gd.

var _elapsed: float = 0.0
var _started: bool = false


func _process(delta: float) -> bool:
	var net: Node = root.get_node_or_null("/root/NetworkManager")
	if net == null:
		print("CLIENT: NetworkManager autoload missing")
		return true

	if not _started:
		_started = true
		net.join_failed.connect(func(reason: String) -> void:
			print("CLIENT: join_failed -> ", reason))
		print("CLIENT: join_session -> ", net.join_session("127.0.0.1", "ElAmigo"))

	_elapsed += delta
	if _elapsed < 3.0:
		return false

	print("CLIENT: online=", net.is_online(), " is_host=", net.is_host())
	print("CLIENT: local_id=", net.local_id())
	print("CLIENT: peers=", net.get_peer_ids())
	for peer_id: int in net.get_peer_ids():
		print("CLIENT:   seat ", peer_id, " -> ", net.get_player_name(peer_id))
	return true
