class_name PlayerSpawnController
extends Node
## Puts the player's body in the arena.
##
## The game scene used to carry a single hand-placed Player node. Spawning it
## from here instead keeps the spawn point as data next to the controller that
## uses it, and gives the arena one place to ask for a body rather than a node
## that is already standing there before anything is ready for it.

@export var player_scene: PackedScene
## Where the spawned player is parented.
@export var container: Node3D

## The arena's spawn point.
@export var spawn_point: Vector3 = Vector3(0.0, 0.2, 26.0)

var _spawned: Node3D = null


func _ready() -> void:
	_spawn()


# Private

func _spawn() -> void:
	if player_scene == null or container == null or is_instance_valid(_spawned):
		return
	var body := player_scene.instantiate() as Node3D
	if body == null:
		push_error("PlayerSpawnController: player_scene is not a Node3D")
		return
	body.position = spawn_point
	container.add_child(body, true)
	_spawned = body
