extends SceneTree
## Manual harness: joins the match opened by tools/net_smoke_wave_host.gd and
## traces the enemies it was handed. Every one of them should be a puppet, and
## the wave line should track the host's rather than being computed here.

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
				_next_trace = _elapsed + 3.0
				_trace(net)
			if _elapsed > 26.0:
				return true
	return false


func _trace(net: Node) -> void:
	var owned: int = 0
	var puppets: int = 0
	for node: Node in get_nodes_in_group(&"enemy"):
		if not node.get(&"is_active"):
			continue
		if node.get(&"is_remote"):
			puppets += 1
		else:
			owned += 1
	var waves: Node = root.get_node_or_null("/root/WaveManager")
	print("CLIENT t=%.0f host=%s scene=%s wave=%d active=%s remaining=%d sim=%d puppets=%d" % [
		_elapsed, net.is_host(),
		current_scene.name if current_scene != null else "<none>",
		waves.current_index, waves.is_wave_active, waves.get_remaining_count(),
		owned, puppets])
