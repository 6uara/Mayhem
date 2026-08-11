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
	hitbox.take_hit(clampf(damage, 0.0, MAX_REPORTED_DAMAGE), hit_position)


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
	var count: int = mini(ids.size() / 2, transforms.size() / 4)
	for i: int in count:
		var net_id: int = ids[i * 2]
		var type_index: int = ids[i * 2 + 1]
		var position := Vector3(transforms[i * 4], transforms[i * 4 + 1],
			transforms[i * 4 + 2])
		var yaw: float = transforms[i * 4 + 3]
		seen[net_id] = true

		var puppet: Enemy = _puppets.get(net_id)
		if puppet == null or not is_instance_valid(puppet) or not puppet.is_active:
			puppet = _make_puppet(net_id, type_index, position)
			if puppet == null:
				continue
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
