class_name EjectedShell
extends Node3D
## A casing kicked sideways from the ejection port, tumbling under its own simple
## gravity until it settles, then it's freed.
##
## Lives inside the viewmodel's own SubViewport world, same reasoning as
## MuzzleFlash: it has to be a child of the visual gun, not of ObjectPool's
## main-world container, or it renders in a space that has no relation to the
## screen position of the gun that supposedly ejected it. Never collides with
## the world - it's a cosmetic detail, not worth a raycast per frame.

const GRAVITY: float = 14.0
const MAX_LIFETIME: float = 2.0
## Local Y drop from the eject point at which the shell is considered landed.
const SETTLE_DROP: float = 0.35

@export var spin_speed_range: Vector2 = Vector2(4.0, 10.0)

@onready var _mesh: MeshInstance3D = $Mesh

var _velocity: Vector3 = Vector3.ZERO
var _spin_axis: Vector3 = Vector3.UP
var _spin_speed: float = 0.0
var _lifetime: float = 0.0
var _drop: float = 0.0
var _settled: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if _mesh != null:
		_mesh.scale = Vector3.ONE * _rng.randf_range(0.85, 1.15)


func _process(delta: float) -> void:
	if _settled:
		return
	_lifetime += delta
	if _lifetime >= MAX_LIFETIME:
		queue_free()
		return

	_velocity.y -= GRAVITY * delta
	var step: Vector3 = _velocity * delta
	position += step
	_drop -= step.y
	rotate_object_local(_spin_axis, _spin_speed * delta)

	if _drop >= SETTLE_DROP:
		_settled = true
		_velocity = Vector3.ZERO


## `eject_direction` and `up` are in the marker's local frame - the marker already
## carries the weapon's own orientation, so "sideways" here means sideways relative
## to the gun regardless of which way the player is looking.
func eject(eject_direction: Vector3, up: Vector3) -> void:
	_velocity = eject_direction * _rng.randf_range(1.0, 1.8) + up * _rng.randf_range(0.8, 1.4)
	_spin_axis = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)).normalized()
	_spin_speed = _rng.randf_range(spin_speed_range.x, spin_speed_range.y)
