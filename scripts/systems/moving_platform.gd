class_name MovingPlatform
extends AnimatableBody3D
## A platform that ferries whatever stands on it between two points.
##
## AnimatableBody3D with sync_to_physics is what makes a CharacterBody3D ride along
## without any code on the player: the physics server carries the passenger. Doing
## it by hand would fight move_and_slide and jitter at speed.
##
## Cyan, because it is traversal - the player can use it.

signal arrived(at_end: bool)

## Local-space offset from the start position to the far end.
@export var travel: Vector3 = Vector3(0, 0, 10)
@export var speed: float = 3.0
## Seconds held at each end, so the player can step on without timing a frame.
@export var dwell: float = 1.2
@export var telegraph: TelegraphComponent

var _origin: Vector3
var _target_end: bool = true
var _dwell_left: float = 0.0


func _ready() -> void:
	add_to_group(&"moving_platform")
	sync_to_physics = true
	_origin = global_position
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.AVAILABLE


func _physics_process(delta: float) -> void:
	if _dwell_left > 0.0:
		_dwell_left -= delta
		return

	var destination: Vector3 = _origin + (travel if _target_end else Vector3.ZERO)
	var step: float = speed * delta
	global_position = global_position.move_toward(destination, step)

	if global_position.distance_to(destination) > 0.001:
		return
	arrived.emit(_target_end)
	_target_end = not _target_end
	_dwell_left = dwell
