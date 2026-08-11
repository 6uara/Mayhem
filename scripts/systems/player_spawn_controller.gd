class_name PlayerSpawnController
extends Node
## Puts a body in the arena for every peer in the session, host included.
##
## The game scene used to carry a single hand-placed Player node. That is the one
## thing coop cannot keep: the number of players is not known until the session
## exists. Spawning them all from here means single player is just a session of
## one, and there is no second code path to keep in sync with this one.
##
## Only the host spawns. The MultiplayerSpawner sitting next to this node
## replicates each add_child() out to the clients, so a late joiner receives the
## players already in the arena without any catch-up logic here.

@export var player_scene: PackedScene
## Where spawned players are parented. Must be the MultiplayerSpawner's
## spawn_path, or the replication never leaves this machine.
@export var container: Node3D

## Spread around the arena's original solo spawn so four players do not
## telefrag each other into the ceiling on the first frame.
@export var spawn_points: Array[Vector3] = [
	Vector3(0.0, 0.2, 26.0),
	Vector3(4.0, 0.2, 26.0),
	Vector3(-4.0, 0.2, 26.0),
	Vector3(0.0, 0.2, 30.0),
]

var _spawned: Dictionary = {}  # peer_id -> Player


func _ready() -> void:
	NetworkManager.player_left.connect(_on_player_left)
	if NetworkManager.is_host():
		# Our own body only. Everyone else's waits for them to say they are
		# standing in the arena - see _announce_ready().
		_spawn_for(NetworkManager.local_id())
		return
	_announce_ready.rpc_id(NetworkManager.SERVER_ID)


# Private

## Client -> host: "my arena is loaded, spawn me".
##
## The host cannot simply spawn every peer the moment the match starts. Peers
## change scene at their own pace, and a MultiplayerSpawner only reaches nodes
## that already exist on the receiving end - a body spawned before the client's
## scene was up would be dropped on the floor, leaving that player with no
## character and no error explaining why. Waiting for the peer to speak first
## makes the ordering explicit instead of a race we would lose intermittently.
@rpc("any_peer", "call_remote", "reliable")
func _announce_ready() -> void:
	if not multiplayer.is_server():
		return
	_spawn_for(multiplayer.get_remote_sender_id())


func _on_player_left(peer_id: int) -> void:
	if not NetworkManager.is_host():
		return
	var body: Node = _spawned.get(peer_id)
	_spawned.erase(peer_id)
	if is_instance_valid(body):
		# queue_free on the host propagates through the spawner as a despawn.
		body.queue_free()


func _spawn_for(peer_id: int) -> void:
	if player_scene == null or container == null or _spawned.has(peer_id):
		return
	var body := player_scene.instantiate() as Node3D
	if body == null:
		push_error("PlayerSpawnController: player_scene is not a Node3D")
		return
	# The name carries the owning peer id: Player._enter_tree() reads it back to
	# claim authority, and it survives replication, so every machine agrees on
	# who drives this body without a second message.
	body.name = str(peer_id)
	body.position = _spawn_position_for(peer_id)
	container.add_child(body, true)
	_spawned[peer_id] = body


func _spawn_position_for(peer_id: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	# Index by join order rather than peer id - ENet ids are arbitrary and would
	# scatter players across the list, reusing the same point for two of them.
	var order: int = maxi(NetworkManager.get_peer_ids().find(peer_id), 0)
	return spawn_points[order % spawn_points.size()]
