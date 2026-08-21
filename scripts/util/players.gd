class_name Players
extends RefCounted
## Finds player bodies in the arena. Static utility, like PhysicsLayers.
##
## Replaces the `get_first_node_in_group(&"player")` calls that were scattered
## across the HUD, the AI and the arena props. That idiom was correct while
## exactly one player existed; with coop it silently returns whichever body
## happened to spawn first, which is the wrong one on most machines.
##
## The distinction the old call could not express is the one that matters here:
##
##   - `local()`  - the body this machine drives. Anything on screen for *me*:
##                  HUD binding, the reticle, damage indicators, hint prompts.
##   - `nearest()` - the closest player to a point. Anything in the world that
##                  reacts to whoever is actually near it: enemy targeting,
##                  proximity triggers.
##
## Picking the wrong one is not a crash, it is a subtle bug (an enemy chasing a
## player on the other side of the arena, a HUD showing someone else's health),
## so callers name the semantics they want.

## The body owned by this peer. Null between scene load and the spawner placing
## it - callers that run at _ready() time must handle that, since on a client
## the player arrives over the network a few frames later.
static func local() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"local_player") as Node3D


static func all() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return found
	for node: Node in tree.get_nodes_in_group(&"player"):
		var body := node as Node3D
		if body != null and is_instance_valid(body):
			found.append(body)
	return found


## Closest living player to `origin`, or null when everyone is down. Dead
## players are skipped so the AI does not keep chasing a corpse while a live
## player shoots it in the back.
static func nearest(origin: Vector3, require_alive: bool = true) -> Node3D:
	var best: Node3D = null
	var best_distance: float = INF
	for body: Node3D in all():
		if require_alive and not is_alive(body):
			continue
		var distance: float = origin.distance_squared_to(body.global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


static func is_alive(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var player := body as Player
	if player == null:
		return true
	return player.health == null or not player.health.is_dead


## Players still in the fight. The match ends when this hits zero, and the
## spectator camera picks its target from it.
static func alive() -> Array[Node3D]:
	var living: Array[Node3D] = []
	for body: Node3D in all():
		if is_alive(body):
			living.append(body)
	return living
