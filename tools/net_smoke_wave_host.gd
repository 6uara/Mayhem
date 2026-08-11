extends SceneTree
## Manual harness: hosts a coop match, runs it into the first waves, and traces
## what is standing in the arena. Pair with tools/net_smoke_wave_client.gd:
##
##   godot --headless --path . -s res://tools/net_smoke_wave_host.gd &
##   sleep 2
##   godot --headless --path . -s res://tools/net_smoke_wave_client.gd
##
## What proves the replication works is the two traces agreeing on the enemy
## count while disagreeing on who owns them: the host's are all simulated, the
## client's are all puppets.

var _elapsed: float = 0.0
var _phase: int = 0
var _next_trace: float = 0.0


func _process(delta: float) -> bool:
	var net: Node = root.get_node_or_null("/root/NetworkManager")
	var game: Node = root.get_node_or_null("/root/GameManager")
	if net == null or game == null:
		print("HOST: autoloads missing")
		return true

	_elapsed += delta
	match _phase:
		0:
			_phase = 1
			print("HOST: host_session -> ", net.host_session("ElHost"))
		1:
			if _elapsed > 5.0:
				_phase = 2
				print("HOST: roster at start -> ", net.get_peer_ids())
				game.start_coop_run()
		2:
			if _elapsed > _next_trace:
				_next_trace = _elapsed + 4.0
				_trace()
			if _elapsed > 64.0:
				return true
	return false


func _trace() -> void:
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
	var state: Node = root.get_node_or_null("/root/GameManager")
	print("HOST t=%.0f scene=%s state=%d wave=%d active=%s remaining=%d sim=%d puppets=%d" % [
		_elapsed,
		current_scene.name if current_scene != null else "<none>",
		int(state.state), waves.current_index, waves.is_wave_active,
		waves.get_remaining_count(), owned, puppets])
