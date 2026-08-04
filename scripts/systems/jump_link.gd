class_name JumpLink
extends NavigationLink3D
## A route the navmesh cannot bake: a gap or a ledge the enemy crosses by jumping.
##
## With the ramps gone, the raised platforms are separate navmesh islands, and an
## island is a place enemies simply never go. A NavigationLink3D tells the pathfinder
## "these two points connect, at this cost", and the enemy executes the crossing as a
## ballistic hop rather than by walking.
##
## Cyan, because it is traversal - the player can take the same line with a dash or
## the grapple, and the arena should say so.

## How long the hop is allowed to take. Longer links need a higher arc, so this also
## sets how floaty the jump looks.
@export var flight_time: float = 0.75
@export var telegraph: TelegraphComponent
## Drawn at each end so the route is visible rather than a secret the AI keeps.
@export var start_marker: MeshInstance3D
@export var end_marker: MeshInstance3D


func _ready() -> void:
	add_to_group(&"jump_link")
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.AVAILABLE
	_place_markers()


# Public API

func get_start_global() -> Vector3:
	return global_transform * start_position


func get_end_global() -> Vector3:
	return global_transform * end_position


## The end nearest `from`, so an enemy approaching either side takes the right one.
func get_exit_for(from: Vector3) -> Vector3:
	var start: Vector3 = get_start_global()
	var end: Vector3 = get_end_global()
	return end if from.distance_squared_to(start) < from.distance_squared_to(end) else start


## Launch velocity for a ballistic arc that lands on the far end.
##
## Solved rather than tuned: horizontal speed is distance over flight time, and the
## vertical component is whatever it takes to arrive at the right height under the
## enemy's own gravity. Anything else drifts as the link lengths change.
func get_launch_velocity(from: Vector3, to: Vector3, gravity: float) -> Vector3:
	var time: float = maxf(flight_time, 0.1)
	var offset: Vector3 = to - from
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	var velocity: Vector3 = horizontal / time
	velocity.y = offset.y / time + 0.5 * gravity * time
	return velocity


# Private

func _place_markers() -> void:
	if start_marker != null:
		start_marker.global_position = get_start_global() + Vector3.UP * 0.1
	if end_marker != null:
		end_marker.global_position = get_end_global() + Vector3.UP * 0.1
