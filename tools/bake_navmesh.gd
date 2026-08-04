extends SceneTree
## Bakes the arena navmesh offline and saves it next to the scene.
##
## Baking at runtime works, but parsing CSG geometry pulls meshes back from the GPU,
## which Godot rightly warns about. The layout is grey-box and still moving, so the
## bake is a tool step rather than a hand process: re-run this after changing the
## arena and commit the result.
##
##     godot --headless --path . -s tools/bake_navmesh.gd
##
## Add new arena geometry to the "navigation_source" group or the bake will not see it.
##
## Implemented against the MainLoop callbacks rather than `await`, because awaiting
## frames from a SceneTree script's _init() hangs - the loop is not running yet.

const ARENA_PATH: String = "res://scenes/arena/greybox_arena.tscn"
const OUTPUT_PATH: String = "res://scenes/arena/greybox_arena_navmesh.tres"
## Frames to let the CSG shapes resolve before the geometry is parsed.
const SETTLE_FRAMES: int = 4
## Wide enough for the biggest archetype (the Elite, at 0.75), so no enemy is ever
## routed closer to an edge than its own body can survive.
const AGENT_RADIUS: float = 0.85

var _frames: int = 0
var _region: NavigationRegion3D


func _initialize() -> void:
	var arena: Node3D = (load(ARENA_PATH) as PackedScene).instantiate()
	root.add_child(arena)
	_region = arena.get_node_or_null("Navigation") as NavigationRegion3D
	if _region == null:
		push_error("bake_navmesh: no Navigation region in %s" % ARENA_PATH)
		quit(1)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	if _region == null:
		return true

	var navmesh: NavigationMesh = _region.navigation_mesh
	navmesh.agent_radius = AGENT_RADIUS
	_region.bake_navigation_mesh(false)

	var vertices: int = navmesh.get_vertices().size()
	var polygons: int = navmesh.get_polygon_count()
	if vertices == 0 or polygons == 0:
		push_error("bake_navmesh: empty bake - is the geometry in the navigation_source group?")
		quit(1)
		return true

	var error: int = ResourceSaver.save(navmesh, OUTPUT_PATH)
	if error != OK:
		push_error("bake_navmesh: failed to save (%d)" % error)
		quit(1)
		return true

	print("Baked %s: %d vertices, %d polygons" % [OUTPUT_PATH, vertices, polygons])
	quit()
	return true
