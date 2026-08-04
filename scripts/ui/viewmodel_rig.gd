class_name ViewmodelRig
extends SubViewportContainer
## Renders the equipped weapon in its own world, composited over the main view.
##
## A viewmodel is half a metre of geometry held ~35cm from the eye, so in the main
## world it does what any object that close does: it intersects the wall you are
## standing against, and the camera's near plane slices through it. Neither is
## fixable by moving the model - the world is simply not where a viewmodel belongs.
##
## Its own World3D solves both at once. Nothing in the arena exists in here to
## clip against, and the field of view is decoupled from the player's, so a player
## on 120 FOV gets a wide arena without a fisheye rifle.
##
## Weapons keep their logic in the main world. `WeaponComponent` sends only the
## visual pivot here; the muzzle node, and therefore where rounds actually spawn,
## stays where the body is.

## Narrower than the world camera on purpose - viewmodels distort badly at the wide
## FOVs first-person players prefer, which is why shipped games separate the two.
@export var viewmodel_fov: float = 62.0
@export var camera: Camera3D
## Weapon pivots are parented here.
@export var slots: Node3D


func _ready() -> void:
	if camera != null:
		camera.fov = viewmodel_fov


## Where WeaponComponent should mount its viewmodel.
func get_slot_parent() -> Node3D:
	return slots
