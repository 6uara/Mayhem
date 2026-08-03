class_name ArenaNavigation
extends NavigationRegion3D
## Bakes the ground-level navmesh at runtime from the arena's static colliders.
##
## Baking at runtime rather than committing a baked resource keeps the grey-box
## arena editable without a re-bake step - the layout is still changing every
## playtest. Swap this for a committed navmesh when the layout locks (CLAUDE.md 5.6).

signal navigation_ready()

@export var bake_on_ready: bool = true

var is_baked: bool = false


func _ready() -> void:
	if not bake_on_ready:
		return
	# Deferred so every CSG shape has resolved its collision before the bake reads it.
	_bake.call_deferred()


func _bake() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	bake_navigation_mesh(false)
	is_baked = true
	navigation_ready.emit()
