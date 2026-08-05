class_name MuzzleFlash
extends Node3D
## A bright quad that pops and fades at the barrel tip, gone before the next shot
## from a fast weapon can double it up.
##
## Not pooled through ObjectPool: it has to live inside the viewmodel's own
## SubViewport world (see WeaponComponent._muzzle_marker), and ObjectPool's
## container is parented in the main world - pooling it there would render the
## flash in the wrong space entirely, at a position that has nothing to do with
## where the gun is drawn on screen. One-shot instances are cheap enough at any
## weapon's fire rate that pooling would be solving a cost that doesn't exist.

const LIFETIME: float = 0.06

@onready var _mesh: MeshInstance3D = $Quad

var _timer: float = LIFETIME
var _material: StandardMaterial3D


func _ready() -> void:
	# Sub-resources in a .tscn are shared across every instantiate() of that scene,
	# so two flashes alive at once (a fast weapon firing inside this lifetime)
	# would otherwise fade in lockstep off one shared alpha value.
	_material = (_mesh.material_override as StandardMaterial3D).duplicate()
	_mesh.material_override = _material


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
		return
	var t: float = _timer / LIFETIME
	_material.albedo_color.a = t
	_mesh.scale = Vector3.ONE * lerpf(0.6, 1.0, 1.0 - t)


## Orientation comes free from being parented at zero local transform onto an
## already-correctly-oriented marker - only the quad's own facing (authored flat,
## needs tipping onto the barrel axis) is this component's job.
func play(scale_multiplier: float = 1.0) -> void:
	rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	scale = Vector3.ONE * scale_multiplier
