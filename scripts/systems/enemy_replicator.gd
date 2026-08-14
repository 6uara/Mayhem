class_name EnemyReplicator
extends Node
## Mirrors the host's enemies onto every client, and the wave state with them.
##
## Enemies deliberately do not go through MultiplayerSpawner. They are pooled:
## ObjectPool keeps them parented under its own autoload, recycles them instead
## of freeing them, and "despawns" one by moving it below the floor. There is no
## add_child on a match scene for a spawner to notice and no queue_free for it to
## replicate, so the built-in path would have meant unwinding the pool - and the
## pool exists because instantiating a full elite wave hitches.
##
## What travels instead is a snapshot: who is alive, of what type, and where.
## The client keeps a mirror of pooled puppets keyed by the host's net_id.
##
## Absence is the despawn signal. An enemy missing from a snapshot is gone,
## which means deaths need no separate message and a dropped packet cannot
## strand a corpse on a client forever - the next snapshot corrects it. The cost
## is that a client's death effect fires when the news arrives rather than on
## the exact frame of the kill, which for a horde shooter is not a difference
## anyone can see.

## Snapshots per second. Enemies move at walking pace and clients interpolate,
## so this buys little above 20 and costs bandwidth linearly.
const SEND_RATE: float = 20.0
## How hard a puppet is pulled toward its last known position. High enough to
## keep up with a charging rusher, low enough to smooth packet jitter.
const INTERP_SPEED: float = 14.0
const CATALOG_DIR: String = "res://data/enemies/"
## Ints per enemy in a snapshot: net_id, type index, wind-up percent.
const FIELDS_PER_ENEMY: int = 3

## A client may not claim more than this in one hit. Not anti-cheat - the
## movement is client-authoritative anyway, and this is a game for friends - just
## a bound so a corrupted or badly-scaled value cannot one-shot a whole wave.
const MAX_REPORTED_DAMAGE: float = 500.0

@export var enemy_scene: PackedScene

## The live replicator, for callers that cannot reach it through the tree.
##
## Projectiles are pooled under the ObjectPool autoload and get generated node
## names, so their paths do not match across peers and they cannot carry an rpc
## of their own. They route damage through here, which does sit at a stable path.
static var instance: EnemyReplicator

## Enemy types in a stable order. The index is what goes on the wire, and it is
## derived by sorting the catalog by id so host and client agree without having
## to send a resource path per enemy.
var _catalog: Array[EnemyData] = []
var _index_of: Dictionary = {}  # StringName -> int

var _next_net_id: int = 1
var _puppets: Dictionary = {}  # net_id -> Enemy
var _targets: Dictionary = {}  # net_id -> Vector4(x, y, z, yaw)
var _send_countdown: float = 0.0


func _ready() -> void:
	instance = self
	_build_catalog()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _physics_process(delta: float) -> void:
	# Solo runs never pay for any of this: no peer, no snapshots, and the enemies
	# are simulated locally exactly as they always were.
	if not NetworkManager.is_online():
		return
	if not NetworkManager.is_host():
		_interpolate(delta)
		return
	_send_countdown -= delta
	if _send_countdown > 0.0:
		return
	_send_countdown = 1.0 / SEND_RATE
	_broadcast()


# Damage

## Routes a hit to whoever is entitled to apply it.
##
## Clients still raycast locally - that is what keeps shooting feel immediate,
## and it lets them draw their own hitmarker on the frame they pulled the
## trigger. But the hit they found is a request, not a result. Applying it
## locally as well would kill the enemy twice: once here, where nobody else
## agrees it happened, and again when the host works through the same shot.
func report_hit(hitbox: HitboxComponent, damage: float, hit_position: Vector3) -> void:
	if hitbox == null:
		return
	if not NetworkManager.is_online() or NetworkManager.is_host():
		# Ours. Claim the bounty before the hit lands, since the hit is what may
		# kill it - claiming afterwards would credit nobody for the killing blow.
		var mine := hitbox.owner as Enemy
		if mine != null:
			mine.last_damager = 0
		hitbox.take_hit(damage, hit_position)
		return

	var target := hitbox.owner as Enemy
	# Anything that is not a replicated enemy - a target dummy in the practice
	# range - is nobody's business but this machine's.
	if target == null or target.net_id == 0:
		hitbox.take_hit(damage, hit_position)
		return


	_receive_hit.rpc_id(NetworkManager.SERVER_ID, target.net_id, damage,
		hitbox.is_headshot_zone, hit_position)
	# Optimistic feedback: the hitmarker and damage number fire now rather than
	# after a round trip. The host may resolve a slightly different number - the
	# enemy could already be dead - but a hitmarker that lags the shot by a ping
	# is worse than one that is occasionally generous.
	EventBus.damage_dealt.emit(target, damage, hitbox.is_headshot_zone)


@rpc("any_peer", "call_remote", "reliable")
func _receive_hit(net_id: int, damage: float, is_headshot: bool,
		hit_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var target: Enemy = _find_owned(net_id)
	if target == null or not target.is_active:
		# Already dead, or never existed. Both are ordinary: the client fired at
		# what it could see, which is always a little behind what the host knows.
		return
	var hitbox: HitboxComponent = target.head_hitbox if is_headshot else target.body_hitbox
	if hitbox == null:
		hitbox = target.body_hitbox
	if hitbox == null:
		return
	target.last_damager = multiplayer.get_remote_sender_id()
	hitbox.take_hit(clampf(damage, 0.0, MAX_REPORTED_DAMAGE), hit_position)


# Kill credit
#
# Kills are resolved on the host and paid on whichever machine earned them. The
# arithmetic stays local everywhere: what crosses the wire is the bare fact that
# a peer killed something worth this much, and that peer's own EconomyManager
# scales and banks it exactly as it would in a solo run.

## Hands the bounty for a kill to `peer_id`. Returns true when the money left
## this machine, so the caller knows not to pay itself as well.
func credit_kill(peer_id: int, enemy_type: StringName, position: Vector3,
		reward: int) -> bool:
	if not NetworkManager.is_online() or not NetworkManager.is_host():
		return false
	if peer_id == 0 or peer_id == NetworkManager.SERVER_ID:
		return false
	# A peer that left mid-wave still has enemies it last hit. Nobody is there to
	# be paid, and rpc_id to a dead peer is an error, so the money is dropped.
	if not NetworkManager.players.has(peer_id):
		return true
	_receive_kill_credit.rpc_id(peer_id, enemy_type, position, reward)
	return true


## The kill lands on the client as both events: enemy_killed so the reticle
## flashes a kill marker and the announcer reacts to what this player did, and
## kill_credited so it gets paid. WaveManager ignores the first one off-host -
## the wave count belongs to the snapshot.
# Attacks
#
# What a wave does to you is not in the snapshot. Snapshots say where everything
# is standing; the attacks are the moments in between, and on a client none of
# them happened - the puppets have no brain, so nothing fired, nothing swung and
# nothing lit up. That left a client watching its health drop with an empty
# screen in front of it, which reads as the game cheating rather than as an enemy
# getting a hit in.
#
# Each attack is broadcast as the event it is. The damage stays where it was
# resolved, on the host; what travels is what a player has to see to react.

## Host: an enemy fired. Clients fly their own harmless copy of the shot.
func broadcast_projectile(enemy: Enemy, origin: Vector3, direction: Vector3) -> void:
	if not _can_broadcast(enemy):
		return
	_receive_projectile.rpc(enemy.net_id, origin, direction)


## Unreliable: a shot that arrives late is worse than one that never arrives.
## The projectile is a warning to move, and a warning delivered after the round
## has already landed on the host is just a confusing sprite.
@rpc("authority", "call_remote", "unreliable")
func _receive_projectile(net_id: int, origin: Vector3, direction: Vector3) -> void:
	var puppet: Enemy = _puppets.get(net_id)
	if puppet == null or not is_instance_valid(puppet) or puppet.data == null:
		return
	var scene: PackedScene = puppet.data.projectile_scene
	if scene == null:
		return
	var shot := ObjectPool.acquire(scene) as EnemyProjectile
	if shot == null:
		return
	shot.launch_cosmetic(origin, direction, puppet.data.projectile_speed, puppet)
	AudioPool.play_3d(puppet.data.attack_sound, origin, AudioPool.BUS_ENEMIES)


## Host: an enemy connected with a melee swing.
func broadcast_melee(enemy: Enemy) -> void:
	if not _can_broadcast(enemy):
		return
	_receive_melee.rpc(enemy.net_id)


@rpc("authority", "call_remote", "unreliable")
func _receive_melee(net_id: int) -> void:
	var puppet: Enemy = _puppets.get(net_id)
	if puppet == null or not is_instance_valid(puppet) or puppet.data == null:
		return
	AudioPool.play_3d(puppet.data.attack_sound, puppet.global_position,
		AudioPool.BUS_ENEMIES)


## Solo runs broadcast nothing - there is nobody to tell, and rpc() with no peer
## is an error. An enemy with no net_id has never been in a snapshot either, so
## no client has a puppet to hang the event on.
func _can_broadcast(enemy: Enemy) -> bool:
	return NetworkManager.is_online() and NetworkManager.is_host() \
		and enemy != null and enemy.net_id != 0


@rpc("authority", "call_remote", "reliable")
func _receive_kill_credit(enemy_type: StringName, position: Vector3,
		reward: int) -> void:
	var paid: int = maxi(reward, 0)
	EventBus.enemy_killed.emit(enemy_type, position, paid)
	EventBus.kill_credited.emit(paid)


func _find_owned(net_id: int) -> Enemy:
	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Enemy
		if enemy != null and not enemy.is_remote and enemy.net_id == net_id:
			return enemy
	return null


# Host

func _broadcast() -> void:
	var ids := PackedInt32Array()
	var transforms := PackedFloat32Array()

	for node: Node in get_tree().get_nodes_in_group(&"enemy"):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_active or enemy.is_remote:
			continue
		if enemy.data == null or not _index_of.has(enemy.data.id):
			continue
		# Assigned lazily rather than in EnemySpawner, so summoned adds and
		# door spawns get an id through the same door and neither path can
		# forget to hand one out.
		if enemy.net_id == 0:
			enemy.net_id = _next_net_id
			_next_net_id += 1
		ids.push_back(enemy.net_id)
		ids.push_back(int(_index_of[enemy.data.id]))
		# Quantised to a percent: it drives an emission multiplier, and nobody
		# can see the difference between 0.61 and 0.62 of a glow.
		ids.push_back(int(round(enemy.windup_progress * 100.0)))
		transforms.push_back(enemy.global_position.x)
		transforms.push_back(enemy.global_position.y)
		transforms.push_back(enemy.global_position.z)
		transforms.push_back(enemy.rotation.y)

	_receive.rpc(ids, transforms, WaveManager.current_index,
		WaveManager.is_wave_active, WaveManager.get_remaining_count(),
		WaveManager.get_wave_duration())


# Client

## Unreliable: a lost snapshot is replaced by the next one 50ms later, and
## resending stale positions would only queue up work behind fresher truth.
@rpc("authority", "call_remote", "unreliable_ordered")
func _receive(ids: PackedInt32Array, transforms: PackedFloat32Array,
		wave_index: int, wave_active: bool, remaining: int, duration: float) -> void:
	WaveManager.apply_remote_state(wave_index, wave_active, remaining, duration)

	var seen: Dictionary = {}
	# Three ints and four floats per enemy. Both arrays are read against the same
	# count so a truncated packet drops whole enemies rather than reading one of
	# them out of the middle of another's numbers.
	var count: int = mini(ids.size() / FIELDS_PER_ENEMY, transforms.size() / 4)
	for i: int in count:
		var net_id: int = ids[i * FIELDS_PER_ENEMY]
		var type_index: int = ids[i * FIELDS_PER_ENEMY + 1]
		var windup: float = float(ids[i * FIELDS_PER_ENEMY + 2]) / 100.0
		var position := Vector3(transforms[i * 4], transforms[i * 4 + 1],
			transforms[i * 4 + 2])
		var yaw: float = transforms[i * 4 + 3]
		seen[net_id] = true

		var puppet: Enemy = _puppets.get(net_id)
		if puppet == null or not is_instance_valid(puppet) or not puppet.is_active:
			puppet = _make_puppet(net_id, type_index, position)
			if puppet == null:
				continue
		puppet.windup_progress = windup
		_targets[net_id] = Vector4(position.x, position.y, position.z, yaw)

	_retire_unseen(seen)


func _make_puppet(net_id: int, type_index: int, position: Vector3) -> Enemy:
	if enemy_scene == null or type_index < 0 or type_index >= _catalog.size():
		return null
	var puppet := ObjectPool.acquire(enemy_scene) as Enemy
	if puppet == null:
		return null
	puppet.net_id = net_id
	# Set before setup(): it is what stops setup() building a behaviour tree,
	# and a puppet that grows a brain will walk away from its own snapshot.
	puppet.is_remote = true
	puppet.setup(_catalog[type_index], position)
	_puppets[net_id] = puppet
	return puppet


func _retire_unseen(seen: Dictionary) -> void:
	for net_id: int in _puppets.keys():
		if seen.has(net_id):
			continue
		var puppet: Enemy = _puppets[net_id]
		_puppets.erase(net_id)
		_targets.erase(net_id)
		if is_instance_valid(puppet):
			puppet.despawn_remote()


## Puppets are moved here rather than snapped on arrival: at 20 snapshots a
## second, snapping reads as a strobe rather than as an enemy running at you.
func _interpolate(delta: float) -> void:
	var weight: float = clampf(INTERP_SPEED * delta, 0.0, 1.0)
	for net_id: int in _puppets:
		var puppet: Enemy = _puppets[net_id]
		if not is_instance_valid(puppet) or not _targets.has(net_id):
			continue
		var target: Vector4 = _targets[net_id]
		puppet.global_position = puppet.global_position.lerp(
			Vector3(target.x, target.y, target.z), weight)
		puppet.rotation.y = lerp_angle(puppet.rotation.y, target.w, weight)


# Private

func _build_catalog() -> void:
	_catalog.clear()
	_index_of.clear()
	var dir := DirAccess.open(CATALOG_DIR)
	if dir == null:
		push_error("EnemyReplicator: cannot read %s" % CATALOG_DIR)
		return
	var names: Array[String] = []
	for file: String in dir.get_files():
		# Exported builds see .remap next to the imported resource.
		if file.ends_with(".tres") or file.ends_with(".tres.remap"):
			names.append(file.trim_suffix(".remap"))
	# Sorted so the index a type gets is identical on every machine without
	# anyone having to agree on it at runtime.
	names.sort()
	for file: String in names:
		var data := load(CATALOG_DIR + file) as EnemyData
		if data == null:
			continue
		_index_of[data.id] = _catalog.size()
		_catalog.append(data)
