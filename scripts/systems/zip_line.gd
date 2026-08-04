class_name ZipLine
extends Node3D
## A one-way ride between two points, taken by looking at it and interacting.
##
## The travelling arrow marker is the direction: a one-way line only ever shows one
## arrow, so a player never guesses which way a cable goes. Exit momentum is kept,
## because a zip line that dumps you at zero speed is a punishment for using it.

signal ride_started()
signal ride_finished()

@export var end_point: Node3D
@export var speed: float = 16.0
## Fraction of ride speed kept on dismount - the same momentum handoff as the dash.
@export var exit_speed_fraction: float = 0.8
@export var telegraph: TelegraphComponent
@export var cable_mesh: MeshInstance3D
@export var arrow: Node3D

@export_group("Audio")
@export var attach_sound: AudioStream
@export var release_sound: AudioStream

var is_occupied: bool = false

var _rider: CharacterBody3D
var _progress: float = 0.0
var _arrow_progress: float = 0.0


func _ready() -> void:
	add_to_group(&"zip_line")
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.AVAILABLE
	_fit_cable()


func _physics_process(delta: float) -> void:
	_animate_arrow(delta)
	if not is_occupied or _rider == null or not is_instance_valid(_rider):
		return

	var length: float = _length()
	if length < 0.01:
		_release()
		return

	_progress = minf(_progress + (speed / length) * delta, 1.0)
	_rider.global_position = global_position.lerp(end_point.global_position, _progress)
	_rider.velocity = _direction() * speed

	if _progress >= 1.0 or Input.is_action_just_pressed("jump"):
		_release()


# Public API

func try_mount(rider: CharacterBody3D) -> bool:
	if is_occupied or end_point == null or rider == null:
		return false
	is_occupied = true
	_rider = rider
	_progress = 0.0
	AudioPool.play_3d(attach_sound, global_position, AudioPool.BUS_WORLD)
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.ACTIVE
	ride_started.emit()
	return true


# Private

func _release() -> void:
	if _rider != null and is_instance_valid(_rider):
		# Dismount keeps most of the ride's speed rather than zeroing it.
		_rider.velocity = _direction() * speed * exit_speed_fraction
	is_occupied = false
	_rider = null
	AudioPool.play_3d(release_sound, global_position, AudioPool.BUS_WORLD)
	if telegraph != null:
		telegraph.state = TelegraphComponent.State.AVAILABLE
	ride_finished.emit()


func _direction() -> Vector3:
	if end_point == null:
		return Vector3.FORWARD
	return (end_point.global_position - global_position).normalized()


func _length() -> float:
	if end_point == null:
		return 0.0
	return global_position.distance_to(end_point.global_position)


## The marker slides along the cable on a loop; its motion states the ride direction
## without needing a colour or a label.
func _animate_arrow(delta: float) -> void:
	if arrow == null or end_point == null:
		return
	_arrow_progress = fmod(_arrow_progress + delta * 0.4, 1.0)
	arrow.global_position = global_position.lerp(end_point.global_position, _arrow_progress)
	arrow.look_at(end_point.global_position, Vector3.UP)


func _fit_cable() -> void:
	if cable_mesh == null or end_point == null:
		return
	var length: float = _length()
	if length < 0.01:
		return
	cable_mesh.global_position = global_position.lerp(end_point.global_position, 0.5)
	cable_mesh.look_at(end_point.global_position, Vector3.UP)
	cable_mesh.scale = Vector3(1.0, 1.0, length)
