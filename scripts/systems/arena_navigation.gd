class_name ArenaNavigation
extends NavigationRegion3D
## Owns the arena's ground-level navmesh.
##
## The navmesh is baked offline by `tools/bake_navmesh.gd` and committed, because
## baking CSG geometry at runtime pulls meshes back from the GPU - Godot warns about
## it, and it is a startup cost for something the layout only changes at author time.
## Re-run the tool after moving arena geometry.
##
## `bake_on_ready` is the escape hatch for iterating on layout without re-running the
## tool. It is off by default and should stay off in anything committed.

signal navigation_ready()

## Dev-only convenience: re-bake at startup instead of using the committed navmesh.
@export var bake_on_ready: bool = false

var is_baked: bool = false


func _ready() -> void:
	if not bake_on_ready:
		is_baked = navigation_mesh != null and navigation_mesh.get_polygon_count() > 0
		if not is_baked:
			push_warning("ArenaNavigation: no baked navmesh - run tools/bake_navmesh.gd")
		navigation_ready.emit()
		return
	# Deferred so every CSG shape has resolved its geometry before the bake reads it.
	_bake.call_deferred()


func _bake() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	bake_navigation_mesh(false)
	is_baked = true
	navigation_ready.emit()
