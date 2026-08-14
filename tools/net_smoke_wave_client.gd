extends SceneTree
## Manual harness: joins the match opened by tools/net_smoke_wave_host.gd,
## traces what it sees, and at t=14 shoots one enemy dead.
##
## The kill is the point. It drives the exact path a client's bullet takes -
## report_hit() -> rpc to the host -> the host's own enemy takes the damage -
## and what proves it landed is both sides dropping from 6 enemies to 5. A
## client that killed only its own copy would show 5 here and 6 on the host.
##
## Both harnesses stand still otherwise, so the enemies eventually kill them,
## which is what also makes this the spectator test - and, now that the wave
## break stands the fallen back up, the revive test: `downed` has to go back to
## false on both peers the moment the shop opens.
##
## The other two things to read in the trace are money and shop. The kill above
## must move this client's money and not the host's, and both peers must sit in
## the break together and leave it on the same tick.

var _elapsed: float = 0.0
var _phase: int = 0
var _next_trace: float = 0.0
var _shot_at: int = 0
var _next_shot: float = 0.0


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
			if _elapsed > 14.0 and _shot_at == 0:
				_shoot_one()
			# One puppet a second after the first kill, so this peer keeps
			# earning while the host clears its side. Two wallets moving
			# independently is what the money column is there to show.
			if _elapsed > 20.0 and _elapsed > _next_shot:
				_next_shot = _elapsed + 1.0
				_keep_shooting()
			if _elapsed > _next_trace:
				_next_trace = _elapsed + 4.0
				_trace(net)
			if _elapsed > 106.0:
				return true
	return false


## Fires the client's damage path at one puppet, hard enough to kill it.
func _shoot_one() -> void:
	var scene: Node = current_scene
	if scene == null:
		return
	var replicator: Node = scene.get_node_or_null("EnemyReplicator")
	if replicator == null:
		print("CLIENT: no EnemyReplicator in the scene")
		return
	for node: Node in get_nodes_in_group(&"enemy"):
		if not node.get(&"is_active") or not node.get(&"is_remote"):
			continue
		_shot_at = node.get(&"net_id")
		var hitbox: Node = node.get(&"body_hitbox")
		print("CLIENT: shooting net_id=", _shot_at)
		for _i: int in 4:
			replicator.report_hit(hitbox, 200.0, node.global_position)
		return


## The same client damage path as _shoot_one(), on a loop and without the
## bookkeeping - by this point what is being watched is the wallet, not one
## particular enemy.
func _keep_shooting() -> void:
	var scene: Node = current_scene
	if scene == null:
		return
	var replicator: Node = scene.get_node_or_null("EnemyReplicator")
	if replicator == null:
		return
	for node: Node in get_nodes_in_group(&"enemy"):
		if not node.get(&"is_active") or not node.get(&"is_remote"):
			continue
		replicator.report_hit(node.get(&"body_hitbox"), 500.0, node.global_position)
		return


func _trace(net: Node) -> void:
	var puppets: int = 0
	var still_there: bool = false
	for node: Node in get_nodes_in_group(&"enemy"):
		if node.get(&"is_active") and node.get(&"is_remote"):
			puppets += 1
			if _shot_at != 0 and node.get(&"net_id") == _shot_at:
				still_there = true

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

	var shop: Node = null
	if current_scene != null:
		shop = current_scene.get_node_or_null("ShopScreen")
	var shop_state: Variant = "<no node>"
	if shop != null:
		shop_state = "closed" if not bool(shop.get(&"is_open")) \
			else ("waiting" if bool(shop.get(&"_is_waiting")) else "open")
	var economy: Node = root.get_node_or_null("/root/EconomyManager")

	# money is the client-side half of the kill credit: it must move when this
	# harness shoots something dead, and not when the host kills its own.
	# downed going back to false across the break is the revive.
	print(("CLIENT t=%.0f puppets=%d shot(%d)_alive=%s players_alive=%d downed=%s "
		+ "spectating=%s money=%d shop=%s") % [
		_elapsed, puppets, _shot_at, still_there, alive, mine_downed, watching,
		int(economy.currency) if economy != null else -1, shop_state])
