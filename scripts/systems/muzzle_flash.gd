class_name MuzzleFlash
extends Node3D
## A bright quad that pops and fades at the barrel tip, gone before the next shot
## from a fast weapon can double it up.
##
## One per weapon, reused for every shot. It used to be instantiated per shot and
## freed 60 ms later: fifteen nodes and fifteen duplicated materials a second on
## the SMG, allocation churn right on the input that has to feel the smoothest.
## Its lifetime is shorter than the fastest weapon's interval, so a single flash
## restarted on each shot never has to be in two places at once.
##
## Not pooled through ObjectPool: it has to live inside the viewmodel's own
## SubViewport world (see WeaponComponent._muzzle_marker), and ObjectPool's
## container is parented in the main world - pooling it there would render the
## flash in the wrong space entirely.

const LIFETIME: float = 0.06

@onready var _mesh: MeshInstance3D = $Quad

var _timer: float = 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	# Sub-resources in a .tscn are shared across every instantiate() of that scene:
	# each weapon's flash fades on its own alpha, not on one shared value.
	_material = (_mesh.material_override as StandardMaterial3D).duplicate()
	_mesh.material_override = _material
	# The quad is authored flat and needs tipping onto the barrel axis; the marker
	# it hangs off already carries the barrel's orientation.
	rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		visible = false
		set_process(false)
		return
	var t: float = _timer / LIFETIME
	_material.albedo_color.a = t
	_mesh.scale = Vector3.ONE * lerpf(0.6, 1.0, 1.0 - t)


## Starts (or restarts) the flash.
func play(scale_multiplier: float = 1.0) -> void:
	scale = Vector3.ONE * scale_multiplier
	_timer = LIFETIME
	_material.albedo_color.a = 1.0
	_mesh.scale = Vector3.ONE * 0.6
	visible = true
	set_process(true)
