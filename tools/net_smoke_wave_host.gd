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
##
## Both harnesses stand still, which used to mean both were dead inside twenty
## seconds and the run was over before a wave was ever cleared - the whole
## between-wave flow went untested. They make themselves invulnerable and shoot
## instead, so the wave clears, the break opens on both peers at once, the shop
## timer readies them, and wave two starts. That sequence in the two traces is
## the thing to read.

var _elapsed: float = 0.0
var _phase: int = 0
var _next_trace: float = 0.0
var _next_shot: float = 0.0
var _client_downed: bool = false


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
			_make_players_unkillable()
			if _elapsed > 12.0 and not _client_downed:
				_client_downed = true
				_drop_the_client()
			if _elapsed > _next_shot:
				_next_shot = _elapsed + 1.0
				_shoot_something()
			if _elapsed > _next_trace:
				_next_trace = _elapsed + 4.0
				_trace()
			# Long enough to clear a wave and sit through the whole break: the
			# shop opens on both peers, the 30s timer readies them, and the next
			# wave starts for everyone at once.
			if _elapsed > 110.0:
				return true
	return false


## Nobody here can dodge, and a harness that dies in wave one never reaches the
## part of the run this is meant to exercise. Set from the host, which is where
## damage to any player is resolved.
##
## Its own body only, deliberately. The client is left mortal so it goes down
## during the wave and the break has somebody to stand back up: `downed` flipping
## from true to false when the shop opens is the only proof the revive works,
## and a session where nobody can die never produces it.
func _make_players_unkillable() -> void:
	for node: Node in get_nodes_in_group(&"player"):
		if node.name.to_int() != 1:
			continue
		var health: Node = node.get_node_or_null("HealthComponent")
		if health != null:
			health.set(&"is_invulnerable", true)


## Kills the client's player outright, mid-wave.
##
## Not cheating the test: this is the same thing an enemy does, in the same
## place. A player's damage is resolved on the host, always - which is why the
## client's own health component never fires a died() of its own. Doing it on
## purpose is the only way to get a reliable death out of a harness that clears
## its own waves before the horde arrives.
##
## What follows is the sequence worth reading in the client's trace: downed goes
## true, spectating goes true, and both go back to false the moment the shop
## opens. That is the revive.
func _drop_the_client() -> void:
	for node: Node in get_nodes_in_group(&"player"):
		if node.name.to_int() == 1:
			continue
		var health: Node = node.get_node_or_null("HealthComponent")
		if health == null:
			continue
		print("HOST: dropping peer ", node.name)
		health.call(&"apply_damage", 9999.0)


## One enemy per second, killed outright through the host's own damage path.
## Enough to clear a six-enemy wave inside the trace window without pretending
## to be a player who can aim.
func _shoot_something() -> void:
	for node: Node in get_nodes_in_group(&"enemy"):
		var enemy: Node = node
		if not enemy.get(&"is_active") or enemy.get(&"is_remote"):
			continue
		var hitbox: Node = enemy.get(&"body_hitbox")
		if hitbox == null:
			continue
		hitbox.call(&"take_hit", 500.0, enemy.get(&"global_position"))
		return


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
	var economy: Node = root.get_node_or_null("/root/EconomyManager")
	print(("HOST t=%.0f scene=%s state=%d wave=%d active=%s remaining=%d sim=%d "
		+ "puppets=%d money=%d shop=%s") % [
		_elapsed,
		current_scene.name if current_scene != null else "<none>",
		int(state.state), waves.current_index, waves.is_wave_active,
		waves.get_remaining_count(), owned, puppets,
		int(economy.currency), _shop_state()])


## The wave break is the half of this that the enemy count cannot show: both
## traces should sit in shop=open together and leave it on the same tick, with
## each side's money moving by what it personally earned.
func _shop_state() -> String:
	if current_scene == null:
		return "<no scene>"
	var shop: Node = current_scene.get_node_or_null("ShopScreen")
	if shop == null:
		return "<no node>"
	if not bool(shop.get(&"is_open")):
		return "closed"
	return "waiting" if bool(shop.get(&"_is_waiting")) else "open"
