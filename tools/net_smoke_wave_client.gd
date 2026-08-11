extends SceneTree
## Manual harness: joins the match opened by tools/net_smoke_wave_host.gd and
## traces what it sees. Both harnesses stand still, so the enemies eventually
## kill them - which is exactly what makes this the spectator test too.
##
## What to look for: the client's own body flips downed=true, spectating turns
## on with a target name, and it keeps watching until nobody is left standing.

var _elapsed: float = 0.0
var _phase: int = 0
var _next_trace: float = 0.0


func _process(delta: float) -> bool:
	var net: Node = root.get_node_or_null("/root/NetworkManager")
	if net == null:
		print("CLIENT: autoloads missing")
		return true

	_elapsed += delta
	match _phase:
		0:
			_phase = 1
			net.join_failed.connect(func(reason: String) -> void:
				print("CLIENT: join_failed -> ", reason))
			print("CLIENT: join_session -> ", net.join_session("127.0.0.1", "ElAmigo"))
		1:
			if _elapsed > _next_trace:
				_next_trace = _elapsed + 4.0
				_trace(net)
			if _elapsed > 60.0:
				return true
	return false


func _trace(net: Node) -> void:
	var puppets: int = 0
	for node: Node in get_nodes_in_group(&"enemy"):
		if node.get(&"is_active") and node.get(&"is_remote"):
			puppets += 1

	var alive: int = 0
	var mine_downed: Variant = "<none>"
	for node: Node in get_nodes_in_group(&"player"):
		if not node.get(&"is_downed"):
			alive += 1
		if node.name.to_int() == net.local_id():
			mine_downed = node.get(&"is_downed")

	var spectator: Node = null
	if current_scene != null:
		spectator = current_scene.get_node_or_null("SpectatorView")
	var watching: Variant = spectator.get(&"_is_spectating") if spectator != null else "<no node>"
	var target: Node = spectator.get(&"_target") if spectator != null else null

	print("CLIENT t=%.0f puppets=%d players_alive=%d mine_downed=%s spectating=%s target=%s" % [
		_elapsed, puppets, alive, mine_downed, watching,
		target.name if target != null else "-"])
